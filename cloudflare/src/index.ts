/**
 * Molian API Worker
 * 入口：将请求交给 Hono 应用（/api/* 与 /messager/*）；/ws 转发至 ChatRoom Durable Object。
 */

import { verifyJwt } from "./auth/jwt";
import app from "./app";
import type { Env } from "./app";

export type { Env };

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
  "Access-Control-Max-Age": "86400",
};

/** 带 Authorization 的请求为“带凭证”请求，浏览器要求响应必须返回具体 Origin，不能为 *。 */
function getAllowOrigin(request: Request): string {
  const origin = request.headers.get("Origin");
  if (
    origin &&
    (origin.startsWith("http://localhost") ||
      origin.startsWith("http://127.0.0.1") ||
      origin.includes("molian.app") ||
      origin.includes("pages.dev"))
  ) {
    return origin;
  }
  return "*";
}

/** 为 API 响应统一加上基于请求 Origin 的 CORS 头，避免 web.molian.app 带凭证请求被浏览器拦截。 */
function withCors(request: Request, response: Response): Response {
  const allowOrigin = getAllowOrigin(request);
  const newHeaders = new Headers(response.headers);
  newHeaders.set("Access-Control-Allow-Origin", allowOrigin);
  for (const [k, v] of Object.entries(CORS_HEADERS)) newHeaders.set(k, v);
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers: newHeaders,
  });
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    if (request.method === "OPTIONS") {
      const allowOrigin = getAllowOrigin(request);
      return new Response(null, {
        status: 204,
        headers: {
          ...CORS_HEADERS,
          "Access-Control-Allow-Origin": allowOrigin,
        },
      });
    }
    const url = new URL(request.url);
    const pathname = url.pathname.replace(/\/$/, "") || "/";
    if (pathname === "/ws" || pathname === "/api/ws") {
      const id = env.CHAT.idFromName("default");
      const stub = env.CHAT.get(id);
      return stub.fetch(request);
    }
    if (pathname.startsWith("/broadcast/")) {
      const id = env.CHAT.idFromName("default");
      const stub = env.CHAT.get(id);
      return stub.fetch(request);
    }
    // /messager/chat/:roomId/broadcast 由 app.ts 内部调用，转发到 DO
    if (pathname.startsWith("/internal/chat/broadcast/")) {
      const roomId = pathname.replace("/internal/chat/broadcast/", "");
      const id = env.CHAT.idFromName("default");
      const stub = env.CHAT.get(id);
      return stub.fetch(request);
    }
    const response = await app.fetch(request, env, ctx);
    return withCors(request, response);
  },
};

/**
 * 聊天室 Durable Object（Hibernation API 版本）：
 *   - 接受 WebSocket（URL 带 token），用 userId 作为 tag
 *   - 收到 HTTP POST /broadcast/:roomId 时，查询 D1 获取房间成员，
 *     通过 ctx.getWebSockets(userId) 向所有在线成员推送消息
 *   - 不使用内存 Map（DO 休眠后内存会被清除，必须依赖 Hibernation API）
 *   - 支持 ping/pong 心跳
 *   - 支持输入状态（messages.typing）
 */
export class ChatRoom implements DurableObject {
  constructor(private ctx: DurableObjectState, private env: Env) {}

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    // 内部广播接口：POST /broadcast/:roomId
    if (request.method === "POST" && url.pathname.startsWith("/broadcast/")) {
      const roomId = decodeURIComponent(url.pathname.replace("/broadcast/", ""));
      const payload = await request.json() as Record<string, unknown>;
      await this.broadcastToRoom(roomId, payload);
      return Response.json({ ok: true });
    }

    const token = url.searchParams.get("token")?.trim();
    const secret = this.env.JWT_SECRET || "dev-secret-change-in-production";
    if (!token) {
      return new Response(JSON.stringify({ error: "缺少 token" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }
    const jwtPayload = await verifyJwt(token, secret);
    if (!jwtPayload?.sub) {
      return new Response(JSON.stringify({ error: "token 无效" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }
    const userId = jwtPayload.sub;
    const upgrade = request.headers.get("Upgrade");
    if (upgrade !== "websocket") {
      return new Response(JSON.stringify({ message: "ChatRoom WS" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair) as [WebSocket, WebSocket];
    // 使用 Hibernation API：tag = userId，DO 休眠后仍可通过 getWebSockets(userId) 找到连接
    this.ctx.acceptWebSocket(server, [userId]);
    return new Response(null, {
      status: 101,
      webSocket: client,
      headers: { Upgrade: "websocket", Connection: "Upgrade" },
    });
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    // Hibernation API：通过 getTags 获取 userId，不依赖内存 Map
    const tags = this.ctx.getTags(ws);
    const userId = tags?.[0];
    if (!userId) return;
    const raw = typeof message === "string" ? message : new TextDecoder().decode(message);
    let data: {
      type?: string;
      chat_room_id?: string;
      is_typing?: boolean;
    };
    try {
      data = JSON.parse(raw) as typeof data;
    } catch {
      return;
    }
    switch (data.type) {
      case "ping":
        ws.send(JSON.stringify({ type: "pong" }));
        break;
      case "messages.typing":
        await this.handleTyping(userId, data.chat_room_id ?? "", data.is_typing ?? true);
        break;
      // subscribe/unsubscribe 不再需要，保留以兼容旧客户端，但为 no-op
      case "messages.subscribe":
      case "messages.unsubscribe":
        break;
    }
  }

  /**
   * 向指定房间的所有在线成员广播消息。
   * 每次广播都查询 D1 获取最新成员列表，再通过 Hibernation API 找到在线连接。
   * 即使 DO 重启或休眠过，也能正确广播。
   */
  private async broadcastToRoom(roomId: string, payload: Record<string, unknown>): Promise<void> {
    try {
      const { results } = await this.env.molian_db
        .prepare("SELECT user_id FROM chat_room_members WHERE room_id = ?")
        .bind(roomId)
        .all();
      const msg = JSON.stringify(payload);
      for (const row of results as { user_id: string }[]) {
        // getWebSockets(tag) 返回该 userId 对应的所有活跃 WebSocket（Hibernation API）
        const sockets = this.ctx.getWebSockets(row.user_id);
        for (const ws of sockets) {
          try {
            ws.send(msg);
          } catch (_) {
            // 连接已断开，忽略
          }
        }
      }
    } catch (e) {
      console.error("broadcastToRoom error:", e);
    }
  }

  /** 向房间内其他所有在线成员广播输入状态。 */
  private async handleTyping(userId: string, roomId: string, isTyping: boolean): Promise<void> {
    if (!roomId) return;
    const payload = JSON.stringify({
      type: "messages.typing",
      chat_room_id: roomId,
      user_id: userId,
      is_typing: isTyping,
    });
    try {
      const { results } = await this.env.molian_db
        .prepare("SELECT user_id FROM chat_room_members WHERE room_id = ? AND user_id != ?")
        .bind(roomId, userId)
        .all();
      for (const row of results as { user_id: string }[]) {
        const sockets = this.ctx.getWebSockets(row.user_id);
        for (const ws of sockets) {
          try {
            ws.send(payload);
          } catch (_) {}
        }
      }
    } catch (e) {
      console.error("handleTyping error:", e);
    }
  }

  async webSocketClose(_ws: WebSocket): Promise<void> {
    // Hibernation API 自动管理连接生命周期，无需手动清理内存 Map
  }

  async webSocketError(_ws: WebSocket): Promise<void> {
    // 同上
  }
}
