# Supabase Edge Functions

下面是两个 Function 的完整代码，直接粘贴到 Supabase Dashboard 的在线编辑器里即可。

---

## 1) auth-device

路径：`/functions/v1/auth-device`

```ts
// supabase/functions/auth-device/index.ts
import { SignJWT } from "npm:jose@5.9.6";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", ...corsHeaders },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const jwtSecret = Deno.env.get("JWT_SECRET");
  if (!jwtSecret) return json({ error: "missing_JWT_SECRET" }, 500);

  let body: any;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const deviceId = typeof body?.deviceId === "string" ? body.deviceId.trim() : "";
  if (!deviceId) return json({ error: "missing_deviceId" }, 400);

  const now = Math.floor(Date.now() / 1000);
  const expiresIn = 60 * 60 * 24 * 7; // 7 days

  const key = new TextEncoder().encode(jwtSecret);

  const accessToken = await new SignJWT({
    tier: "free",
    schemaVersion: Number(Deno.env.get("SCHEMA_VERSION") ?? "1"),
    policyVersion: Number(Deno.env.get("POLICY_VERSION") ?? "1"),
  })
    .setProtectedHeader({ alg: "HS256", typ: "JWT" })
    .setIssuer("notelab")
    .setSubject(deviceId)
    .setJti(crypto.randomUUID())
    .setIssuedAt(now)
    .setExpirationTime(now + expiresIn)
    .sign(key);

  return json({ accessToken, expiresIn });
});
```

---

## 2) ai

路径：
- `/functions/v1/ai/format`
- `/functions/v1/ai/extractTasks`
- `/functions/v1/ai/plan`

```ts
// supabase/functions/ai/index.ts
import { jwtVerify } from "npm:jose@5.9.6";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", ...corsHeaders },
  });
}

function getBearer(req: Request): string | null {
  const h = req.headers.get("authorization") || req.headers.get("Authorization");
  if (!h) return null;
  const m = h.match(/^Bearer\s+(.+)$/i);
  return m?.[1] ?? null;
}

async function sha256Hex(input: string): Promise<string> {
  const buf = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", buf);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function extractOutputText(resp: any): string {
  if (typeof resp?.output_text === "string") return resp.output_text;

  const output = resp?.output;
  if (Array.isArray(output)) {
    for (const item of output) {
      const content = item?.content;
      if (Array.isArray(content)) {
        for (const c of content) {
          if (typeof c?.text === "string") return c.text;
          if (typeof c?.content === "string") return c.content;
        }
      }
    }
  }

  const choices = resp?.choices;
  if (Array.isArray(choices)) {
    const c0 = choices[0];
    const msg = c0?.message?.content;
    if (typeof msg === "string") return msg;
  }

  throw new Error("cannot_extract_model_text");
}

function strictJsonParse(s: string): any {
  const trimmed = s.trim();
  const fence = trimmed.match(/```json\s*([\s\S]*?)\s*```/i);
  const payload = fence?.[1]?.trim() ?? trimmed;
  return JSON.parse(payload);
}

function nowIso() {
  return new Date().toISOString();
}

function expiresAt(days: number): string {
  const d = new Date();
  d.setDate(d.getDate() + days);
  return d.toISOString();
}

type Route = "format" | "extractTasks" | "plan";

function detectRoute(req: Request): Route | null {
  const url = new URL(req.url);
  const parts = url.pathname.split("/").filter(Boolean);
  const idx = parts.findIndex((p) => p === "ai");
  if (idx === -1) return null;
  const next = parts[idx + 1];
  if (next === "format") return "format";
  if (next === "extractTasks") return "extractTasks";
  if (next === "plan") return "plan";
  return null;
}

function buildPrompt(route: Route, body: any) {
  const locale = body?.locale ?? "zh-CN";
  const timezone = body?.timezone ?? "Asia/Shanghai";

  if (route === "format") {
    return {
      system:
        "你是笔记整理器。只基于输入内容，不要编造。输出必须是严格 JSON，且只能输出 JSON，不要输出任何解释或 Markdown。",
      user: {
        text: body?.text ?? "",
        locale,
        timezone,
        styleHint: body?.styleHint ?? "auto",
        maxSections: body?.maxSections ?? 8,
        schema: {
          title: "string",
          summary: "string",
          sections: [{ heading: "string", bullets: ["string"], paragraphs: ["string"], anchors: [{ paragraphIndex: 0 }] }],
          highlights: [{ text: "string", anchor: { paragraphIndex: 0 } }],
          metrics: { paragraphCount: 0, bulletCount: 0, checklistCount: 0 },
          formattedMarkdown: "string"
        }
      },
    };
  }

  if (route === "extractTasks") {
    return {
      system:
        "你是待办提取器。只基于输入内容，不要编造。输出必须是严格 JSON，且只能输出 JSON。",
      user: {
        text: body?.text ?? "",
        locale,
        timezone,
        maxTasks: body?.maxTasks ?? 12,
        schema: {
          tasks: [{ text: "string", dueDate: "YYYY-MM-DD|omit", priority: "low|medium|high|unknown", confidence: 0.0, sourceAnchor: { paragraphIndex: 0 } }],
        },
      },
    };
  }

  return {
    system:
      "你是工作计划助手。只基于输入任务与目标，不要编造不存在的信息。输出必须是严格 JSON，且只能输出 JSON。必须原样保留并输出每个行动项对应的 taskId、sourceRef.noteId、sourceRef.notebookId（来自输入 tasks），不得修改或遗漏。",
    user: {
      mode: body?.mode ?? "today",
      goal: body?.goal ?? "",
      locale,
      timezone,
      availableMinutesPerDay: body?.availableMinutesPerDay ?? 240,
      tasks: Array.isArray(body?.tasks) ? body.tasks : [],
      schema: {
        topFocus: { text: "string", estMinutes: 0, sourceRefs: [{ taskId: "string" }] },
        actionQueue: [{ taskId: "string", text: "string", estMinutes: 0, scheduledDate: "YYYY-MM-DD", sourceRef: { noteTitle: "string|omit", noteId: "string", notebookId: "string", sourceAnchor: { paragraphIndex: 0 } } }],
        risks: [{ text: "string", suggestion: "string|omit", draftMessage: "string|omit" }],
        rationale: "string"
      },
    },
  };
}

async function callArkResponses(model: string, prompt: { system: string; user: any }) {
  const baseUrl = Deno.env.get("ARK_BASE_URL") ?? "https://ark.cn-beijing.volces.com/api/v3";
  const apiKey = Deno.env.get("ARK_API_KEY") ?? Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) throw new Error("missing_ARK_API_KEY");

  const url = `${baseUrl.replace(/\/$/, "")}/responses`;

  const input = [
    { role: "system", content: [{ type: "input_text", text: prompt.system }] },
    { role: "user", content: [{ type: "input_text", text: JSON.stringify(prompt.user) }] },
  ];

  const started = Date.now();
  const resp = await fetch(url, {
    method: "POST",
    headers: {
      "authorization": `Bearer ${apiKey}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model,
      input,
    }),
  });

  const latencyMs = Date.now() - started;
  const text = await resp.text();
  if (!resp.ok) {
    throw new Error(`ark_error_${resp.status}: ${text}`);
  }
  const jsonResp = JSON.parse(text);
  return { jsonResp, latencyMs };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const route = detectRoute(req);
  if (!route) return json({ error: "unknown_route" }, 404);

  const jwtSecret = Deno.env.get("JWT_SECRET");
  if (!jwtSecret) return json({ error: "missing_JWT_SECRET" }, 500);

  const token = getBearer(req);
  if (!token) return json({ error: "missing_authorization" }, 401);

  let deviceId = "";
  try {
    const key = new TextEncoder().encode(jwtSecret);
    const verified = await jwtVerify(token, key, { issuer: "notelab" });
    deviceId = String(verified.payload.sub ?? "");
    if (!deviceId) return json({ error: "invalid_token_sub" }, 401);
  } catch {
    return json({ error: "invalid_token" }, 401);
  }

  let body: any;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const schemaVersion = Number(Deno.env.get("SCHEMA_VERSION") ?? "1");
  const policyVersion = Number(Deno.env.get("POLICY_VERSION") ?? "1");
  const model = Deno.env.get("ARK_MODEL") ?? "doubao-seed-1-8-251228";

  const textInput = route === "plan" ? JSON.stringify(body) : String(body?.text ?? "");
  const inputHash = await sha256Hex(
    JSON.stringify({
      route,
      schemaVersion,
      policyVersion,
      model,
      body: route === "plan" ? body : { ...body, text: textInput },
    }),
  );

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    return json({ error: "missing_SUPABASE_URL_or_SERVICE_ROLE_KEY" }, 500);
  }
  const sb = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });

  const requestId = crypto.randomUUID();

  const cacheLookup = await sb
    .from("ai_cache")
    .select("response_json, provider, model")
    .eq("job_type", route)
    .eq("input_hash", inputHash)
    .order("created_at", { ascending: false })
    .limit(1);

  if (!cacheLookup.error && cacheLookup.data && cacheLookup.data.length > 0) {
    const row = cacheLookup.data[0];
    (async () => {
      try {
        await sb.from("ai_logs").insert({
          request_id: requestId,
          job_type: route,
          device_id: deviceId,
          latency_ms: 0,
          cache_hit: true,
          provider: row.provider ?? "ark",
          model: row.model ?? model,
          created_at: nowIso(),
        });
      } catch {}
    })();
    return json({
      requestId,
      cacheHit: true,
      provider: row.provider ?? "ark",
      model: row.model ?? model,
      latencyMs: 0,
      schemaVersion,
      data: row.response_json,
    });
  }

  const prompt = buildPrompt(route, body);

  try {
    const { jsonResp, latencyMs } = await callArkResponses(model, prompt);

    let parsed: any;
    try {
      const outText = extractOutputText(jsonResp);
      parsed = strictJsonParse(outText);
    } catch {
      const retryPrompt = {
        system: prompt.system + " 再强调：只能输出 JSON，禁止输出任何多余字符。",
        user: prompt.user,
      };
      const retry = await callArkResponses(model, retryPrompt);
      const outText2 = extractOutputText(retry.jsonResp);
      parsed = strictJsonParse(outText2);
    }

    const ttlDays = route === "format" ? 7 : route === "extractTasks" ? 3 : 1;

    await sb.from("ai_cache").upsert({
      job_type: route,
      input_hash: inputHash,
      response_json: parsed,
      provider: "ark",
      model,
      schema_version: schemaVersion,
      policy_version: policyVersion,
      created_at: nowIso(),
      expires_at: expiresAt(ttlDays),
    }, { onConflict: "job_type,input_hash" });

    (async () => {
      try {
        await sb.from("ai_logs").insert({
          request_id: requestId,
          job_type: route,
          device_id: deviceId,
          latency_ms: latencyMs,
          cache_hit: false,
          provider: "ark",
          model,
          created_at: nowIso(),
        });
      } catch {}
    })();

    return json({
      requestId,
      cacheHit: false,
      provider: "ark",
      model,
      latencyMs,
      schemaVersion,
      data: parsed,
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    (async () => {
      try {
        await sb.from("ai_logs").insert({
          request_id: requestId,
          job_type: route,
          device_id: deviceId,
          latency_ms: null,
          cache_hit: false,
          provider: "ark",
          model,
          error_code: "model_call_failed",
          error_message: msg.slice(0, 500),
          created_at: nowIso(),
        });
      } catch {}
    })();
    return json({ error: "model_call_failed", message: msg }, 502);
  }
});
```
```

---

## Secrets（确认已添加）

- `ARK_API_KEY`
- `ARK_BASE_URL` = `https://ark.cn-beijing.volces.com/api/v3`
- `ARK_MODEL` = `doubao-seed-1-8-251228`
- `JWT_SECRET`
- `SCHEMA_VERSION` = `1`
- `POLICY_VERSION` = `1`
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
