// ULLAH server — Node stdlib only. Proxies to the local OmniRoute gateway so the
// API key never reaches the browser.
const http = require("http");
const fs = require("fs");
const path = require("path");

const PORT = process.env.PORT || 8081;
const GATEWAY = process.env.OMNIROUTE_URL || "http://127.0.0.1:20128";
const API_KEY = process.env.OMNIROUTE_KEY || "omniroute-local";
const ROOT = __dirname;

const TYPES = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".txt": "text/plain; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".webmanifest": "application/manifest+json",
};

function readPersona() {
  try {
    return fs.readFileSync(path.join(ROOT, "persona.txt"), "utf8").trim();
  } catch {
    return "You are ULLAH, a helpful coding agent.";
  }
}

function send(res, code, body, type) {
  res.writeHead(code, { "Content-Type": type || "application/json; charset=utf-8" });
  res.end(body);
}

function serveStatic(req, res, urlPath) {
  let rel = urlPath === "/" ? "/index.html" : urlPath;
  const full = path.join(ROOT, rel);
  // prevent path traversal
  if (!full.startsWith(ROOT)) return send(res, 403, "Forbidden", "text/plain");
  fs.readFile(full, (err, data) => {
    if (err) return send(res, 404, "Not found", "text/plain");
    let type = TYPES[path.extname(full)] || "application/octet-stream";
    if (path.basename(full) === "manifest.json") type = "application/manifest+json";
    res.writeHead(200, { "Content-Type": type });
    res.end(data);
  });
}

// POST /api/chat  { model, messages:[{role,content}] }  -> streams SSE back
async function handleChat(req, res) {
  let body = "";
  req.on("data", (c) => (body += c));
  req.on("end", async () => {
    let payload;
    try {
      payload = JSON.parse(body || "{}");
    } catch {
      return send(res, 400, JSON.stringify({ error: "bad json" }));
    }
    const messages = Array.isArray(payload.messages) ? payload.messages.slice() : [];
    messages.unshift({ role: "system", content: readPersona() });
    const out = {
      model: payload.model || "auto",
      stream: true,
      messages,
    };
    let upstream;
    try {
      upstream = await fetch(GATEWAY + "/v1/chat/completions", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: "Bearer " + API_KEY,
        },
        body: JSON.stringify(out),
      });
    } catch (e) {
      return send(res, 502, JSON.stringify({ error: "gateway unreachable: " + e.message }));
    }
    if (!upstream.ok) {
      const txt = await upstream.text().catch(() => "");
      return send(res, upstream.status, JSON.stringify({ error: "gateway error", detail: txt.slice(0, 500) }));
    }
    res.writeHead(200, {
      "Content-Type": "text/event-stream; charset=utf-8",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
    });
    const reader = upstream.body.getReader();
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        res.write(Buffer.from(value));
      }
    } catch {
      // client disconnected or upstream ended
    }
    res.end();
  });
}

// GET /api/models -> {"data":[{id,...}]}  tries /v1/models then /v1beta/models
async function handleModels(req, res) {
  try {
    let r = await fetch(GATEWAY + "/v1/models", {
      headers: { Authorization: "Bearer " + API_KEY },
    });
    if (r.ok) {
      const j = await r.json();
      return send(res, 200, JSON.stringify({ data: j.data || j.models || [] }));
    }
    // fall back to Gemini-format catalog
    r = await fetch(GATEWAY + "/v1beta/models");
    if (r.ok) {
      const j = await r.json();
      const data = (j.models || []).map((m) => ({
        id: (m.name || "").replace(/^models\//, ""),
        name: m.displayName || m.name,
      }));
      return send(res, 200, JSON.stringify({ data }));
    }
    return send(res, r.status, JSON.stringify({ error: "models unavailable" }));
  } catch (e) {
    return send(res, 502, JSON.stringify({ error: "gateway unreachable: " + e.message }));
  }
}

http
  .createServer((req, res) => {
    const url = new URL(req.url, "http://localhost");
    const p = url.pathname;
    if (req.method === "POST" && p === "/api/chat") return handleChat(req, res);
    if (req.method === "GET" && p === "/api/models") return handleModels(req, res);
    if (req.method === "GET") return serveStatic(req, res, p);
    return send(res, 405, "Method not allowed", "text/plain");
  })
  .listen(PORT, () => {
    console.log(`ULLAH running: http://127.0.0.1:${PORT}`);
    console.log(`Gateway: ${GATEWAY}`);
  });
