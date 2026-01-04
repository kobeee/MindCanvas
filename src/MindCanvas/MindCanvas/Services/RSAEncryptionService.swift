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
            let publicKey: String?

            enum CodingKeys: String, CodingKey {
                case hasPublicKey = "has_public_key"
                case publicKey = "public_key"
            }
        }

        let decoder = JSONDecoder()
        let keyResponse = try decoder.decode(PublicKeyResponse.self, from: data)

        guard keyResponse.hasPublicKey, let publicKeyBase64 = keyResponse.publicKey else {
            throw RSAEncryptionError.invalidPublicKey
        }

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

        let base64Encoded = (encryptedData as Data).base64EncodedString()

        return base64Encoded
    }
    
    /// 从 Base64 字符串加载公钥
    private func loadPublicKey(fromBase64 base64: String) throws -> SecKey {
        // 解码 Base64 得到 PEM 格式的公钥
        guard let pemData = Data(base64Encoded: base64) else {
            throw RSAEncryptionError.invalidPublicKey
        }

        let pemString = String(data: pemData, encoding: .utf8) ?? ""

        // 从 PEM 格式提取 DER 格式的公钥数据
        // PEM 格式: -----BEGIN PUBLIC KEY-----\n<base64>\n-----END PUBLIC KEY-----
        let lines = pemString.components(separatedBy: "\n")
        var base64Lines: [String] = []

        var inKeySection = false
        for line in lines {
            if line.contains("-----BEGIN PUBLIC KEY-----") {
                inKeySection = true
                continue
            }
            if line.contains("-----END PUBLIC KEY-----") {
                inKeySection = false
                continue
            }
            if inKeySection && !line.isEmpty {
                base64Lines.append(line)
            }
        }

        let base64String = base64Lines.joined()
        guard let derData = Data(base64Encoded: base64String) else {
            throw RSAEncryptionError.invalidPublicKey
        }

        let options: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecReturnPersistentRef as String: false
        ]

        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(
            derData as CFData,
            options as CFDictionary,
            &error
        ) else {
            throw RSAEncryptionError.invalidPublicKey
        }

        return key
    }
}
