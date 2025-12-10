# MindCanvas

基于 AI 的创意绘图应用，专为 iPad 设计。

## 项目概述

MindCanvas 是一个集成了 AI 图像生成能力的创意工具，允许用户通过简单的画布操作和文字描述来创作独特的艺术作品。应用采用前后端分离架构，iOS 端使用 SwiftUI 构建现代化的用户界面。

## 技术栈

### iOS 客户端
- Swift 5.9+
- SwiftUI
- SwiftData
- WKWebView
- iPadOS 17.0+

### 后端（待开发）
- Python 3.11
- FastAPI
- PostgreSQL
- Redis
- Docker

## 项目结构

```
MindCanvas/
├── docs/                   # 文档
│   ├── prd/               # 产品需求文档
│   ├── design/            # 设计文档
│   └── archive/           # 归档文档
├── src/                   # 源代码
│   └── MindCanvas/        # iOS 项目
└── tests/                 # 测试代码
```

## 快速开始

### iOS 开发

1. 环境要求：
   - macOS 14.0+
   - Xcode 15.0+
   - iPad 模拟器或真机

2. 打开项目：
```bash
cd src/MindCanvas
open MindCanvas.xcodeproj
```

3. 选择 iPad 目标设备并运行（⌘R）

## 核心功能

- ✅ **身份认证**: 支持 Apple/Google/GitHub/邮箱多种登录方式
- ✅ **项目管理**: 创建、编辑、管理多个绘图项目
- ✅ **核心编辑器**: 三栏式编辑界面（资源库 + 画布 + 控制面板）
- ✅ **AI 生成**: 基于提示词生成图像（当前使用 Mock）
- ✅ **社区模块**: MindStream 灵感流，浏览和分享作品
- ✅ **订阅系统**: Pro 会员展示和订阅计划
- ✅ **设置中心**: 账号管理、配置和退出登录

## 开发状态

### 已完成 ✅
- iOS 客户端基础架构
- 所有核心模块的 UI 和交互
- Mock 服务层（模拟后端接口）
- SwiftData 本地数据持久化
- WebView 画布基础功能

### 进行中 🚧
- 真实后端 API 集成
- tldraw 完整画布集成
- IAP 订阅功能

### 待开发 📋
- 后端服务器
- 真实 AI 模型集成
- 图片下载功能
- Remix 完整流程
- 性能优化

## 文档

- [产品需求文档 (PRD)](docs/prd/v1.0.md)
- [iOS 架构设计](docs/design/ios_architecture.md)
- [后端架构设计](docs/design/backend_architecture.md)
- [开发记录](docs/archive/CHANGELOG.md)
- [iOS 客户端 README](src/MindCanvas/README.md)

## Mock 数据说明

**当前版本使用完全本地化的 Mock 数据**：
- 所有登录都会成功（邮箱验证码: `123456`）
- 图片生成使用 picsum.photos 随机图片
- 社区内容为随机生成
- 无需后端服务即可完整体验 UI 和交互

## 贡献指南

本项目目前处于初期开发阶段。如有建议或发现问题，欢迎提 Issue。

## 许可证

Copyright © 2025 MindCanvas. All rights reserved.

