#!/usr/bin/env node
const process = require("process");

const cloudURL = process.env.NOTELAB_CLOUD_URL || "wss://notelab.aedc.cc/connect";
const originURL = process.env.NOTELAB_LOCAL_AGENT_URL || "http://127.0.0.1:47719";
const originToken = process.env.NOTELAB_ORIGIN_TOKEN || "";
const localToken = process.env.NOTELAB_LOCAL_TOKEN || originToken;
const reconnectMs = Number(process.env.NOTELAB_BRIDGE_RECONNECT_MS || "3000");

if (!originToken.trim()) {
  console.error("notelab-cloud-bridge: NOTELAB_ORIGIN_TOKEN is required");
  process.exit(1);
}

let stopping = false;
process.on("SIGINT", () => {
  stopping = true;
  process.exit(0);
});
process.on("SIGTERM", () => {
  stopping = true;
  process.exit(0);
});

connect();

function connect() {
  const connectURL = new URL(cloudURL);
  connectURL.searchParams.set("token", originToken);
  const socket = new WebSocket(connectURL);

  socket.addEventListener("open", () => {
    console.error(`notelab-cloud-bridge: connected to ${cloudURL}`);
  });

  socket.addEventListener("message", (event) => {
    handleMessage(socket, String(event.data)).catch((error) => {
      console.error(`notelab-cloud-bridge: ${error.message}`);
    });
  });

  socket.addEventListener("close", () => {
    if (!stopping) {
      console.error(`notelab-cloud-bridge: disconnected, reconnecting in ${reconnectMs}ms`);
      setTimeout(connect, reconnectMs);
    }
  });

  socket.addEventListener("error", () => {
    socket.close();
  });
}

async function handleMessage(socket, raw) {
  const message = JSON.parse(raw);
  const target = new URL(message.path || "/", originURL);
  const headers = new Headers(message.headers || {});
  if (localToken.trim()) {
    headers.set("Authorization", `Bearer ${localToken}`);
    headers.set("X-NoteLab-Agent-Key", localToken);
  }

  const body = message.bodyBase64 ? Buffer.from(message.bodyBase64, "base64") : undefined;
  const response = await fetch(target, {
    method: message.method,
    headers,
    body
  });

  const responseBody = Buffer.from(await response.arrayBuffer());
  const responseHeaders = {};
  for (const [key, value] of response.headers) {
    responseHeaders[key] = value;
  }

  socket.send(JSON.stringify({
    id: message.id,
    status: response.status,
    statusText: response.statusText,
    headers: responseHeaders,
    bodyBase64: responseBody.toString("base64")
  }));
}
