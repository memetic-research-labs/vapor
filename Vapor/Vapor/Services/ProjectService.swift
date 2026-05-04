import Foundation
import SwiftData
import OSLog

nonisolated private let projectLogger = Logger(subsystem: "lol.mrl.app.Vapor", category: "ProjectService")

struct GitInfo {
    let rootPath: String
    let remoteURL: String?
    let branch: String?
    let prNumber: Int?
}

struct BrowserProjectMatch {
    let org: String
    let repo: String
    let host: String
}

@MainActor
@Observable
final class ProjectService {
    static let shared = ProjectService()

    private var modelContext: ModelContext?

    private(set) var projects: [VaporProject] = []
    private(set) var isRefreshing = false

    private init() {}

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        Task { @MainActor in
            refreshProjects()
            restoreBookmarks()
        }
    }

    func refreshProjects() {
        guard let modelContext else { return }
        do {
            let descriptor = FetchDescriptor<VaporProject>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)])
            projects = try modelContext.fetch(descriptor)
        } catch {
            projectLogger.error("Failed to fetch projects: \(error.localizedDescription, privacy: .public)")
        }
    }

    func createProject(
        name: String,
        notes: String? = nil,
        gitPath: String? = nil,
        remoteURL: String? = nil,
        branch: String? = nil,
        prNumber: Int? = nil,
        colorHex: String? = nil
    ) throws -> VaporProject {
        guard let modelContext else {
            projectLogger.error("createProject called but modelContext is nil")
            throw ProjectServiceError.noModelContext
        }

        let gitInfo: GitInfo? = if let gitPath {
            try? detectGitInfo(at: gitPath)
        } else { nil }

        let project = VaporProject(
            name: name,
            notes: notes,
            gitLocalPath: gitInfo?.rootPath ?? gitPath,
            gitRemoteURL: remoteURL ?? gitInfo?.remoteURL,
            gitCurrentBranch: branch ?? gitInfo?.branch,
            detectedPRNumber: prNumber ?? gitInfo?.prNumber,
            colorHex: colorHex,
            sortOrder: projects.count
        )

        modelContext.insert(project)
        try modelContext.save()

        if let localPath = project.gitLocalPath {
            saveBookmark(for: project, path: localPath)
        }

        refreshProjects()
        StatusBarService.shared.log("Project created: \(name)", domain: .system, level: .success)
        return project
    }

    func detectProject(from gitPath: String) -> VaporProject? {
        guard let gitInfo = try? detectGitInfo(at: gitPath) else {
            projectLogger.debug("Not a git repo: \(gitPath, privacy: .public)")
            return nil
        }

        let existing = projects.first { project in
            if let localPath = project.gitLocalPath, localPath == gitInfo.rootPath {
                return true
            }
            if let remote = gitInfo.remoteURL, let projectRemote = project.gitRemoteURL,
               normalizeRemoteURL(remote) == normalizeRemoteURL(projectRemote) {
                return true
            }
            return false
        }

        if let existing {
            existing.lastActiveAt = Date()
            if let branch = gitInfo.branch {
                existing.gitCurrentBranch = branch
            }
            if let prNumber = gitInfo.prNumber {
                existing.detectedPRNumber = prNumber
            }
            try? modelContext?.save()
            return existing
        }

        let repoName = (gitInfo.rootPath as NSString).lastPathComponent
        do {
            return try createProject(
                name: repoName,
                gitPath: gitInfo.rootPath,
                remoteURL: gitInfo.remoteURL,
                branch: gitInfo.branch,
                prNumber: gitInfo.prNumber
            )
        } catch {
            projectLogger.error("Failed to auto-create project: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func detectProject(fromBrowserURL browserURL: String) -> VaporProject? {
        guard let match = parseBrowserProjectURL(browserURL) else { return nil }

        let normalizedRemote = "\(match.host)/\(match.org)/\(match.repo)"
        return projects.first { project in
            guard let projectRemote = project.gitRemoteURL else { return false }
            return normalizeRemoteURL(projectRemote).contains(normalizedRemote)
        }
    }

    func assignContextItem(_ item: ContextItem, to project: VaporProject?) throws {
        guard let modelContext else { return }
        item.project = project
        try modelContext.save()
    }

    func assignPromptRecord(_ record: PromptRecord, to project: VaporProject?) throws {
        guard let modelContext else { return }
        record.project = project
        try modelContext.save()
    }

    func assignImageAsset(_ asset: ImageAsset, to project: VaporProject?) throws {
        guard let modelContext else { return }
        asset.project = project
        try modelContext.save()
    }

    func assignSession(_ session: AISession, to project: VaporProject?) throws {
        guard let modelContext else { return }
        session.project = project
        try modelContext.save()
    }

    func refreshGitState(for project: VaporProject) {
        guard let localPath = project.gitLocalPath else { return }

        let info = try? detectGitInfo(at: localPath)
        project.gitCurrentBranch = info?.branch
        project.detectedPRNumber = info?.prNumber
        project.lastActiveAt = Date()
        try? modelContext?.save()
    }

    func contextItemCount(for project: VaporProject?) -> Int {
        guard let modelContext else { return 0 }
        do {
            if let project {
                let projectID = project.id
                let descriptor = FetchDescriptor<ContextItem>(
                    predicate: #Predicate { item in
                        item.project?.id == projectID
                    }
                )
                return try modelContext.fetchCount(descriptor)
            } else {
                let descriptor = FetchDescriptor<ContextItem>(
                    predicate: #Predicate { item in
                        item.project == nil
                    }
                )
                return try modelContext.fetchCount(descriptor)
            }
        } catch {
            return 0
        }
    }

    func unassignedContextItemCount() -> Int {
        contextItemCount(for: nil)
    }
}

// MARK: - Git Detection (Task 1.6)

extension ProjectService {

    func detectGitInfo(at path: String) throws -> GitInfo? {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: path) else {
            return nil
        }

        let rootPath = runGitCommand("rev-parse --show-toplevel", at: path)
        guard let rootPath, !rootPath.isEmpty else { return nil }

        let remoteURL = runGitCommand("remote get-url origin", at: path)
        let branch = runGitCommand("rev-parse --abbrev-ref HEAD", at: path)
        let prNumber = branch.flatMap { parsePRNumber(from: $0) }

        return GitInfo(
            rootPath: rootPath,
            remoteURL: remoteURL.nilIfEmpty,
            branch: branch.nilIfEmpty,
            prNumber: prNumber
        )
    }

    private func runGitCommand(_ arguments: String, at path: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments.split(separator: " ").map(String.init)
        process.currentDirectoryURL = URL(fileURLWithPath: path)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            projectLogger.debug("Git command failed at \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func parsePRNumber(from branch: String) -> Int? {
        let patterns = [
            "pr-(\\d+)",
            "PR-(\\d+)",
            "pr_(\\d+)",
            "feature/(\\d+)-",
            "fix/(\\d+)-",
            "copilot/(\\d+)-"
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: branch, range: NSRange(branch.startIndex..., in: branch)),
                  let range = Range(match.range(at: 1), in: branch) else {
                continue
            }
            return Int(branch[range])
        }
        return nil
    }

    private func normalizeRemoteURL(_ url: String) -> String {
        var normalized = url
            .replacingOccurrences(of: "git@", with: "")
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: ".git", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if normalized.contains(":") {
            normalized = normalized.replacingOccurrences(of: ":", with: "/")
        }

        return normalized.lowercased()
    }
}

// MARK: - Browser URL Detection (Task 1.7)

extension ProjectService {

    func parseBrowserProjectURL(_ urlString: String) -> BrowserProjectMatch? {
        let patterns: [(String, String)] = [
            ("github.com", #"github\.com/([^/]+)/([^/?#]+)"#),
            ("gitlab.com", #"gitlab\.com/([^/]+)/([^/?#]+)"#),
            ("bitbucket.org", #"bitbucket\.org/([^/]+)/([^/?#]+)"#),
        ]

        for (host, pattern) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)),
                  match.numberOfRanges >= 3,
                  let orgRange = Range(match.range(at: 1), in: urlString),
                  let repoRange = Range(match.range(at: 2), in: urlString) else {
                continue
            }
            return BrowserProjectMatch(
                org: String(urlString[orgRange]),
                repo: String(urlString[repoRange]),
                host: host
            )
        }

        return nil
    }
}

// MARK: - Security-Scoped Bookmarks (Task 1.8)

extension ProjectService {

    func saveBookmark(for project: VaporProject, path: String) {
        let url = URL(fileURLWithPath: path)
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            guard let modelContext else { return }

            let existingBookmark = project.bookmarks.first
            if let existingBookmark {
                existingBookmark.bookmarkData = data
                existingBookmark.createdAt = Date()
            } else {
                let bookmark = VaporProjectBookmark(bookmarkData: data, bookmark: project)
                modelContext.insert(bookmark)
            }
            try modelContext.save()
            projectLogger.debug("Saved security-scoped bookmark for \(path, privacy: .public)")
        } catch {
            projectLogger.error("Failed to save bookmark for \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func restoreBookmarks() {
        guard let modelContext else { return }
        do {
            let descriptor = FetchDescriptor<VaporProjectBookmark>()
            let allBookmarks = try modelContext.fetch(descriptor)

            for bookmarkRecord in allBookmarks {
                guard let project = bookmarkRecord.bookmark else { continue }
                var isStale = false
                do {
                    let url = try URL(
                        resolvingBookmarkData: bookmarkRecord.bookmarkData,
                        options: .withoutUI,
                        relativeTo: nil,
                        bookmarkDataIsStale: &isStale
                    )
                    let didAccess = url.startAccessingSecurityScopedResource()
                    if didAccess {
                        projectLogger.debug("Restored access to \(url.path, privacy: .public)")
                        if isStale {
                            saveBookmark(for: project, path: url.path)
                        }
                    }
                    if !didAccess {
                        projectLogger.warning("Could not access security-scoped resource: \(url.path, privacy: .public)")
                    }
                } catch {
                    projectLogger.error("Failed to restore bookmark: \(error.localizedDescription, privacy: .public)")
                }
            }
        } catch {
            projectLogger.error("Failed to fetch bookmarks: \(error.localizedDescription, privacy: .public)")
        }
    }
}

enum ProjectServiceError: Error, LocalizedError {
    case noModelContext

    var errorDescription: String? {
        switch self {
        case .noModelContext: "ModelContext is not available"
        }
    }
}

private extension Optional where Wrapped == String {
    var nilIfEmpty: String? {
        guard let self, !self.isEmpty else { return nil }
        return self
    }
}
