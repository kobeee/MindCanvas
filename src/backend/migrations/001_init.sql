-- MindCanvas 数据库初始化脚本
-- 版本: 1.0.0
-- 创建日期: 2025-12-27

-- 启用 UUID 扩展
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ==================== 用户表 ====================
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    username VARCHAR(100),
    auth_provider VARCHAR(50) NOT NULL, -- 'apple', 'google', 'github', 'email'
    provider_id VARCHAR(255),
    avatar_url VARCHAR(500),
    refresh_token VARCHAR(500), -- 刷新令牌（30天有效期）
    refresh_token_expires_at TIMESTAMP WITH TIME ZONE, -- 刷新令牌过期时间
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 用户表索引
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_provider_id ON users(provider_id);
CREATE INDEX idx_users_refresh_token ON users(refresh_token);

-- ==================== 资源表 ====================
CREATE TABLE IF NOT EXISTS assets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    url VARCHAR(500) NOT NULL,
    type VARCHAR(50) NOT NULL, -- 'upload', 'generated'
    prompt TEXT,
    model_version VARCHAR(100),
    is_public BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 资源表索引
CREATE INDEX idx_assets_user_id ON assets(user_id);
CREATE INDEX idx_assets_type ON assets(type);
CREATE INDEX idx_assets_is_public ON assets(is_public);
CREATE INDEX idx_assets_created_at ON assets(created_at);

-- ==================== 社区动态表 ====================
CREATE TABLE IF NOT EXISTS feed_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    asset_id UUID NOT NULL REFERENCES assets(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(255),
    likes_count INTEGER DEFAULT 0,
    published_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 社区动态表索引
CREATE INDEX idx_feed_items_asset_id ON feed_items(asset_id);
CREATE INDEX idx_feed_items_user_id ON feed_items(user_id);
CREATE INDEX idx_feed_items_published_at ON feed_items(published_at);

-- ==================== 生图任务表 ====================
CREATE TABLE IF NOT EXISTS generation_tasks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status VARCHAR(50) NOT NULL, -- 'pending', 'processing', 'completed', 'failed'
    prompt TEXT NOT NULL,
    base_image TEXT,
    encrypted_api_key TEXT, -- 任务完成后删除
    image_url VARCHAR(500),
    image_expires_at TIMESTAMP WITH TIME ZONE, -- 图片过期时间（7天后自动清理）
    error_message TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 生图任务表索引
CREATE INDEX idx_generation_tasks_user_id ON generation_tasks(user_id);
CREATE INDEX idx_generation_tasks_status ON generation_tasks(status);
CREATE INDEX idx_generation_tasks_created_at ON generation_tasks(created_at);
CREATE INDEX idx_generation_tasks_image_expires_at ON generation_tasks(image_expires_at);

-- ==================== 举报表 ====================
CREATE TABLE IF NOT EXISTS reports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    feed_item_id UUID NOT NULL REFERENCES feed_items(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reason VARCHAR(100) NOT NULL,
    description TEXT,
    status VARCHAR(50) DEFAULT 'pending', -- 'pending', 'reviewed', 'resolved', 'dismissed'
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 举报表索引
CREATE INDEX idx_reports_feed_item_id ON reports(feed_item_id);
CREATE INDEX idx_reports_user_id ON reports(user_id);
CREATE INDEX idx_reports_status ON reports(status);

-- ==================== 更新时间触发器 ====================
-- 创建更新时间自动更新函数
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- 为所有表添加更新时间触发器
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_assets_updated_at BEFORE UPDATE ON assets
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_generation_tasks_updated_at BEFORE UPDATE ON generation_tasks
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ==================== 注释 ====================
COMMENT ON TABLE users IS '用户表';
COMMENT ON TABLE assets IS '资源/图片表';
COMMENT ON TABLE feed_items IS '社区动态表';
COMMENT ON TABLE generation_tasks IS '生图任务表';
COMMENT ON TABLE reports IS '举报表';

COMMENT ON COLUMN users.auth_provider IS '认证提供者: apple, google, github, email';
COMMENT ON COLUMN users.refresh_token IS '刷新令牌（30天有效期）';
COMMENT ON COLUMN users.refresh_token_expires_at IS '刷新令牌过期时间';
COMMENT ON COLUMN assets.type IS '资源类型: upload(上传), generated(AI生成)';
COMMENT ON COLUMN generation_tasks.status IS '任务状态: pending(待处理), processing(处理中), completed(已完成), failed(失败)';
COMMENT ON COLUMN generation_tasks.image_expires_at IS '图片过期时间（7天后自动清理）';
COMMENT ON COLUMN reports.status IS '举报状态: pending(待审核), reviewed(已审核), resolved(已解决), dismissed(已驳回)';