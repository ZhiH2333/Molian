-- 帖子可见性：title、is_public；post_communities 多对多（帖子-圈子）
-- 兼容旧数据：is_public 默认 1（全站可见）
ALTER TABLE posts ADD COLUMN title TEXT NOT NULL DEFAULT '';
ALTER TABLE posts ADD COLUMN is_public INTEGER NOT NULL DEFAULT 1;

CREATE INDEX IF NOT EXISTS idx_posts_public ON posts(is_public);

-- post_communities: 帖子与圈子多对多（community_id 即 realms.id）
CREATE TABLE IF NOT EXISTS post_communities (
  post_id TEXT NOT NULL,
  community_id TEXT NOT NULL,
  PRIMARY KEY (post_id, community_id),
  FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE,
  FOREIGN KEY (community_id) REFERENCES realms(id)
);

CREATE INDEX IF NOT EXISTS idx_pc_community ON post_communities(community_id);
CREATE INDEX IF NOT EXISTS idx_pc_post ON post_communities(post_id);
