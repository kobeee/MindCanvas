-- MindCanvas 数据库迁移脚本
-- 版本: 1.1.0
-- 创建日期: 2026-01-22
-- 说明: 添加 Laozhang API 支持和配额管理功能

-- ==================== 添加 User 表字段 ====================
ALTER TABLE users ADD COLUMN IF NOT EXISTS api_provider VARCHAR(50) DEFAULT 'google';
ALTER TABLE users ADD COLUMN IF NOT EXISTS free_quota INTEGER DEFAULT 0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS total_quota_used INTEGER DEFAULT 0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS subscription_tier VARCHAR(50) DEFAULT 'free';
ALTER TABLE users ADD COLUMN IF NOT EXISTS subscription_expires_at TIMESTAMP WITH TIME ZONE;

-- 添加索引
CREATE INDEX IF NOT EXISTS idx_users_api_provider ON users(api_provider);
CREATE INDEX IF NOT EXISTS idx_users_subscription_tier ON users(subscription_tier);

-- ==================== 添加 generation_tasks 表字段 ====================
ALTER TABLE generation_tasks ADD COLUMN IF NOT EXISTS api_provider VARCHAR(50) DEFAULT 'google';
ALTER TABLE generation_tasks ADD COLUMN IF NOT EXISTS image_size VARCHAR(10) DEFAULT '1K';

-- 添加索引
CREATE INDEX IF NOT EXISTS idx_generation_tasks_api_provider ON generation_tasks(api_provider);

-- ==================== 创建邮箱配额配置表 ====================
CREATE TABLE IF NOT EXISTS email_quota_configs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    initial_quota INTEGER NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(100) DEFAULT 'admin'
);

-- 添加索引
CREATE INDEX IF NOT EXISTS idx_email_quota_configs_email ON email_quota_configs(email);

-- ==================== 注释 ====================
COMMENT ON COLUMN users.api_provider IS 'API 提供商: google, laozhang';
COMMENT ON COLUMN users.free_quota IS '免费额度（从 email_quota_configs 表读取）';
COMMENT ON COLUMN users.total_quota_used IS '总使用次数';
COMMENT ON COLUMN users.subscription_tier IS '订阅等级: free, pro, enterprise';
COMMENT ON COLUMN users.subscription_expires_at IS '订阅过期时间';

COMMENT ON COLUMN generation_tasks.api_provider IS '任务使用的 API 提供商: google, laozhang';
COMMENT ON COLUMN generation_tasks.image_size IS '生成的图片尺寸: 1K, 2K, 4K';

COMMENT ON TABLE email_quota_configs IS '邮箱配额配置表';
COMMENT ON COLUMN email_quota_configs.email IS '用户邮箱（唯一）';
COMMENT ON COLUMN email_quota_configs.initial_quota IS '初始配额（免费次数）';
COMMENT ON COLUMN email_quota_configs.created_by IS '创建者标识';

-- ==================== 数据迁移说明 ====================
-- 本迁移脚本添加了 Laozhang API 支持和配额管理功能
-- 不涉及数据迁移，所有新字段都有默认值
-- 现有用户默认使用 Google API，配额为 0