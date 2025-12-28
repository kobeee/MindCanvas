# MindCanvas 后端服务

MindCanvas 后端服务，提供用户认证、资源管理、社区功能和 AI 生图服务。

## 技术栈

- **Web 框架**: FastAPI 0.104.1
- **应用服务器**: Uvicorn 0.24.0
- **数据库**: PostgreSQL 15+
- **缓存/队列**: Redis 7+
- **ORM**: SQLAlchemy 2.0.23 (asyncio)
- **加密**: cryptography 41.0.7
- **HTTP 客户端**: httpx 0.25.2

## 项目结构

```
src/backend/
├── app/
│   ├── __init__.py
│   ├── main.py                 # FastAPI 应用入口
│   ├── config.py               # 配置管理
│   ├── models/                 # 数据模型
│   ├── routers/                # API 路由
│   ├── services/               # 业务逻辑服务
│   ├── database/               # 数据库连接
│   ├── utils/                  # 工具函数
│   └── storage/                # 存储服务
├── migrations/                 # 数据库迁移脚本
├── tests/                      # 测试代码
├── docker-compose.yml          # Docker Compose 配置
├── Dockerfile                  # Docker 镜像构建文件
├── requirements.txt            # Python 依赖
└── .env.example                # 环境变量示例
```

## 快速开始

### 1. 生成加密密钥

```bash
python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
```

### 2. 配置环境变量

```bash
cp .env.example .env
# 编辑 .env 文件，设置 ENCRYPTION_SECRET_KEY
```

### 3. 启动服务

使用 Docker Compose 一键启动：

```bash
docker-compose up -d
```

### 4. 查看日志

```bash
docker-compose logs -f backend
```

### 5. 停止服务

```bash
docker-compose down
```

## 本地开发

### 1. 创建虚拟环境

```bash
python -m venv venv
source venv/bin/activate  # Linux/Mac
# venv\Scripts\activate  # Windows
```

### 2. 安装依赖

```bash
pip install -r requirements.txt
```

### 3. 配置环境变量

```bash
cp .env.example .env
# 编辑 .env 文件
```

### 4. 启动数据库和 Redis

```bash
docker-compose up -d db redis
```

### 5. 运行应用

```bash
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

## API 文档

启动服务后，访问以下地址查看 API 文档：

- Swagger UI: http://localhost:8000/api/docs
- ReDoc: http://localhost:8000/api/redoc
- OpenAPI JSON: http://localhost:8000/api/openapi.json

## 数据库初始化

数据库表结构会在首次启动时自动通过 `migrations/001_init.sql` 初始化。

## 环境变量说明

| 变量名 | 说明 | 默认值 |
|--------|------|--------|
| DATABASE_URL | 数据库连接字符串 | postgresql://mindcanvas:mindcanvas@localhost:5432/mindcanvas |
| REDIS_URL | Redis 连接字符串 | redis://localhost:6379/0 |
| ENCRYPTION_SECRET_KEY | 加密密钥（必须设置） | - |
| JWT_SECRET_KEY | JWT 密钥 | your-jwt-secret-key-change-in-production |
| LOG_LEVEL | 日志级别 | INFO |
| IMAGE_STORAGE_PATH | 图片存储路径 | /app/storage/images |

## 开发规范

- 遵循 PEP 8 代码风格
- 使用类型提示
- 编写单元测试
- 使用异步编程
- API 接口使用 Pydantic 模型进行验证

## 安全注意事项

1. **生产环境必须修改默认密钥**：
   - `ENCRYPTION_SECRET_KEY`
   - `JWT_SECRET_KEY`

2. **API Key 安全**：
   - API Key 在传输、存储、使用全过程中加密
   - 任务完成后立即删除数据库中的 API Key

3. **HTTPS**：
   - 生产环境必须使用 HTTPS
   - 配置 SSL 证书

4. **速率限制**：
   - 限制 API 调用频率
   - 防止滥用

## 故障排查

### 数据库连接失败

检查数据库服务是否启动：

```bash
docker-compose ps db
```

查看数据库日志：

```bash
docker-compose logs db
```

### Redis 连接失败

检查 Redis 服务是否启动：

```bash
docker-compose ps redis
```

查看 Redis 日志：

```bash
docker-compose logs redis
```

### 应用启动失败

查看应用日志：

```bash
docker-compose logs backend
```

检查环境变量是否正确配置。

## 联系方式

如有问题，请联系开发团队。