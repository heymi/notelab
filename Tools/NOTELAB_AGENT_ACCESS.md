# NoteLab Agent Access

`Tools/notelab` is a read-only CLI for local NoteLab resources. It opens the
`NoteLabStorageV3.sqlite` Core Data store and returns stable JSON for agents.

## Examples

```bash
Tools/notelab stores
Tools/notelab profiles list --json
Tools/notelab notebooks list --json
Tools/notelab notebooks read NOTEBOOK_ID --json
Tools/notelab notebooks create --write --title "DockDay"
Tools/notelab notebooks update NOTEBOOK_ID --write --title "New title"
Tools/notelab notebooks delete NOTEBOOK_ID --write
Tools/notelab notes search --query "meeting" --json
Tools/notelab notes read NOTE_ID --json
Tools/notelab notes create --write --notebook NOTEBOOK_ID --title "Title" --content-file note.md
Tools/notelab notes update NOTE_ID --write --title "Title" --content-file note.md
Tools/notelab notes append NOTE_ID --write --content "More context"
Tools/notelab notes delete NOTE_ID --write
Tools/notelab content read NOTE_ID
Tools/notelab content update NOTE_ID --write --content-file note.md
Tools/notelab content append NOTE_ID --write --content "More"
Tools/notelab content clear NOTE_ID --write
Tools/notelab attachments list NOTE_ID --json
Tools/notelab attachments export ATTACHMENT_ID --output /tmp/notelab-export
Tools/notelab attachments add NOTE_ID --write --file ./image.png
Tools/notelab resources list --json
```

If auto-detection cannot find the store, pass it explicitly:

```bash
Tools/notelab --store "$HOME/Library/Containers/com.psg.NoteLab/Data/Library/Application Support/NoteLabStorageV3.sqlite" notes list
```

## Agent Contract

- Output is JSON by default.
- Read commands never write to the NoteLab database.
- Write commands require the App-local service and an explicit `--write` flag.
- `attachments export` only copies a local original/cache file to the requested
  output path.
- Use `--profile PROFILE_ID`, `--notebook NOTEBOOK_ID`, and `--limit N` to keep
  agent reads narrow.

Recommended read flow:

```text
profiles list -> notebooks list -> notes search/list -> notes read -> attachments export
```

## MCP

Agents that support MCP can use the stdio bridge:

```bash
node /Users/strictly/DEV/NoteLab/Tools/notelab-mcp.js
```

The MCP bridge exposes tools for profiles, notebooks CRUD, note CRUD, content
read/update/append/clear, attachment listing/add, and resource counts. It shells
out to `Tools/notelab`, so the NoteLab macOS app must be running for sandboxed
data. Write MCP calls must include `write: true`.

## Runtime

In Debug builds, the macOS app starts the loopback service automatically on
`127.0.0.1:47719` and allows write calls when the CLI/MCP request includes the
explicit write opt-in. In Release builds, the service starts only when
`AgentAccessEnabled` is enabled, and write calls require `AgentWriteEnabled` to
be enabled from inside the app sandbox.

When `AgentAccessToken` is configured in NoteLab Settings, callers must send it
as either:

```text
Authorization: Bearer TOKEN
X-NoteLab-Agent-Key: TOKEN
```

The CLI can pass this with `--agent-token TOKEN` or the
`NOTELAB_AGENT_TOKEN` environment variable.

## Cloudflare

`Cloudflare/notelab-agent-worker` contains the public Worker for
`https://notelab.aedc.cc`.

The Worker:

- requires `Authorization: Bearer AGENT_BEARER_TOKEN` for all note/resource
  endpoints;
- blocks POST/write calls unless `ALLOW_WRITE = "true"` is deployed;
- accepts one local bridge connection at `wss://notelab.aedc.cc/connect`;
- forwards approved calls through that bridge to the app-local service.

Deploy:

```bash
cd Cloudflare/notelab-agent-worker
npm run dry-run
npm run deploy
```

Required Cloudflare secrets:

```bash
printf '%s' "$CLOUD_AGENT_TOKEN" | npx wrangler secret put AGENT_BEARER_TOKEN
printf '%s' "$LOCAL_NOTELAB_AGENT_TOKEN" | npx wrangler secret put ORIGIN_AGENT_TOKEN
```

Run the bridge locally:

```bash
set -a
. "$HOME/.notelab/cloud-agent.env"
set +a
node /Users/strictly/DEV/NoteLab/Tools/notelab-cloud-bridge.js
```

On this machine the bridge is installed as the LaunchAgent
`com.psg.NoteLab.cloud-agent-bridge`.
