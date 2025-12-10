import Foundation
import SwiftData

@Model
final class Project {
    @Attribute(.unique) var id: UUID
    var name: String
    var tldrawSnapshot: Data?
    var lastModified: Date
    var thumbnailUrl: String?
    
    init(id: UUID = UUID(), name: String, tldrawSnapshot: Data? = nil, thumbnailUrl: String? = nil) {
        self.id = id
        self.name = name
        self.tldrawSnapshot = tldrawSnapshot
        self.lastModified = Date()
        self.thumbnailUrl = thumbnailUrl
    }
}

