import Foundation
import SwiftUI
import Combine

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
    
    func compressAndCopy() async {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let compressionService else { return }
        
        isCompressing = true
        defer { isCompressing = false }
        
        do {
            let result = try await compressionService.compress(content)
            compressedContent = result.text
            compressionRatio = result.ratio
            originalTokenCount = result.originalTokens
            compressedTokenCount = result.compressedTokens
            selectedCompressor = result.compressorUsed
            
            clipboardService.copy(compressedContent)
            print("[EditorViewModel] Compressed using: \(selectedCompressor.rawValue)")
            print("[EditorViewModel] Original: \(content)")
            print("[EditorViewModel] Compressed: \(compressedContent)")
            print("[EditorViewModel] Ratio: \(String(format: "%.2f", compressionRatio))")
            
            if let historyService, content != lastSavedContent {
                let record = PromptRecord(
                    originalText: content,
                    compressedText: compressedContent,
                    originalTokenCount: originalTokenCount,
                    compressedTokenCount: compressedTokenCount,
                    compressionRatio: compressionRatio,
                    compressorUsed: selectedCompressor
                )
                try? await historyService.save(record)
                lastSavedContent = content
            }
        } catch {
            print("Compression error: \(error)")
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
    
    func applyDictationTranscript(_ text: String, isFinal: Bool) {
        if activeDictationRange == nil {
            activeDictationRange = NSRange(location: (content as NSString).length, length: 0)
        }
        
        guard let range = activeDictationRange else { return }
        
        let nsString = content as NSString
        let newContent = nsString.replacingCharacters(in: range, with: text)
        content = newContent
        isDirty = true
        
        if isFinal {
            activeDictationRange = nil
        } else {
            activeDictationRange = NSRange(location: range.location, length: (text as NSString).length)
        }
    }
}
