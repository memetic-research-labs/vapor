import Foundation

struct AttachedImage: Identifiable, Sendable {
    let id: UUID
    let assetId: UUID
    let shaPrefix: String
    let mimeType: String
    let webpPath: String
    let markdownReference: String
    let base64: String
}
