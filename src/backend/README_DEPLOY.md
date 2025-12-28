# MindCanvas 后端部署指南

本文档介绍如何部署 MindCanvas 后端服务。

## 前提条件

- Docker 20.10+
- Docker Compose 2.0+
- 至少 2GB 可用内存
- 至少 10GB 可用磁盘空间

## 快速开始

### 1. 一键部署（推荐）

使用部署脚本一键部署：

```bash
cd src/backend
./deploy.sh
```

部署脚本会自动：
- 检查 Docker 和 Docker Compose 是否安装
- 创建 .env 文件（如果不存在）
- 生成加密密钥
- 创建存储目录
- 构建 Docker 镜像
- 启动所有服务

### 2. 手动部署

如果需要手动部署，请按照以下步骤：

#### 步骤 1：配置环境变量

```bash
cd src/backend
cp .env.example .env
```

编辑 .env 文件，配置以下参数：

```env
# 数据库密码（修改为强密码）
DATABASE_URL=postgresql://mindcanvas:your_secure_password@db:5432/mindcanvas

# 生成加密密钥
ENCRYPTION_SECRET_KEY=your_generated_secret_key_here

# JWT 密钥（修改为强密码）
JWT_SECRET_KEY=your-jwt-secret-key-change-in-production
```

#### 步骤 2：生成加密密钥

```bash
python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
```

将生成的密钥复制到 .env 文件的 ENCRYPTION_SECRET_KEY 参数。

#### 步骤 3：创建存储目录

```bash
mkdir -p storage/images/generated
mkdir -p storage/images/uploaded
```

#### 步骤 4：构建并启动服务

```bash
docker-compose build
docker-compose up -d
```

#### 步骤 5：检查服务状态

```bash
docker-compose ps
```

## 验证部署

### 1. 健康检查

```bash
curl http://localhost:8000/health
```

预期响应：

```json
{
  "status": "healthy",
  "timestamp": "2025-12-27T00:00:00.000000"
}
```

### 2. 查看 API 文档

访问：http://localhost:8000/docs

### 3. 查看日志

```bash
# 查看所有服务日志
docker-compose logs -f

# 查看后端服务日志
docker-compose logs -f backend

# 查看数据库日志
docker-compose logs -f db

# 查看 Redis 日志
docker-compose logs -f redis
```

## 常用命令

### 服务管理

```bash
# 启动服务
docker-compose up -d

# 停止服务
docker-compose down

# 重启服务
docker-compose restart

# 查看服务状态
docker-compose ps

# 查看资源使用情况
docker stats
```

### 日志管理

```bash
# 查看实时日志
docker-compose logs -f backend

# 查看最近 100 行日志
docker-compose logs --tail=100 backend

# 查看特定时间的日志
docker-compose logs --since="2025-12-27T00:00:00" backend
```

### 数据库管理

```bash
# 连接到数据库
docker-compose exec db psql -U mindcanvas -d mindcanvas

# 备份数据库
docker-compose exec db pg_dump -U mindcanvas mindcanvas > backup.sql

# 恢复数据库
docker-compose exec -T db psql -U mindcanvas mindcanvas < backup.sql
```

### Redis 管理

```bash
# 连接到 Redis
docker-compose exec redis redis-cli

# 清空 Redis 缓存
docker-compose exec redis redis-cli FLUSHALL
```

## 服务端点

部署完成后，以下端点将可用：

| 端点 | 说明 |
|------|------|
| http://localhost:8000 | 后端 API 根路径 |
| http://localhost:8000/health | 健康检查 |
| http://localhost:8000/docs | API 文档（Swagger UI） |
| http://localhost:8000/redoc | API 文档（ReDoc） |

**注意**：PostgreSQL (5432) 和 Redis (6379) 端口未暴露到宿主机，只能在 Docker 内部网络中访问。这是为了安全考虑，防止外部直接访问数据库和缓存服务。

## 生产环境部署建议

### 1. 安全加固

- 修改数据库密码
- 修改 JWT 密钥
- 修改加密密钥
- 启用 HTTPS
- 配置防火墙规则
- 限制访问 IP

### 2. 性能优化

- 调整数据库连接池大小
- 调整 Redis 内存限制
- 配置 CDN 加速图片访问
- 启用 Gzip 压缩
- 配置负载均衡

### 3. 监控和日志

- 配置日志收集（ELK Stack）
- 配置监控告警（Prometheus + Grafana）
- 配置性能监控（APM）
- 定期备份数据库

### 4. 高可用部署

- 使用负载均衡器
- 部署多个后端实例
- 配置数据库主从复制
- 配置 Redis 哨兵模式
- 使用对象存储（AWS S3 / Aliyun OSS）

## 故障排查

### 问题 1：服务无法启动

**症状**：docker-compose ps 显示服务状态为 Exit

**解决方案**：

```bash
# 查看日志
docker-compose logs backend

# 检查配置文件
cat .env

# 检查端口占用
lsof -i :8000
lsof -i :5432
lsof -i :6379
```

### 问题 2：数据库连接失败

**症状**：后端日志显示数据库连接错误

**解决方案**：

```bash
# 检查数据库是否启动
docker-compose ps db

# 检查数据库日志
docker-compose logs db

# 测试数据库连接
docker-compose exec db pg_isready -U mindcanvas

# 检查数据库密码
docker-compose exec db psql -U mindcanvas -d mindcanvas -c "SELECT version();"
```

### 问题 3：Redis 连接失败

**症状**：后端日志显示 Redis 连接错误

**解决方案**：

```bash
# 检查 Redis 是否启动
docker-compose ps redis

# 检查 Redis 日志
docker-compose logs redis

# 测试 Redis 连接
docker-compose exec redis redis-cli ping
```

### 问题 4：磁盘空间不足

**症状**：docker-compose build 失败，提示磁盘空间不足

**解决方案**：

```bash
# 清理未使用的 Docker 资源
docker system prune -a

# 清理未使用的镜像
docker image prune -a

# 清理未使用的容器
docker container prune

# 清理未使用的卷
docker volume prune
```

## 更新部署

### 1. 拉取最新代码

```bash
git pull origin main
```

### 2. 重新构建镜像

```bash
docker-compose build
```

### 3. 重启服务

```bash
docker-compose up -d
```

### 4. 验证更新

```bash
curl http://localhost:8000/health
```

## 卸载

### 1. 停止并删除所有服务

```bash
docker-compose down -v
```

### 2. 删除所有数据

```bash
# 删除存储目录
rm -rf storage

# 删除 Docker 卷
docker volume rm mindcanvas_postgres_data
```

### 3. 删除镜像

```bash
docker rmi mindcanvas_backend
```

## 支持

如有问题，请联系技术支持或查看文档：

- 项目文档：docs/design/backend/
- API 文档：http://localhost:8000/docs
- GitHub Issues：https://github.com/kobeee/MindCanvas/issues