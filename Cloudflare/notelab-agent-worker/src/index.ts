import { allowanceForProductId, costForAction, periodKey } from "./ai-rules.mjs";

interface Env {
  AGENT_BEARER_TOKEN?: string;
  ORIGIN_AGENT_TOKEN?: string;
  ALLOW_WRITE?: string;
  AI_DB: D1Database;
  AI_API_KEY?: string;
  AI_BASE_URL?: string;
  AI_MODEL?: string;
  AI_PROVIDER?: string;
  ARK_API_KEY?: string;
  ARK_BASE_URL?: string;
  ARK_MODEL?: string;
  APP_STORE_ISSUER_ID?: string;
  APP_STORE_KEY_ID?: string;
  APP_STORE_PRIVATE_KEY?: string;
  BUNDLE_ID?: string;
  DEV_ALLOW_TOKEN?: string;
  DEV_SUBSCRIPTION_TOKEN?: string;
  DEV_SUBSCRIPTION_PRODUCT_ID?: string;
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

    if (url.pathname === "/v1/subscription/verify" && request.method === "POST") {
      return handleVerify(request, env);
    }

    if (url.pathname === "/v1/quota" && request.method === "GET") {
      return handleQuota(request, env);
    }

    if (url.pathname === "/v1/ai/generate" && request.method === "POST") {
      return handleAIGenerate(request, env);
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

type SubscriptionIdentity = {
  originalTransactionId: string;
  productId: string;
  expiresAt: string | null;
  environment: string;
  credentialHash: string;
};

async function handleVerify(request: Request, env: Env): Promise<Response> {
  const verified = await verifySubscription(request, env);
  if ("response" in verified) return verified.response;
  const quota = await ensureQuota(env.AI_DB, verified.identity);
  return json({ subscription: publicSubscription(verified.identity), quota });
}

async function handleQuota(request: Request, env: Env): Promise<Response> {
  const verified = await verifySubscription(request, env);
  if ("response" in verified) return verified.response;
  return json(await ensureQuota(env.AI_DB, verified.identity));
}

async function handleAIGenerate(request: Request, env: Env): Promise<Response> {
  const verified = await verifySubscription(request, env);
  if ("response" in verified) return verified.response;

  const idempotencyKey = request.headers.get("Idempotency-Key")?.trim();
  if (!idempotencyKey) return errorJson("bad_request", 400);

  let body: { feature?: string; prompt?: string };
  try {
    body = await request.json();
  } catch {
    return errorJson("bad_request", 400);
  }

  const feature = typeof body.feature === "string" ? body.feature : "";
  const prompt = typeof body.prompt === "string" ? body.prompt : "";
  const creditCost = costForAction(feature);
  if (!prompt.trim() || creditCost <= 0) return errorJson("bad_request", 400);

  const identity = verified.identity;
  const quota = await ensureQuota(env.AI_DB, identity);
  if (quota.remainingCredits < creditCost) return errorJson("quota_exhausted", 402);

  const existing = await env.AI_DB.prepare(
    "SELECT response_json FROM idempotency_keys WHERE original_transaction_id = ? AND idempotency_key = ?"
  ).bind(identity.originalTransactionId, idempotencyKey).first<{ response_json: string | null }>();
  if (existing?.response_json) {
    return json(JSON.parse(existing.response_json));
  }
  if (existing) return errorJson("idempotency_in_progress", 409);

  const now = new Date().toISOString();
  await env.AI_DB.prepare(
    "INSERT INTO idempotency_keys (original_transaction_id, idempotency_key, endpoint, response_json, credit_cost, created_at) VALUES (?, ?, ?, NULL, ?, ?)"
  ).bind(identity.originalTransactionId, idempotencyKey, feature, creditCost, now).run();

  const started = Date.now();
  try {
    const text = await callAIProvider(prompt, env);
    if (!text.trim()) throw new Error("model_empty_response");

    const debited = await env.AI_DB.prepare(
      "UPDATE quota_periods SET used = used + ?, updated_at = ? WHERE original_transaction_id = ? AND period = ? AND used + ? <= allowance"
    ).bind(creditCost, new Date().toISOString(), identity.originalTransactionId, quota.period, creditCost).run();
    if ((debited.meta?.changes ?? 0) === 0) {
      await deleteIdempotency(env.AI_DB, identity.originalTransactionId, idempotencyKey);
      return errorJson("quota_exhausted", 402);
    }

    const nextQuota = await ensureQuota(env.AI_DB, identity);
    const payload = { text, quota: nextQuota };
    await env.AI_DB.prepare(
      "UPDATE idempotency_keys SET response_json = ? WHERE original_transaction_id = ? AND idempotency_key = ?"
    ).bind(JSON.stringify(payload), identity.originalTransactionId, idempotencyKey).run();
    await logUsage(env.AI_DB, identity.originalTransactionId, feature, creditCost, 200, Date.now() - started);
    return json(payload);
  } catch (error) {
    await deleteIdempotency(env.AI_DB, identity.originalTransactionId, idempotencyKey);
    const code = modelErrorCode(error);
    await logUsage(env.AI_DB, identity.originalTransactionId, feature, creditCost, code === "model_upstream_timeout" ? 504 : 502, Date.now() - started, code);
    return errorJson(code, code === "model_upstream_timeout" ? 504 : 502);
  }
}

async function verifySubscription(
  request: Request,
  env: Env
): Promise<{ identity: SubscriptionIdentity } | { response: Response }> {
  const credential = bearerToken(request);
  if (!credential) return { response: errorJson("missing_subscription_credential", 401) };

  if (env.DEV_ALLOW_TOKEN === "true" && env.DEV_SUBSCRIPTION_TOKEN && credential === env.DEV_SUBSCRIPTION_TOKEN) {
    // ponytail: local StoreKit config cannot be checked by App Store Server API; remove this when TestFlight-only QA is enough.
    const productId = env.DEV_SUBSCRIPTION_PRODUCT_ID || "com.notelab.pro.monthly";
    const identity: SubscriptionIdentity = {
      originalTransactionId: `dev:${(await sha256Hex(credential)).slice(0, 24)}`,
      productId,
      expiresAt: null,
      environment: "Local",
      credentialHash: await sha256Hex(credential)
    };
    await persistSubscription(env.AI_DB, identity);
    return { identity };
  }

  let localPayload: any;
  try {
    localPayload = decodeJWSPayload(credential);
  } catch {
    return { response: errorJson("invalid_subscription_credential", 401) };
  }

  const transactionId = String(localPayload.transactionId || "");
  if (!transactionId) return { response: errorJson("invalid_subscription_credential", 401) };

  let applePayload: any;
  try {
    applePayload = await fetchAppleTransaction(transactionId, env);
  } catch {
    return { response: errorJson("invalid_subscription_credential", 401) };
  }

  const bundleId = String(applePayload.bundleId || "");
  const expectedBundleId = env.BUNDLE_ID || "com.psg.NoteLab";
  if (bundleId !== expectedBundleId) return { response: errorJson("bundle_mismatch", 401) };

  const productId = String(applePayload.productId || "");
  if (allowanceForProductId(productId) <= 0) return { response: errorJson("product_mismatch", 401) };
  if (applePayload.revocationDate) return { response: errorJson("subscription_revoked", 401) };

  const expiresMs = Number(applePayload.expiresDate || 0);
  if (expiresMs > 0 && expiresMs < Date.now()) return { response: errorJson("subscription_expired", 401) };

  const identity: SubscriptionIdentity = {
    originalTransactionId: String(applePayload.originalTransactionId || transactionId),
    productId,
    expiresAt: expiresMs > 0 ? new Date(expiresMs).toISOString() : null,
    environment: String(applePayload.environment || "Production"),
    credentialHash: await sha256Hex(credential)
  };
  await persistSubscription(env.AI_DB, identity);
  return { identity };
}

async function fetchAppleTransaction(transactionId: string, env: Env): Promise<any> {
  const token = await appStoreServerToken(env);
  const hosts = [
    "https://api.storekit.itunes.apple.com",
    "https://api.storekit-sandbox.itunes.apple.com"
  ];
  for (const host of hosts) {
    const response = await fetch(`${host}/inApps/v1/transactions/${transactionId}`, {
      headers: { authorization: `Bearer ${token}` }
    });
    if (response.ok) {
      const body = await response.json() as { signedTransactionInfo?: string };
      if (!body.signedTransactionInfo) throw new Error("missing_signed_transaction_info");
      return decodeJWSPayload(body.signedTransactionInfo);
    }
  }
  throw new Error("apple_transaction_not_found");
}

async function appStoreServerToken(env: Env): Promise<string> {
  const issuer = env.APP_STORE_ISSUER_ID;
  const keyId = env.APP_STORE_KEY_ID;
  const privateKey = env.APP_STORE_PRIVATE_KEY;
  const bundleId = env.BUNDLE_ID || "com.psg.NoteLab";
  if (!issuer || !keyId || !privateKey) throw new Error("missing_app_store_credentials");

  const now = Math.floor(Date.now() / 1000);
  const header = base64UrlJson({ alg: "ES256", kid: keyId, typ: "JWT" });
  const payload = base64UrlJson({
    iss: issuer,
    iat: now,
    exp: now + 300,
    aud: "appstoreconnect-v1",
    bid: bundleId
  });
  const signingInput = `${header}.${payload}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(privateKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"]
  );
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput)
  );
  return `${signingInput}.${base64UrlBytes(joseSignature(new Uint8Array(signature)))}`;
}

async function callAIProvider(prompt: string, env: Env): Promise<string> {
  const apiKey = env.AI_API_KEY || env.ARK_API_KEY;
  if (!apiKey) throw new Error("model_upstream_failed");
  const provider = (env.AI_PROVIDER || "responses").toLowerCase();
  const baseURL = (env.AI_BASE_URL || env.ARK_BASE_URL || (provider === "deepseek" ? "https://api.deepseek.com/v1" : "https://ark.cn-beijing.volces.com/api/v3")).replace(/\/$/, "");
  const model = env.AI_MODEL || env.ARK_MODEL || (provider === "deepseek" ? "deepseek-chat" : "doubao-seed-1-8-251228");
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 120_000);
  try {
    const response = await fetch(`${baseURL}/${provider === "deepseek" ? "chat/completions" : "responses"}`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${apiKey}`,
        "content-type": "application/json"
      },
      body: JSON.stringify(provider === "deepseek"
        ? {
            model,
            messages: [
              { role: "system", content: "你是 NoteLab 的助手。只输出用户要求的内容。" },
              { role: "user", content: prompt }
            ],
            temperature: 0.2,
            max_tokens: 8192
          }
        : {
            model,
            input: [
              { role: "system", content: [{ type: "input_text", text: "你是 NoteLab 的助手。只输出用户要求的内容。" }] },
              { role: "user", content: [{ type: "input_text", text: prompt }] }
            ]
          }),
      signal: controller.signal
    });
    const body = await response.text();
    if (!response.ok) throw new Error(`model_upstream_failed:${response.status}`);
    return extractOutputText(JSON.parse(body));
  } finally {
    clearTimeout(timeout);
  }
}

function extractOutputText(response: any): string {
  if (typeof response?.output_text === "string") return response.output_text;
  const messageContent = response?.choices?.[0]?.message?.content;
  if (typeof messageContent === "string") return messageContent;
  for (const item of response?.output || []) {
    for (const content of item?.content || []) {
      if (typeof content?.text === "string") return content.text;
      if (typeof content?.content === "string") return content.content;
    }
  }
  throw new Error("model_empty_response");
}

async function ensureQuota(db: D1Database, identity: SubscriptionIdentity) {
  const period = periodKey();
  const allowance = allowanceForProductId(identity.productId);
  const now = new Date().toISOString();
  await db.prepare(
    "INSERT OR IGNORE INTO quota_periods (original_transaction_id, period, allowance, used, updated_at) VALUES (?, ?, ?, 0, ?)"
  ).bind(identity.originalTransactionId, period, allowance, now).run();
  const row = await db.prepare(
    "SELECT allowance, used FROM quota_periods WHERE original_transaction_id = ? AND period = ?"
  ).bind(identity.originalTransactionId, period).first<{ allowance: number; used: number }>();
  const used = row?.used ?? 0;
  const monthlyAllowance = row?.allowance ?? allowance;
  return {
    monthlyAllowance,
    usedCredits: used,
    remainingCredits: Math.max(0, monthlyAllowance - used),
    period,
    periodEndsAt: nextMonthStartISO()
  };
}

async function persistSubscription(db: D1Database, identity: SubscriptionIdentity): Promise<void> {
  await db.prepare(
    "INSERT INTO subscriptions (original_transaction_id, product_id, status, expires_at, last_verified_at, environment, raw_payload_hash) VALUES (?, ?, 'active', ?, ?, ?, ?) ON CONFLICT(original_transaction_id) DO UPDATE SET product_id = excluded.product_id, status = excluded.status, expires_at = excluded.expires_at, last_verified_at = excluded.last_verified_at, environment = excluded.environment, raw_payload_hash = excluded.raw_payload_hash"
  ).bind(
    identity.originalTransactionId,
    identity.productId,
    identity.expiresAt,
    new Date().toISOString(),
    identity.environment,
    identity.credentialHash
  ).run();
}

async function deleteIdempotency(db: D1Database, originalTransactionId: string, idempotencyKey: string): Promise<void> {
  await db.prepare(
    "DELETE FROM idempotency_keys WHERE original_transaction_id = ? AND idempotency_key = ?"
  ).bind(originalTransactionId, idempotencyKey).run();
}

async function logUsage(
  db: D1Database,
  originalTransactionId: string,
  endpoint: string,
  creditCost: number,
  status: number,
  latencyMs: number,
  modelErrorCode: string | null = null
): Promise<void> {
  await db.prepare(
    "INSERT INTO usage_events (id, original_transaction_id, endpoint, credit_cost, status, latency_ms, model_error_code, estimated_cost_usd, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, NULL, ?)"
  ).bind(crypto.randomUUID(), originalTransactionId, endpoint, creditCost, status, latencyMs, modelErrorCode, new Date().toISOString()).run();
}

function publicSubscription(identity: SubscriptionIdentity) {
  return {
    productId: identity.productId,
    environment: identity.environment,
    expiresAt: identity.expiresAt
  };
}

function modelErrorCode(error: unknown): string {
  if (error instanceof DOMException && error.name === "AbortError") return "model_upstream_timeout";
  const message = error instanceof Error ? error.message : String(error);
  if (message === "model_empty_response") return "model_empty_response";
  return "model_upstream_failed";
}

function bearerToken(request: Request): string | null {
  const authorization = request.headers.get("authorization") || "";
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  return match?.[1] ?? null;
}

function decodeJWSPayload(jws: string): any {
  const parts = jws.split(".");
  if (parts.length !== 3) throw new Error("invalid_jws");
  return JSON.parse(new TextDecoder().decode(base64UrlToBytes(parts[1])));
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function nextMonthStartISO(): string {
  const now = new Date();
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1)).toISOString();
}

function base64UrlJson(value: unknown): string {
  return base64UrlBytes(new TextEncoder().encode(JSON.stringify(value)));
}

function base64UrlBytes(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function base64UrlToBytes(value: string): Uint8Array {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(value.length / 4) * 4, "=");
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
  return bytes;
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const base64 = pem.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, "");
  return base64ToArrayBuffer(base64);
}

function joseSignature(signature: Uint8Array): Uint8Array {
  if (signature.length === 64) return signature;
  let offset = 3;
  let rLength = signature[offset + 1];
  let r = signature.slice(offset + 2, offset + 2 + rLength);
  offset += 2 + rLength;
  let sLength = signature[offset + 1];
  let s = signature.slice(offset + 2, offset + 2 + sLength);
  r = trimAndPadInteger(r);
  s = trimAndPadInteger(s);
  const out = new Uint8Array(64);
  out.set(r, 0);
  out.set(s, 32);
  return out;
}

function trimAndPadInteger(value: Uint8Array): Uint8Array {
  let start = 0;
  while (value.length - start > 32 && value[start] === 0) start += 1;
  const trimmed = value.slice(start);
  const out = new Uint8Array(32);
  out.set(trimmed.slice(-32), 32 - Math.min(32, trimmed.length));
  return out;
}

function errorJson(code: string, status: number): Response {
  return json({ error: code }, status);
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
