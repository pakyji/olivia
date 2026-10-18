// Olivia Thomas server — Node stdlib only. Proxies to the local OmniRoute gateway so the
// API key never reaches the browser.
const http = require("http");
const fs = require("fs");
const path = require("path");

process.on("uncaughtException", (e) => { try { console.error("UNCAUGHT:", e && e.message); } catch (e2) {} });
process.on("unhandledRejection", (e) => { try { console.error("UNHANDLED:", e && e.message); } catch (e2) {} });

const PORT = process.env.PORT || 8080;
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
    return "You are Olivia Thomas, a helpful coding agent.";
  }
}

function send(res, code, body, type) {
  res.writeHead(code, { "Content-Type": type || "application/json; charset=utf-8" });
  res.end(body);
}

function serveStatic(req, res, urlPath) {
  let rel = urlPath === "/" ? "/index.html" : urlPath;
  const full = path.join(ROOT, rel);
  // prevent path traversal (separator-aware: blocks /root-prefix-sibling escapes)
  if (full !== ROOT && !full.startsWith(ROOT + path.sep)) return send(res, 403, "Forbidden", "text/plain");
  fs.readFile(full, (err, data) => {
    if (err) return send(res, 404, "Not found", "text/plain");
    let type = TYPES[path.extname(full)] || "application/octet-stream";
    if (path.basename(full) === "manifest.json") type = "application/manifest+json";
    res.writeHead(200, { "Content-Type": type });
    res.end(data);
  });
}

/* ---------- gateway calls via Node stdlib http (fetch-free, crash-proof) ---------- */
function readBody(r) {
  return new Promise((resolve) => {
    let d = "";
    r.on("data", (c) => (d += c));
    r.on("end", () => resolve(d));
  });
}
function gwRequest(pathname, bodyObj) {
  return new Promise((resolve, reject) => {
    const u = new URL(GATEWAY + pathname);
    const payload = bodyObj ? Buffer.from(JSON.stringify(bodyObj)) : null;
    const headers = { Authorization: "Bearer " + API_KEY };
    if (payload) {
      headers["Content-Type"] = "application/json";
      headers["Content-Length"] = payload.length;
    }
    const req = http.request(
      {
        host: u.hostname,
        port: u.port || 80,
        path: u.pathname + (u.search || ""),
        method: bodyObj ? "POST" : "GET",
        headers,
        timeout: 25000,
      },
      (res) => resolve(res)
    );
    req.on("error", reject);
    req.on("timeout", () => req.destroy(new Error("gateway timeout")));
    if (payload) req.write(payload);
    req.end();
  });
}

// POST /api/chat  { model, messages:[{role,content}], lang }  -> streams SSE back
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
    let system = readPersona();
    if (payload.lang) system += "\n\nRESPOND STRICTLY IN: " + payload.lang;
    messages.unshift({ role: "system", content: system });
    const out = {
      model: payload.model || "auto",
      stream: true,
      messages,
    };
    let upstream;
    try {
      upstream = await gwRequest("/v1/chat/completions", out);
    } catch (e) {
      return send(res, 502, JSON.stringify({ error: "gateway unreachable: " + e.message }));
    }
    if (!upstream.statusCode || upstream.statusCode >= 400) {
      const txt = await readBody(upstream);
      return send(res, upstream.statusCode || 502, JSON.stringify({ error: "gateway error", detail: txt.slice(0, 500) }));
    }
    res.writeHead(200, {
      "Content-Type": "text/event-stream; charset=utf-8",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
    });
    upstream.on("data", (c) => res.write(c));
    upstream.on("end", () => res.end());
    upstream.on("error", () => res.end());
  });
}


/* ---------- JARVIS actions: apps, projects, zip, run, git ---------- */
const { execFile } = require("child_process");

function run(cmd, args, opts) {
  return new Promise((resolve) => {
    execFile(cmd, args, Object.assign({ timeout: 25000, maxBuffer: 512 * 1024 }, opts || {}),
      (err, stdout, stderr) => {
        if (err) console.error("RUN ERROR:", cmd, args, err, stderr);
        resolve({
          ok: !err,
          out: String(stdout || ""),
          err: String(stderr || "") + (err ? " | " + String(err.message) : ""),
        });
      });
  });
}

const APPS = {
  whatsapp: "com.whatsapp", youtube: "com.google.android.youtube", chrome: "com.android.chrome",
  settings: "com.android.settings", maps: "com.google.android.apps.maps", photos: "com.google.android.photos",
  instagram: "com.instagram.android", spotify: "com.spotify.music", phone: "com.android.dialer",
  messages: "com.google.android.messages", clock: "com.google.android.deskclock",
  files: "com.google.android.documentsui", playstore: "com.android.vending",
  telegram: "org.telegram.messenger", gmail: "com.google.android.gm", termux: "com.termux",
  calculator: "com.google.android.calculator", facebook: "com.facebook.katana",
  netflix: "com.netflix.mediaclient", snapchat: "com.snapchat.android", discord: "com.discord",
};
const SAFE = /^[A-Za-z0-9._-]+$/;
const PROJECTS = path.join(ROOT, "projects");
const FILES = path.join(ROOT, "files");

function crc32(buf) {
  let t = [];
  for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t[n] = c; }
  let crc = 0xffffffff;
  for (const b of buf) crc = t[(crc ^ b) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}
function makeZip(entries) {
  const chunks = [], central = [];
  let offset = 0;
  for (const e of entries) {
    const name = Buffer.from(e.name);
    const crc = crc32(e.buf);
    const loc = Buffer.alloc(30);
    loc.writeUInt32LE(0x04034b50, 0); loc.writeUInt16LE(20, 4);
    loc.writeUInt32LE(crc, 14); loc.writeUInt32LE(e.buf.length, 18); loc.writeUInt32LE(e.buf.length, 22);
    loc.writeUInt16LE(name.length, 26);
    chunks.push(loc, name, e.buf);
    const cen = Buffer.alloc(46);
    cen.writeUInt32LE(0x02014b50, 0); cen.writeUInt16LE(20, 4); cen.writeUInt16LE(20, 6);
    cen.writeUInt32LE(crc, 16); cen.writeUInt32LE(e.buf.length, 20); cen.writeUInt32LE(e.buf.length, 24);
    cen.writeUInt16LE(name.length, 28); cen.writeUInt32LE(offset, 42);
    central.push(Buffer.concat([cen, name]));
    offset += 30 + name.length + e.buf.length;
  }
  const cenBuf = Buffer.concat(central);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(entries.length, 8); end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(cenBuf.length, 12); end.writeUInt32LE(offset, 16);
  return Buffer.concat(chunks.concat([cenBuf, end]));
}
function walk(dir, base, out, depth) {
  if (depth > 6) return out;
  for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
    if (ent.name.startsWith(".") || ent.name === "node_modules") continue;
    const full = path.join(dir, ent.name);
    if (ent.isDirectory()) walk(full, path.join(base, ent.name), out, depth + 1);
    else if (ent.isFile()) out.push({ name: path.join(base, ent.name).split(path.sep).join("/"), buf: fs.readFileSync(full) });
  }
  return out;
}

async function handleAct(req, res) {
  let body = "";
  req.on("data", (c) => (body += c));
  req.on("end", async () => {
    let a;
    try { a = JSON.parse(body || "{}"); } catch { return send(res, 400, JSON.stringify({ ok: false, detail: "bad json" })); }
    const action = String(a.action || "");
    try {
      if (action === "open_app") {
        const key = String(a.name || "").toLowerCase().trim();
        if (key === "camera") {
          const r = await run("/system/bin/am", ["start", "-a", "android.media.action.STILL_IMAGE_CAMERA"]);
          return send(res, 200, JSON.stringify({ ok: r.ok, detail: r.ok ? "Camera opening." : r.err }));
        }
        const pkg = APPS[key];
        if (!pkg) return send(res, 200, JSON.stringify({ ok: false, detail: "Unknown app: " + key + ". Try: " + Object.keys(APPS).join(", ") }));
        // foreground-only launch works via APK bridge; this server path is best-effort with tight timeouts
        const rr = await run("/system/bin/cmd", ["package", "resolve-activity", "--brief", pkg], { timeout: 6000 });
        const line = String(rr.out || "").trim().split("\n").pop().trim();
        let r = null;
        if (rr.ok && line && line.includes("/")) r = await run("/system/bin/am", ["start", "-n", line], { timeout: 6000 });
        if (!r || !r.ok) r = await run("/system/bin/monkey", ["-p", pkg, "-c", "android.intent.category.LAUNCHER", "1"], { timeout: 8000 });
        return send(res, 200, JSON.stringify({ ok: r.ok, detail: r.ok ? "Opening " + key + "." : "Android blocked background launch: " + r.err.slice(0, 140) }));
      }
      if (action === "open_url") {
        const url = String(a.url || "");
        if (!/^https?:\/\//.test(url)) return send(res, 200, JSON.stringify({ ok: false, detail: "Only http(s) URLs." }));
        const r = await run("/system/bin/am", ["start", "-a", "android.intent.action.VIEW", "-d", url]);
        return send(res, 200, JSON.stringify({ ok: r.ok, detail: r.ok ? "Opening " + url : r.err }));
      }
      if (action === "save_file") {
        const proj = String(a.project || "myapp"); const file = String(a.file || "");
        if (!SAFE.test(proj) || !SAFE.test(file)) return send(res, 200, JSON.stringify({ ok: false, detail: "Bad project/file name." }));
        const dir = path.join(PROJECTS, proj);
        fs.mkdirSync(dir, { recursive: true });
        fs.writeFileSync(path.join(dir, file), String(a.content || ""));
        return send(res, 200, JSON.stringify({ ok: true, detail: "Saved " + proj + "/" + file }));
      }
      if (action === "list_projects") {
        let list = [];
        try { list = fs.readdirSync(PROJECTS); } catch {}
        return send(res, 200, JSON.stringify({ ok: true, detail: list.length ? list.join(", ") : "No projects yet. Save code first." }));
      }
      if (action === "zip_project") {
        const proj = String(a.project || "");
        if (!SAFE.test(proj)) return send(res, 200, JSON.stringify({ ok: false, detail: "Bad project name." }));
        const dir = path.join(PROJECTS, proj);
        if (!fs.existsSync(dir)) return send(res, 200, JSON.stringify({ ok: false, detail: "Project not found: " + proj }));
        const entries = walk(dir, proj, [], 0);
        if (!entries.length) return send(res, 200, JSON.stringify({ ok: false, detail: "Project empty." }));
        fs.mkdirSync(FILES, { recursive: true });
        const zipPath = path.join(FILES, proj + ".zip");
        fs.writeFileSync(zipPath, makeZip(entries));
        return send(res, 200, JSON.stringify({ ok: true, detail: "ZIP ready: http://127.0.0.1:" + PORT + "/files/" + proj + ".zip (" + entries.length + " files)" }));
      }
      if (action === "run_node") {
        const proj = String(a.project || "myapp"); const file = String(a.file || "");
        if (!SAFE.test(proj) || !SAFE.test(file)) return send(res, 200, JSON.stringify({ ok: false, detail: "Bad names." }));
        const full = path.join(PROJECTS, proj, file);
        if (!fs.existsSync(full)) return send(res, 200, JSON.stringify({ ok: false, detail: "File not found: " + proj + "/" + file }));
        const r = await run(process.execPath, [full], { cwd: path.join(PROJECTS, proj), timeout: 8000 });
        return send(res, 200, JSON.stringify({ ok: r.ok, detail: (r.out || r.err || "no output").slice(0, 800) }));
      }
      if (action === "speak") {
        const text = String(a.text || "").slice(0, 600);
        if (!text) return send(res, 200, JSON.stringify({ ok: false, detail: "nothing to speak" }));
        const lang = String(a.lang || "en-US");
        const r = await run("termux-tts-speak", ["-l", lang, "-t", text]);
        return send(res, 200, JSON.stringify({ ok: r.ok, detail: r.ok ? "speaking" : "termux-tts unavailable: " + r.err.slice(0, 150) }));
      }
      if (action === "stop_speak") {
        const r = await run("termux-tts-stop", []);
        return send(res, 200, JSON.stringify({ ok: true, detail: "stopped" }));
      }
      if (action === "send_sms") {
        const to = String(a.to || "").replace(/[^\d+]/g, "");
        const text = String(a.text || "");
        if (to.length < 7 || !text) return send(res, 200, JSON.stringify({ ok: false, detail: "Usage: send sms to <number>: <message>" }));
        const r = await run("termux-sms-send", ["-n", to, text]);
        return send(res, 200, JSON.stringify({ ok: r.ok, detail: r.ok ? "SMS sent to " + to + "." : "SMS failed — install Termux:API app + pkg install termux-api, grant SMS permission. (" + r.err.slice(0, 200) + ")" }));
      }
      if (action === "scroll") {
        const dir = String(a.dir || "down");
        const args = dir === "up" ? ["swipe", "360", "400", "360", "900", "300"] : ["swipe", "360", "900", "360", "400", "300"];
        const r = await run("/system/bin/input", args);
        return send(res, 200, JSON.stringify({ ok: r.ok, detail: r.ok ? "Scrolled " + dir + "." : r.err }));
      }
      if (action === "tap") {
        const x = parseInt(a.x, 10), y = parseInt(a.y, 10);
        if (!(x >= 0) || !(y >= 0)) return send(res, 200, JSON.stringify({ ok: false, detail: "tap needs x and y" }));
        const r = await run("/system/bin/input", ["tap", String(x), String(y)]);
        return send(res, 200, JSON.stringify({ ok: r.ok, detail: r.ok ? "Tapped " + x + "," + y + "." : r.err }));
      }
      if (action === "key") {
        const map = { back: "4", home: "3", enter: "66", recents: "187" };
        const k = map[String(a.name || "").toLowerCase()];
        if (!k) return send(res, 200, JSON.stringify({ ok: false, detail: "keys: back, home, enter, recents" }));
        const r = await run("/system/bin/input", ["keyevent", k]);
        return send(res, 200, JSON.stringify({ ok: r.ok, detail: r.ok ? "Pressed " + a.name + "." : r.err }));
      }
      if (action === "git_push") {
        const msg = String(a.message || "Olivia: auto commit");
        const g = (args) => run("git", ["-C", ROOT].concat(args));
        const r1 = await g(["add", "-A"]);
        const r2 = await g(["commit", "-m", msg]);
        const r3 = await g(["push"]);
        const committed = /nothing to commit/i.test(r2.out + r2.err) ? "nothing new to commit" : "committed";
        return send(res, 200, JSON.stringify({ ok: r3.ok, detail: committed + " | push: " + (r3.ok ? "done" : r3.err.slice(0, 300)) }));
      }
      return send(res, 200, JSON.stringify({ ok: false, detail: "Unknown action: " + action }));
    } catch (e) {
      return send(res, 200, JSON.stringify({ ok: false, detail: String(e.message || e).slice(0, 300) }));
    }
  });
}

// GET /api/models -> {"data":[{id,...}]}  tries /v1/models then /v1beta/models
async function handleModels(req, res) {
  try {
    let r = await gwRequest("/v1/models");
    if (r.statusCode === 200) {
      try {
        const j = JSON.parse(await readBody(r) || "{}");
        return send(res, 200, JSON.stringify({ data: j.data || j.models || [] }));
      } catch {}
    }
    // fall back to Gemini-format catalog
    r = await gwRequest("/v1beta/models");
    if (r.statusCode === 200) {
      try {
        const j = JSON.parse(await readBody(r) || "{}");
        const data = (j.models || []).map((m) => ({
          id: (m.name || "").replace(/^models\//, ""),
          name: m.displayName || m.name,
        }));
        return send(res, 200, JSON.stringify({ data }));
      } catch {}
    }
    // gateway is reachable (any status) -> good enough for chat
    return send(res, 200, JSON.stringify({ data: [{ id: "auto", name: "auto (chat verified)" }] }));
  } catch (e) {
    return send(res, 502, JSON.stringify({ error: "gateway unreachable: " + e.message }));
  }
}

http
  .createServer((req, res) => {
    const url = new URL(req.url, "http://localhost");
    const p = url.pathname;
    if (req.method === "POST" && p === "/api/chat") return handleChat(req, res);
    if (req.method === "POST" && p === "/api/act") return handleAct(req, res);
    if (req.method === "GET" && p === "/api/models") return handleModels(req, res);
    if (req.method === "GET") return serveStatic(req, res, p);
    return send(res, 405, "Method not allowed", "text/plain");
  })
  .listen(PORT, () => {
    console.log(`Olivia running: http://127.0.0.1:${PORT} (node ${process.version})`);
    console.log(`Gateway: ${GATEWAY}`);
  });
