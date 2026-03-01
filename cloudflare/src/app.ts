/**
 * Hono 应用：聚合 /api 路由，与 Flutter 模块一一对应。
 * /cgi/im 为 IM 协议（scope/alias → channel_id）REST 接口。
 */

import { Hono } from "hono";
import { hashPassword, verifyPassword } from "./auth/password";
import { signJwt, verifyJwt } from "./auth/jwt";
import {
  generateRefreshToken,
  sha256Hex,
  uuid,
  REFRESH_TOKEN_EXPIRY_SECONDS,
} from "./auth/refresh";
import im from "./im/routes";

export interface Env {
  molian_db: D1Database;
  ASSETS: R2Bucket;
  CHAT: DurableObjectNamespace;
  JWT_SECRET: string;
}

const CORS_ALLOW_METHODS = "GET, POST, PUT, PATCH, DELETE, OPTIONS";
const CORS_ALLOW_HEADERS = "Content-Type, Authorization";

/** 允许的 Origin 前缀（本地开发 + 生产）；其余用 *。 */
function getAllowedOrigin(requestOrigin: string | null): string {
  if (!requestOrigin) return "*";
  try {
    const o = new URL(requestOrigin);
    if (o.hostname === "localhost" || o.hostname === "127.0.0.1") return requestOrigin;
    if (o.hostname.endsWith(".molian.app") || o.hostname === "molian.app") return requestOrigin;
    if (o.hostname.endsWith(".pages.dev")) return requestOrigin;
  } catch {
    return "*";
  }
  return "*";
}

function corsHeaders(origin?: string | null): HeadersInit {
  const allowOrigin = origin !== undefined ? getAllowedOrigin(origin) : "*";
  return {
    "Access-Control-Allow-Origin": allowOrigin,
    "Access-Control-Allow-Methods": CORS_ALLOW_METHODS,
    "Access-Control-Allow-Headers": CORS_ALLOW_HEADERS,
    "Access-Control-Max-Age": "86400",
  };
}

async function getUserIdFromRequest(c: { req: Request; env: Env }): Promise<string | null> {
  const auth = c.req.header("Authorization");
  const token = auth?.startsWith("Bearer ") ? auth.slice(7) : "";
  if (!token) return null;
  const secret = c.env.JWT_SECRET || "dev-secret-change-in-production";
  const payload = await verifyJwt(token, secret);
  return payload ? payload.sub : null;
}

function getSecret(env: Env): string {
  return env.JWT_SECRET || "dev-secret-change-in-production";
}

const app = new Hono<{ Bindings: Env }>();

app.use("*", async (c, next) => {
  if (c.req.method === "OPTIONS") {
    const origin = c.req.header("Origin");
    return new Response(null, { status: 204, headers: corsHeaders(origin) });
  }
  await next();
});

app.get("/", (c) => c.json({ ok: true }, 200, corsHeaders()));
app.get("/health", (c) => c.json({ ok: true }, 200, corsHeaders()));

// IM 协议：/cgi/im/channels/:scope/:alias/...（与说明文档对齐）
app.route("/cgi/im", im);

// ----- Auth -----
app.post("/api/auth/register", async (c) => {
  const env = c.env;
  const secret = getSecret(env);
  try {
    const body = (await c.req.json()) as { username?: string; password?: string; displayName?: string };
    const username = String(body?.username ?? "").trim().toLowerCase();
    const password = String(body?.password ?? "");
    const displayName = (body?.displayName as string)?.trim() || username;
    if (!username || username.length < 2) return c.json({ error: "用户名至少 2 个字符" }, 400, corsHeaders());
    if (!password || password.length < 6) return c.json({ error: "密码至少 6 个字符" }, 400, corsHeaders());
    const { hashHex, saltBase64 } = await hashPassword(password);
    const id = uuid();
    await env.molian_db.prepare(
      "INSERT INTO users (id, username, password_hash, salt, display_name) VALUES (?, ?, ?, ?, ?)"
    )
      .bind(id, username, hashHex, saltBase64, displayName)
      .run();
    const token = await signJwt({ sub: id }, secret);
    let refreshToken: string | undefined;
    try {
      refreshToken = generateRefreshToken();
      const tokenHash = await sha256Hex(refreshToken);
      const expiresAt = new Date(Date.now() + REFRESH_TOKEN_EXPIRY_SECONDS * 1000).toISOString().replace("T", " ").slice(0, 19);
      await env.molian_db.prepare(
        "INSERT INTO refresh_tokens (id, user_id, token_hash, expires_at) VALUES (?, ?, ?, ?)"
      )
        .bind(uuid(), id, tokenHash, expiresAt)
        .run();
    } catch (_) {
      // refresh_tokens 表可能未迁移，仅跳过 refresh_token，仍返回 token 与 user
    }
    const row = await env.molian_db.prepare(
      "SELECT id, username, display_name, avatar_url, bio, created_at FROM users WHERE id = ?"
    )
      .bind(id)
      .first();
    return c.json({ token, ...(refreshToken && { refresh_token: refreshToken }), user: row }, 200, corsHeaders());
  } catch (e: unknown) {
    const msg = e && typeof (e as { message?: string }).message === "string" ? (e as { message: string }).message : String(e);
    console.error("Register error:", msg);
    if (msg.includes("UNIQUE") || msg.includes("unique")) return c.json({ error: "用户名已存在" }, 409, corsHeaders());
    return c.json({ error: "注册失败: " + msg }, 500, corsHeaders());
  }
});

app.post("/api/auth/login", async (c) => {
  const env = c.env;
  const secret = getSecret(env);
  try {
    const body = (await c.req.json()) as { username?: string; password?: string };
    const username = String(body?.username ?? "").trim().toLowerCase();
    const password = String(body?.password ?? "");
    if (!username || !password) return c.json({ error: "用户名和密码必填" }, 400, corsHeaders());
    const row = await env.molian_db.prepare(
      "SELECT id, username, password_hash, salt, display_name, avatar_url, bio, created_at FROM users WHERE username = ?"
    )
      .bind(username)
      .first();
    if (!row || typeof row !== "object") return c.json({ error: "用户名或密码错误" }, 401, corsHeaders());
    const r = row as Record<string, unknown>;
    const ok = await verifyPassword(password, String(r.salt), String(r.password_hash));
    if (!ok) return c.json({ error: "用户名或密码错误" }, 401, corsHeaders());
    const token = await signJwt({ sub: String(r.id) }, secret);
    let refreshToken: string | undefined;
    try {
      refreshToken = generateRefreshToken();
      const tokenHash = await sha256Hex(refreshToken);
      const expiresAt = new Date(Date.now() + REFRESH_TOKEN_EXPIRY_SECONDS * 1000).toISOString().replace("T", " ").slice(0, 19);
      await env.molian_db.prepare(
        "INSERT INTO refresh_tokens (id, user_id, token_hash, expires_at) VALUES (?, ?, ?, ?)"
      )
        .bind(uuid(), String(r.id), tokenHash, expiresAt)
        .run();
    } catch (_) {
      // refresh_tokens 表可能未迁移，仅跳过 refresh_token
    }
    const user = {
      id: r.id,
      username: r.username,
      display_name: r.display_name,
      avatar_url: r.avatar_url,
      bio: r.bio,
      created_at: r.created_at,
    };
    return c.json({ token, ...(refreshToken && { refresh_token: refreshToken }), user }, 200, corsHeaders());
  } catch {
    return c.json({ error: "登录失败" }, 500, corsHeaders());
  }
});

app.get("/api/auth/me", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const row = await c.env.molian_db.prepare(
    "SELECT id, username, display_name, avatar_url, bio, created_at FROM users WHERE id = ?"
  )
    .bind(userId)
    .first();
  if (!row || typeof row !== "object") return c.json({ error: "用户不存在" }, 404, corsHeaders());
  return c.json({ user: row }, 200, corsHeaders());
});

app.post("/api/auth/refresh", async (c) => {
  const env = c.env;
  const secret = getSecret(env);
  try {
    const body = (await c.req.json()) as { refresh_token?: string };
    const refreshToken = String(body?.refresh_token ?? "").trim();
    if (!refreshToken) return c.json({ error: "refresh_token 必填" }, 400, corsHeaders());
    const tokenHash = await sha256Hex(refreshToken);
    const row = await env.molian_db.prepare(
      "SELECT id, user_id FROM refresh_tokens WHERE token_hash = ? AND expires_at > datetime('now')"
    )
      .bind(tokenHash)
      .first();
    if (!row || typeof row !== "object") return c.json({ error: "refresh token 无效或已过期" }, 401, corsHeaders());
    const r = row as { id: string; user_id: string };
    await env.molian_db.prepare("DELETE FROM refresh_tokens WHERE id = ?").bind(r.id).run();
    const token = await signJwt({ sub: r.user_id }, secret);
    const newRefreshToken = generateRefreshToken();
    const newHash = await sha256Hex(newRefreshToken);
    const expiresAt = new Date(Date.now() + REFRESH_TOKEN_EXPIRY_SECONDS * 1000).toISOString().replace("T", " ").slice(0, 19);
    await env.molian_db.prepare(
      "INSERT INTO refresh_tokens (id, user_id, token_hash, expires_at) VALUES (?, ?, ?, ?)"
    )
      .bind(uuid(), r.user_id, newHash, expiresAt)
      .run();
    const userRow = await env.molian_db.prepare(
      "SELECT id, username, display_name, avatar_url, bio, created_at FROM users WHERE id = ?"
    )
      .bind(r.user_id)
      .first();
    return c.json({ token, refresh_token: newRefreshToken, user: userRow }, 200, corsHeaders());
  } catch (e) {
    console.error("Refresh error:", e);
    return c.json({ error: "刷新失败" }, 500, corsHeaders());
  }
});

// ----- Users -----
app.patch("/api/users/me", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  try {
    const body = (await c.req.json()) as { display_name?: string; bio?: string; avatar_url?: string };
    const updates: string[] = [];
    const values: unknown[] = [];
    if (body?.display_name !== undefined) {
      updates.push("display_name = ?");
      values.push(String(body.display_name).trim());
    }
    if (body?.bio !== undefined) {
      updates.push("bio = ?");
      values.push(String(body.bio).trim());
    }
    if (body?.avatar_url !== undefined) {
      updates.push("avatar_url = ?");
      values.push(String(body.avatar_url).trim());
    }
    if (updates.length === 0) return c.json({ error: "无有效字段" }, 400, corsHeaders());
    values.push(userId);
    await c.env.molian_db.prepare(`UPDATE users SET ${updates.join(", ")} WHERE id = ?`).bind(...values).run();
    const row = await c.env.molian_db.prepare(
      "SELECT id, username, display_name, avatar_url, bio, created_at FROM users WHERE id = ?"
    )
      .bind(userId)
      .first();
    return c.json({ user: row }, 200, corsHeaders());
  } catch {
    return c.json({ error: "更新失败" }, 500, corsHeaders());
  }
});

app.get("/api/users/me/following", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const { results } = await c.env.molian_db.prepare(
    "SELECT u.id, u.username, u.display_name, u.avatar_url FROM users u INNER JOIN follows f ON f.following_id = u.id WHERE f.follower_id = ?"
  )
    .bind(userId)
    .all();
  return c.json({ users: results }, 200, corsHeaders());
});

app.get("/api/users/me/followers", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const { results } = await c.env.molian_db.prepare(
    "SELECT u.id, u.username, u.display_name, u.avatar_url FROM users u INNER JOIN follows f ON f.follower_id = u.id WHERE f.following_id = ?"
  )
    .bind(userId)
    .all();
  return c.json({ users: results }, 200, corsHeaders());
});

app.get("/api/users/search", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const q = String(c.req.query("q") ?? "").trim();
  if (!q) return c.json({ users: [] }, 200, corsHeaders());
  try {
    const pattern = `%${q}%`;
    const { results } = await c.env.molian_db.prepare(
      "SELECT id, username, display_name, avatar_url FROM users WHERE (username LIKE ? OR display_name LIKE ?) AND id != ? LIMIT 30"
    )
      .bind(pattern, pattern, userId)
      .all();
    return c.json({ users: results }, 200, corsHeaders());
  } catch (e) {
    console.error("users/search error:", e);
    return c.json({ error: "搜索失败，请稍后重试" }, 500, corsHeaders());
  }
});

app.get("/api/users/me/friends", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  try {
    await ensureFriendRequestTables(c.env.molian_db);
    const { results } = await c.env.molian_db.prepare(
      `SELECT u.id, u.username, u.display_name, u.avatar_url
       FROM friend_requests fr
       JOIN users u ON u.id = CASE WHEN fr.requester_id = ? THEN fr.target_id ELSE fr.requester_id END
       WHERE (fr.requester_id = ? OR fr.target_id = ?) AND fr.status = 'accepted'`
    )
      .bind(userId, userId, userId)
      .all();
    return c.json({ friends: results }, 200, corsHeaders());
  } catch (e) {
    console.error("users/me/friends GET error:", e);
    const msg = e && typeof (e as { message?: string }).message === "string" ? (e as { message: string }).message : String(e);
    if (msg.includes("no such table") || msg.includes("friend_requests")) return c.json({ error: "服务未就绪" }, 503, corsHeaders());
    return c.json({ error: "获取失败" }, 500, corsHeaders());
  }
});

app.delete("/api/users/me/friends/:id", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const friendId = c.req.param("id");
  try {
    await ensureFriendRequestTables(c.env.molian_db);
    const result = await c.env.molian_db.prepare(
      "UPDATE friend_requests SET status = 'removed' WHERE ((requester_id = ? AND target_id = ?) OR (requester_id = ? AND target_id = ?)) AND status = 'accepted'"
    )
      .bind(userId, friendId, friendId, userId)
      .run();
    const rowsWritten = (result as { meta?: { rows_written?: number } }).meta?.rows_written ?? 0;
    if (rowsWritten === 0) return c.json({ error: "不是好友或已删除" }, 404, corsHeaders());
    return c.json({}, 200, corsHeaders());
  } catch (e) {
    console.error("users/me/friends DELETE error:", e);
    return c.json({ error: "删除失败" }, 500, corsHeaders());
  }
});

// ----- Posts -----
const postsSelectColumns =
  "p.id, p.user_id, p.title, p.content, p.image_urls, p.is_public, p.created_at, p.updated_at, u.username, u.display_name, u.avatar_url";
const postsPublicWhere = "p.is_public = 1";

app.get("/api/posts", async (c) => {
  const env = c.env;
  const limit = Math.min(Number(c.req.query("limit")) || 20, 100);
  const cursor = c.req.query("cursor") ?? "";
  const userId = await getUserIdFromRequest(c);
  let results: Record<string, unknown>[];
  if (cursor) {
    const cursorRow = await env.molian_db.prepare("SELECT created_at FROM posts WHERE id = ?").bind(cursor).first();
    const cursorCreated = cursorRow && typeof cursorRow === "object" ? (cursorRow as Record<string, unknown>).created_at : null;
    if (cursorCreated) {
      const s = await env.molian_db.prepare(
        `SELECT ${postsSelectColumns} FROM posts p JOIN users u ON p.user_id = u.id WHERE ${postsPublicWhere} AND p.created_at < ? ORDER BY p.created_at DESC LIMIT ?`
      )
        .bind(cursorCreated, limit)
        .all();
      results = s.results as Record<string, unknown>[];
    } else {
      const s = await env.molian_db.prepare(
        `SELECT ${postsSelectColumns} FROM posts p JOIN users u ON p.user_id = u.id WHERE ${postsPublicWhere} ORDER BY p.created_at DESC LIMIT ?`
      )
        .bind(limit)
        .all();
      results = s.results as Record<string, unknown>[];
    }
  } else {
    const s = await env.molian_db.prepare(
      `SELECT ${postsSelectColumns} FROM posts p JOIN users u ON p.user_id = u.id WHERE ${postsPublicWhere} ORDER BY p.created_at DESC LIMIT ?`
    )
      .bind(limit)
      .all();
    results = s.results as Record<string, unknown>[];
  }
  const posts = await Promise.all(
    results.map(async (r) => {
      const postId = r.id as string;
      const likeCount = (await env.molian_db.prepare("SELECT COUNT(*) as c FROM post_likes WHERE post_id = ?").bind(postId).first()) as { c: number };
      let liked = false;
      if (userId) {
        const l = await env.molian_db.prepare("SELECT 1 FROM post_likes WHERE post_id = ? AND user_id = ?").bind(postId, userId).first();
        liked = !!l;
      }
      const commentCount = (await env.molian_db.prepare("SELECT COUNT(*) as c FROM comments WHERE post_id = ?").bind(postId).first()) as { c: number };
      return {
        id: r.id,
        user_id: r.user_id,
        title: r.title,
        content: r.content,
        image_urls: r.image_urls,
        is_public: r.is_public,
        created_at: r.created_at,
        updated_at: r.updated_at,
        like_count: likeCount?.c ?? 0,
        liked,
        comment_count: commentCount?.c ?? 0,
        user: { username: r.username, display_name: r.display_name, avatar_url: r.avatar_url },
      };
    })
  );
  const nextCursor = posts.length === limit && posts.length > 0 ? (posts[posts.length - 1] as { id?: unknown }).id : null;
  return c.json({ posts, nextCursor }, 200, corsHeaders());
});

app.post("/api/posts", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  try {
    const body = (await c.req.json()) as {
      content?: string;
      image_urls?: string[];
      title?: string;
      is_public?: boolean;
      community_ids?: string[];
    };
    const content = String(body?.content ?? "").trim();
    if (!content) return c.json({ error: "内容不能为空" }, 400, corsHeaders());
    const title = String(body?.title ?? "").trim();
    const isPublic = body?.is_public !== false ? 1 : 0;
    const communityIds = Array.isArray(body?.community_ids) ? (body.community_ids as string[]) : [];
    if (communityIds.length > 0) {
      for (const rid of communityIds) {
        const realm = await c.env.molian_db.prepare("SELECT id FROM realms WHERE id = ?").bind(rid).first();
        if (!realm) return c.json({ error: `圈子不存在: ${rid}` }, 400, corsHeaders());
      }
    }
    const imageUrls = Array.isArray(body?.image_urls) ? (body.image_urls as string[]) : [];
    const imageUrlsJson = JSON.stringify(imageUrls);
    const id = uuid();
    await c.env.molian_db.prepare(
      "INSERT INTO posts (id, user_id, title, content, image_urls, is_public, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, datetime('now'), datetime('now'))"
    )
      .bind(id, userId, title || (content.split("\n")[0] ?? content), content, imageUrlsJson, isPublic)
      .run();
    for (const communityId of communityIds) {
      await c.env.molian_db.prepare(
        "INSERT OR IGNORE INTO post_communities (post_id, community_id) VALUES (?, ?)"
      )
        .bind(id, communityId)
        .run();
    }
    const row = await c.env.molian_db.prepare(
      "SELECT p.id, p.user_id, p.title, p.content, p.image_urls, p.is_public, p.created_at, p.updated_at, u.username, u.display_name, u.avatar_url FROM posts p JOIN users u ON p.user_id = u.id WHERE p.id = ?"
    )
      .bind(id)
      .first();
    return c.json({ post: row }, 200, corsHeaders());
  } catch {
    return c.json({ error: "发布失败" }, 500, corsHeaders());
  }
});

app.get("/api/posts/:id", async (c) => {
  const id = c.req.param("id");
  const row = await c.env.molian_db.prepare(
    `SELECT ${postsSelectColumns} FROM posts p JOIN users u ON p.user_id = u.id WHERE p.id = ?`
  )
    .bind(id)
    .first();
  if (!row || typeof row !== "object") return c.json({ error: "帖子不存在" }, 404, corsHeaders());
  const r = row as Record<string, unknown>;
  return c.json(
    {
      post: {
        id: r.id,
        user_id: r.user_id,
        title: r.title,
        content: r.content,
        image_urls: r.image_urls,
        is_public: r.is_public,
        created_at: r.created_at,
        updated_at: r.updated_at,
        user: { username: r.username, display_name: r.display_name, avatar_url: r.avatar_url },
      },
    },
    200,
    corsHeaders()
  );
});

app.patch("/api/posts/:id", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const id = c.req.param("id");
  const row = (await c.env.molian_db.prepare("SELECT user_id FROM posts WHERE id = ?").bind(id).first()) as { user_id: string } | null;
  if (!row) return c.json({ error: "帖子不存在" }, 404, corsHeaders());
  if (row.user_id !== userId) return c.json({ error: "只能编辑自己的帖子" }, 403, corsHeaders());
  const body = (await c.req.json()) as { content?: string; image_urls?: string[] };
  const content = body?.content !== undefined ? String(body.content).trim() : null;
  const imageUrls = Array.isArray(body?.image_urls) ? (body.image_urls as string[]) : null;
  if (content === null && imageUrls === null) return c.json({ error: "无有效更新字段" }, 400, corsHeaders());
  if (content !== null && !content) return c.json({ error: "内容不能为空" }, 400, corsHeaders());
  const updates: string[] = ["updated_at = datetime('now')"];
  const values: unknown[] = [];
  if (content !== null) {
    updates.push("content = ?");
    values.push(content);
  }
  if (imageUrls !== null) {
    updates.push("image_urls = ?");
    values.push(JSON.stringify(imageUrls));
  }
  values.push(id);
  await c.env.molian_db.prepare(`UPDATE posts SET ${updates.join(", ")} WHERE id = ?`).bind(...values).run();
  const updatedRow = (await c.env.molian_db.prepare(
    `SELECT ${postsSelectColumns} FROM posts p JOIN users u ON p.user_id = u.id WHERE p.id = ?`
  )
    .bind(id)
    .first()) as Record<string, unknown> | null;
  if (!updatedRow) return c.json({ error: "更新失败" }, 500, corsHeaders());
  const post = {
    id: updatedRow.id,
    user_id: updatedRow.user_id,
    title: updatedRow.title,
    content: updatedRow.content,
    image_urls: updatedRow.image_urls,
    is_public: updatedRow.is_public,
    created_at: updatedRow.created_at,
    updated_at: updatedRow.updated_at,
    user: { username: updatedRow.username, display_name: updatedRow.display_name, avatar_url: updatedRow.avatar_url },
  };
  return c.json({ post }, 200, corsHeaders());
});

// 删除帖子：级联删除该帖下所有回复（含子回复）、post_likes，以及仅被本帖引用的附件（图片）；被其他帖子引用的图片不删。
app.delete("/api/posts/:id", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const postId = c.req.param("id");
  try {
    const row = (await c.env.molian_db
      .prepare("SELECT user_id, image_urls FROM posts WHERE id = ?")
      .bind(postId)
      .first()) as { user_id: string; image_urls?: unknown } | null;
    if (!row) return c.json({ error: "帖子不存在" }, 404, corsHeaders());
    if (row.user_id !== userId) return c.json({ error: "只能删除自己的帖子" }, 403, corsHeaders());

    const parseImageUrls = (raw: unknown): string[] => {
      if (Array.isArray(raw)) return raw.map((v) => String(v)).filter((v) => v.trim().length > 0);
      if (typeof raw === "string") {
        const s = raw.trim();
        if (!s) return [];
        try {
          const parsed = JSON.parse(s);
          if (Array.isArray(parsed)) return parsed.map((v) => String(v)).filter((v) => v.trim().length > 0);
        } catch (_) {
          // ignore json parse error
        }
        return [s];
      }
      return [];
    };

    const extractAssetKey = (url: string): string | null => {
      const marker = "/api/asset/";
      const safeDecode = (s: string): string => {
        try {
          return decodeURIComponent(s);
        } catch (_) {
          return s;
        }
      };
      try {
        const u = url.startsWith("http://") || url.startsWith("https://")
          ? new URL(url)
          : new URL(url, "https://dummy.local");
        const pathname = u.pathname;
        const idx = pathname.indexOf(marker);
        if (idx < 0) return null;
        return safeDecode(pathname.slice(idx + marker.length));
      } catch (_) {
        const idx = url.indexOf(marker);
        if (idx < 0) return null;
        return safeDecode(url.slice(idx + marker.length));
      }
    };

    await c.env.molian_db.prepare("DELETE FROM post_likes WHERE post_id = ?").bind(postId).run();

    // 删除帖子下全部评论（包含回复树）。
    const { results: commentRows } = await c.env.molian_db
      .prepare("SELECT id, parent_id FROM comments WHERE post_id = ?")
      .bind(postId)
      .all();
    const childrenMap = new Map<string, string[]>();
    const roots: string[] = [];
    for (const r of commentRows as { id: string; parent_id?: string | null }[]) {
      const id = r.id;
      const parentId = r.parent_id ?? null;
      if (parentId && parentId.trim().length > 0) {
        const list = childrenMap.get(parentId) ?? [];
        list.push(id);
        childrenMap.set(parentId, list);
      } else {
        roots.push(id);
      }
      if (!childrenMap.has(id)) childrenMap.set(id, []);
    }
    const deleteCommentIds: string[] = [];
    const visited = new Set<string>();
    const visit = (id: string): void => {
      if (visited.has(id)) return;
      visited.add(id);
      for (const child of childrenMap.get(id) ?? []) visit(child);
      deleteCommentIds.push(id);
    };
    for (const id of roots) visit(id);
    // 兜底：处理异常孤儿节点（parent 不在本帖或数据异常）
    for (const r of commentRows as { id: string }[]) visit(r.id);
    const uniqueCommentIds = [...new Set(deleteCommentIds)];
    for (const id of uniqueCommentIds) {
      await c.env.molian_db.prepare("DELETE FROM comments WHERE id = ?").bind(id).run();
    }

    const imageUrls = parseImageUrls(row.image_urls);
    const postKeys = Array.from(
      new Set(
        imageUrls
          .map((url) => extractAssetKey(url))
          .filter((v): v is string => !!v && v.trim().length > 0)
      )
    );

    // 仅删除未被其它帖子复用的资源，避免误删共享图片。
    const { results: otherPostRows } = await c.env.molian_db
      .prepare("SELECT image_urls FROM posts WHERE id != ? AND image_urls IS NOT NULL")
      .bind(postId)
      .all();
    const usedByOthers = new Set<string>();
    for (const r of otherPostRows as { image_urls?: unknown }[]) {
      const urls = parseImageUrls(r.image_urls);
      for (const url of urls) {
        const key = extractAssetKey(url);
        if (key) usedByOthers.add(key);
      }
    }
    const deletableKeys = postKeys.filter((k) => !usedByOthers.has(k));

    for (const key of deletableKeys) {
      try {
        await c.env.ASSETS.delete(key);
      } catch (e) {
        console.error("delete asset error:", key, e);
      }
    }

    // 同步清理附件登记记录；老环境若无 files 表则忽略。
    if (deletableKeys.length > 0) {
      try {
        const placeholders = deletableKeys.map(() => "?").join(",");
        await c.env.molian_db
          .prepare(`DELETE FROM files WHERE key IN (${placeholders})`)
          .bind(...deletableKeys)
          .run();
      } catch (e) {
        const msg = e && typeof (e as { message?: string }).message === "string" ? (e as { message: string }).message : String(e);
        if (!msg.includes("no such table")) {
          console.error("delete files records error:", e);
        }
      }
    }

    await c.env.molian_db.prepare("DELETE FROM posts WHERE id = ?").bind(postId).run();
    return c.json(
      {
        deleted: true,
        deleted_comments: uniqueCommentIds.length,
        deleted_assets: deletableKeys.length,
        skipped_assets: postKeys.length - deletableKeys.length,
      },
      200,
      corsHeaders()
    );
  } catch (e) {
    console.error("delete post error:", e);
    return c.json({ error: "删除失败" }, 500, corsHeaders());
  }
});

app.post("/api/posts/:id/like", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const postId = c.req.param("id");
  await c.env.molian_db.prepare("INSERT OR IGNORE INTO post_likes (post_id, user_id) VALUES (?, ?)").bind(postId, userId).run();
  const count = (await c.env.molian_db.prepare("SELECT COUNT(*) as c FROM post_likes WHERE post_id = ?").bind(postId).first()) as { c: number };
  return c.json({ liked: true, count: count?.c ?? 0 }, 200, corsHeaders());
});

app.delete("/api/posts/:id/like", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const postId = c.req.param("id");
  await c.env.molian_db.prepare("DELETE FROM post_likes WHERE post_id = ? AND user_id = ?").bind(postId, userId).run();
  const count = (await c.env.molian_db.prepare("SELECT COUNT(*) as c FROM post_likes WHERE post_id = ?").bind(postId).first()) as { c: number };
  return c.json({ liked: false, count: count?.c ?? 0 }, 200, corsHeaders());
});

app.get("/api/posts/:id/likes", async (c) => {
  const userId = await getUserIdFromRequest(c);
  const postId = c.req.param("id");
  const count = (await c.env.molian_db.prepare("SELECT COUNT(*) as c FROM post_likes WHERE post_id = ?").bind(postId).first()) as { c: number };
  const liked = userId
    ? await c.env.molian_db.prepare("SELECT 1 FROM post_likes WHERE post_id = ? AND user_id = ?").bind(postId, userId).first()
    : null;
  return c.json({ count: count?.c ?? 0, liked: !!liked }, 200, corsHeaders());
});

app.get("/api/posts/:id/comments", async (c) => {
  const postId = c.req.param("id");
  const limit = Math.min(Number(c.req.query("limit")) || 20, 100);
  const { results } = await c.env.molian_db.prepare(
    "SELECT c.id, c.post_id, c.user_id, c.content, c.created_at, c.parent_id, u.username, u.display_name, u.avatar_url FROM comments c JOIN users u ON c.user_id = u.id WHERE c.post_id = ? ORDER BY c.created_at ASC LIMIT ?"
  )
    .bind(postId, limit)
    .all();
  const comments = (results as Record<string, unknown>[]).map((r) => ({
    id: r.id,
    post_id: r.post_id,
    user_id: r.user_id,
    content: r.content,
    created_at: r.created_at,
    parent_id: r.parent_id ?? null,
    user: { username: r.username, display_name: r.display_name, avatar_url: r.avatar_url },
  }));
  return c.json({ comments }, 200, corsHeaders());
});

app.post("/api/posts/:id/comments", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const postId = c.req.param("id");
  const body = (await c.req.json()) as { content?: string; parent_comment_id?: string };
  const content = String(body?.content ?? "").trim();
  if (!content) return c.json({ error: "内容不能为空" }, 400, corsHeaders());
  const parentId = body?.parent_comment_id ? String(body.parent_comment_id).trim() || null : null;
  const id = uuid();
  if (parentId) {
    const parentRow = await c.env.molian_db.prepare("SELECT id FROM comments WHERE id = ? AND post_id = ?").bind(parentId, postId).first();
    if (!parentRow) return c.json({ error: "被回复的评论不存在" }, 400, corsHeaders());
  }
  await c.env.molian_db
    .prepare("INSERT INTO comments (id, post_id, user_id, content, parent_id) VALUES (?, ?, ?, ?, ?)")
    .bind(id, postId, userId, content, parentId ?? null)
    .run();
  const row = (await c.env.molian_db.prepare(
    "SELECT c.id, c.post_id, c.user_id, c.content, c.created_at, c.parent_id, u.username, u.display_name, u.avatar_url FROM comments c JOIN users u ON c.user_id = u.id WHERE c.id = ?"
  )
    .bind(id)
    .first()) as Record<string, unknown> | null;
  const comment = row
    ? {
        id: row.id,
        post_id: row.post_id,
        user_id: row.user_id,
        content: row.content,
        created_at: row.created_at,
        parent_id: row.parent_id ?? null,
        user: { username: row.username, display_name: row.display_name, avatar_url: row.avatar_url },
      }
    : null;
  return c.json({ comment }, 200, corsHeaders());
});

app.delete("/api/posts/:postId/comments/:commentId", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const postId = c.req.param("postId");
  const commentId = c.req.param("commentId");
  const row = (await c.env.molian_db.prepare("SELECT user_id FROM comments WHERE id = ? AND post_id = ?").bind(commentId, postId).first()) as { user_id: string } | null;
  if (!row) return c.json({ error: "评论不存在" }, 404, corsHeaders());
  if (row.user_id !== userId) return c.json({ error: "只能删除自己的评论" }, 403, corsHeaders());

  // 递归删除该评论及其全部子回复，避免因 parent_id 外键导致删除失败。
  const queue: string[] = [commentId];
  const deleteIds: string[] = [];
  while (queue.length > 0) {
    const currentId = queue.shift() as string;
    deleteIds.push(currentId);
    const { results } = await c.env.molian_db.prepare("SELECT id FROM comments WHERE post_id = ? AND parent_id = ?").bind(postId, currentId).all();
    for (const child of results as { id: string }[]) {
      queue.push(child.id);
    }
  }
  for (let i = deleteIds.length - 1; i >= 0; i--) {
    await c.env.molian_db.prepare("DELETE FROM comments WHERE id = ?").bind(deleteIds[i]).run();
  }
  return c.json({ deleted: true, deleted_count: deleteIds.length }, 200, corsHeaders());
});

app.patch("/api/posts/:postId/comments/:commentId", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const postId = c.req.param("postId");
  const commentId = c.req.param("commentId");
  const row = (await c.env.molian_db.prepare("SELECT user_id FROM comments WHERE id = ? AND post_id = ?").bind(commentId, postId).first()) as { user_id: string } | null;
  if (!row) return c.json({ error: "评论不存在" }, 404, corsHeaders());
  if (row.user_id !== userId) return c.json({ error: "只能编辑自己的评论" }, 403, corsHeaders());
  const body = (await c.req.json()) as { content?: string };
  const content = String(body?.content ?? "").trim();
  if (!content) return c.json({ error: "内容不能为空" }, 400, corsHeaders());
  await c.env.molian_db.prepare("UPDATE comments SET content = ? WHERE id = ?").bind(content, commentId).run();
  const updated = (await c.env.molian_db.prepare(
    "SELECT c.id, c.post_id, c.user_id, c.content, c.created_at, c.parent_id, u.username, u.display_name, u.avatar_url FROM comments c JOIN users u ON c.user_id = u.id WHERE c.id = ?"
  )
    .bind(commentId)
    .first()) as Record<string, unknown> | null;
  if (!updated) return c.json({ error: "更新失败" }, 500, corsHeaders());
  const comment = {
    id: updated.id,
    post_id: updated.post_id,
    user_id: updated.user_id,
    content: updated.content,
    created_at: updated.created_at,
    parent_id: updated.parent_id ?? null,
    user: { username: updated.username, display_name: updated.display_name, avatar_url: updated.avatar_url },
  };
  return c.json({ comment }, 200, corsHeaders());
});

// ----- Follows -----
app.post("/api/follows", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const body = (await c.req.json()) as { following_id?: string };
  const followingId = String(body?.following_id ?? "").trim();
  if (!followingId || followingId === userId) return c.json({ error: "无效的 following_id" }, 400, corsHeaders());
  await c.env.molian_db.prepare("INSERT OR IGNORE INTO follows (follower_id, following_id) VALUES (?, ?)").bind(userId, followingId).run();
  return c.json({ followed: true }, 200, corsHeaders());
});

app.delete("/api/follows/:id", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const followingId = c.req.param("id");
  await c.env.molian_db.prepare("DELETE FROM follows WHERE follower_id = ? AND following_id = ?").bind(userId, followingId).run();
  return c.json({ followed: false }, 200, corsHeaders());
});

// ----- Friend requests -----
app.get("/api/friend-requests", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  try {
    await ensureFriendRequestTables(c.env.molian_db);
    const { results } = await c.env.molian_db.prepare(
      "SELECT fr.id, fr.requester_id, fr.target_id, fr.status, fr.created_at, u.username, u.display_name, u.avatar_url FROM friend_requests fr JOIN users u ON fr.requester_id = u.id WHERE fr.target_id = ? AND fr.status = 'pending' ORDER BY fr.created_at DESC"
    )
      .bind(userId)
      .all();
    return c.json({ friend_requests: results }, 200, corsHeaders());
  } catch (e) {
    console.error("friend-requests GET error:", e);
    const msg = e && typeof (e as { message?: string }).message === "string" ? (e as { message: string }).message : String(e);
    if (msg.includes("no such table") || msg.includes("friend_requests")) return c.json({ error: "服务未就绪" }, 503, corsHeaders());
    return c.json({ error: "获取失败" }, 500, corsHeaders());
  }
});

app.post("/api/friend-requests", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  try {
    await ensureFriendRequestTables(c.env.molian_db);
    const body = (await c.req.json()) as { target_id?: string };
    const targetId = String(body?.target_id ?? "").trim();
    if (!targetId || targetId === userId) return c.json({ error: "无效的 target_id" }, 400, corsHeaders());
    const existing = await c.env.molian_db.prepare(
      "SELECT id, status FROM friend_requests WHERE requester_id = ? AND target_id = ?"
    )
      .bind(userId, targetId)
      .first();
    if (existing && typeof existing === "object") {
      const status = (existing as { status: string }).status;
      if (status === "pending") return c.json({ error: "已发送过好友申请" }, 409, corsHeaders());
      if (status === "accepted") return c.json({ error: "已是好友" }, 409, corsHeaders());
      if (status === "rejected" || status === "removed") {
        const existingId = (existing as { id: string }).id;
        await c.env.molian_db
          .prepare(
            "UPDATE friend_requests SET status = 'pending', created_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = ?"
          )
          .bind(existingId)
          .run();
        const row = await c.env.molian_db
          .prepare("SELECT id, requester_id, target_id, status, created_at FROM friend_requests WHERE id = ?")
          .bind(existingId)
          .first();
        return c.json({ friend_request: row }, 201, corsHeaders());
      }
    }
    const id = uuid();
    await c.env.molian_db.prepare("INSERT INTO friend_requests (id, requester_id, target_id, status) VALUES (?, ?, ?, 'pending')").bind(id, userId, targetId).run();
    const row = await c.env.molian_db.prepare("SELECT id, requester_id, target_id, status, created_at FROM friend_requests WHERE id = ?").bind(id).first();
    return c.json({ friend_request: row }, 201, corsHeaders());
  } catch (e) {
    const msg = e && typeof (e as { message?: string }).message === "string" ? (e as { message: string }).message : String(e);
    console.error("friend-requests POST error:", msg);
    if (msg.includes("no such table") || msg.includes("friend_requests"))
      return c.json({ error: "服务未就绪，请先执行数据库迁移：wrangler d1 migrations apply molian-db --remote" }, 503, corsHeaders());
    return c.json({ error: "发送失败，请稍后重试" }, 500, corsHeaders());
  }
});

app.post("/api/friend-requests/:id/accept", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const requestId = c.req.param("id");
  try {
    await ensureFriendRequestTables(c.env.molian_db);
    const row = await c.env.molian_db.prepare(
      "SELECT id, requester_id, target_id, status FROM friend_requests WHERE id = ? AND target_id = ? AND status = 'pending'"
    )
      .bind(requestId, userId)
      .first();
    if (!row || typeof row !== "object") return c.json({ error: "申请不存在或已处理" }, 404, corsHeaders());
    const r = row as { requester_id: string; target_id: string };
    await c.env.molian_db.prepare("UPDATE friend_requests SET status = 'accepted' WHERE id = ?").bind(requestId).run();
    await c.env.molian_db.prepare("INSERT OR IGNORE INTO follows (follower_id, following_id) VALUES (?, ?)").bind(r.requester_id, r.target_id).run();
    await c.env.molian_db.prepare("INSERT OR IGNORE INTO follows (follower_id, following_id) VALUES (?, ?)").bind(r.target_id, r.requester_id).run();
    return c.json({ accepted: true }, 200, corsHeaders());
  } catch (e) {
    console.error("friend-requests accept error:", e);
    return c.json({ error: "操作失败" }, 500, corsHeaders());
  }
});

app.post("/api/friend-requests/:id/reject", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const requestId = c.req.param("id");
  try {
    await ensureFriendRequestTables(c.env.molian_db);
    const row = await c.env.molian_db.prepare(
      "SELECT id FROM friend_requests WHERE id = ? AND target_id = ? AND status = 'pending'"
    )
      .bind(requestId, userId)
      .first();
    if (!row || typeof row !== "object") return c.json({ error: "申请不存在或已处理" }, 404, corsHeaders());
    await c.env.molian_db.prepare("UPDATE friend_requests SET status = 'rejected' WHERE id = ?").bind(requestId).run();
    return c.json({ rejected: true }, 200, corsHeaders());
  } catch (e) {
    console.error("friend-requests reject error:", e);
    return c.json({ error: "操作失败" }, 500, corsHeaders());
  }
});

// ----- Messages -----
app.get("/api/messages", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const withUser = c.req.query("with_user") ?? "";
  const limit = Math.min(Number(c.req.query("limit")) || 50, 100);
  const cursor = c.req.query("cursor") ?? "";
  if (withUser) {
    const sql = cursor
      ? "SELECT id, sender_id, receiver_id, content, created_at, read FROM messages WHERE ((sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)) AND created_at < ? ORDER BY created_at DESC LIMIT ?"
      : "SELECT id, sender_id, receiver_id, content, created_at, read FROM messages WHERE (sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?) ORDER BY created_at DESC LIMIT ?";
    const bind = cursor ? [userId, withUser, withUser, userId, cursor, limit] : [userId, withUser, withUser, userId, limit];
    const { results } = await c.env.molian_db.prepare(sql).bind(userId, withUser, withUser, userId, ...(cursor ? [cursor, limit] : [limit])).all();
    return c.json({ messages: results }, 200, corsHeaders());
  }
  const { results: convList } = await c.env.molian_db.prepare(
    "SELECT DISTINCT CASE WHEN sender_id = ? THEN receiver_id ELSE sender_id END as peer_id FROM messages WHERE sender_id = ? OR receiver_id = ?"
  )
    .bind(userId, userId, userId)
    .all();
  const withLast = await Promise.all(
    (convList as { peer_id: string }[]).map(async (row) => {
      const peerId = row.peer_id;
      const [last, unread, peerRow] = await Promise.all([
        c.env.molian_db.prepare(
          "SELECT content, created_at FROM messages WHERE (sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?) ORDER BY created_at DESC LIMIT 1"
        )
          .bind(userId, peerId, peerId, userId)
          .first(),
        c.env.molian_db.prepare("SELECT COUNT(*) as c FROM messages WHERE receiver_id = ? AND sender_id = ? AND read = 0")
          .bind(userId, peerId)
          .first(),
        c.env.molian_db.prepare("SELECT username, display_name FROM users WHERE id = ?").bind(peerId).first(),
      ]);
      const unreadCount = (unread as { c: number })?.c ?? 0;
      const peer = peerRow as { username?: string; display_name?: string } | null;
      return {
        peer_id: peerId,
        peer_username: peer?.username ?? null,
        peer_display_name: peer?.display_name ?? null,
        last_content: (last as Record<string, unknown>)?.content,
        last_at: (last as Record<string, unknown>)?.created_at,
        unread_count: unreadCount,
      };
    })
  );
  return c.json({ conversations: withLast }, 200, corsHeaders());
});

app.post("/api/messages/mark-read", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const body = (await c.req.json()) as { with_user?: string };
  const withUser = String(body?.with_user ?? "").trim();
  if (!withUser) return c.json({ error: "with_user 必填" }, 400, corsHeaders());
  try {
    await c.env.molian_db.prepare("UPDATE messages SET read = 1 WHERE receiver_id = ? AND sender_id = ? AND read = 0")
      .bind(userId, withUser)
      .run();
    return c.json({ marked: true }, 200, corsHeaders());
  } catch (e) {
    console.error("messages/mark-read error:", e);
    return c.json({ error: "操作失败" }, 500, corsHeaders());
  }
});

app.post("/api/messages", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const body = (await c.req.json()) as { receiver_id?: string; content?: string };
  const receiverId = String(body?.receiver_id ?? "").trim();
  const content = String(body?.content ?? "").trim();
  if (!receiverId || !content) return c.json({ error: "receiver_id 和 content 必填" }, 400, corsHeaders());
  const id = uuid();
  await c.env.molian_db.prepare("INSERT INTO messages (id, sender_id, receiver_id, content, read) VALUES (?, ?, ?, ?, 0)").bind(id, userId, receiverId, content).run();
  const row = await c.env.molian_db.prepare("SELECT id, sender_id, receiver_id, content, created_at, read FROM messages WHERE id = ?").bind(id).first();
  return c.json({ message: row }, 200, corsHeaders());
});

// ----- Upload & asset -----
app.post("/api/upload", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const contentType = c.req.header("Content-Type") ?? "";
  if (!contentType.includes("multipart/form-data")) return c.json({ error: "需要 multipart/form-data" }, 400, corsHeaders());
  try {
    const formData = await c.req.formData();
    const file = formData.get("file") as File | null;
    if (!file) return c.json({ error: "缺少 file 字段" }, 400, corsHeaders());
    const ext = (file.name.split(".").pop() || "bin").slice(0, 4);
    const key = `assets/${userId}/${uuid()}.${ext}`;
    await c.env.ASSETS.put(key, file.stream(), { httpMetadata: { contentType: file.type || "application/octet-stream" } });
    const base = new URL(c.req.url).origin;
    return c.json({ url: `${base}/api/asset/${encodeURIComponent(key)}` }, 200, corsHeaders());
  } catch {
    return c.json({ error: "上传失败" }, 500, corsHeaders());
  }
});

// 使用 {.+} 确保整段 key（含 %2F 等编码）被捕获，decode 后与 R2 一致
app.get("/api/asset/:key{.+}", async (c) => {
  const raw = c.req.param("key");
  const key = decodeURIComponent(raw);
  const obj = await c.env.ASSETS.get(key);
  if (!obj) return new Response("Not Found", { status: 404, headers: corsHeaders() });
  const headers = new Headers(corsHeaders());
  if (obj.httpMetadata?.contentType) headers.set("Content-Type", obj.httpMetadata.contentType);
  return new Response(obj.body, { status: 200, headers });
});

// ----- Notifications -----
// 推送发送：可在此处或 Cron 中调 FCM HTTP v1 API（需服务端密钥），从 push_subscriptions 表取 fcm_token 下发。
app.get("/api/notifications", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const limit = Math.min(Number(c.req.query("limit")) || 20, 100);
  const cursor = c.req.query("cursor") ?? "";
  try {
    const sql = cursor
      ? "SELECT id, user_id, type, title, body, data, read, created_at FROM notifications WHERE user_id = ? AND created_at < ? ORDER BY created_at DESC LIMIT ?"
      : "SELECT id, user_id, type, title, body, data, read, created_at FROM notifications WHERE user_id = ? ORDER BY created_at DESC LIMIT ?";
    const bind = cursor ? [userId, cursor, limit] : [userId, limit];
    const { results } = await c.env.molian_db.prepare(sql).bind(...bind).all();
    const nextCursor =
      results.length === limit && results.length > 0 ? (results[results.length - 1] as Record<string, unknown>).created_at : null;
    return c.json({ notifications: results, nextCursor }, 200, corsHeaders());
  } catch (e) {
    console.error("notifications GET error:", e);
    const msg = e && typeof (e as { message?: string }).message === "string" ? (e as { message: string }).message : String(e);
    if (msg.includes("no such table")) return c.json({ error: "服务未就绪" }, 503, corsHeaders());
    return c.json({ error: "获取失败" }, 500, corsHeaders());
  }
});

app.post("/api/notifications/read", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const body = (await c.req.json()) as { id?: string; ids?: string[] };
  const id = body?.id;
  const ids = body?.ids as string[] | undefined;
  try {
    if (id) {
      await c.env.molian_db.prepare("UPDATE notifications SET read = 1 WHERE id = ? AND user_id = ?").bind(id, userId).run();
    } else if (ids && Array.isArray(ids) && ids.length > 0) {
      const placeholders = ids.map(() => "?").join(",");
      await c.env.molian_db.prepare(`UPDATE notifications SET read = 1 WHERE id IN (${placeholders}) AND user_id = ?`).bind(...ids, userId).run();
    } else {
      await c.env.molian_db.prepare("UPDATE notifications SET read = 1 WHERE user_id = ?").bind(userId).run();
    }
    return c.json({ ok: true }, 200, corsHeaders());
  } catch (e) {
    console.error("notifications read error:", e);
    return c.json({ error: "操作失败" }, 500, corsHeaders());
  }
});

app.post("/api/notifications/subscribe", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const body = (await c.req.json()) as { fcm_token?: string };
  const fcmToken = String(body?.fcm_token ?? "").trim();
  if (!fcmToken) return c.json({ error: "fcm_token 必填" }, 400, corsHeaders());
  try {
    const id = uuid();
    await c.env.molian_db.prepare(
      "INSERT INTO push_subscriptions (id, user_id, fcm_token) VALUES (?, ?, ?) ON CONFLICT(user_id, fcm_token) DO UPDATE SET fcm_token = excluded.fcm_token"
    ).bind(id, userId, fcmToken).run();
    return c.json({ subscribed: true }, 200, corsHeaders());
  } catch (e) {
    console.error("notifications subscribe error:", e);
    const msg = e && typeof (e as { message?: string }).message === "string" ? (e as { message: string }).message : String(e);
    if (msg.includes("no such table")) return c.json({ error: "服务未就绪" }, 503, corsHeaders());
    return c.json({ error: "订阅失败" }, 500, corsHeaders());
  }
});

// ----- Feeds（发现流，仅 is_public 帖子）-----
app.get("/api/feeds", async (c) => {
  const env = c.env;
  const limit = Math.min(Number(c.req.query("limit")) || 20, 100);
  const cursor = c.req.query("cursor") ?? "";
  const userId = await getUserIdFromRequest(c);
  let results: Record<string, unknown>[];
  if (cursor) {
    const cursorRow = await env.molian_db.prepare("SELECT created_at FROM posts WHERE id = ?").bind(cursor).first();
    const cursorCreated = cursorRow && typeof cursorRow === "object" ? (cursorRow as Record<string, unknown>).created_at : null;
    if (cursorCreated) {
      const s = await env.molian_db.prepare(
        `SELECT ${postsSelectColumns} FROM posts p JOIN users u ON p.user_id = u.id WHERE ${postsPublicWhere} AND p.created_at < ? ORDER BY p.created_at DESC LIMIT ?`
      )
        .bind(cursorCreated, limit)
        .all();
      results = s.results as Record<string, unknown>[];
    } else {
      const s = await env.molian_db.prepare(
        `SELECT ${postsSelectColumns} FROM posts p JOIN users u ON p.user_id = u.id WHERE ${postsPublicWhere} ORDER BY p.created_at DESC LIMIT ?`
      )
        .bind(limit)
        .all();
      results = s.results as Record<string, unknown>[];
    }
  } else {
    const s = await env.molian_db.prepare(
      `SELECT ${postsSelectColumns} FROM posts p JOIN users u ON p.user_id = u.id WHERE ${postsPublicWhere} ORDER BY p.created_at DESC LIMIT ?`
    )
      .bind(limit)
      .all();
    results = s.results as Record<string, unknown>[];
  }
  const posts = await Promise.all(
    results.map(async (r) => {
      const postId = r.id as string;
      const likeCount = (await env.molian_db.prepare("SELECT COUNT(*) as c FROM post_likes WHERE post_id = ?").bind(postId).first()) as { c: number };
      let liked = false;
      if (userId) {
        const l = await env.molian_db.prepare("SELECT 1 FROM post_likes WHERE post_id = ? AND user_id = ?").bind(postId, userId).first();
        liked = !!l;
      }
      const commentCount = (await env.molian_db.prepare("SELECT COUNT(*) as c FROM comments WHERE post_id = ?").bind(postId).first()) as { c: number };
      return {
        id: r.id,
        user_id: r.user_id,
        title: r.title,
        content: r.content,
        image_urls: r.image_urls,
        is_public: r.is_public,
        created_at: r.created_at,
        updated_at: r.updated_at,
        like_count: likeCount?.c ?? 0,
        liked,
        comment_count: commentCount?.c ?? 0,
        user: { username: r.username, display_name: r.display_name, avatar_url: r.avatar_url },
      };
    })
  );
  const nextCursor = posts.length === limit && posts.length > 0 ? (posts[posts.length - 1] as { id?: unknown }).id : null;
  return c.json({ posts, nextCursor }, 200, corsHeaders());
});

// ----- Realms -----
app.get("/api/realms", async (c) => {
  try {
    const { results } = await c.env.molian_db.prepare(
      "SELECT id, name, slug, description, avatar_url, created_at FROM realms ORDER BY created_at DESC LIMIT 50"
    ).all();
    return c.json({ realms: results }, 200, corsHeaders());
  } catch (e) {
    const msg = e && typeof (e as { message?: string }).message === "string" ? (e as { message: string }).message : String(e);
    if (msg.includes("no such table")) return c.json({ realms: [] }, 200, corsHeaders());
    return c.json({ error: "获取失败" }, 500, corsHeaders());
  }
});

app.get("/api/realms/:id", async (c) => {
  const id = c.req.param("id");
  const row = await c.env.molian_db.prepare(
    "SELECT id, name, slug, description, avatar_url, created_at FROM realms WHERE id = ? OR slug = ?"
  )
    .bind(id, id)
    .first();
  if (!row || typeof row !== "object") return c.json({ error: "圈子不存在" }, 404, corsHeaders());
  return c.json({ realm: row }, 200, corsHeaders());
});

// 圈子页帖子列表：仅通过 post_communities 关联的帖子（含 only 与 public+圈子）
app.get("/api/realms/:id/posts", async (c) => {
  const realmId = c.req.param("id");
  const limit = Math.min(Number(c.req.query("limit")) || 20, 100);
  const cursor = c.req.query("cursor") ?? "";
  const userId = await getUserIdFromRequest(c);
  const realm = await c.env.molian_db.prepare("SELECT id FROM realms WHERE id = ? OR slug = ?").bind(realmId, realmId).first();
  if (!realm || typeof realm !== "object") return c.json({ error: "圈子不存在" }, 404, corsHeaders());
  const rid = (realm as { id: string }).id;
  let results: Record<string, unknown>[];
  if (cursor) {
    const cursorRow = await c.env.molian_db.prepare("SELECT p.created_at FROM posts p JOIN post_communities pc ON p.id = pc.post_id WHERE pc.community_id = ? AND p.id = ?").bind(rid, cursor).first();
    const cursorCreated = cursorRow && typeof cursorRow === "object" ? (cursorRow as Record<string, unknown>).created_at : null;
    if (cursorCreated) {
      const s = await c.env.molian_db.prepare(
        `SELECT ${postsSelectColumns} FROM posts p JOIN users u ON p.user_id = u.id JOIN post_communities pc ON p.id = pc.post_id WHERE pc.community_id = ? AND p.created_at < ? ORDER BY p.created_at DESC LIMIT ?`
      )
        .bind(rid, cursorCreated, limit)
        .all();
      results = s.results as Record<string, unknown>[];
    } else {
      const s = await c.env.molian_db.prepare(
        `SELECT ${postsSelectColumns} FROM posts p JOIN users u ON p.user_id = u.id JOIN post_communities pc ON p.id = pc.post_id WHERE pc.community_id = ? ORDER BY p.created_at DESC LIMIT ?`
      )
        .bind(rid, limit)
        .all();
      results = s.results as Record<string, unknown>[];
    }
  } else {
    const s = await c.env.molian_db.prepare(
      `SELECT ${postsSelectColumns} FROM posts p JOIN users u ON p.user_id = u.id JOIN post_communities pc ON p.id = pc.post_id WHERE pc.community_id = ? ORDER BY p.created_at DESC LIMIT ?`
    )
      .bind(rid, limit)
      .all();
    results = s.results as Record<string, unknown>[];
  }
  const posts = await Promise.all(
    results.map(async (r) => {
      const postId = r.id as string;
      const likeCount = (await c.env.molian_db.prepare("SELECT COUNT(*) as c FROM post_likes WHERE post_id = ?").bind(postId).first()) as { c: number };
      let liked = false;
      if (userId) {
        const l = await c.env.molian_db.prepare("SELECT 1 FROM post_likes WHERE post_id = ? AND user_id = ?").bind(postId, userId).first();
        liked = !!l;
      }
      const commentCount = (await c.env.molian_db.prepare("SELECT COUNT(*) as c FROM comments WHERE post_id = ?").bind(postId).first()) as { c: number };
      return {
        id: r.id,
        user_id: r.user_id,
        title: r.title,
        content: r.content,
        image_urls: r.image_urls,
        is_public: r.is_public,
        created_at: r.created_at,
        updated_at: r.updated_at,
        like_count: likeCount?.c ?? 0,
        liked,
        comment_count: commentCount?.c ?? 0,
        user: { username: r.username, display_name: r.display_name, avatar_url: r.avatar_url },
      };
    })
  );
  const nextCursor = posts.length === limit && posts.length > 0 ? (posts[posts.length - 1] as { id?: unknown }).id : null;
  return c.json({ posts, nextCursor }, 200, corsHeaders());
});

app.post("/api/realms/:id/join", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const realmId = c.req.param("id");
  try {
    await c.env.molian_db.prepare(
      "INSERT OR IGNORE INTO realm_members (realm_id, user_id, role) VALUES (?, ?, 'member')"
    ).bind(realmId, userId).run();
    return c.json({ joined: true }, 200, corsHeaders());
  } catch (e) {
    const msg = e && typeof (e as { message?: string }).message === "string" ? (e as { message: string }).message : String(e);
    if (msg.includes("no such table")) return c.json({ error: "服务未就绪" }, 503, corsHeaders());
    return c.json({ error: "加入失败" }, 500, corsHeaders());
  }
});

app.post("/api/realms/:id/leave", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const realmId = c.req.param("id");
  try {
    await c.env.molian_db.prepare("DELETE FROM realm_members WHERE realm_id = ? AND user_id = ?").bind(realmId, userId).run();
    return c.json({ left: true }, 200, corsHeaders());
  } catch (e) {
    const msg = e && typeof (e as { message?: string }).message === "string" ? (e as { message: string }).message : String(e);
    if (msg.includes("no such table")) return c.json({ error: "服务未就绪" }, 503, corsHeaders());
    return c.json({ error: "退出失败" }, 500, corsHeaders());
  }
});

// ----- Files -----
app.get("/api/files", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  try {
    const { results } = await c.env.molian_db.prepare(
      "SELECT id, user_id, key, name, size, mime_type, created_at FROM files WHERE user_id = ? ORDER BY created_at DESC LIMIT 100"
    )
      .bind(userId)
      .all();
    return c.json({ files: results }, 200, corsHeaders());
  } catch (e) {
    const msg = e && typeof (e as { message?: string }).message === "string" ? (e as { message: string }).message : String(e);
    if (msg.includes("no such table")) return c.json({ files: [] }, 200, corsHeaders());
    return c.json({ error: "获取失败" }, 500, corsHeaders());
  }
});

app.post("/api/files/confirm", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const body = (await c.req.json()) as { key?: string; name?: string; size?: number; mime_type?: string };
  const key = String(body?.key ?? "").trim();
  const name = String(body?.name ?? "").trim();
  if (!key) return c.json({ error: "key 必填" }, 400, corsHeaders());
  const id = uuid();
  const size = Number(body?.size) || 0;
  const mimeType = (body?.mime_type as string) ?? null;
  const displayName = name || key.split("/").pop() || key;
  try {
    await c.env.molian_db.prepare(
      "INSERT INTO files (id, user_id, key, name, size, mime_type) VALUES (?, ?, ?, ?, ?, ?)"
    )
      .bind(id, userId, key, displayName, size, mimeType)
      .run();
    const row = await c.env.molian_db.prepare(
      "SELECT id, user_id, key, name, size, mime_type, created_at FROM files WHERE id = ?"
    )
      .bind(id)
      .first();
    return c.json({ file: row }, 201, corsHeaders());
  } catch (e) {
    const msg = e && typeof (e as { message?: string }).message === "string" ? (e as { message: string }).message : String(e);
    if (msg.includes("no such table")) return c.json({ error: "服务未就绪" }, 503, corsHeaders());
    return c.json({ error: "登记失败" }, 500, corsHeaders());
  }
});

// ----- Messager: 房间制聊天 -----

// 聊天相关 DB 表初始化（首次调用时自动建表）。
// D1 的 exec() 每次只支持一条语句，需逐条执行。
async function ensureChatTables(db: D1Database): Promise<void> {
  // 使用 prepare().run() 逐条执行 DDL，避免 exec() 在 D1 生产环境中的不稳定问题
  const ddlStatements = [
    `CREATE TABLE IF NOT EXISTS chat_rooms (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      type TEXT NOT NULL DEFAULT 'direct',
      description TEXT,
      avatar_url TEXT,
      member_count INTEGER DEFAULT 0,
      last_message_at TEXT,
      created_at TEXT DEFAULT (datetime('now'))
    )`,
    `CREATE TABLE IF NOT EXISTS chat_room_members (
      id TEXT PRIMARY KEY,
      room_id TEXT NOT NULL,
      user_id TEXT NOT NULL,
      role TEXT NOT NULL DEFAULT 'member',
      joined_at TEXT DEFAULT (datetime('now')),
      UNIQUE(room_id, user_id)
    )`,
    `CREATE TABLE IF NOT EXISTS chat_room_messages (
      id TEXT PRIMARY KEY,
      room_id TEXT NOT NULL,
      sender_id TEXT NOT NULL,
      content TEXT NOT NULL DEFAULT '',
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now')),
      deleted_at TEXT,
      nonce TEXT,
      reply_id TEXT,
      forwarded_id TEXT,
      attachments TEXT NOT NULL DEFAULT '[]',
      reactions TEXT NOT NULL DEFAULT '{}',
      meta TEXT
    )`,
    `CREATE INDEX IF NOT EXISTS idx_chat_room_messages_room ON chat_room_messages (room_id, created_at)`,
    `CREATE INDEX IF NOT EXISTS idx_chat_room_messages_nonce ON chat_room_messages (nonce)`,
  ];
  for (const sql of ddlStatements) {
    try {
      await db.prepare(sql).run();
    } catch (_) {
      // 表/索引已存在时忽略错误，继续执行后续语句
    }
  }
}

// 好友申请表初始化（首次调用时自动建表）。
async function ensureFriendRequestTables(db: D1Database): Promise<void> {
  const ddlStatements = [
    `CREATE TABLE IF NOT EXISTS friend_requests (
      id TEXT PRIMARY KEY,
      requester_id TEXT NOT NULL,
      target_id TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
      UNIQUE(requester_id, target_id)
    )`,
    `CREATE INDEX IF NOT EXISTS idx_friend_requests_target ON friend_requests(target_id)`,
    `CREATE INDEX IF NOT EXISTS idx_friend_requests_requester ON friend_requests(requester_id)`,
  ];
  for (const sql of ddlStatements) {
    try {
      await db.prepare(sql).run();
    } catch (_) {
      // 表/索引已存在时忽略错误，继续执行后续语句
    }
  }
}

/** 将 SQLite datetime('now') 格式转为 ISO8601，便于客户端正确解析时间（避免 00:00）。 */
function toIsoIfNeeded(s: unknown): unknown {
  if (s == null || typeof s !== "string") return s;
  const t = String(s).trim();
  if (t.includes("Z") || t.includes("+")) return t;
  const space = t.indexOf(" ");
  if (space <= 0) {
    if (/^\d{4}-\d{2}-\d{2}$/.test(t)) return t + "T12:00:00.000Z";
    return t;
  }
  const withT = t.slice(0, space) + "T" + t.slice(space + 1);
  return withT + (withT.includes(".") ? "" : ".000") + "Z";
}

async function buildMessageResponse(
  env: Env,
  row: Record<string, unknown>
): Promise<Record<string, unknown>> {
  const senderRow = await env.molian_db
    .prepare("SELECT id, username, display_name, avatar_url FROM users WHERE id = ?")
    .bind(row.sender_id)
    .first() as Record<string, unknown> | null;
  let replyMessage: Record<string, unknown> | null = null;
  if (row.reply_id) {
    const rr = await env.molian_db
      .prepare("SELECT * FROM chat_room_messages WHERE id = ?")
      .bind(row.reply_id)
      .first() as Record<string, unknown> | null;
    if (rr) {
      const rrSender = await env.molian_db
        .prepare("SELECT id, username, display_name, avatar_url FROM users WHERE id = ?")
        .bind(rr.sender_id)
        .first() as Record<string, unknown> | null;
      replyMessage = {
        ...rr,
        room_id: rr.room_id,
        created_at: toIsoIfNeeded(rr.created_at),
        updated_at: toIsoIfNeeded(rr.updated_at),
        deleted_at: toIsoIfNeeded(rr.deleted_at),
        attachments: JSON.parse(String(rr.attachments || "[]")),
        reactions: JSON.parse(String(rr.reactions || "{}")),
        sender: rrSender,
      };
    }
  }
  const nonce = row.nonce != null ? String(row.nonce) : null;
  return {
    id: row.id,
    room_id: row.room_id,
    sender_id: row.sender_id,
    content: row.content,
    created_at: toIsoIfNeeded(row.created_at),
    updated_at: toIsoIfNeeded(row.updated_at),
    deleted_at: toIsoIfNeeded(row.deleted_at),
    nonce,
    local_id: nonce,
    attachments: JSON.parse(String(row.attachments || "[]")),
    reactions: JSON.parse(String(row.reactions || "{}")),
    meta: row.meta ? JSON.parse(String(row.meta)) : null,
    reply_message: replyMessage,
    sender: senderRow ? {
      id: senderRow.id,
      username: senderRow.username,
      display_name: senderRow.display_name,
      avatar_url: senderRow.avatar_url,
    } : null,
  };
}

async function broadcastRoomMessage(
  env: Env,
  roomId: string,
  type: string,
  message: Record<string, unknown>
): Promise<void> {
  try {
    const id = env.CHAT.idFromName("default");
    const stub = env.CHAT.get(id);
    await stub.fetch(new Request(
      `https://internal/broadcast/${encodeURIComponent(roomId)}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ type, message }),
      }
    ));
  } catch (e) {
    console.error("broadcastRoomMessage error:", e);
  }
}

// GET /messager/chat - 获取用户所在的聊天房间列表（含 peer_id/members 便于客户端解析私信房间）
app.get("/messager/chat", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  try {
    await ensureChatTables(c.env.molian_db);
    const { results } = await c.env.molian_db
      .prepare(
        `SELECT r.id, r.name, r.type, r.description, r.avatar_url, r.member_count, r.last_message_at, r.created_at,
                (SELECT m2.user_id FROM chat_room_members m2
                 WHERE m2.room_id = r.id AND m2.user_id != ? LIMIT 1) as peer_id
         FROM chat_rooms r
         INNER JOIN chat_room_members m ON m.room_id = r.id AND m.user_id = ?
         ORDER BY COALESCE(r.last_message_at, r.created_at, '1970-01-01') DESC`
      )
      .bind(userId, userId)
      .all();
    const rooms = (results as Record<string, unknown>[]).map((row) => {
      const peerId = row.peer_id as string | null | undefined;
      const members = peerId
        ? [{ user_id: peerId }]
        : [];
      return {
        id: row.id,
        name: row.name,
        type: row.type,
        description: row.description,
        avatar_url: row.avatar_url,
        member_count: row.member_count,
        last_message_at: toIsoIfNeeded(row.last_message_at),
        created_at: toIsoIfNeeded(row.created_at),
        members,
      };
    });
    return c.json({ rooms }, 200, corsHeaders());
  } catch (e) {
    console.error("GET /messager/chat error:", e);
    return c.json({ error: "获取失败" }, 500, corsHeaders());
  }
});

// POST /messager/chat - 创建聊天房间
app.post("/messager/chat", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  try {
    await ensureChatTables(c.env.molian_db);
    const body = (await c.req.json()) as {
      name?: string;
      type?: string;
      description?: string;
      member_ids?: string[];
    };
    const name = String(body?.name ?? "").trim();
    if (!name) return c.json({ error: "name 必填" }, 400, corsHeaders());
    const type = body?.type === "group" ? "group" : "direct";
    const id = uuid();
    await c.env.molian_db
      .prepare(
        "INSERT INTO chat_rooms (id, name, type, description) VALUES (?, ?, ?, ?)"
      )
      .bind(id, name, type, body?.description ?? null)
      .run();
    await c.env.molian_db
      .prepare(
        "INSERT INTO chat_room_members (id, room_id, user_id, role) VALUES (?, ?, ?, 'owner')"
      )
      .bind(uuid(), id, userId)
      .run();
    const memberIds = Array.isArray(body?.member_ids) ? body.member_ids : [];
    for (const memberId of memberIds) {
      if (memberId !== userId) {
        await c.env.molian_db
          .prepare(
            "INSERT OR IGNORE INTO chat_room_members (id, room_id, user_id) VALUES (?, ?, ?)"
          )
          .bind(uuid(), id, memberId)
          .run();
      }
    }
    await c.env.molian_db
      .prepare("UPDATE chat_rooms SET member_count = (SELECT COUNT(*) FROM chat_room_members WHERE room_id = ?) WHERE id = ?")
      .bind(id, id)
      .run();
    const room = await c.env.molian_db
      .prepare("SELECT * FROM chat_rooms WHERE id = ?")
      .bind(id)
      .first();
    return c.json({ room }, 201, corsHeaders());
  } catch (e) {
    console.error("POST /messager/chat error:", e);
    return c.json({ error: "创建失败" }, 500, corsHeaders());
  }
});

// POST /messager/chat/direct/:peerId - 获取或创建与某用户的私信房间
app.post("/messager/chat/direct/:peerId", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const peerId = c.req.param("peerId");
  if (!peerId || peerId === userId) return c.json({ error: "无效的 peerId" }, 400, corsHeaders());
  try {
    await ensureChatTables(c.env.molian_db);
    // 查找已存在的私信房间
    const existing = await c.env.molian_db
      .prepare(
        `SELECT r.id, r.name, r.type, r.description, r.avatar_url, r.member_count, r.last_message_at, r.created_at
         FROM chat_rooms r
         INNER JOIN chat_room_members m1 ON m1.room_id = r.id AND m1.user_id = ?
         INNER JOIN chat_room_members m2 ON m2.room_id = r.id AND m2.user_id = ?
         WHERE r.type = 'direct' AND r.member_count = 2
         LIMIT 1`
      )
      .bind(userId, peerId)
      .first() as Record<string, unknown> | null;
    if (existing) return c.json({ room: existing }, 200, corsHeaders());
    // 创建新私信房间
    const peerUser = await c.env.molian_db
      .prepare("SELECT display_name, username FROM users WHERE id = ?")
      .bind(peerId)
      .first() as { display_name?: string; username?: string } | null;
    const peerName = peerUser?.display_name || peerUser?.username || peerId;
    const id = uuid();
    await c.env.molian_db
      .prepare("INSERT INTO chat_rooms (id, name, type, member_count) VALUES (?, ?, 'direct', 2)")
      .bind(id, peerName)
      .run();
    for (const uid of [userId, peerId]) {
      await c.env.molian_db
        .prepare("INSERT INTO chat_room_members (id, room_id, user_id) VALUES (?, ?, ?)")
        .bind(uuid(), id, uid)
        .run();
    }
    const room = await c.env.molian_db
      .prepare("SELECT * FROM chat_rooms WHERE id = ?")
      .bind(id)
      .first();
    return c.json({ room }, 201, corsHeaders());
  } catch (e) {
    console.error("POST /messager/chat/direct error:", e);
    return c.json({ error: "操作失败" }, 500, corsHeaders());
  }
});

// GET /messager/chat/:roomId - 获取房间详情
app.get("/messager/chat/:roomId", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const roomId = c.req.param("roomId");
  try {
    await ensureChatTables(c.env.molian_db);
    const member = await c.env.molian_db
      .prepare("SELECT 1 FROM chat_room_members WHERE room_id = ? AND user_id = ?")
      .bind(roomId, userId)
      .first();
    if (!member) return c.json({ error: "无权限" }, 403, corsHeaders());
    const room = await c.env.molian_db
      .prepare("SELECT * FROM chat_rooms WHERE id = ?")
      .bind(roomId)
      .first() as Record<string, unknown> | null;
    if (!room) return c.json({ error: "房间不存在" }, 404, corsHeaders());
    return c.json({ room }, 200, corsHeaders());
  } catch (e) {
    console.error("GET /messager/chat/:roomId error:", e);
    return c.json({ error: "获取失败" }, 500, corsHeaders());
  }
});

// GET /messager/chat/:roomId/messages - 分页获取消息
app.get("/messager/chat/:roomId/messages", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const roomId = c.req.param("roomId");
  const offset = Math.max(0, Number(c.req.query("offset")) || 0);
  const take = Math.min(100, Math.max(1, Number(c.req.query("take")) || 50));
  try {
    await ensureChatTables(c.env.molian_db);
    const member = await c.env.molian_db
      .prepare("SELECT 1 FROM chat_room_members WHERE room_id = ? AND user_id = ?")
      .bind(roomId, userId)
      .first();
    if (!member) return c.json({ error: "无权限" }, 403, corsHeaders());
    const { results } = await c.env.molian_db
      .prepare(
        "SELECT * FROM chat_room_messages WHERE room_id = ? ORDER BY created_at ASC LIMIT ? OFFSET ?"
      )
      .bind(roomId, take, offset)
      .all();
    const messages = await Promise.all(
      (results as Record<string, unknown>[]).map((r) => buildMessageResponse(c.env, r))
    );
    return c.json({ messages }, 200, corsHeaders());
  } catch (e) {
    console.error("GET /messager/chat/:roomId/messages error:", e);
    return c.json({ error: "获取失败" }, 500, corsHeaders());
  }
});

// POST /messager/chat/:roomId/messages - 发送消息
app.post("/messager/chat/:roomId/messages", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const roomId = c.req.param("roomId");
  try {
    await ensureChatTables(c.env.molian_db);
    const member = await c.env.molian_db
      .prepare("SELECT 1 FROM chat_room_members WHERE room_id = ? AND user_id = ?")
      .bind(roomId, userId)
      .first();
    if (!member) return c.json({ error: "无权限" }, 403, corsHeaders());
    const body = (await c.req.json()) as {
      content?: string;
      nonce?: string;
      attachments?: unknown[];
      reply_id?: string;
      forwarded_id?: string;
      meta?: unknown;
    };
    const content = String(body?.content ?? "").trim();
    const nonce = String(body?.nonce ?? "").trim();
    const attachments = JSON.stringify(Array.isArray(body?.attachments) ? body.attachments : []);
    const id = nonce.length > 0 ? nonce : uuid();
    await c.env.molian_db
      .prepare(
        `INSERT INTO chat_room_messages
          (id, room_id, sender_id, content, nonce, attachments, reply_id, forwarded_id, meta)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
      )
      .bind(
        id, roomId, userId, content,
        nonce.length > 0 ? nonce : null, attachments,
        body?.reply_id ?? null, body?.forwarded_id ?? null,
        body?.meta ? JSON.stringify(body.meta) : null
      )
      .run();
    await c.env.molian_db
      .prepare("UPDATE chat_rooms SET last_message_at = datetime('now') WHERE id = ?")
      .bind(roomId)
      .run();
    const row = await c.env.molian_db
      .prepare("SELECT * FROM chat_room_messages WHERE id = ?")
      .bind(id)
      .first() as Record<string, unknown> | null;
    if (!row) return c.json({ error: "发送失败" }, 500, corsHeaders());
    const message = await buildMessageResponse(c.env, row);
    await broadcastRoomMessage(c.env, roomId, "messages.new", message);
    return c.json({ message }, 200, corsHeaders());
  } catch (e) {
    console.error("POST /messager/chat/:roomId/messages error:", e);
    return c.json({ error: "发送失败" }, 500, corsHeaders());
  }
});

// PATCH /messager/chat/:roomId/messages/:messageId - 编辑消息
app.patch("/messager/chat/:roomId/messages/:messageId", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const roomId = c.req.param("roomId");
  const messageId = c.req.param("messageId");
  try {
    const row = await c.env.molian_db
      .prepare("SELECT sender_id FROM chat_room_messages WHERE id = ? AND room_id = ?")
      .bind(messageId, roomId)
      .first() as { sender_id: string } | null;
    if (!row) return c.json({ error: "消息不存在" }, 404, corsHeaders());
    if (row.sender_id !== userId) return c.json({ error: "只能编辑自己的消息" }, 403, corsHeaders());
    const body = (await c.req.json()) as { content?: string };
    const content = String(body?.content ?? "").trim();
    if (!content) return c.json({ error: "内容不能为空" }, 400, corsHeaders());
    await c.env.molian_db
      .prepare("UPDATE chat_room_messages SET content = ?, updated_at = datetime('now') WHERE id = ?")
      .bind(content, messageId)
      .run();
    const updated = await c.env.molian_db
      .prepare("SELECT * FROM chat_room_messages WHERE id = ?")
      .bind(messageId)
      .first() as Record<string, unknown> | null;
    if (!updated) return c.json({ error: "操作失败" }, 500, corsHeaders());
    const message = await buildMessageResponse(c.env, updated);
    await broadcastRoomMessage(c.env, roomId, "messages.update", message);
    return c.json({ message }, 200, corsHeaders());
  } catch (e) {
    console.error("PATCH /messager/chat/:roomId/messages/:messageId error:", e);
    return c.json({ error: "编辑失败" }, 500, corsHeaders());
  }
});

// DELETE /messager/chat/:roomId/messages/:messageId - 撤回消息（软删除）
app.delete("/messager/chat/:roomId/messages/:messageId", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const roomId = c.req.param("roomId");
  const messageId = c.req.param("messageId");
  try {
    const row = await c.env.molian_db
      .prepare("SELECT sender_id FROM chat_room_messages WHERE id = ? AND room_id = ?")
      .bind(messageId, roomId)
      .first() as { sender_id: string } | null;
    if (!row) return c.json({ error: "消息不存在" }, 404, corsHeaders());
    if (row.sender_id !== userId) return c.json({ error: "只能撤回自己的消息" }, 403, corsHeaders());
    await c.env.molian_db
      .prepare("UPDATE chat_room_messages SET deleted_at = datetime('now') WHERE id = ?")
      .bind(messageId)
      .run();
    await broadcastRoomMessage(c.env, roomId, "messages.delete", {
      message_id: messageId,
      room_id: roomId,
    });
    return c.json({ deleted: true }, 200, corsHeaders());
  } catch (e) {
    console.error("DELETE /messager/chat/:roomId/messages/:messageId error:", e);
    return c.json({ error: "撤回失败" }, 500, corsHeaders());
  }
});

// PUT /messager/chat/:roomId/messages/:messageId/reactions/:emoji - 添加反应
app.put("/messager/chat/:roomId/messages/:messageId/reactions/:emoji", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const roomId = c.req.param("roomId");
  const messageId = c.req.param("messageId");
  const emoji = decodeURIComponent(c.req.param("emoji"));
  try {
    const row = await c.env.molian_db
      .prepare("SELECT reactions FROM chat_room_messages WHERE id = ? AND room_id = ?")
      .bind(messageId, roomId)
      .first() as { reactions: string } | null;
    if (!row) return c.json({ error: "消息不存在" }, 404, corsHeaders());
    const reactions = JSON.parse(row.reactions || "{}") as Record<string, string[]>;
    if (!Array.isArray(reactions[emoji])) reactions[emoji] = [];
    if (!reactions[emoji].includes(userId)) reactions[emoji].push(userId);
    await c.env.molian_db
      .prepare("UPDATE chat_room_messages SET reactions = ? WHERE id = ?")
      .bind(JSON.stringify(reactions), messageId)
      .run();
    await broadcastRoomMessage(c.env, roomId, "messages.reaction.added", {
      message_id: messageId,
      room_id: roomId,
      emoji,
      user_id: userId,
    });
    return c.json({ ok: true }, 200, corsHeaders());
  } catch (e) {
    console.error("PUT reactions error:", e);
    return c.json({ error: "操作失败" }, 500, corsHeaders());
  }
});

// DELETE /messager/chat/:roomId/messages/:messageId/reactions/:emoji - 移除反应
app.delete("/messager/chat/:roomId/messages/:messageId/reactions/:emoji", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const roomId = c.req.param("roomId");
  const messageId = c.req.param("messageId");
  const emoji = decodeURIComponent(c.req.param("emoji"));
  try {
    const row = await c.env.molian_db
      .prepare("SELECT reactions FROM chat_room_messages WHERE id = ? AND room_id = ?")
      .bind(messageId, roomId)
      .first() as { reactions: string } | null;
    if (!row) return c.json({ error: "消息不存在" }, 404, corsHeaders());
    const reactions = JSON.parse(row.reactions || "{}") as Record<string, string[]>;
    if (Array.isArray(reactions[emoji])) {
      reactions[emoji] = reactions[emoji].filter((id) => id !== userId);
      if (reactions[emoji].length === 0) delete reactions[emoji];
    }
    await c.env.molian_db
      .prepare("UPDATE chat_room_messages SET reactions = ? WHERE id = ?")
      .bind(JSON.stringify(reactions), messageId)
      .run();
    await broadcastRoomMessage(c.env, roomId, "messages.reaction.removed", {
      message_id: messageId,
      room_id: roomId,
      emoji,
      user_id: userId,
    });
    return c.json({ ok: true }, 200, corsHeaders());
  } catch (e) {
    console.error("DELETE reactions error:", e);
    return c.json({ error: "操作失败" }, 500, corsHeaders());
  }
});

app.all("*", (c) => c.json({ error: "Not Found" }, 404, corsHeaders()));

export default app;
