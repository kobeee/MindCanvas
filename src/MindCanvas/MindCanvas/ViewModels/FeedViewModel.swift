import Foundation
import Observation

@Observable
@MainActor
final class FeedViewModel {
    var items: [FeedItem] = []
    var isLoading = false
    private var currentPage = 0
    
    private let feedService = MockFeedService.shared
    
    func loadFeed() async {
        guard !isLoading else { return }
        isLoading = true

        do {
            let newItems = try await feedService.fetchFeed(page: currentPage)
            items.append(contentsOf: newItems)
            currentPage += 1
        } catch {
        }

        isLoading = false
    }
    
    func refresh() async {
        items = []
        currentPage = 0
        await loadFeed()
    }
    
    func toggleLike(_ item: FeedItem) async {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        
        items[index].isLiked.toggle()
        
        do {
            if items[index].isLiked {
                try await feedService.likeImage(id: item.id)
            } else {
                try await feedService.unlikeImage(id: item.id)
            }
        } catch {
            items[index].isLiked.toggle()
            print("点赞失败: \(error)")
        }
    }
    
    func remixItem(_ item: FeedItem) {
        print("Remix: \(item.id)")
    }
}

