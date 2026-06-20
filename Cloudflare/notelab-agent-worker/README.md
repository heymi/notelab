# NoteLab Cloud Agent Worker

This Worker is the public HTTPS entrypoint for cloud agents at
`https://notelab.aedc.cc`.

It does not store notes. It authenticates cloud agent requests, optionally blocks
write calls, and forwards approved traffic to a local NoteLab bridge connected
over WebSocket.

## Required Secrets

```bash
cd Cloudflare/notelab-agent-worker
printf '%s' "$CLOUD_AGENT_TOKEN" | npx wrangler secret put AGENT_BEARER_TOKEN
printf '%s' "$LOCAL_NOTELAB_AGENT_TOKEN" | npx wrangler secret put ORIGIN_AGENT_TOKEN
```

`AGENT_BEARER_TOKEN` is the token a cloud agent sends to
`notelab.aedc.cc`. `ORIGIN_AGENT_TOKEN` must match the token configured inside
NoteLab Settings for the app-local service.

## Local Bridge

Run the macOS app so the local service is listening on `127.0.0.1:47719`, then:

```bash
NOTELAB_ORIGIN_TOKEN="$LOCAL_NOTELAB_AGENT_TOKEN" \
NOTELAB_LOCAL_TOKEN="$LOCAL_NOTELAB_AGENT_TOKEN" \
node /Users/strictly/DEV/NoteLab/Tools/notelab-cloud-bridge.js
```

The bridge keeps an outbound WebSocket open to
`wss://notelab.aedc.cc/connect`; no public inbound port or Cloudflare Tunnel DNS
record is required.

## Deploy

```bash
npm run dry-run
npm run deploy
```

Writes are blocked by default. Set `ALLOW_WRITE = "true"` in `wrangler.toml`
when cloud writes should be enabled, then redeploy.
