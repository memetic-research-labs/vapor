import Foundation
import SwiftData
import CryptoKit

@Model
final class PromptRecord {
    enum UsageReason: String, Codable {
        case copiedOriginal
        case compressedAndCopied
        case sentToBrowser
        case copiedAndCleared
        case draftSnapshot
    }

    var id: UUID
    var contentHash: String = ""
    var originalText: String
    var compressedText: String
    var originalTokenCount: Int
    var compressedTokenCount: Int
    var compressionRatio: Double
    var compressorUsed: String
    var createdAt: Date
    var modifiedAt: Date
    var lastUsedAt: Date?
    var useCount: Int
    var lastUsageReasonRaw: String?
    var isFavorite: Bool
    var tags: [String]
    var embeddingID: String?

    var project: VaporProject?
    
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
        self.lastUsedAt = nil
        self.useCount = 0
        self.lastUsageReasonRaw = nil
        self.isFavorite = false
        self.tags = []
        self.embeddingID = nil
    }

    var lastUsageReason: UsageReason? {
        get {
            guard let lastUsageReasonRaw else { return nil }
            return UsageReason(rawValue: lastUsageReasonRaw)
        }
        set {
            lastUsageReasonRaw = newValue?.rawValue
        }
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
