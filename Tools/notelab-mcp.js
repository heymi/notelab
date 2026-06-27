#!/usr/bin/env node
const { execFile } = require("child_process");
const path = require("path");

const cli = path.join(__dirname, "notelab");
let buffer = Buffer.alloc(0);

const tools = [
  {
    name: "notelab_profiles_list",
    description: "List local NoteLab profiles.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false }
  },
  {
    name: "notelab_notebooks_list",
    description: "List NoteLab notebooks.",
    inputSchema: {
      type: "object",
      properties: {
        profile: { type: "string" },
        limit: { type: "number" }
      },
      additionalProperties: false
    }
  },
  {
    name: "notelab_notebook_create",
    description: "Create a NoteLab notebook. Requires write: true.",
    inputSchema: {
      type: "object",
      properties: {
        write: { type: "boolean" },
        title: { type: "string" },
        profile: { type: "string" },
        color: { type: "string" },
        icon: { type: "string" }
      },
      required: ["write", "title"],
      additionalProperties: false
    }
  },
  {
    name: "notelab_notebook_read",
    description: "Read one NoteLab notebook.",
    inputSchema: {
      type: "object",
      properties: { id: { type: "string" }, profile: { type: "string" } },
      required: ["id"],
      additionalProperties: false
    }
  },
  {
    name: "notelab_notebook_update",
    description: "Update a NoteLab notebook. Requires write: true.",
    inputSchema: {
      type: "object",
      properties: {
        write: { type: "boolean" },
        id: { type: "string" },
        title: { type: "string" },
        profile: { type: "string" },
        color: { type: "string" },
        icon: { type: "string" },
        description: { type: "string" }
      },
      required: ["write", "id"],
      additionalProperties: false
    }
  },
  {
    name: "notelab_notebook_delete",
    description: "Soft-delete a NoteLab notebook. Requires write: true.",
    inputSchema: {
      type: "object",
      properties: { write: { type: "boolean" }, id: { type: "string" }, profile: { type: "string" } },
      required: ["write", "id"],
      additionalProperties: false
    }
  },
  {
    name: "notelab_notes_search",
    description: "Search NoteLab notes by title, summary, and content.",
    inputSchema: {
      type: "object",
      properties: {
        query: { type: "string" },
        profile: { type: "string" },
        notebook: { type: "string" },
        limit: { type: "number" }
      },
      required: ["query"],
      additionalProperties: false
    }
  },
  {
    name: "notelab_note_read",
    description: "Read one NoteLab note with attachment metadata.",
    inputSchema: {
      type: "object",
      properties: {
        id: { type: "string" },
        profile: { type: "string" }
      },
      required: ["id"],
      additionalProperties: false
    }
  },
  {
    name: "notelab_note_create",
    description: "Create a NoteLab note. Requires write: true.",
    inputSchema: {
      type: "object",
      properties: {
        write: { type: "boolean" },
        notebook: { type: "string" },
        title: { type: "string" },
        content: { type: "string" },
        profile: { type: "string" }
      },
      required: ["write", "notebook"],
      additionalProperties: false
    }
  },
  {
    name: "notelab_note_append",
    description: "Append content to a NoteLab note. Requires write: true.",
    inputSchema: {
      type: "object",
      properties: {
        write: { type: "boolean" },
        id: { type: "string" },
        content: { type: "string" },
        profile: { type: "string" }
      },
      required: ["write", "id", "content"],
      additionalProperties: false
    }
  },
  {
    name: "notelab_note_update",
    description: "Update a NoteLab note title, content, or notebook. Requires write: true.",
    inputSchema: {
      type: "object",
      properties: {
        write: { type: "boolean" },
        id: { type: "string" },
        title: { type: "string" },
        content: { type: "string" },
        notebook: { type: "string" },
        profile: { type: "string" }
      },
      required: ["write", "id"],
      additionalProperties: false
    }
  },
  {
    name: "notelab_note_delete",
    description: "Soft-delete a NoteLab note. Requires write: true.",
    inputSchema: {
      type: "object",
      properties: { write: { type: "boolean" }, id: { type: "string" }, profile: { type: "string" } },
      required: ["write", "id"],
      additionalProperties: false
    }
  },
  {
    name: "notelab_content_read",
    description: "Read only the content of a NoteLab note.",
    inputSchema: {
      type: "object",
      properties: { id: { type: "string" }, profile: { type: "string" } },
      required: ["id"],
      additionalProperties: false
    }
  },
  {
    name: "notelab_content_update",
    description: "Replace note content. Requires write: true.",
    inputSchema: {
      type: "object",
      properties: { write: { type: "boolean" }, id: { type: "string" }, content: { type: "string" }, profile: { type: "string" } },
      required: ["write", "id", "content"],
      additionalProperties: false
    }
  },
  {
    name: "notelab_content_append",
    description: "Append note content. Requires write: true.",
    inputSchema: {
      type: "object",
      properties: { write: { type: "boolean" }, id: { type: "string" }, content: { type: "string" }, profile: { type: "string" } },
      required: ["write", "id", "content"],
      additionalProperties: false
    }
  },
  {
    name: "notelab_content_clear",
    description: "Clear note content. Requires write: true.",
    inputSchema: {
      type: "object",
      properties: { write: { type: "boolean" }, id: { type: "string" }, profile: { type: "string" } },
      required: ["write", "id"],
      additionalProperties: false
    }
  },
  {
    name: "notelab_attachments_list",
    description: "List NoteLab attachments, optionally for one note.",
    inputSchema: {
      type: "object",
      properties: {
        noteId: { type: "string" },
        profile: { type: "string" },
        limit: { type: "number" }
      },
      additionalProperties: false
    }
  },
  {
    name: "notelab_attachment_add",
    description: "Add a local file as a NoteLab note attachment. Requires write: true.",
    inputSchema: {
      type: "object",
      properties: {
        write: { type: "boolean" },
        noteId: { type: "string" },
        file: { type: "string" },
        mimeType: { type: "string" },
        appendMarkdown: { type: "boolean" },
        profile: { type: "string" }
      },
      required: ["write", "noteId", "file"],
      additionalProperties: false
    }
  },
  {
    name: "notelab_resources_list",
    description: "Count readable NoteLab resources.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false }
  }
];

function send(message) {
  const body = Buffer.from(JSON.stringify(message), "utf8");
  process.stdout.write(`Content-Length: ${body.length}\r\n\r\n`);
  process.stdout.write(body);
}

function cliArgsForTool(name, args) {
  const common = [];
  if (args.profile) common.push("--profile", String(args.profile));
  if (args.notebook) common.push("--notebook", String(args.notebook));
  if (args.limit) common.push("--limit", String(args.limit));
  const writeArgs = args.write === true ? ["--write"] : [];

  switch (name) {
    case "notelab_profiles_list":
      return ["profiles", "list"];
    case "notelab_notebooks_list":
      return [...common, "notebooks", "list"];
    case "notelab_notebook_create": {
      const createArgs = [...common, ...writeArgs, "notebooks", "create", "--title", String(args.title)];
      if (args.color) createArgs.push("--color", String(args.color));
      if (args.icon) createArgs.push("--icon", String(args.icon));
      return createArgs;
    }
    case "notelab_notebook_read":
      return [...common, "notebooks", "read", String(args.id)];
    case "notelab_notebook_update": {
      const updateArgs = [...common, ...writeArgs, "notebooks", "update", String(args.id)];
      if (args.title) updateArgs.push("--title", String(args.title));
      if (args.color) updateArgs.push("--color", String(args.color));
      if (args.icon) updateArgs.push("--icon", String(args.icon));
      if (args.description) updateArgs.push("--description", String(args.description));
      return updateArgs;
    }
    case "notelab_notebook_delete":
      return [...common, ...writeArgs, "notebooks", "delete", String(args.id)];
    case "notelab_notes_search":
      return [...common, "notes", "search", "--query", String(args.query)];
    case "notelab_note_read":
      return [...common, "notes", "read", String(args.id)];
    case "notelab_note_create": {
      const createArgs = [...common, ...writeArgs, "notes", "create"];
      if (args.title) createArgs.push("--title", String(args.title));
      if (args.content) createArgs.push("--content", String(args.content));
      return createArgs;
    }
    case "notelab_note_append":
      return [...common, ...writeArgs, "notes", "append", String(args.id), "--content", String(args.content)];
    case "notelab_note_update": {
      const updateArgs = [...common, ...writeArgs, "notes", "update", String(args.id)];
      if (args.title) updateArgs.push("--title", String(args.title));
      if (args.content !== undefined) updateArgs.push("--content", String(args.content));
      return updateArgs;
    }
    case "notelab_note_delete":
      return [...common, ...writeArgs, "notes", "delete", String(args.id)];
    case "notelab_content_read":
      return [...common, "content", "read", String(args.id)];
    case "notelab_content_update":
      return [...common, ...writeArgs, "content", "update", String(args.id), "--content", String(args.content)];
    case "notelab_content_append":
      return [...common, ...writeArgs, "content", "append", String(args.id), "--content", String(args.content)];
    case "notelab_content_clear":
      return [...common, ...writeArgs, "content", "clear", String(args.id)];
    case "notelab_attachments_list":
      return args.noteId ? [...common, "attachments", "list", String(args.noteId)] : [...common, "attachments", "list"];
    case "notelab_attachment_add": {
      const addArgs = [...common, ...writeArgs, "attachments", "add", String(args.noteId), "--file", String(args.file)];
      if (args.mimeType) addArgs.push("--mime-type", String(args.mimeType));
      if (args.appendMarkdown === false) addArgs.push("--no-append-markdown");
      return addArgs;
    }
    case "notelab_resources_list":
      return ["resources", "list"];
    default:
      throw new Error(`Unknown tool: ${name}`);
  }
}

function runCli(args) {
  return new Promise((resolve, reject) => {
    execFile(cli, args, { maxBuffer: 10 * 1024 * 1024 }, (error, stdout, stderr) => {
      if (error) {
        reject(new Error((stderr || error.message).trim()));
      } else {
        resolve(stdout.trim());
      }
    });
  });
}

async function handle(message) {
  if (message.method === "notifications/initialized") return;

  if (message.method === "initialize") {
    send({
      jsonrpc: "2.0",
      id: message.id,
      result: {
        protocolVersion: "2024-11-05",
        capabilities: { tools: {} },
        serverInfo: { name: "notelab", version: "0.1.0" }
      }
    });
    return;
  }

  if (message.method === "tools/list") {
    send({ jsonrpc: "2.0", id: message.id, result: { tools } });
    return;
  }

  if (message.method === "tools/call") {
    try {
      const name = message.params && message.params.name;
      const args = (message.params && message.params.arguments) || {};
      const output = await runCli(cliArgsForTool(name, args));
      send({
        jsonrpc: "2.0",
        id: message.id,
        result: { content: [{ type: "text", text: output }] }
      });
    } catch (error) {
      send({
        jsonrpc: "2.0",
        id: message.id,
        error: { code: -32000, message: error.message }
      });
    }
    return;
  }

  send({
    jsonrpc: "2.0",
    id: message.id,
    error: { code: -32601, message: `Method not found: ${message.method}` }
  });
}

function drain() {
  while (true) {
    const headerEnd = buffer.indexOf("\r\n\r\n");
    if (headerEnd === -1) return;

    const header = buffer.slice(0, headerEnd).toString("utf8");
    const match = header.match(/Content-Length:\s*(\d+)/i);
    if (!match) {
      buffer = Buffer.alloc(0);
      return;
    }

    const length = Number(match[1]);
    const bodyStart = headerEnd + 4;
    const bodyEnd = bodyStart + length;
    if (buffer.length < bodyEnd) return;

    const body = buffer.slice(bodyStart, bodyEnd).toString("utf8");
    buffer = buffer.slice(bodyEnd);
    Promise.resolve()
      .then(() => handle(JSON.parse(body)))
      .catch((error) => send({ jsonrpc: "2.0", id: null, error: { code: -32700, message: error.message } }));
  }
}

process.stdin.on("data", (chunk) => {
  buffer = Buffer.concat([buffer, chunk]);
  drain();
});
