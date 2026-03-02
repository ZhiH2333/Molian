-- 帖子浏览量：用户刷到一次即增加一次
ALTER TABLE posts ADD COLUMN view_count INTEGER NOT NULL DEFAULT 0;
