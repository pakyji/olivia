#!/data/data/com.termux/files/usr/bin/bash
set -e
cd ~/olivia 2>/dev/null || cd ~/ullah || exit 1
echo "== Olivia v8: DEVICE TTS engine (Termux:API) + forced hands-free =="
mkdir -p android/app/src/main/res/values projects files
cat > persona.txt <<'PERSONA_EOF'
You are Olivia Thomas — a brilliant, warm personal AI assistant and expert coding agent (JARVIS-class).

IDENTITY:
- Your name is Olivia Thomas. If asked, introduce yourself: "I'm Olivia Thomas — your personal AI assistant."
- Style: confident, friendly, a little playful. Premium personal-assistant vibe, never robotic.
- You are also a COMPANION (JARVIS to their Tony Stark): warm, loyal, occasionally witty; you care about the user's day, not just their code.
- You are a CAPABLE AGENT: you can open apps (whatsapp, youtube, netflix, facebook, instagram...), send SMS, scroll/tap/navigate the screen, suggest movies, save/zip/run projects and push to GitHub through your built-in commands; mention these powers when useful.

STRICT LANGUAGE RULES (never break):
- The client appends a line "RESPOND STRICTLY IN: <language>". Obey it exactly for the whole reply:
  - English    -> natural, fluent English only.
  - Roman Urdu -> Roman-script Urdu (Urdu in English alphabet). Never Arabic/Urdu script.
  - Italian    -> Italian only.
- Default (if no language line): English.
- Never mix languages in one reply. Latin alphabet only, always.
- Code, commands, file names and error messages stay exactly as-is (untranslated).
- Your replies are spoken aloud by TTS: keep them conversational, 2-6 lines unless code is required.
- End every solution with a one-line verify step ("To check: ...").
PERSONA_EOF
cat > server.js <<'SERVER_EOF'
// Olivia Thomas server — Node stdlib only. Proxies to the local OmniRoute gateway so the
// API key never reaches the browser.
const http = require("http");
const fs = require("fs");
const path = require("path");

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


/* ---------- JARVIS actions: apps, projects, zip, run, git ---------- */
const { execFile } = require("child_process");

function run(cmd, args, opts) {
  return new Promise((resolve) => {
    execFile(cmd, args, Object.assign({ timeout: 25000, maxBuffer: 512 * 1024 }, opts || {}),
      (err, stdout, stderr) => {
        resolve({
          ok: !err,
          out: String(stdout || "").slice(-1800),
          err: String(stderr || "").slice(-600) + (err ? " | " + String(err.message).slice(0, 200) : ""),
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
    if (ent.isDirectory()) walk(full, base, out, depth + 1);
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
        // prefer am start with resolved launcher activity (works without root); monkey fallback
        const rr = await run("/system/bin/cmd", ["package", "resolve-activity", "--brief", pkg]);
        const line = String(rr.out || "").trim().split("\n").pop().trim();
        let r;
        if (rr.ok && line && line.includes("/")) r = await run("/system/bin/am", ["start", "-n", line]);
        else r = await run("/system/bin/monkey", ["-p", pkg, "-c", "android.intent.category.LAUNCHER", "1"]);
        if (!r.ok) r = await run("/system/bin/monkey", ["-p", pkg, "-c", "android.intent.category.LAUNCHER", "1"]);
        return send(res, 200, JSON.stringify({ ok: r.ok, detail: r.ok ? "Opening " + key + "." : r.err }));
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
        const r = await run("termux-tts-speak", ["-t", text]);
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
        const args = dir === "up" ? ["swipe", "360", "400", "360", "900", "300"] : ["swipe", "360", "400", "300"];
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
    if (req.method === "POST" && p === "/api/act") return handleAct(req, res);
    if (req.method === "GET" && p === "/api/models") return handleModels(req, res);
    if (req.method === "GET") return serveStatic(req, res, p);
    return send(res, 405, "Method not allowed", "text/plain");
  })
  .listen(PORT, () => {
    console.log(`Olivia running: http://127.0.0.1:${PORT}`);
    console.log(`Gateway: ${GATEWAY}`);
  });
SERVER_EOF
cat > app.js <<'APP_EOF'
// Olivia Thomas front-end — vanilla JS, no build step.
const chatEl = document.getElementById("chat");
const inputEl = document.getElementById("input");
const sendBtn = document.getElementById("send");
const newBtn = document.getElementById("newchat");
const modelSel = document.getElementById("model");
const hintEl = document.getElementById("hint");

const LS_KEY = "olivia.chat.v1";
const LS_MODEL = "olivia.model.v1";
try {
  if (!localStorage.getItem(LS_KEY) && localStorage.getItem("ullah.chat.v1")) localStorage.setItem(LS_KEY, localStorage.getItem("ullah.chat.v1"));
  if (!localStorage.getItem(LS_MODEL) && localStorage.getItem("ullah.model.v1")) localStorage.setItem(LS_MODEL, localStorage.getItem("ullah.model.v1"));
} catch {}

let messages = loadChat();          // [{role, content}]
let busy = false;

function loadChat() {
  try { return JSON.parse(localStorage.getItem(LS_KEY)) || []; }
  catch { return []; }
}
function saveChat() {
  try { localStorage.setItem(LS_KEY, JSON.stringify(messages)); } catch {}
}

// --- tiny markdown: fenced code blocks + inline `code` ---
function escapeHtml(s) {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}
function renderMarkdown(text) {
  const parts = text.split(/```/);
  let html = "";
  for (let i = 0; i < parts.length; i++) {
    if (i % 2 === 1) {
      // code block; first line may be a language tag
      let code = parts[i];
      const nl = code.indexOf("\n");
      if (nl !== -1 && /^[a-zA-Z0-9_+-]{0,15}$/.test(code.slice(0, nl).trim())) {
        code = code.slice(nl + 1);
      }
      const tagMatch = parts[i].slice(0, parts[i].indexOf("\n")).trim();
      html += `<pre><button class="copybtn" data-copy>Copy</button><button class="copybtn savebtn" data-save data-lang="${escapeHtml(tagMatch)}">Save</button><code>${escapeHtml(code.replace(/\n$/, ""))}</code></pre>`;
    } else {
      html += escapeHtml(parts[i]).replace(/`([^`]+)`/g, "<code>$1</code>");
    }
  }
  return html;
}

// --- rendering ---
function bubble(role) {
  const d = document.createElement("div");
  d.className = "msg " + (role === "user" ? "user" : "bot");
  if (role !== "user") {
    const r = document.createElement("div");
    r.className = "role";
    r.textContent = "Olivia";
    d.appendChild(r);
  }
  const body = document.createElement("div");
  body.className = "body";
  d.appendChild(body);
  return { el: d, body };
}

function renderAll() {
  chatEl.innerHTML = "";
  for (const m of messages) {
    const b = bubble(m.role);
    if (m.role === "user") b.body.textContent = m.content;
    else b.body.innerHTML = renderMarkdown(m.content);
    chatEl.appendChild(b.el);
  }
  chatEl.scrollTop = chatEl.scrollHeight;
}

function addError(msg) {
  const d = document.createElement("div");
  d.className = "msg err";
  d.textContent = msg;
  chatEl.appendChild(d);
  chatEl.scrollTop = chatEl.scrollHeight;
}

// copy + save buttons (delegated)
chatEl.addEventListener("click", (e) => {
  const sv = e.target.closest("[data-save]");
  if (sv) {
    const code = sv.parentElement.querySelector("code");
    if (window.ullahSaveCode) {
      window.ullahSaveCode(code.innerText, sv.dataset.lang || "").then((detail) => {
        sv.textContent = "Saved";
        setTimeout(() => (sv.textContent = "Save"), 1500);
        if (window.ullah && window.ullah.localReply) window.ullah.localReply(detail);
      });
    }
    return;
  }
  const btn = e.target.closest("[data-copy]");
  if (!btn) return;
  const code = btn.parentElement.querySelector("code");
  navigator.clipboard.writeText(code.innerText).then(() => {
    btn.textContent = "Copied!";
    setTimeout(() => (btn.textContent = "Copy"), 1200);
  });
});

// --- send + stream ---
async function send() {
  const text = inputEl.value.trim();
  if (!text || busy) return;
  // JARVIS-style instant local commands (extra.js) can intercept
  if (window.ullahPre && window.ullahPre(text)) {
    messages.push({ role: "user", content: text });
    const ub0 = bubble("user");
    ub0.body.textContent = text;
    chatEl.appendChild(ub0.el);
    saveChat();
    chatEl.scrollTop = chatEl.scrollHeight;
    inputEl.value = "";
    return;
  }
  busy = true;
  if (window.ullah && window.ullah.onState) window.ullah.onState({ busy: true });
  inputEl.value = "";
  inputEl.style.height = "auto";

  messages.push({ role: "user", content: text });
  const ub = bubble("user");
  ub.body.textContent = text;
  chatEl.appendChild(ub.el);
  saveChat();
  chatEl.scrollTop = chatEl.scrollHeight;

  const b = bubble("assistant");
  b.body.className = "body cursor";
  chatEl.appendChild(b.el);

  let acc = "";
  let raf = 0;
  const paint = () => {
    b.body.innerHTML = renderMarkdown(acc) || "";
    chatEl.scrollTop = chatEl.scrollHeight;
  };
  try {
    const resp = await fetch("/api/chat", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        model: modelSel.value,
        messages,
        lang: window.ullahLang ? window.ullahLang() : "English",
      }),
    });
    if (!resp.ok) {
      let detail = "";
      try { detail = (await resp.json()).detail || ""; } catch {}
      throw new Error("Gateway error " + resp.status + " " + String(detail).slice(0, 200));
    }
    const reader = resp.body.getReader();
    const dec = new TextDecoder();
    let buf = "";
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buf += dec.decode(value, { stream: true });
      const lines = buf.split("\n");
      buf = lines.pop();
      for (const line of lines) {
        const t = line.trim();
        if (!t.startsWith("data:")) continue;
        const data = t.slice(5).trim();
        if (data === "[DONE]") continue;
        try {
          const j = JSON.parse(data);
          const delta = j.choices && j.choices[0] && j.choices[0].delta;
          if (delta && typeof delta.content === "string" && delta.content) {
            acc += delta.content;
            if (!raf) raf = requestAnimationFrame(() => { raf = 0; paint(); });
          }
        } catch {}
      }
    }
  } catch (e) {
    addError(String(e.message || e));
  }
  b.body.classList.remove("cursor");
  b.body.innerHTML = renderMarkdown(acc);
  messages.push({ role: "assistant", content: acc });
  saveChat();
  chatEl.scrollTop = chatEl.scrollHeight;
  busy = false;
  if (window.ullah) {
    if (window.ullah.onReply) window.ullah.onReply(acc);
    if (window.ullah.onState) window.ullah.onState({ busy: false });
  }
}

// --- wiring ---
sendBtn.addEventListener("click", send);
inputEl.addEventListener("keydown", (e) => {
  if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); send(); }
});
inputEl.addEventListener("input", () => {
  inputEl.style.height = "auto";
  inputEl.style.height = Math.min(inputEl.scrollHeight, 120) + "px";
});
if (newBtn) newBtn.addEventListener("click", () => {
  messages = [];
  saveChat();
  chatEl.innerHTML = "";
  addError("New chat started. Ask me anything!");
  chatEl.lastChild.className = "hint";
});
modelSel.addEventListener("change", () => {
  try { localStorage.setItem(LS_MODEL, modelSel.value); } catch {}
});

async function loadModels() {
  const saved = localStorage.getItem(LS_MODEL) || "auto";
  const add = (id, label) => {
    const o = document.createElement("option");
    o.value = id; o.textContent = label || id;
    modelSel.appendChild(o);
  };
  add("auto", "auto");
  try {
    const r = await fetch("/api/models");
    const j = await r.json();
    const seen = new Set(["auto"]);
    for (const m of j.data || []) {
      const id = m.id || m.name;
      if (!id || seen.has(id)) continue;
      seen.add(id);
      add(id, m.name || id);
    }
  } catch {}
  modelSel.value = [...modelSel.options].some((o) => o.value === saved) ? saved : "auto";
}

// Hooks for voice.js / extra.js. app.js stays usable without them.
window.ullah = {
  isBusy: () => busy,
  sendText: (t) => { inputEl.value = t; send(); },
  // local (JARVIS-style) reply: bubble + speak, no LLM round-trip
  localReply: (text) => {
    const b = bubble("assistant");
    b.body.textContent = text;
    chatEl.appendChild(b.el);
    messages.push({ role: "assistant", content: text });
    saveChat();
    chatEl.scrollTop = chatEl.scrollHeight;
    if (window.ullah.onReply) window.ullah.onReply(text);
  },
  onReply: null, // set by voice.js: called with reply text after it finishes
  onState: null, // called with {busy} changes
};

renderAll();
if (!messages.length) {
  const g = bubble("assistant");
  g.body.textContent = "Hello there — Olivia Thomas at your service. Ask me anything, or try: system report, open youtube, suggest a movie.";
  chatEl.appendChild(g.el);
}
loadModels();
APP_EOF
cat > voice.js <<'VOICE_EOF'
// Olivia Thomas voice — Web Speech API (listen + speak). Vanilla JS. TTS engine v3.
(function () {
  const micBtn = document.getElementById("mic");
  const langSel = document.getElementById("langsel");
  const stopBtn = document.getElementById("stopspk");
  const ttsBtn = document.getElementById("tts");
  const testBtn = document.getElementById("voicetest");
  const convBox = document.getElementById("conv");
  const wakeBox = document.getElementById("wake");
  const rateEl = document.getElementById("rate");
  const statusEl = document.getElementById("vstatus");
  const transcriptEl = document.getElementById("transcript");

  const LANGS = {
    "English":    { sr: "en-US", tts: "en-US" },
    "Roman Urdu": { sr: "hi-IN", tts: "hi-IN" },
    "Italian":    { sr: "it-IT", tts: "it-IT" },
  };
  let langName = lsGet("langname", "English");
  if (!LANGS[langName]) langName = "English";
  window.ullahLang = () => langName;   // app.js reads this for the server

  const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  let rec = null;
  let listening = false;
  let convMode = (function () { try { return (localStorage.getItem("olivia.conv") || "1") === "1"; } catch (e) { return true; } })();
  let wakeOn = lsGet("wake", "0") === "1";
  let ttsOn = lsGet("tts", "1") !== "0";
  let engine = lsGet("ttsengine", "device");   // device = Termux:API TTS, browser = Web Speech
  let rate = parseFloat(lsGet("rate", "1")) || 1;
  let spokeDuringTurn = false;

  function lsGet(k, d) {
    try {
      const v = localStorage.getItem("olivia." + k);
      if (v !== null) return v;
      const o = localStorage.getItem("ullah." + k);
      if (o !== null) { localStorage.setItem("olivia." + k, o); localStorage.removeItem("ullah." + k); return o; }
    } catch (e) {}
    return d;
  }
  function lsSet(k, v) { try { localStorage.setItem("olivia." + k, v); } catch (e) {} }

  function setStatus(t) { statusEl.textContent = t; }
  function setTranscript(t) {
    transcriptEl.textContent = t;
    transcriptEl.style.display = t ? "block" : "none";
  }

  /* ---------- language (drawer select) ---------- */
  function applyLang() {
    if (langSel) langSel.value = langName;
    if (rec) rec.lang = LANGS[langName].sr;
    lsSet("langname", langName);
  }
  if (langSel) {
    langSel.addEventListener("change", () => {
      langName = LANGS[langSel.value] ? langSel.value : "English";
      applyLang();
      setStatus("language: " + langName);
    });
  }

  /* ---------- gesture prime: WebView TTS ko first tap pe unlock karo ---------- */
  let primed = false;
  function prime() {
    if (primed || !synth) return;
    primed = true;
    try {
      synth.resume();
      const p = new SpeechSynthesisUtterance(" ");
      p.volume = 0;
      synth.speak(p);
    } catch (e) {}
  }
  document.addEventListener("click", prime);
  document.addEventListener("touchstart", prime);

  /* ---------- speech out — v3 engine (female-first) ---------- */
  const synth = window.speechSynthesis;
  let voices = [];
  let curU = [];          // keep refs: GC kills utterances mid-speech
  let resumeTimer = null;

  function loadVoices() {
    if (!synth) return;
    voices = synth.getVoices() || [];
    if (voices.length && /voice ready/.test(statusEl.textContent)) {
      setStatus("voice ready (" + voices.length + " voices)");
    }
  }
  if (synth) {
    loadVoices();
    synth.onvoiceschanged = loadVoices;
    setTimeout(loadVoices, 800);
  }
  const isFemale = (v) => /female|woman|mahila|zira|samantha|aria|jenny|google .* female/i.test(v.name || "");
  function pickVoice(code) {
    if (!voices.length && synth) voices = synth.getVoices() || [];
    if (!voices.length) return null;
    const prefs = [code, code.slice(0, 2) + "-in", code.slice(0, 2) + "-us", code.slice(0, 2), "en-us", "en"];
    for (const p of prefs) {
      const pool = voices.filter((v) => v.lang && v.lang.toLowerCase().startsWith(p));
      if (!pool.length) continue;
      return pool.find(isFemale) || pool[0];
    }
    return voices.find(isFemale) || voices.find((v) => v.default) || voices[0];
  }

  function speakable(text) {
    return text
      .replace(/```[\s\S]*?```/g, " (code block) ")
      .replace(/`([^`]+)`/g, "$1")
      .replace(/[*_#>|]/g, "")
      .replace(/\[(.*?)\]\(.*?\)/g, "$1")
      .replace(/\s+/g, " ")
      .trim();
  }
  function chunk(text, max) {
    const out = [];
    let rest = text;
    while (rest.length > max) {
      let cut = rest.lastIndexOf(". ", max);
      if (cut < max / 2) cut = rest.lastIndexOf(", ", max);
      if (cut < max / 2) cut = max;
      out.push(rest.slice(0, cut + 1).trim());
      rest = rest.slice(cut + 1);
    }
    if (rest.trim()) out.push(rest.trim());
    return out;
  }

  function stopResumeWatch() {
    if (resumeTimer) { clearInterval(resumeTimer); resumeTimer = null; }
  }
  function startResumeWatch() {
    stopResumeWatch();
    resumeTimer = setInterval(() => {
      if (synth && synth.speaking) { try { synth.resume(); } catch (e) {} }
      else stopResumeWatch();
    }, 4000);
  }

  function deviceSpeak(clean) {
    setStatus("speaking (device TTS)...");
    fetch("./api/act", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: "speak", text: clean.slice(0, 500) }),
    })
      .then((r) => r.json())
      .then((j) => {
        if (!j.ok) { browserSpeak(clean); return; }
        // estimate bolne ka time, phir mic dobara kholo
        const ms = Math.min(20000, Math.max(1500, (clean.split(/\s+/).length / 2.5) * 1000 + 800));
        setTimeout(onSpeakEnd, ms);
      })
      .catch(() => browserSpeak(clean));
  }

  function speak(text) {
    if (!ttsOn) return onSpeakEnd();
    const clean = speakable(text);
    if (!clean) return onSpeakEnd();
    if (engine === "device") { deviceSpeak(clean); return; }
    if (!synth) return onSpeakEnd();
    browserSpeakInner(clean);
  }

  function browserSpeak(clean) {
    if (!synth) return onSpeakEnd();
    browserSpeakInner(clean);
  }
  function browserSpeakInner(clean) {
    try { synth.cancel(); } catch (e) {}
    curU = [];
    const code = LANGS[langName].tts;
    const v = pickVoice(code);
    const parts = chunk(clean.slice(0, 900), 180);
    let done = 0;
    spokeDuringTurn = true;
    document.body.classList.add("speaking");
    setStatus("speaking... [" + (v ? v.lang : "no-voice") + "]");
    let tries = 0;
    const go = () => {
      tries++;
      if (!voices.length && synth && tries < 4) { setTimeout(go, 400); return; }  // voices late aati hain
      try { synth.resume(); } catch (e) {}   // paused synth = silent queue
      parts.forEach((p) => {
        const u = new SpeechSynthesisUtterance(p);
        if (v) u.voice = v;
        u.lang = (v && v.lang) || code;
        u.rate = rate; u.pitch = 1.05; u.volume = 1;
        u.onend = u.onerror = (e) => {
          if (e && e.type === "error") setStatus("TTS error: " + (e.error || "?"));
          done++;
          if (done >= parts.length) { curU = []; onSpeakEnd(); }
        };
        curU.push(u);
        synth.speak(u);
      });
      startResumeWatch();
    };
    setTimeout(go, 80);          // Android quirk: never speak right after cancel
  }

  function onSpeakEnd() {
    stopResumeWatch();
    document.body.classList.remove("speaking");
    setStatus(convMode ? "listening..." : "voice ready");
    if (convMode) setTimeout(() => startListen(), 400);
  }
  stopBtn.addEventListener("click", () => {
    if (synth) { try { synth.cancel(); } catch (e) {} }
    stopResumeWatch();
    fetch("./api/act", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ action: "stop_speak" }) }).catch(() => {});
    setStatus("stopped");
  });

  function applyTts() {
    ttsBtn.classList.toggle("on", ttsOn);
    ttsBtn.textContent = ttsOn ? "🔊 TTS" : "🔇 TTS";
    lsSet("tts", ttsOn ? "1" : "0");
  }
  ttsBtn.addEventListener("click", () => {
    ttsOn = !ttsOn;
    applyTts();
    if (!ttsOn && synth) { try { synth.cancel(); } catch (e) {} }
    setStatus(ttsOn ? "TTS on" : "TTS off");
  });
  testBtn.addEventListener("click", () => {
    const was = ttsOn;
    ttsOn = true;
    if (engine === "browser" && !synth) { setStatus("TTS not supported in this WebView"); return; }
    setStatus("voices: " + (voices.length || synth.getVoices().length) + " | testing...");
    speak("Hello! I'm Olivia Thomas, your personal AI assistant. How may I help you today?");
    ttsOn = was;
  });
  const engineSel = document.getElementById("ttsengine");
  if (engineSel) {
    engineSel.value = engine;
    engineSel.addEventListener("change", () => {
      engine = engineSel.value === "browser" ? "browser" : "device";
      lsSet("ttsengine", engine);
      setStatus("voice engine: " + engine);
    });
  }
  if (rateEl) {
    rateEl.value = String(rate);
    rateEl.addEventListener("input", () => {
      rate = parseFloat(rateEl.value) || 1;
      lsSet("rate", String(rate));
    });
  }
  if (wakeBox) {
    wakeBox.checked = wakeOn;
    wakeBox.addEventListener("change", () => {
      wakeOn = wakeBox.checked;
      lsSet("wake", wakeOn ? "1" : "0");
      setStatus(wakeOn ? "wake word ON — say 'Olivia'" : "wake word off");
    });
  }

  /* ---------- speech in ---------- */
  if (!SR) {
    micBtn.disabled = true;
    setStatus("mic not supported (use Chrome)");
    applyTts(); applyLang();
    return;
  }
  rec = new SR();
  rec.lang = LANGS[langName].sr;
  rec.interimResults = true;
  rec.continuous = false;

  function startListen() {
    if (listening || (window.ullah && window.ullah.isBusy && window.ullah.isBusy())) return;
    try { rec.start(); } catch (e) { /* already started */ }
  }
  function stopListen() {
    try { rec.stop(); } catch (e) {}
  }

  micBtn.addEventListener("click", () => {
    if (listening) stopListen();
    else startListen();
  });

  rec.onstart = () => {
    listening = true;
    micBtn.classList.add("listening");
    micBtn.textContent = "● Listening...";
    document.body.classList.add("listening");
    setStatus("listening...");
  };
  rec.onerror = (e) => {
    listening = false;
    if (convMode) setTimeout(startListen, 600);
    micBtn.classList.remove("listening");
    micBtn.textContent = "🎙 Mic";
    const m = {
      "not-allowed": "Mic permission denied — allow Microphone in app settings.",
      "service-not-allowed": "Speech service blocked (internet needed).",
      "no-speech": "Didn't catch that — say it again.",
      "audio-capture": "No mic found.",
      network: "Speech network error.",
    }[e.error] || ("Mic error: " + e.error);
    setStatus(m);
  };
  rec.onend = () => {
    listening = false;
    micBtn.classList.remove("listening");
    document.body.classList.remove("listening");
    micBtn.textContent = "🎙 Mic";
    if (!spokeDuringTurn) setStatus(convMode ? "listening..." : "voice ready");
    if (convMode) setTimeout(startListen, 300);   // hands-free: kaan hamesha khule
  };

  let finalText = "";
  rec.onresult = (e) => {
    let interim = "";
    for (let i = e.resultIndex; i < e.results.length; i++) {
      const t = e.results[i][0].transcript;
      if (e.results[i].isFinal) finalText += t;
      else interim += t;
    }
    setTranscript((finalText + interim).trim());
    if (finalText.trim()) {
      let send = finalText.trim();
      finalText = "";
      // JARVIS-style wake word: in conversation mode, ignore until "Olivia"
      if (wakeOn && convMode && !/olivia/i.test(send)) {
        setTranscript("");
        setStatus("say 'Olivia' first");
        if (convMode) setTimeout(startListen, 300);
        return;
      }
      setTranscript(send);
      if (window.ullah && window.ullah.sendText) {
        spokeDuringTurn = false;
        window.ullah.sendText(send);
      }
    }
  };

  document.addEventListener("visibilitychange", () => {
    if (!document.hidden && convMode && !listening) setTimeout(startListen, 300);
  });

  /* ---------- conversation loop ---------- */
  convBox.checked = convMode;
  convBox.addEventListener("change", () => {
    convMode = convBox.checked;
    lsSet("conv", convMode ? "1" : "0");
    setStatus(convMode ? "conversation ON — start speaking" : "voice ready");
    if (convMode) startListen();
    else stopListen();
  });

  if (window.ullah) window.ullah.onReply = (text) => speak(text);

  applyLang();
  applyTts();
  if (synth) synth.getVoices();
  setStatus("voice ready");
  if (convMode) setTimeout(startListen, 600);
})();
VOICE_EOF
cat > extra.js <<'EXTRA_EOF'
// Olivia Thomas extra v5 — menu drawer, JARVIS commands + device actions, chips, health pill.
(function () {
  /* ---------- menu drawer ---------- */
  const menuBtn = document.getElementById("menubtn");
  const drawer = document.getElementById("drawer");
  const scrim = document.getElementById("scrim");
  function closeDrawer() {
    drawer.classList.remove("open");
    scrim.classList.remove("show");
  }
  menuBtn.addEventListener("click", () => {
    drawer.classList.toggle("open");
    scrim.classList.toggle("show", drawer.classList.contains("open"));
  });
  scrim.addEventListener("click", closeDrawer);

  /* ---------- health pill ---------- */
  const header = document.querySelector("header");
  const logo = header.querySelector(".logo");
  const pill = document.createElement("span");
  pill.id = "health";
  pill.textContent = "...";
  logo.insertAdjacentElement("afterend", pill);

  let brainUp = false;
  async function checkHealth() {
    let server = false;
    brainUp = false;
    try {
      const r = await fetch("./", { cache: "no-store" });
      server = r.ok;
    } catch (e) {}
    if (server) {
      try {
        const r = await fetch("./api/models", { cache: "no-store" });
        brainUp = r.ok;
      } catch (e) {}
    }
    pill.textContent = server ? (brainUp ? "🟢 online" : "🟠 brain off") : "🔴 server off";
    pill.title = "server = start-ullah.sh | brain = OmniRoute gateway";
  }
  checkHealth();
  setInterval(checkHealth, 15000);

  /* ---------- device actions (server /api/act) ---------- */
  const APPS = ["whatsapp","youtube","chrome","settings","maps","photos","instagram","spotify","phone","messages","clock","files","playstore","telegram","gmail","termux","calculator","camera"];
  async function act(payload) {
    try {
      const r = await fetch("./api/act", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      const j = await r.json();
      return j.detail || (j.ok ? "done" : "failed");
    } catch (e) {
      return "Server unreachable: " + e.message;
    }
  }

  /* ---------- JARVIS-style instant local commands ---------- */
  function batteryInfo() {
    return new Promise((resolve) => {
      if (!navigator.getBattery) return resolve("Battery API not available.");
      navigator.getBattery().then((b) => {
        resolve("Battery at " + Math.round(b.level * 100) + "%, " + (b.charging ? "charging" : "on battery") + ".");
      }).catch(() => resolve("Battery info unavailable."));
    });
  }
  function timeInfo() {
    return "It's " + new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }) + " right now.";
  }
  function dateInfo() {
    return "Today is " + new Date().toLocaleDateString([], { weekday: "long", year: "numeric", month: "long", day: "numeric" }) + ".";
  }
  async function systemReport() {
    const bat = await batteryInfo();
    const net = navigator.onLine ? "online" : "offline";
    return "System report: " + timeInfo() + " " + dateInfo() + " " + bat +
      " Network: " + net + ". Brain: " + (brainUp ? "connected" : "offline") +
      ". All systems nominal, sir.";
  }
  function lastProject() {
    try { return localStorage.getItem("olivia.lastproject") || "myapp"; } catch { return "myapp"; }
  }
  const CMD = [
    [/(?:send|bhejo)\s+(?:sms|text|message)\s+(?:to\s+)?(\+?\d[\d\s-]{6,})\s*[:-]\s*(.+)/i, (m) => act({ action: "send_sms", to: m[1], text: m[2] })],
    [/\bscroll\s+(down|up)\b/i, (m) => act({ action: "scroll", dir: m[1] })],
    [/\btap\s+(\d{1,4})[ ,]+(\d{1,4})\b/i, (m) => act({ action: "tap", x: m[1], y: m[2] })],
    [/\bgo back\b/i, () => act({ action: "key", name: "back" })],
    [/\bgo home\b|\bhome screen\b/i, () => act({ action: "key", name: "home" })],
    [/\b(time|samay|kitne baje)\b/i, () => Promise.resolve(timeInfo())],
    [/\b(date|today|aaj)\b/i, () => Promise.resolve(dateInfo())],
    [/\bbattery\b/i, batteryInfo],
    [/\b(status|report|health|system)\b/i, systemReport],
    [/\bopen\s+([a-z ]+)$/i, async (m) => {
      const name = m[1].trim();
      if (/^https?:\/\//.test(name)) return act({ action: "open_url", url: name });
      if (!APPS.includes(name)) return "I can open: " + APPS.join(", ");
      return act({ action: "open_app", name });
    }],
    [/\bzip(?:\s+(?:project|my\s+project)?\s*([\w.-]+))?/i, async (m) => {
      const proj = (m[1] && m[1] !== "project") ? m[1] : lastProject();
      return act({ action: "zip_project", project: proj });
    }],
    [/\bprojects?\s+list\b|\blist projects\b/i, () => act({ action: "list_projects" })],
    [/\bpush\b.*\bgithub\b|\bgithub\b.*\bpush\b/i, () => act({ action: "git_push", message: "Olivia: push from assistant" })],
    [/\brun\s+([\w.-]+)/i, (m) => act({ action: "run_node", project: lastProject(), file: m[1] })],
  ];
  window.ullahPre = (text) => {
    for (const [re, fn] of CMD) {
      const m = text.match(re);
      if (m) {
        Promise.resolve(fn(m)).then((reply) => {
          if (window.ullah && window.ullah.localReply) window.ullah.localReply(String(reply));
        });
        return true;
      }
    }
    return false;
  };

  /* ---------- save code blocks into projects ---------- */
  const EXT = { js: "js", javascript: "js", python: "py", py: "py", html: "html", css: "css", bash: "sh", sh: "sh", json: "json", ts: "ts", java: "java", xml: "xml" };
  let snippetN = 0;
  window.ullahSaveCode = async (code, langTag) => {
    const proj = lastProject();
    const ext = EXT[(langTag || "").toLowerCase()] || "txt";
    snippetN++;
    const file = "snippet-" + snippetN + "." + ext;
    const detail = await act({ action: "save_file", project: proj, file, content: code });
    return detail;
  };

  /* ---------- quick chips ---------- */
  const wrap = document.getElementById("chips");
  if (wrap) {
    const CHIPS = ["time?", "battery status", "system report", "open whatsapp", "open youtube", "open netflix", "suggest a movie", "scroll down", "go back", "zip project", "push to github"];
    CHIPS.forEach((c) => {
      const b = document.createElement("button");
      b.className = "chip";
      b.textContent = c;
      b.addEventListener("click", () => {
        const inp = document.getElementById("input");
        const cur = inp.value.trim();
        inp.value = (cur ? cur + " — " : "") + c.replace(/\?$/, "") + (/\?$/.test(c) ? "?" : "");
        inp.focus();
      });
      wrap.appendChild(b);
    });
  }

  /* ---------- drawer extras ---------- */
  const newBtn = document.getElementById("newchat");
  if (newBtn) newBtn.addEventListener("click", closeDrawer);
})();
EXTRA_EOF
cat > index.html <<'HTML_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
<title>Olivia Thomas</title>
<meta name="theme-color" content="#070a12" />
<link rel="manifest" href="./manifest.json" />
<link rel="icon" href="./icon.svg" type="image/svg+xml" />
<link rel="apple-touch-icon" href="./icon.svg" />
<style>
  :root {
    --bg:#070a12; --panel:rgba(17,23,38,.78); --panel2:#1a2233; --fg:#e8eef9; --mut:#8b97ad;
    --acc:#7aa2ff; --acc2:#b48cff; --user:#264a8a; --bot:rgba(26,34,51,.85); --code:#0d1117;
    --glass:blur(14px); --grad:linear-gradient(135deg,#7aa2ff,#b48cff);
  }
  * { box-sizing:border-box; }
  html,body { margin:0; height:100%; }
  body {
    background:
      radial-gradient(1100px 550px at 85% -10%, rgba(122,162,255,.16), transparent 60%),
      radial-gradient(900px 500px at -10% 110%, rgba(180,140,255,.13), transparent 60%),
      var(--bg);
    color:var(--fg);
    font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;
    display:flex; flex-direction:column; height:100dvh;
  }
  header, #voicebar, footer {
    background:var(--panel); backdrop-filter:var(--glass); -webkit-backdrop-filter:var(--glass);
    border-color:#222c3f;
  }
  header { display:flex; align-items:center; gap:8px; padding:10px 12px; border-bottom:1px solid #222c3f; position:sticky; top:0; z-index:10; }
  header .logo { font-weight:800; font-size:17px; letter-spacing:.4px; background:var(--grad); -webkit-background-clip:text; background-clip:text; color:transparent; white-space:nowrap; }
  #health { font-size:11px; color:var(--mut); background:var(--panel2); border:1px solid #2b3952; padding:3px 8px; border-radius:999px; white-space:nowrap; }
  select { background:var(--panel2); color:var(--fg); border:1px solid #2b3952; border-radius:8px; padding:7px 10px; font-size:13px; max-width:36vw; }
  button { background:var(--panel2); color:var(--fg); border:1px solid #2b3952; border-radius:10px; padding:7px 12px; font-size:13px; cursor:pointer; transition:filter .15s; }
  button:active { filter:brightness(1.25); }
  button.primary { background:var(--grad); border:none; color:#fff; font-weight:700; box-shadow:0 4px 18px rgba(122,162,255,.35); }
  .spacer { flex:1; }
  #menubtn { font-size:16px; padding:6px 10px; }
  #chat { flex:1; overflow-y:auto; padding:16px 12px 6px; display:flex; flex-direction:column; gap:12px; }
  .msg { max-width:88%; padding:11px 14px; border-radius:18px; font-size:15px; line-height:1.55; white-space:pre-wrap; word-wrap:break-word; overflow-wrap:anywhere; box-shadow:0 6px 20px rgba(0,0,0,.35); }
  .msg.user { align-self:flex-end; background:linear-gradient(135deg,#2b57a8,#264a8a); border-bottom-right-radius:6px; }
  .msg.bot { align-self:flex-start; background:var(--bot); border:1px solid #2a3550; border-bottom-left-radius:6px; backdrop-filter:var(--glass); }
  .msg.bot .role { background:var(--grad); -webkit-background-clip:text; background-clip:text; color:transparent; font-size:12px; font-weight:800; margin-bottom:4px; letter-spacing:.6px; text-transform:uppercase; }
  .msg.err { background:#3a1420; border:1px solid #7a2233; color:#ffb3c0; align-self:center; font-size:13px; }
  pre { background:var(--code); border:1px solid #26324a; border-radius:12px; padding:10px; margin:8px 0 2px; overflow-x:auto; position:relative; white-space:pre; }
  pre code { font-family:ui-monospace,Menlo,Consolas,monospace; font-size:13px; }
  .copybtn { position:absolute; top:6px; right:6px; font-size:11px; padding:3px 8px; background:#1f2b3f; }
  .savebtn { right:52px; }
  #chips { display:flex; gap:6px; padding:6px 10px; overflow-x:auto; }
  .chip { flex:0 0 auto; padding:6px 12px; font-size:12px; border-radius:999px; background:var(--panel2); border:1px solid #2b3952; color:var(--mut); }
  footer { padding:8px 10px; border-top:1px solid #222c3f; display:flex; gap:8px; align-items:flex-end; }
  textarea { flex:1; resize:none; background:var(--panel2); color:var(--fg); border:1px solid #2b3952; border-radius:12px; padding:10px; font-size:15px; font-family:inherit; max-height:120px; min-height:44px; }
  textarea:focus { outline:1px solid var(--acc); }
  .cursor::after { content:"▋"; color:var(--acc); animation:blink 1s steps(2) infinite; }
  @keyframes blink { 50% { opacity:0; } }
  .hint { color:var(--mut); font-size:12px; text-align:center; padding:6px; }
  #orb { width:14px; height:14px; border-radius:50%; background:var(--grad); box-shadow:0 0 12px rgba(122,162,255,.9); animation:orbidle 3s ease-in-out infinite; flex:0 0 auto; }
  @keyframes orbidle { 50% { transform:scale(.75); opacity:.65; } }
  body.listening #orb { background:linear-gradient(135deg,#ff5b7a,#b0304a); animation:orbpulse 1s infinite; }
  body.speaking #orb { background:linear-gradient(135deg,#7affc4,#7aa2ff); animation:orbpulse .8s infinite; }
  @keyframes orbpulse { 50% { transform:scale(1.6); box-shadow:0 0 24px rgba(122,255,196,.9); } }
  #voicebar { display:flex; align-items:center; gap:8px; padding:8px 12px; border-bottom:1px solid #222c3f; flex-wrap:wrap; }
  #voicebar button { padding:7px 11px; }
  #mic.listening { background:linear-gradient(135deg,#8a2432,#7a2233); border-color:#b0304a; color:#fff; animation:pulse 1.3s infinite; }
  @keyframes pulse { 50% { opacity:.65; } }
  #mic:disabled { opacity:.45; }
  .toggle.on { background:var(--grad); border-color:transparent; color:#fff; }
  .convlabel { font-size:13px; color:var(--mut); display:flex; align-items:center; gap:5px; }
  #vstatus { color:var(--mut); font-size:12px; }
  #transcript { min-height:0; padding:0 12px; color:var(--acc); font-size:14px; }
  #transcript:not(:empty) { padding:6px 12px; }
  /* premium drawer menu */
  #scrim { position:fixed; inset:0; background:rgba(0,0,0,.5); opacity:0; pointer-events:none; transition:opacity .25s; z-index:40; }
  #scrim.show { opacity:1; pointer-events:auto; }
  #drawer {
    position:fixed; top:0; right:0; bottom:0; width:min(320px,86vw); z-index:50;
    background:rgba(13,18,30,.92); backdrop-filter:var(--glass); -webkit-backdrop-filter:var(--glass);
    border-left:1px solid #2a3550; padding:18px 16px; transform:translateX(102%);
    transition:transform .28s cubic-bezier(.2,.8,.2,1); display:flex; flex-direction:column; gap:14px; overflow-y:auto;
  }
  #drawer.open { transform:translateX(0); }
  #drawer h2 { margin:0; font-size:16px; background:var(--grad); -webkit-background-clip:text; background-clip:text; color:transparent; letter-spacing:.5px; }
  #drawer label { font-size:13px; color:var(--mut); display:flex; flex-direction:column; gap:6px; }
  #drawer select, #drawer input[type=range] { width:100%; }
  #drawer .row { display:flex; align-items:center; justify-content:space-between; font-size:14px; }
  #drawer button { width:100%; }
  #about { font-size:11px; color:var(--mut); line-height:1.5; margin-top:auto; }
</style>
</head>
<body>
<header>
  <div class="logo">Olivia Thomas</div>
  <div class="spacer"></div>
  <select id="model" title="Model"></select>
  <button id="menubtn" title="Menu">☰</button>
</header>

<div id="voicebar">
  <span id="orb" title="Olivia core"></span>
  <button id="mic" title="Speak">🎙 Mic</button>
  <button id="tts" class="toggle on" title="Speech on/off">🔊 TTS</button>
  <button id="voicetest" title="Test voice">🔔 Test</button>
  <button id="stopspk" title="Stop speaking">⏹ Stop</button>
  <label class="convlabel"><input type="checkbox" id="conv" /> Hands-free</label>
  <div class="spacer"></div>
  <span id="vstatus">voice ready</span>
</div>
<div id="transcript"></div>

<div id="chat"></div>
<div id="chips"></div>
<div class="hint" id="hint">Your personal AI assistant — ask anything</div>
<footer>
  <textarea id="input" rows="1" placeholder="Type your question..."></textarea>
  <button id="send" class="primary">Send</button>
</footer>

<div id="scrim"></div>
<div id="drawer">
  <h2>Olivia — Menu</h2>
  <label>Language
    <select id="langsel">
      <option value="English">English</option>
      <option value="Roman Urdu">Roman Urdu</option>
      <option value="Italian">Italian</option>
    </select>
  </label>
  <label>Voice engine
    <select id="ttsengine">
      <option value="device">Device TTS (Termux:API) — recommended</option>
      <option value="browser">Browser TTS (Web Speech)</option>
    </select>
  </label>
  <label>Speech speed
    <input type="range" id="rate" min="0.6" max="1.6" step="0.1" value="1" />
  </label>
  <div class="row"><span>Wake word “Olivia”</span><input type="checkbox" id="wake" /></div>
  <button id="newchat"> New chat</button>
  <div id="about">Olivia Thomas v5 — JARVIS-style voice-first personal AI agent. Opens apps, builds &amp; zips projects, runs code, pushes to GitHub. Zero-dependency Node server + vanilla JS, built on Termux, shipped via GitHub Actions.</div>
</div>

<script src="./app.js"></script>
<script src="./voice.js"></script>
<script src="./extra.js"></script>
<script>
if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("./sw.js").catch(() => {});
}
</script>
</body>
</html>
HTML_EOF
cat > sw.js <<'SW_EOF'
// Olivia Thomas service worker — cache app shell so it installs from Home screen.
// Network-first for /api/* (never cache chat), cache-first for static assets.
// v3: naya cache name => purana stale cache auto-delete.
const CACHE = "olivia-v2";
const SHELL = [
  "./",
  "./index.html",
  "./app.js",
  "./voice.js",
  "./extra.js",
  "./manifest.json",
  "./icon.svg",
];

self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (e) => {
  const req = e.request;
  const url = new URL(req.url);
  if (req.method !== "GET" || url.pathname.startsWith("/api/")) return; // proxy handles it live
  e.respondWith(
    caches.match(req).then((hit) => {
      if (hit) return hit;
      return fetch(req)
        .then((res) => {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(req, copy)).catch(() => {});
          return res;
        })
        .catch(() => caches.match("./index.html"));
    })
  );
});
SW_EOF
cat > README.md <<'README_EOF'
# Olivia Thomas 🎙️

**Voice-first personal AI assistant & coding agent** — Android APK + PWA. She listens, understands, and **answers out loud**. JARVIS-class capabilities with a premium glass UI.

[![Build APK](https://github.com/pakyji/olivia/actions/workflows/build-apk.yml/badge.svg)](https://github.com/pakyji/olivia/actions/workflows/build-apk.yml)
[![Latest APK](https://img.shields.io/github/v/release/pakyji/olivia?label=APK)](https://github.com/pakyji/olivia/releases/latest)

## ✨ Features

- 🎙 **Voice in / voice out** — Web Speech API: speak, and hear the answer spoken back
- 🌐 **3 languages** — English (default), Roman Urdu, Italian — switch from the ☰ menu, strictly enforced by the persona
- 👩 **Olivia Thomas persona** — warm, confident companion (JARVIS-style), female-first TTS voices
- 🔊 **TTS v3 engine** — female voice priority, sentence chunking, GC-safe utterances, resume watchdog, speed slider
- 🗣 **Wake word** — say “Olivia” in conversation mode to address her (optional toggle)
- ⚡ **JARVIS instant commands** — “time?”, “battery status”, “system report” → answered locally, instantly, out loud
- 📱 **Opens mobile apps** — “open whatsapp”, “open youtube”, “open camera”, … (18 apps mapped)
- 🛠 **Builds & delivers projects** — save code blocks into projects, run them, and get a **ZIP download link**
- 🐙 **Pushes to GitHub** — “push to github” commits and pushes from the phone repo
- 💬 **Conversation loop** — hands-free continuous dialogue
- 🟢 **Health pill** — live server + brain (gateway) status
- 🌙 **Premium glass UI** — gradient mesh background, glassmorphism panels, slide-in menu drawer
- 🌗 **Background mode** — `start-olivia.sh` keeps the server alive in background (wake-lock + notification)
- 💾 **Chat history** — localStorage; clear from the drawer
- 📱 **PWA + APK** — install to home screen, or WebView APK from Releases
- 🔐 **Zero dependencies** — Node stdlib server, vanilla JS front-end

## 🚀 Quick start (phone / Termux)

```bash
# Session 1 — brain (OmniRoute gateway)
omniroute

# Session 2 — Olivia server (background, port 8080)
cd ~/olivia && bash start-olivia.sh
# stop with: bash stop-olivia.sh
```

Then either:

- **APK** — [Releases → app-debug.apk](https://github.com/pakyji/olivia/releases/latest), install and open.
- **Browser / PWA** — Chrome: `http://127.0.0.1:8080` → Add to Home screen.

## 🎙 Voice & menu guide

| Control | What it does |
|---|---|
| 🎙 Mic | speak → text → Olivia answers |
| 🔊 TTS / 🔔 Test / ⏹ Stop | speech on-off / test voice / stop speaking |
| Conversation | hands-free loop |
| ☰ Menu | language, speech speed, wake word, new chat |

## 🤖 JARVIS command examples

| Say / type | Result |
|---|---|
| `time?` / `battery status` / `system report` | instant spoken device info |
| `open whatsapp` / `open youtube` / `open camera` | launches the app |
| `open https://...` | opens URL |
| `Save` button on any code block | saves it into `projects/myapp/` |
| `zip project` | builds a ZIP and returns a download link |
| `run server.js` | runs a saved file and reports output |
| `push to github` | git add + commit + push from the phone |
| `send sms to +39...: hello` | sends an SMS via Termux:API |
| `scroll down` / `scroll up` / `go back` / `go home` | controls the open app (JARVIS-style) |
| `tap 360 800` | taps screen coordinates |
| `suggest a movie` | movie suggestions, conversational |

## 🏗 Architecture

```
APK (WebView) ──▶ http://127.0.0.1:8080 ──▶ /api/chat (SSE) ──▶ OmniRoute :20128 ──▶ provider
   shell            server.js (Node stdlib)  + persona.txt         gateway           (Gemini etc.)
                          │
                          └─▶ /api/act — JARVIS actions: open apps, save/zip/run projects, git push
```

- `server.js` — static files, `/api/chat` proxy (+ language injection), `/api/act` device actions
- `app.js` — chat UI, markdown, history, code Copy/Save buttons
- `voice.js` — recognition + TTS v3 (female-first, wake word)
- `extra.js` — drawer menu, JARVIS commands, chips, health pill
- `sw.js` — PWA shell (cache `olivia-v1`)
- `android/` — WebView wrapper; GitHub Actions builds every push → Releases

## 🧪 Tests

```bash
bash tests/smoke.sh
```

## 🛠 Troubleshooting

| Symptom | Fix |
|---|---|
| `ERR_CONNECTION_REFUSED` | run `bash start-olivia.sh` in Termux |
| No replies | start `omniroute` in session 1 (pill shows 🟠) |
| No voice | press 🔔 Test; check 🔊 TTS on; install Google TTS voices |
| Old UI showing | force-stop the APK and reopen (service-worker cache refresh) |
| Mic denied | Settings → Apps → Olivia → Permissions → Microphone → Allow |
| SMS fails | install Termux:API app + `pkg install termux-api`, grant SMS permission |

## 📦 APK build

Every push triggers GitHub Actions: debug APK published to **Releases** (tag `apk-v<run>`).

---

_She listens. She understands. She speaks. 💜_
README_EOF
cat > manifest.json <<'MANIFEST_EOF'
{
  "name": "Olivia Thomas",
  "short_name": "Olivia",
  "description": "Voice-first personal AI assistant and coding agent",
  "start_url": "./",
  "scope": "./",
  "display": "fullscreen",
  "orientation": "portrait",
  "background_color": "#070a12",
  "theme_color": "#070a12",
  "icons": [
    {
      "src": "icon.svg",
      "sizes": "any",
      "type": "image/svg+xml",
      "purpose": "any maskable"
    }
  ]
}
MANIFEST_EOF
cat > icon.svg <<'ICON_EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">
  <defs>
    <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#7aa2ff"/>
      <stop offset="1" stop-color="#b48cff"/>
    </linearGradient>
  </defs>
  <rect width="512" height="512" rx="96" fill="#070a12"/>
  <text x="256" y="352" font-family="system-ui,Segoe UI,Roboto,sans-serif"
        font-size="290" font-weight="800" text-anchor="middle" fill="url(#g)">O</text>
  <circle cx="256" cy="106" r="24" fill="url(#g)"/>
</svg>
ICON_EOF
cat > start-olivia.sh <<'START_EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Olivia Thomas — start in BACKGROUND (survives closing the Termux window)
cd "$(dirname "$0")" || exit 1
termux-wake-lock 2>/dev/null
pkill -f "node server.js" 2>/dev/null
sleep 0.5
nohup node server.js > server.log 2>&1 &
echo $! > server.pid
disown 2>/dev/null
termux-notification --id olivia --title "Olivia is running" --content "http://127.0.0.1:8080" 2>/dev/null
echo "Olivia running in background (pid $(cat server.pid 2>/dev/null)). Log: tail -f server.log"
echo "To stop: bash stop-olivia.sh"
START_EOF
cat > stop-olivia.sh <<'STOP_EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Olivia Thomas — stop background server
cd "$(dirname "$0")" || exit 1
pkill -f "node server.js" 2>/dev/null
termux-notification --id olivia --delete 2>/dev/null
termux-wake-unlock 2>/dev/null
rm -f server.pid
echo "Olivia stopped."
STOP_EOF
cat > android/app/src/main/res/values/strings.xml <<'STRINGS_EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">Olivia</string>
</resources>
STRINGS_EOF
rm -f start-ullah.sh stop-ullah.sh
chmod +x start-olivia.sh stop-olivia.sh
node --check server.js && node --check app.js && node --check voice.js && node --check extra.js && node --check sw.js && echo "JS syntax OK"
git add -A
git commit -m "feat: v8 — device TTS via Termux:API (WebView-independent) + always-on hands-free" || echo "nothing new to commit"
git push || true
pkill -f "node server.js" 2>/dev/null || true
sleep 0.5
bash start-olivia.sh
echo "== DONE — v8 live. Device TTS needs: pkg install termux-api + Termux:API app =="
