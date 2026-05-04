import XCTest
@testable import Vapor

final class VaporProjectTests: XCTestCase {

    func testVaporProjectDefaults() {
        let project = VaporProject(name: "Test Project")

        XCTAssertEqual(project.name, "Test Project")
        XCTAssertNil(project.notes)
        XCTAssertNil(project.gitLocalPath)
        XCTAssertNil(project.gitRemoteURL)
        XCTAssertNil(project.gitCurrentBranch)
        XCTAssertNil(project.detectedPRNumber)
        XCTAssertNil(project.colorHex)
        XCTAssertEqual(project.sortOrder, 0)
        XCTAssertNotNil(project.createdAt)
        XCTAssertNotNil(project.lastActiveAt)
        XCTAssertTrue(project.contextItems.isEmpty)
        XCTAssertTrue(project.promptRecords.isEmpty)
        XCTAssertTrue(project.sessions.isEmpty)
        XCTAssertTrue(project.imageAssets.isEmpty)
        XCTAssertTrue(project.bookmarks.isEmpty)
    }

    func testVaporProjectWithGitFields() {
        let project = VaporProject(
            name: "Vapor",
            notes: "AI research assistant",
            gitLocalPath: "/Users/dev/vapor",
            gitRemoteURL: "https://github.com/org/vapor",
            gitCurrentBranch: "main",
            detectedPRNumber: 42,
            colorHex: "#FF0000",
            sortOrder: 5
        )

        XCTAssertEqual(project.name, "Vapor")
        XCTAssertEqual(project.notes, "AI research assistant")
        XCTAssertEqual(project.gitLocalPath, "/Users/dev/vapor")
        XCTAssertEqual(project.gitRemoteURL, "https://github.com/org/vapor")
        XCTAssertEqual(project.gitCurrentBranch, "main")
        XCTAssertEqual(project.detectedPRNumber, 42)
        XCTAssertEqual(project.colorHex, "#FF0000")
        XCTAssertEqual(project.sortOrder, 5)
    }

    func testVaporProjectBookmarkDefaults() {
        let bookmark = VaporProjectBookmark(bookmarkData: Data("test".utf8))

        XCTAssertNotNil(bookmark.id)
        XCTAssertEqual(bookmark.bookmarkData, Data("test".utf8))
        XCTAssertNotNil(bookmark.createdAt)
        XCTAssertNil(bookmark.bookmark)
    }
}

final class AISessionModelTests: XCTestCase {

    func testAISessionDefaults() {
        let session = AISession(title: "Test Session", tool: "opencode")

        XCTAssertEqual(session.title, "Test Session")
        XCTAssertEqual(session.tool, "opencode")
        XCTAssertNil(session.projectPath)
        XCTAssertNil(session.projectName)
        XCTAssertNil(session.branchName)
        XCTAssertNil(session.prNumber)
        XCTAssertNotNil(session.startedAt)
        XCTAssertNil(session.endedAt)
        XCTAssertTrue(session.tags.isEmpty)
        XCTAssertFalse(session.isArchived)
        XCTAssertNil(session.gitCommitSHA)
        XCTAssertNil(session.embeddingID)
        XCTAssertNil(session.summaryAbstract)
        XCTAssertNil(session.summaryKeyPointsData)
        XCTAssertEqual(session.totalTokensEstimated, 0)
        XCTAssertEqual(session.totalTurns, 0)
        XCTAssertEqual(session.totalAttachedImages, 0)
        XCTAssertEqual(session.totalAttachedURLs, 0)
        XCTAssertNil(session.project)
        XCTAssertTrue(session.turns.isEmpty)
        XCTAssertTrue(session.entityLinks.isEmpty)
        XCTAssertTrue(session.exportRecords.isEmpty)
    }

    func testAISessionWithGitFields() {
        let session = AISession(
            title: "Auth Refactor",
            tool: "claude-desktop",
            projectPath: "/Users/dev/app",
            projectName: "app",
            branchName: "feature/auth",
            prNumber: 27
        )

        XCTAssertEqual(session.tool, "claude-desktop")
        XCTAssertEqual(session.projectPath, "/Users/dev/app")
        XCTAssertEqual(session.projectName, "app")
        XCTAssertEqual(session.branchName, "feature/auth")
        XCTAssertEqual(session.prNumber, 27)
    }

    func testAITurnDefaults() {
        let turn = AITurn(role: "user", content: "How do I add rate limiting?", turnIndex: 0)

        XCTAssertNotNil(turn.id)
        XCTAssertEqual(turn.role, "user")
        XCTAssertEqual(turn.content, "How do I add rate limiting?")
        XCTAssertEqual(turn.turnIndex, 0)
        XCTAssertNotNil(turn.capturedAt)
        XCTAssertNil(turn.embeddingID)
        XCTAssertNil(turn.modelID)
        XCTAssertNil(turn.toolName)
        XCTAssertTrue(turn.attachedImageIDs.isEmpty)
        XCTAssertTrue(turn.attachedURLs.isEmpty)
        XCTAssertNil(turn.durationSeconds)
        XCTAssertFalse(turn.isEdited)
        XCTAssertFalse(turn.isRedacted)
        XCTAssertNil(turn.session)
        XCTAssertTrue(turn.entityLinks.isEmpty)
    }

    func testAITurnAssistantWithMetadata() {
        let turn = AITurn(
            role: "assistant",
            content: "Use express-rate-limit middleware.",
            turnIndex: 1,
            capturedAt: Date(),
            contentTokenCount: 42,
            modelID: "claude-opus-4-5",
            toolName: "opencode",
            durationSeconds: 3.2
        )

        XCTAssertEqual(turn.role, "assistant")
        XCTAssertEqual(turn.contentTokenCount, 42)
        XCTAssertEqual(turn.modelID, "claude-opus-4-5")
        XCTAssertEqual(turn.toolName, "opencode")
        XCTAssertEqual(turn.durationSeconds, 3.2)
    }

    func testAISessionTagDefaults() {
        let tag = AISessionTag(text: "rate-limiting", source: "llm", confidence: 0.9)

        XCTAssertEqual(tag.text, "rate-limiting")
        XCTAssertEqual(tag.sourceRaw, "llm")
        XCTAssertEqual(tag.source, .llm)
        XCTAssertEqual(tag.confidence, 0.9)
        XCTAssertNotNil(tag.createdAt)
        XCTAssertNil(tag.session)
    }

    func testAISessionTagSources() {
        XCTAssertEqual(AISessionTagSource.auto.rawValue, "auto")
        XCTAssertEqual(AISessionTagSource.user.rawValue, "user")
        XCTAssertEqual(AISessionTagSource.llm.rawValue, "llm")

        let tag = AISessionTag(text: "test", source: "user")
        XCTAssertEqual(tag.source, .user)
    }

    func testAIGitExportRecordDefaults() {
        let record = AIGitExportRecord(
            gitCommitSHA: "abc123",
            branchName: "feature/auth",
            sessionDirPath: ".vapor-context/sessions/2025-05-01/uuid"
        )

        XCTAssertNotNil(record.id)
        XCTAssertNotNil(record.exportedAt)
        XCTAssertEqual(record.gitCommitSHA, "abc123")
        XCTAssertEqual(record.branchName, "feature/auth")
        XCTAssertEqual(record.sessionDirPath, ".vapor-context/sessions/2025-05-01/uuid")
        XCTAssertTrue(record.filesIncluded.isEmpty)
        XCTAssertEqual(record.totalBytes, 0)
        XCTAssertEqual(record.redactionCount, 0)
        XCTAssertTrue(record.redactedTurnIDs.isEmpty)
        XCTAssertNil(record.session)
    }

    func testAISessionEntityLinkDefaults() {
        let link = AISessionEntityLink(confidence: 0.95, surfaceText: "express-rate-limit")

        XCTAssertNotNil(link.id)
        XCTAssertEqual(link.confidence, 0.95)
        XCTAssertEqual(link.surfaceText, "express-rate-limit")
        XCTAssertNotNil(link.createdAt)
        XCTAssertNil(link.session)
        XCTAssertNil(link.entityRecord)
    }

    func testAITurnEntityLinkDefaults() {
        let link = AITurnEntityLink(confidence: 0.85, surfaceText: "express")

        XCTAssertNotNil(link.id)
        XCTAssertEqual(link.confidence, 0.85)
        XCTAssertEqual(link.surfaceText, "express")
        XCTAssertNotNil(link.createdAt)
        XCTAssertNil(link.turn)
        XCTAssertNil(link.entityRecord)
    }
}

final class EnumExpansionTests: XCTestCase {

    func testEntityKindNewCasesExist() {
        XCTAssertTrue(EntityKind.allCases.contains(.model))
        XCTAssertTrue(EntityKind.allCases.contains(.tool))
        XCTAssertTrue(EntityKind.allCases.contains(.library))
        XCTAssertTrue(EntityKind.allCases.contains(.api))
        XCTAssertTrue(EntityKind.allCases.contains(.file))
        XCTAssertTrue(EntityKind.allCases.contains(.error))
        XCTAssertTrue(EntityKind.allCases.contains(.decision))
    }

    func testEntityKindCount() {
        XCTAssertEqual(EntityKind.allCases.count, 16)
    }

    func testEntityKindOriginalCasesStillExist() {
        XCTAssertTrue(EntityKind.allCases.contains(.person))
        XCTAssertTrue(EntityKind.allCases.contains(.organization))
        XCTAssertTrue(EntityKind.allCases.contains(.product))
        XCTAssertTrue(EntityKind.allCases.contains(.location))
        XCTAssertTrue(EntityKind.allCases.contains(.date))
        XCTAssertTrue(EntityKind.allCases.contains(.url))
        XCTAssertTrue(EntityKind.allCases.contains(.number))
        XCTAssertTrue(EntityKind.allCases.contains(.code))
        XCTAssertTrue(EntityKind.allCases.contains(.concept))
    }

    func testContextItemKindSpecExists() {
        XCTAssertTrue(ContextItemKind.allCases.contains(.spec))
    }

    func testContextItemKindSpecDisplayName() {
        XCTAssertEqual(ContextItemKind.spec.displayName, "Spec")
    }

    func testContextItemKindSpecSystemImage() {
        XCTAssertEqual(ContextItemKind.spec.systemImage, "doc.badge.gearshape")
    }

    func testAISessionTagSourceAllCases() {
        XCTAssertEqual(AISessionTagSource.allCases.count, 3)
    }
}

final class OptionalFKSafetyTests: XCTestCase {

    func testContextItemProjectDefaultNil() {
        let item = ContextItem(
            sourceURL: "https://example.com",
            sourceTitle: "Test",
            kind: .articleText,
            textContent: "Content"
        )
        XCTAssertNil(item.project, "New ContextItem must have project == nil by default")
    }

    func testImageAssetProjectDefaultNil() {
        let asset = ImageAsset(
            contentHash: "abc",
            mimeType: "image/png",
            pixelWidth: 100,
            pixelHeight: 100,
            byteSize: 1024,
            originalFilename: "test.png",
            originalPath: nil,
            blobPath: "/path/to/blob",
            sourceKind: .manualImport
        )
        XCTAssertNil(asset.project, "New ImageAsset must have project == nil by default")
        XCTAssertNil(asset.aiSession, "New ImageAsset must have aiSession == nil by default")
    }
}

final class SchemaMigrationTests: XCTestCase {

    func testVaporSchemaV2ContainsAllV1Models() {
        let v1Models = Set(VaporSchemaV1.models.map { ObjectIdentifier($0).hashValue })
        let v2Models = Set(VaporSchemaV2.models.map { ObjectIdentifier($0).hashValue })

        for v1Model in VaporSchemaV1.models {
            let hash = ObjectIdentifier(v1Model).hashValue
            XCTAssertTrue(v2Models.contains(hash), "V2 schema missing V1 model: \(v1Model)")
        }
    }

    func testVaporSchemaV2ContainsNewModels() {
        let v2ModelNames = VaporSchemaV2.models.map { String(describing: $0) }

        XCTAssertTrue(v2ModelNames.contains("VaporProject"), "VaporProject not in V2 schema")
        XCTAssertTrue(v2ModelNames.contains("VaporProjectBookmark"), "VaporProjectBookmark not in V2 schema")
        XCTAssertTrue(v2ModelNames.contains("AISession"), "AISession not in V2 schema")
        XCTAssertTrue(v2ModelNames.contains("AITurn"), "AITurn not in V2 schema")
        XCTAssertTrue(v2ModelNames.contains("AISessionEntityLink"), "AISessionEntityLink not in V2 schema")
        XCTAssertTrue(v2ModelNames.contains("AITurnEntityLink"), "AITurnEntityLink not in V2 schema")
        XCTAssertTrue(v2ModelNames.contains("AISessionTag"), "AISessionTag not in V2 schema")
        XCTAssertTrue(v2ModelNames.contains("AIGitExportRecord"), "AIGitExportRecord not in V2 schema")
    }

    func testVaporSchemaV2HasMoreModelsThanV1() {
        XCTAssertGreaterThan(VaporSchemaV2.models.count, VaporSchemaV1.models.count)
    }
}
