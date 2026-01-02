import Foundation
import Security
import CommonCrypto

/// RSA 加密错误
enum RSAEncryptionError: Error, LocalizedError {
    case invalidPublicKey
    case encryptionFailed(String)
    case base64EncodingFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidPublicKey:
            return "无效的公钥格式"
        case .encryptionFailed(let message):
            return "RSA 加密失败: \(message)"
        case .base64EncodingFailed:
            return "Base64 编码失败"
        }
    }
}

/// RSA 加密服务
/// 用于使用后端公钥加密 API Key
@MainActor
final class RSAEncryptionService {
    static let shared = RSAEncryptionService()
    
    private var cachedPublicKey: SecKey?
    
    private init() {}
    
    /// 从后端获取公钥并缓存
    func fetchAndCachePublicKey() async throws {
        guard let url = URL(string: "\(APIClient.shared.baseURL)/api/v1/users/public-key") else {
            throw RSAEncryptionError.invalidPublicKey
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw RSAEncryptionError.invalidPublicKey
        }
        
        struct PublicKeyResponse: Decodable {
            let hasPublicKey: Bool
        }
        
        let decoder = JSONDecoder()
        let keyResponse = try decoder.decode(PublicKeyResponse.self, from: data)
        
        guard keyResponse.hasPublicKey else {
            throw RSAEncryptionError.invalidPublicKey
        }
        
        // 从配置获取公钥
        let publicKeyBase64 = "LS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS0KTUlJQklqQU5CZ2txaGtpRzl3MEJBUUVGQUFPQ0FROEFNSUlCQ2dLQ0FRRUFxdmVhc2pTbXYzMFluMkJONkVzcApybWFTYks1WHorbFJQZjZSeW5EdnZWRDAxUVlYMTVmaThzK1RJZGhvMStTNGtibVQ0T1VpZTZJUEJpc1ZkeVFiCldXUGZNbXdmV0tVMCtDWEhzZzdFOXFHbzFETDEyOFlnWnA0SmdNUEVmUEEvMDVrR0h6YkpuQzRGcUQ4WUtIVXMKaVRXU3JnQ296K3RxYy9UUndXbEM0WDF1dUtzZWN2cXNNZmZsQmVUZVdiUmE5TjNDY2RYQTdOWSt1WWcwakFtSQp2Z284WHB4MVlTQXN6eXQwL2lpUVdkcW82UGcvNEtsK2QvYnhzeUxvY1dUMDhxdURlOHVnYklPaTB5eEVnUTNzCld0bUtqdVJhMXh5bVQxWnpTL1k2SjlIUkR1MThvMldGYWhLY3diOXdZWitTV1pRa0E0eEh5UlU4ZUJEcS92dHAKT1FJREFRQUIKLS0tLS1FTkQgUFVCTElDIEtFWS0tLS0tCg=="
        
        cachedPublicKey = try loadPublicKey(fromBase64: publicKeyBase64)
    }
    
    /// 使用 RSA-OAEP SHA-256 加密数据
    func encrypt(_ plaintext: String) async throws -> String {
        if cachedPublicKey == nil {
            try await fetchAndCachePublicKey()
        }
        
        guard let publicKey = cachedPublicKey else {
            throw RSAEncryptionError.invalidPublicKey
        }
        
        guard let plaintextData = plaintext.data(using: .utf8) else {
            throw RSAEncryptionError.encryptionFailed("无法将字符串转换为数据")
        }
        
        // 使用 SecKey 加密
        var error: Unmanaged<CFError>?
        guard let encryptedData = SecKeyCreateEncryptedData(
            publicKey,
            .rsaEncryptionOAEPSHA256,
            plaintextData as CFData,
            &error
        ) else {
            let errorMessage = error?.takeRetainedValue().localizedDescription ?? "未知错误"
            throw RSAEncryptionError.encryptionFailed(errorMessage)
        }
        
        // Base64 编码
        return (encryptedData as Data).base64EncodedString()
    }
    
    /// 从 Base64 字符串加载公钥
    private func loadPublicKey(fromBase64 base64: String) throws -> SecKey {
        guard let keyData = Data(base64Encoded: base64) else {
            throw RSAEncryptionError.invalidPublicKey
        }
        
        let options: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecReturnPersistentRef as String: false
        ]
        
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(
            keyData as CFData,
            options as CFDictionary,
            &error
        ) else {
            throw RSAEncryptionError.invalidPublicKey
        }
        
        return key
    }
}
