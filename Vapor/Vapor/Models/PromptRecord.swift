import Foundation
import SwiftData

@Model
final class PromptRecord {
    var id: UUID
    var originalText: String
    var compressedText: String
    var originalTokenCount: Int
    var compressedTokenCount: Int
    var compressionRatio: Double
    var compressorUsed: String
    var createdAt: Date
    var modifiedAt: Date
    var isFavorite: Bool
    var tags: [String]
    
    init(
        originalText: String,
        compressedText: String,
        originalTokenCount: Int,
        compressedTokenCount: Int,
        compressionRatio: Double,
        compressorUsed: CompressorType
    ) {
        self.id = UUID()
        self.originalText = originalText
        self.compressedText = compressedText
        self.originalTokenCount = originalTokenCount
        self.compressedTokenCount = compressedTokenCount
        self.compressionRatio = compressionRatio
        self.compressorUsed = compressorUsed.rawValue
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.isFavorite = false
        self.tags = []
    }
}
