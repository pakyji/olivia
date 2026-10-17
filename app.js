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
  if (!acc.trim()) {
    b.el.remove();   // khaali bubble mat dikhao
  } else {
    b.body.innerHTML = renderMarkdown(acc);
    messages.push({ role: "assistant", content: acc });
  }
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
