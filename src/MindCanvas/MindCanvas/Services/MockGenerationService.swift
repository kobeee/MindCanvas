import Foundation

struct GenerationRequest: Codable {
    let prompt: String
    let imageBase64: String?
    let model: String
}

struct GenerationResponse: Codable {
    let id: String
    let imageUrl: String
    let thumbnailUrl: String
    let prompt: String
}

@MainActor
final class MockGenerationService {
    static let shared = MockGenerationService()
    
    private init() {}
    
    private let mockImages = [
        "https://picsum.photos/800/600?random=1",
        "https://picsum.photos/800/600?random=2",
        "https://picsum.photos/800/600?random=3",
        "https://picsum.photos/800/600?random=4",
        "https://picsum.photos/800/600?random=5"
    ]
    
    func generate(request: GenerationRequest) async throws -> GenerationResponse {
        try await Task.sleep(nanoseconds: 3_000_000_000)
        
        let randomImage = mockImages.randomElement() ?? mockImages[0]
        
        return GenerationResponse(
            id: UUID().uuidString,
            imageUrl: randomImage,
            thumbnailUrl: randomImage,
            prompt: request.prompt
        )
    }
    
    func uploadImage(_ imageData: Data) async throws -> String {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        return "https://picsum.photos/800/600?random=\(Int.random(in: 100...999))"
    }
}

