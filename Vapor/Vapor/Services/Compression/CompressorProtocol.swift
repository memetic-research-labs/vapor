import Foundation

struct CompressedResult {
    let text: String
    let originalTokens: Int
    let compressedTokens: Int
    let ratio: Double
    let compressorUsed: CompressorType
}

protocol Compressor {
    var name: String { get }
    var isAvailable: Bool { get async }
    
    func compress(_ text: String) async throws -> CompressedResult
}
