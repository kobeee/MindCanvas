import Foundation

@MainActor
final class MockFeedService {
    static let shared = MockFeedService()
    
    private init() {}
    
    private let mockAuthors = [
        User(id: "1", username: "艺术家小李", avatarUrl: nil, isPro: true),
        User(id: "2", username: "设计师王明", avatarUrl: nil, isPro: false),
        User(id: "3", username: "创意工作者", avatarUrl: nil, isPro: true),
        User(id: "4", username: "灵感收集者", avatarUrl: nil, isPro: false)
    ]
    
    private let mockPrompts = [
        "一只在月光下漫步的猫",
        "未来城市的天际线",
        "梦幻般的森林景观",
        "抽象的几何艺术",
        "宁静的海边日落"
    ]
    
    func fetchFeed(page: Int = 0) async throws -> [FeedItem] {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        return (0..<10).map { index -> FeedItem in
            let globalIndex = page * 10 + index
            return FeedItem(
                id: UUID().uuidString,
                imageUrl: "https://picsum.photos/\(Int.random(in: 400...800))/\(Int.random(in: 400...800))?random=\(globalIndex)",
                author: mockAuthors.randomElement() ?? mockAuthors[0],
                prompt: mockPrompts.randomElement(),
                showPrompt: Bool.random(),
                likesCount: Int.random(in: 0...999),
                createdAt: Date().addingTimeInterval(-Double.random(in: 0...86400*7))
            )
        }
    }
    
    func publishImage(imageUrl: String, title: String, prompt: String?, showPrompt: Bool) async throws {
        try await Task.sleep(nanoseconds: 1_000_000_000)
    }
    
    func likeImage(id: String) async throws {
        try await Task.sleep(nanoseconds: 500_000_000)
    }
    
    func unlikeImage(id: String) async throws {
        try await Task.sleep(nanoseconds: 500_000_000)
    }
}

