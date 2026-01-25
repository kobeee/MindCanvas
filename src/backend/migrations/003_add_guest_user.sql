-- 创建游客用户
INSERT INTO users (id, email, username, auth_provider, created_at, updated_at)
VALUES (
    '00000000-0000-0000-0000-000000000000',
    'guest@mindcanvas.local',
    'Guest User',
    'guest',
    NOW(),
    NOW()
)
ON CONFLICT (id) DO NOTHING;
