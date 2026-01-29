//
//  ErrorMessageMapper.swift
//  MindCanvas
//
//  错误信息映射器，将技术错误转换为用户友好的提示
//

import Foundation

struct ErrorMessageMapper {

    /// 将 APIError 转换为用户友好的错误信息
    static func userFriendlyMessage(for error: APIError) -> String {
        switch error {
        case .httpError(let statusCode, _):
            return httpErrorMessage(statusCode: statusCode)

        case .timeout:
            return "生成时间较长，请稍后在资源栏查看结果"

        case .generationFailed(let msg):
            return generationFailedMessage(originalMessage: msg)

        case .networkError:
            return "网络连接不稳定，请检查网络后重试"

        case .invalidAPIKey:
            return "API Key 无效，请检查配置"

        case .unauthorized:
            return "登录已过期，请重新登录"

        case .tokenExpired:
            return "登录已过期，请重新登录"

        default:
            return "操作失败，请稍后重试"
        }
    }

    /// HTTP 错误码映射
    private static func httpErrorMessage(statusCode: Int) -> String {
        switch statusCode {
        case 400:
            return "请求参数有误，请检查后重试"
        case 401:
            return "登录已过期，请重新登录"
        case 403:
            return "没有权限执行此操作"
        case 404:
            return "请求的资源不存在"
        case 429:
            return "请求过于频繁，请稍后重试"
        case 500:
            return "服务器开小差了，请稍后重试"
        case 502:
            return "服务暂时不可用，请稍后重试"
        case 503:
            return "服务暂时繁忙，请稍后重试"
        case 504:
            return "服务响应超时，请稍后重试"
        default:
            if statusCode >= 500 {
                return "服务器开小差了，请稍后重试"
            }
            return "网络请求失败，请检查网络后重试"
        }
    }

    /// 生成失败错误映射
    private static func generationFailedMessage(originalMessage: String) -> String {
        let lowercased = originalMessage.lowercased()

        if lowercased.contains("timeout") || lowercased.contains("timed out") {
            return "AI服务响应较慢，请稍后重试"
        }

        if lowercased.contains("503") || lowercased.contains("overloaded") || lowercased.contains("busy") {
            return "AI服务暂时繁忙，请稍后重试"
        }

        if lowercased.contains("rate limit") || lowercased.contains("429") || lowercased.contains("too many") {
            return "请求过于频繁，请稍后重试"
        }

        if lowercased.contains("api key") || lowercased.contains("invalid key") || lowercased.contains("401") {
            return "API Key 无效，请检查配置"
        }

        if lowercased.contains("safety") || lowercased.contains("blocked") || lowercased.contains("policy") {
            return "内容不符合安全规范，请修改提示词后重试"
        }

        return "生成失败，请稍后重试"
    }
}