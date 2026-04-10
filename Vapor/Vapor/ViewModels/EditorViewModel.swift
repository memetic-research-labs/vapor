import Foundation
import SwiftUI
import Combine
import OSLog

private let logger = Logger(subsystem: "lol.mrl.app.Vapor", category: "Editor")

@MainActor
@Observable
final class EditorViewModel {
    var content: String = ""
    var compressedContent: String = ""
    var compressionRatio: Double = 0.0
    var originalTokenCount: Int = 0
    var compressedTokenCount: Int = 0
    var isDirty: Bool = false
    var isDictating: Bool = false
    var activeDictationRange: NSRange?
    var selectedCompressor: CompressorType = .ruleBased
    var isCompressing: Bool = false
    var lastSavedContent: String = ""

    private let clipboardService = ClipboardService()
    private var compressionService: CompressionService?
    private var historyService: PromptHistoryService?

    func setServices(compression: CompressionService, history: PromptHistoryService) {
        self.compressionService = compression
        self.historyService = history
        self.selectedCompressor = compression.selectedCompressor
    }

    func copyOriginalToClipboard() {
        clipboardService.copy(content)
    }

    func copyCompressedToClipboard() {
        clipboardService.copy(compressedContent)
    }

    func compressAndCopy() async throws {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let compressionService else { return }

        isCompressing = true
        defer { isCompressing = false }

        let result = try await compressionService.compress(content)
        compressedContent = result.text
        compressionRatio = result.ratio
        originalTokenCount = result.originalTokens
        compressedTokenCount = result.compressedTokens
        selectedCompressor = result.compressorUsed

        clipboardService.copy(compressedContent)
        logger.info("Compressed using: \(self.selectedCompressor.rawValue)")
        logger.debug("Ratio: \(String(format: "%.2f", self.compressionRatio))")

        if let historyService, content != lastSavedContent {
            let record = PromptRecord(
                originalText: content,
                compressedText: compressedContent,
                originalTokenCount: originalTokenCount,
                compressedTokenCount: compressedTokenCount,
                compressionRatio: compressionRatio,
                compressorUsed: selectedCompressor
            )
            try? historyService.save(record)
            lastSavedContent = content
        }
    }

    func clear() {
        content = ""
        compressedContent = ""
        compressionRatio = 0.0
        originalTokenCount = 0
        compressedTokenCount = 0
        isDirty = false
    }

    /// Copies the original text to the clipboard, then clears the buffer.
    func copyAndClear() {
        if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            clipboardService.copy(content)
        }
        clear()
    }

    /// Auto-saves the current content (if any), then replaces with the restored record's original text.
    func restoreFromHistory(_ record: PromptRecord) {
        // Auto-save current content before replacing
        if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           content != lastSavedContent,
           let historyService,
           let compressionService {
            let autoSaveRecord = PromptRecord(
                originalText: content,
                compressedText: compressedContent,
                originalTokenCount: originalTokenCount,
                compressedTokenCount: compressedTokenCount,
                compressionRatio: compressionRatio,
                compressorUsed: selectedCompressor
            )
            try? historyService.save(autoSaveRecord)
        }

        // Replace editor content with restored text
        content = record.originalText
        compressedContent = record.compressedText
        originalTokenCount = record.originalTokenCount
        compressedTokenCount = record.compressedTokenCount
        compressionRatio = record.compressionRatio
        isDirty = false
        lastSavedContent = record.originalText
    }

    /// Whether the next dictation segment should have its first letter lowercased.
    /// True when we're continuing mid-sentence (existing content doesn't end with sentence-ending punctuation).
    private var shouldLowercaseNextSegment = false

    func applyDictationTranscript(_ text: String, isFinal: Bool) {
        if activeDictationRange == nil {
            // Insert a space separator if the existing content doesn't end with whitespace
            if !content.isEmpty, let lastChar = content.last, !lastChar.isWhitespace {
                content.append(" ")
            }

            // Determine if we should lowercase the first character of this new segment.
            // If content is empty or ends with sentence-ending punctuation, keep original case.
            // Otherwise, lowercase to continue mid-sentence naturally.
            let trimmed = content.trimmingCharacters(in: .whitespaces)
            let sentenceEnders: Set<Character> = [".", "!", "?", ":", "\n"]
            shouldLowercaseNextSegment = !trimmed.isEmpty && !sentenceEnders.contains(trimmed.last ?? ".")

            activeDictationRange = NSRange(location: (content as NSString).length, length: 0)
        }

        guard let range = activeDictationRange else { return }

        // Adjust case of the first character if continuing mid-sentence
        let adjustedText: String
        if shouldLowercaseNextSegment, let first = text.first, first.isUppercase {
            adjustedText = first.lowercased() + text.dropFirst()
        } else {
            adjustedText = text
        }

        let nsString = content as NSString
        let newContent = nsString.replacingCharacters(in: range, with: adjustedText)
        content = newContent
        isDirty = true

        if isFinal {
            activeDictationRange = nil
            shouldLowercaseNextSegment = false
        } else {
            activeDictationRange = NSRange(location: range.location, length: (adjustedText as NSString).length)
        }
    }
}
