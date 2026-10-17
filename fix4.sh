#!/data/data/com.termux/files/usr/bin/bash
set -e
cd ~/ullah || exit 1
echo "== Olivia v4: Hinglish removed + crash/bug fixes + Olivia branding =="
mkdir -p android/app/src/main/res/values
cat > persona.txt <<'PERSONA_EOF'
You are Olivia Thomas — a brilliant, warm personal AI assistant and expert coding agent (JARVIS-class).

IDENTITY:
- Your name is Olivia Thomas. If asked, introduce yourself: "I'm Olivia Thomas — your personal AI assistant."
- Style: confident, friendly, a little playful. Premium personal-assistant vibe, never robotic.

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

const LS_KEY = "ullah.chat.v1";
const LS_MODEL = "ullah.model.v1";

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
      html += `<pre><button class="copybtn" data-copy>Copy</button><code>${escapeHtml(code.replace(/\n$/, ""))}</code></pre>`;
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

// copy buttons (delegated)
chatEl.addEventListener("click", (e) => {
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
  let langName = localStorage.getItem("ullah.langname") || "English";
  if (!LANGS[langName]) langName = "English";
  window.ullahLang = () => langName;   // app.js reads this for the server

  const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  let rec = null;
  let listening = false;
  let convMode = localStorage.getItem("ullah.conv") === "1";
  let wakeOn = localStorage.getItem("ullah.wake") === "1";
  let ttsOn = localStorage.getItem("ullah.tts") !== "0";
  let rate = parseFloat(localStorage.getItem("ullah.rate") || "1") || 1;
  let spokeDuringTurn = false;

  function setStatus(t) { statusEl.textContent = t; }
  function setTranscript(t) {
    transcriptEl.textContent = t;
    transcriptEl.style.display = t ? "block" : "none";
  }

  /* ---------- language (drawer select) ---------- */
  function applyLang() {
    if (langSel) langSel.value = langName;
    if (rec) rec.lang = LANGS[langName].sr;
    localStorage.setItem("ullah.langname", langName);
  }
  if (langSel) {
    langSel.addEventListener("change", () => {
      langName = LANGS[langSel.value] ? langSel.value : "English";
      applyLang();
      setStatus("language: " + langName);
    });
  }

  /* ---------- speech out — v3 engine (female-first) ---------- */
  const synth = window.speechSynthesis;
  let voices = [];
  let curU = [];          // keep refs: GC kills utterances mid-speech
  let resumeTimer = null;

  function loadVoices() {
    if (!synth) return;
    voices = synth.getVoices() || [];
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

  function speak(text) {
    if (!synth || !ttsOn) return onSpeakEnd();
    const clean = speakable(text);
    if (!clean) return onSpeakEnd();
    try { synth.cancel(); } catch (e) {}
    curU = [];
    const code = LANGS[langName].tts;
    const v = pickVoice(code);
    const parts = chunk(clean.slice(0, 900), 180);
    let done = 0;
    spokeDuringTurn = true;
    setStatus("speaking... [" + (v ? v.lang : "no-voice") + "]");
    setTimeout(() => {           // Android quirk: never speak right after cancel
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
    }, 80);
  }

  function onSpeakEnd() {
    stopResumeWatch();
    setStatus(convMode ? "listening..." : "voice ready");
    if (convMode) setTimeout(() => startListen(), 400);
  }
  stopBtn.addEventListener("click", () => {
    if (synth) { try { synth.cancel(); } catch (e) {} }
    stopResumeWatch();
    setStatus("stopped");
  });

  function applyTts() {
    ttsBtn.classList.toggle("on", ttsOn);
    ttsBtn.textContent = ttsOn ? "🔊 TTS" : "🔇 TTS";
    localStorage.setItem("ullah.tts", ttsOn ? "1" : "0");
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
    speak("Hello! I'm Olivia Thomas, your personal AI assistant. How may I help you today?");
    ttsOn = was;
  });
  if (rateEl) {
    rateEl.value = String(rate);
    rateEl.addEventListener("input", () => {
      rate = parseFloat(rateEl.value) || 1;
      localStorage.setItem("ullah.rate", String(rate));
    });
  }
  if (wakeBox) {
    wakeBox.checked = wakeOn;
    wakeBox.addEventListener("change", () => {
      wakeOn = wakeBox.checked;
      localStorage.setItem("ullah.wake", wakeOn ? "1" : "0");
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
    setStatus("listening...");
  };
  rec.onerror = (e) => {
    listening = false;
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
    micBtn.textContent = "🎙 Mic";
    if (!spokeDuringTurn) setStatus(convMode ? "listening..." : "voice ready");
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

  /* ---------- conversation loop ---------- */
  convBox.checked = convMode;
  convBox.addEventListener("change", () => {
    convMode = convBox.checked;
    localStorage.setItem("ullah.conv", convMode ? "1" : "0");
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
// Olivia Thomas extra — premium menu drawer, JARVIS-style instant commands, chips, health pill.
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

  /* ---------- JARVIS-style instant local commands ---------- */
  function batteryInfo() {
    return new Promise((resolve) => {
      if (!navigator.getBattery) return resolve("battery API not available");
      navigator.getBattery().then((b) => {
        resolve(
          "Battery at " + Math.round(b.level * 100) + "%, " +
          (b.charging ? "charging" : "on battery") + "."
        );
      }).catch(() => resolve("battery info unavailable"));
    });
  }
  function timeInfo() {
    const d = new Date();
    return "It's " + d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }) + " right now.";
  }
  function dateInfo() {
    return "Today is " + new Date().toLocaleDateString([], { weekday: "long", year: "numeric", month: "long", day: "numeric" }) + ".";
  }
  async function systemReport() {
    const bat = await batteryInfo();
    const net = navigator.onLine ? "online" : "offline";
    return (
      "System report: " + timeInfo() + " " + dateInfo() + " " + bat +
      " Network: " + net + ". Brain: " + (brainUp ? "connected" : "offline") +
      ". I'm Olivia Thomas, all systems nominal."
    );
  }
  const CMD = [
    [/\b(time|samay|kitne baje)\b/i, () => Promise.resolve(timeInfo())],
    [/\b(date|today|aaj)\b/i, () => Promise.resolve(dateInfo())],
    [/\bbattery\b/i, batteryInfo],
    [/\b(status|report|health|system)\b/i, systemReport],
  ];
  window.ullahPre = (text) => {
    for (const [re, fn] of CMD) {
      if (re.test(text)) {
        fn().then((reply) => {
          if (window.ullah && window.ullah.localReply) window.ullah.localReply(reply);
        });
        return true;
      }
    }
    return false;
  };

  /* ---------- quick chips ---------- */
  const wrap = document.getElementById("chips");
  if (wrap) {
    const CHIPS = ["time?", "battery status", "system report", "write code", "find bug", "explain it"];
    CHIPS.forEach((c) => {
      const b = document.createElement("button");
      b.className = "chip";
      b.textContent = c;
      b.addEventListener("click", () => {
        const inp = document.getElementById("input");
        const cur = inp.value.trim();
        inp.value = (cur ? cur + " — " : "") + c.replace(/\?$/, "") + ": ";
        inp.focus();
      });
      wrap.appendChild(b);
    });
  }

  /* ---------- drawer extras ---------- */
  const clearBtn = document.getElementById("clearchat");
  if (clearBtn) clearBtn.addEventListener("click", () => {
    document.getElementById("newchat").click();
    closeDrawer();
  });
  const aboutEl = document.getElementById("about");
  if (aboutEl) aboutEl.textContent = "Olivia Thomas v3 — voice-first personal AI agent. Zero-dependency Node server + vanilla JS. Built on Termux, shipped via GitHub Actions.";
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
  #chips { display:flex; gap:6px; padding:6px 10px; overflow-x:auto; }
  .chip { flex:0 0 auto; padding:6px 12px; font-size:12px; border-radius:999px; background:var(--panel2); border:1px solid #2b3952; color:var(--mut); }
  footer { padding:8px 10px; border-top:1px solid #222c3f; display:flex; gap:8px; align-items:flex-end; }
  textarea { flex:1; resize:none; background:var(--panel2); color:var(--fg); border:1px solid #2b3952; border-radius:12px; padding:10px; font-size:15px; font-family:inherit; max-height:120px; min-height:44px; }
  textarea:focus { outline:1px solid var(--acc); }
  .cursor::after { content:"▋"; color:var(--acc); animation:blink 1s steps(2) infinite; }
  @keyframes blink { 50% { opacity:0; } }
  .hint { color:var(--mut); font-size:12px; text-align:center; padding:6px; }
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
  <button id="mic" title="Speak">🎙 Mic</button>
  <button id="tts" class="toggle on" title="Speech on/off">🔊 TTS</button>
  <button id="voicetest" title="Test voice">🔔 Test</button>
  <button id="stopspk" title="Stop speaking">⏹ Stop</button>
  <label class="convlabel"><input type="checkbox" id="conv" /> Conversation</label>
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
  <label>Speech speed
    <input type="range" id="rate" min="0.6" max="1.6" step="0.1" value="1" />
  </label>
  <div class="row"><span>Wake word “Olivia”</span><input type="checkbox" id="wake" /></div>
  <button id="newchat"> New chat</button>
  <div id="about"></div>
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
const CACHE = "ullah-v3";
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

**Voice-first personal AI assistant & coding agent** — Android APK + PWA. Sun-ti hai, samajh-ti hai, aur **bol kar** jawab deti hai. JARVIS-class features, premium glass UI.

[![Build APK](https://github.com/pakyji/ullah/actions/workflows/build-apk.yml/badge.svg)](https://github.com/pakyji/ullah/actions/workflows/build-apk.yml)
[![Latest APK](https://img.shields.io/github/v/release/pakyji/ullah?label=APK)](https://github.com/pakyji/ullah/releases/latest)

## ✨ Features

- 🎙 **Voice in / voice out** — Web Speech API: bolo, jawab awaz mein suno
- 🌐 **3 languages** — English (default), Roman Urdu, Italian — menu se switch, strict persona enforcement
- 👩 **Olivia Thomas persona** — warm, confident personal assistant (female-first TTS voices)
- 🔊 **TTS v3 engine** — female voice priority, sentence-chunking, GC-safe utterances, resume-watchdog, speed slider
- 🗣 **Wake word** — conversation mode mein "Olivia" bol kar bulao (optional toggle)
- ⚡ **JARVIS-style instant commands** — "time?", "battery status", "system report" → local, instant, spoken
- 💬 **Conversation loop** — hands-free continuous baat-cheet
- 🟢 **Health pill** — live server + brain status
- ⚡ **Quick chips** — time?, battery status, system report, write code, find bug, explain it
-  **Model-agnostic** — OmniRoute gateway se koi bhi provider; API key server-side rehti hai
- 🌙 **Premium glass UI** — gradient mesh background, glassmorphism panels, slide-in menu drawer
- 🌗 **Background mode** — `start-ullah.sh` server ko background mein chalata hai (wake-lock + notification)
- 💾 **Chat history** — localStorage; drawer se clear
- 📱 **PWA + APK** — home-screen install ya WebView APK
- 🔐 **Zero dependencies** — Node stdlib server, vanilla JS front-end

## 🚀 Quick start (phone / Termux)

```bash
# Session 1 — brain (OmniRoute gateway)
omniroute

# Session 2 — Olivia server (background, port 8080)
cd ~/ullah && bash start-ullah.sh
# stop: bash stop-ullah.sh
```

Phir:

- **APK** — [Releases → app-debug.apk](https://github.com/pakyji/ullah/releases/latest) install karo, kholo.
- **Browser / PWA** — Chrome: `http://127.0.0.1:8080` → Add to Home screen.

## 🎙 Voice & menu guide

| Control | Kaam |
|---|---|
| 🎙 Mic | bolo → text → Olivia |
| 🔊 TTS / 🔔 Test / ⏹ Stop | bolna on-off / awaz test / roko |
| Conversation | hands-free loop |
| ☰ Menu | language, speech speed, wake word, clear chat |

## 🏗 Architecture

```
APK (WebView) ──▶ http://127.0.0.1:8080 ──▶ /api/chat (SSE) ──▶ OmniRoute :20128 ──▶ provider
   shell            server.js (Node stdlib)  + persona.txt         gateway           (Gemini etc.)
```

- `server.js` — static + `/api/chat` proxy (+ `lang` system-prompt injection)
- `app.js` — chat UI, markdown, history, local-reply API
- `voice.js` — recognition + TTS v3 (female-first, wake word)
- `extra.js` — menu drawer, JARVIS commands, chips, health pill
- `sw.js` — PWA shell (cache `ullah-v3`)
- `android/` — WebView wrapper; Actions har push pe APK → Releases

## 🧪 Test

```bash
bash tests/smoke.sh
```

## 🛠 Troubleshooting

| Symptom | Fix |
|---|---|
| `ERR_CONNECTION_REFUSED` | `bash start-ullah.sh` chalu nahi |
| Jawab nahi aata | Session 1 mein `omniroute` chalu karo (pill 🟠) |
| Awaz nahi aati | 🔔 Test dabao; 🔊 TTS on; phone mein Google TTS voices |
| Purana UI | APK force-stop → dobara kholo (sw cache v3 refresh) |
| Mic denied | Settings → Apps → Olivia → Microphone → Allow |

## 📦 APK build

Har push pe GitHub Actions debug APK → **Releases** (tag `apk-v<run>`).

---

_Sunti hai, samajhti hai, bolti hai. 💜_
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
cat > start-ullah.sh <<'START_EOF'
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
echo "Stop karne ke liye: bash stop-ullah.sh"
START_EOF
cat > stop-ullah.sh <<'STOP_EOF'
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
chmod +x start-ullah.sh stop-ullah.sh
node --check server.js && node --check app.js && node --check voice.js && node --check extra.js && node --check sw.js && echo "JS syntax OK"
git add -A
git commit -m "fix: v4 — remove Hinglish, fix newchat crash, Olivia manifest/icon" || echo "nothing new to commit"
git push || true
pkill -f "node server.js" 2>/dev/null || true
sleep 0.5
bash start-ullah.sh
echo "== DONE — v4 live. Actions ke baad naya Olivia APK Releases mein =="
