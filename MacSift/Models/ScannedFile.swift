import Foundation

struct ScannedFile: Identifiable, Hashable, Sendable {
    let id: UUID
    let url: URL
    let size: Int64
    let category: FileCategory
    let description: String
    let modificationDate: Date
    let isDirectory: Bool

    init(
        url: URL,
        size: Int64,
        category: FileCategory,
        description: String,
        modificationDate: Date,
        isDirectory: Bool
    ) {
        self.id = UUID()
        self.url = url
        self.size = size
        self.category = category
        self.description = description
        self.modificationDate = modificationDate
        self.isDirectory = isDirectory
    }

    var name: String {
        url.lastPathComponent
    }

    var path: String {
        url.path(percentEncoded: false)
    }
}
