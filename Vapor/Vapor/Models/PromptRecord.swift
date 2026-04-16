import Foundation
import SwiftData
import CryptoKit

@Model
final class PromptRecord {
    var id: UUID
    var contentHash: String
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
        self.contentHash = Self.makeContentHash(
            originalText: originalText,
            compressedText: compressedText,
            compressorUsed: compressorUsed.rawValue
        )
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

    var stableIdentifier: String {
        if !contentHash.isEmpty {
            return contentHash
        }
        return Self.makeContentHash(
            originalText: originalText,
            compressedText: compressedText,
            compressorUsed: compressorUsed
        )
    }

    var shortHash: String {
        String(stableIdentifier.prefix(8))
    }

    static func makeContentHash(
        originalText: String,
        compressedText: String,
        compressorUsed: String
    ) -> String {
        let payload = [originalText, compressedText, compressorUsed].joined(separator: "\u{001F}")
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
