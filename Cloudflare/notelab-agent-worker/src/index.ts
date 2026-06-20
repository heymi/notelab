interface Env {
  AGENT_BEARER_TOKEN?: string;
  ORIGIN_AGENT_TOKEN?: string;
  ALLOW_WRITE?: string;
  RELAY: DurableObjectNamespace<NoteLabRelay>;
}

interface RelayRequest {
  id: string;
  method: string;
  path: string;
  headers: Record<string, string>;
  bodyBase64?: string;
}

interface RelayResponse {
  id: string;
  status: number;
  statusText?: string;
  headers?: Record<string, string>;
  bodyBase64?: string;
  error?: string;
}

const SERVICE = "notelab-cloud-agent";
const RELAY_NAME = "default";
const RELAY_TIMEOUT_MS = 60_000;
const MAX_BODY_BYTES = 8 * 1024 * 1024;
const HOP_BY_HOP_HEADERS = new Set([
  "connection",
  "keep-alive",
  "proxy-authenticate",
  "proxy-authorization",
  "te",
  "trailer",
  "transfer-encoding",
  "upgrade"
]);

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return withCors(new Response(null, { status: 204 }));
    }

    if (url.pathname === "/health") {
      const relay = env.RELAY.get(env.RELAY.idFromName(RELAY_NAME));
      const status = await relay.fetch(new URL("/__relay/status", request.url));
      const relayStatus = await status.json().catch(() => ({ connected: false }));
      return json({
        ok: true,
        service: SERVICE,
        relayConnected: Boolean((relayStatus as { connected?: boolean }).connected),
        writeEnabled: env.ALLOW_WRITE === "true"
      });
    }

    if (url.pathname === "/connect") {
      return env.RELAY.get(env.RELAY.idFromName(RELAY_NAME)).fetch(request);
    }

    const auth = authorize(request, env.AGENT_BEARER_TOKEN);
    if (!auth.ok) {
      return json({ error: auth.error }, auth.status);
    }

    if (request.method !== "GET" && request.method !== "POST") {
      return json({ error: "Method not allowed" }, 405);
    }

    if (request.method === "POST" && env.ALLOW_WRITE !== "true") {
      return json({ error: "Cloud write access is disabled" }, 403);
    }

    const relay = env.RELAY.get(env.RELAY.idFromName(RELAY_NAME));
    return relay.fetch(request);
  }
};

export class NoteLabRelay {
  private socket: WebSocket | null = null;
  private pending = new Map<string, {
    resolve: (response: RelayResponse) => void;
    reject: (error: Error) => void;
    timeout: ReturnType<typeof setTimeout>;
  }>();

  constructor(private readonly state: DurableObjectState, private readonly env: Env) {}

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/__relay/status") {
      return json({ connected: this.socket !== null });
    }

    if (url.pathname === "/connect") {
      return this.connect(request);
    }

    if (!this.socket) {
      return json({ error: "No NoteLab bridge is connected" }, 503);
    }

    return this.forward(request);
  }

  private connect(request: Request): Response {
    const auth = authorize(request, this.env.ORIGIN_AGENT_TOKEN, true);
    if (!auth.ok) {
      return json({ error: auth.error }, auth.status);
    }

    if (request.headers.get("upgrade")?.toLowerCase() !== "websocket") {
      return json({ error: "Expected WebSocket upgrade" }, 426);
    }

    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    server.accept();

    this.socket?.close(1012, "Replaced by a new NoteLab bridge");
    this.socket = server;

    server.addEventListener("message", (event) => {
      this.handleBridgeMessage(String(event.data));
    });
    server.addEventListener("close", () => this.disconnect(server));
    server.addEventListener("error", () => this.disconnect(server));

    return new Response(null, { status: 101, webSocket: client });
  }

  private async forward(request: Request): Promise<Response> {
    const body = request.method === "GET" ? undefined : await request.arrayBuffer();
    if (body && body.byteLength > MAX_BODY_BYTES) {
      return json({ error: "Request body is too large" }, 413);
    }

    const id = crypto.randomUUID();
    const url = new URL(request.url);
    const relayRequest: RelayRequest = {
      id,
      method: request.method,
      path: `${url.pathname}${url.search}`,
      headers: forwardedHeaders(request.headers),
      bodyBase64: body ? arrayBufferToBase64(body) : undefined
    };

    const response = await new Promise<RelayResponse>((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error("NoteLab bridge timed out"));
      }, RELAY_TIMEOUT_MS);
      this.pending.set(id, { resolve, reject, timeout });
      this.socket?.send(JSON.stringify(relayRequest));
    }).catch((error) => ({
      id,
      status: 504,
      error: error instanceof Error ? error.message : "NoteLab bridge failed"
    }));

    if (response.error) {
      return json({ error: response.error }, response.status || 502);
    }

    return withCors(new Response(
      response.bodyBase64 ? base64ToArrayBuffer(response.bodyBase64) : null,
      {
        status: response.status,
        statusText: response.statusText,
        headers: responseHeaders(response.headers ?? {})
      }
    ));
  }

  private handleBridgeMessage(raw: string): void {
    let response: RelayResponse;
    try {
      response = JSON.parse(raw) as RelayResponse;
    } catch {
      return;
    }

    const pending = this.pending.get(response.id);
    if (!pending) {
      return;
    }
    clearTimeout(pending.timeout);
    this.pending.delete(response.id);
    pending.resolve(response);
  }

  private disconnect(socket: WebSocket): void {
    if (this.socket !== socket) {
      return;
    }
    this.socket = null;
    for (const [id, pending] of this.pending) {
      clearTimeout(pending.timeout);
      pending.reject(new Error("NoteLab bridge disconnected"));
      this.pending.delete(id);
    }
  }
}

function authorize(
  request: Request,
  expectedRaw?: string,
  allowQueryToken = false
): { ok: true } | { ok: false; status: number; error: string } {
  const expected = expectedRaw?.trim();
  if (!expected) {
    return { ok: false, status: 503, error: "Token is not configured" };
  }

  const authorization = request.headers.get("authorization") ?? "";
  const prefix = "Bearer ";
  if (!authorization.startsWith(prefix) || authorization.slice(prefix.length) !== expected) {
    if (allowQueryToken && new URL(request.url).searchParams.get("token") === expected) {
      return { ok: true };
    }
    return { ok: false, status: 401, error: "Unauthorized" };
  }

  return { ok: true };
}

function forwardedHeaders(headers: Headers): Record<string, string> {
  const next: Record<string, string> = {};
  for (const [key, value] of headers) {
    const lower = key.toLowerCase();
    if (HOP_BY_HOP_HEADERS.has(lower) || lower === "host" || lower === "authorization") {
      continue;
    }
    next[key] = value;
  }
  return next;
}

function responseHeaders(headers: Record<string, string>): Headers {
  const next = new Headers();
  for (const [key, value] of Object.entries(headers)) {
    if (!HOP_BY_HOP_HEADERS.has(key.toLowerCase())) {
      next.set(key, value);
    }
  }
  next.set("Cache-Control", "no-store");
  return next;
}

function arrayBufferToBase64(buffer: ArrayBuffer): string {
  let binary = "";
  const bytes = new Uint8Array(buffer);
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary);
}

function base64ToArrayBuffer(value: string): ArrayBuffer {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes.buffer;
}

function json(value: unknown, status = 200): Response {
  return withCors(new Response(JSON.stringify(value, null, 2), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store"
    }
  }));
}

function withCors(response: Response): Response {
  const headers = new Headers(response.headers);
  headers.set("Access-Control-Allow-Origin", "*");
  headers.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  headers.set("Access-Control-Allow-Headers", "Authorization, Content-Type");
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers
  });
}
