-- 圈子创建者，用于「我创建的」筛选
ALTER TABLE realms ADD COLUMN creator_id TEXT REFERENCES users(id);
CREATE INDEX IF NOT EXISTS idx_realms_creator ON realms(creator_id);
