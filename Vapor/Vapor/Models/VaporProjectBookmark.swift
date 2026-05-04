import Foundation
import SwiftData

@Model
final class VaporProjectBookmark {
    var id: UUID
    var bookmarkData: Data
    var createdAt: Date

    var bookmark: VaporProject?

    init(bookmarkData: Data, bookmark: VaporProject? = nil) {
        self.id = UUID()
        self.bookmarkData = bookmarkData
        self.createdAt = Date()
        self.bookmark = bookmark
    }
}
