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
      const r = await fetch("./?hb=" + Date.now(), { cache: "no-store" });
      server = r.ok;
    } catch (e) {}
    if (server) {
      try {
        const r = await fetch("./api/models?hb=" + Date.now(), { cache: "no-store" });
        brainUp = r.ok;
      } catch (e) {}
    }
    pill.textContent = server ? (brainUp ? "🟢 online" : "🟠 brain off") : "🔴 server off";
    pill.title = "server = start-olivia.sh | brain = OmniRoute gateway";
  }
  checkHealth();
  setInterval(checkHealth, 15000);

  /* ---------- device actions (server /api/act) ---------- */
  const PKGS = { whatsapp:"com.whatsapp", youtube:"com.google.android.youtube", chrome:"com.android.chrome", settings:"com.android.settings", maps:"com.google.android.apps.maps", photos:"com.google.android.photos", instagram:"com.instagram.android", spotify:"com.spotify.music", phone:"com.android.dialer", messages:"com.google.android.messages", clock:"com.google.android.deskclock", files:"com.google.android.documentsui", playstore:"com.android.vending", telegram:"org.telegram.messenger", gmail:"com.google.android.gm", termux:"com.termux", calculator:"com.google.android.calculator", facebook:"com.facebook.katana", netflix:"com.netflix.mediaclient" };
  const APPS = Object.keys(PKGS).concat(["camera", "snapchat", "discord"]);
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
      const name = m[1].trim().toLowerCase();
      if (/^https?:\/\//.test(name)) {
        if (window.OliviaBridge && window.OliviaBridge.openUrl(name)) return "Opening " + name;
        return act({ action: "open_url", url: name });
      }
      const toks = name.split(/\s+/);
      const norm = name.replace(/\s+/g, "");
      const hit = APPS.includes(name) ? name : APPS.includes(norm) ? norm : toks.find((c) => APPS.includes(c));
      if (!hit) return "I can open: " + APPS.join(", ");
      name = hit;
      if (window.OliviaBridge && window.OliviaBridge.openApp) {
        if (!PKGS[name]) return act({ action: "open_app", name });   // camera etc: server intent path
        const ok = window.OliviaBridge.openApp(PKGS[name]);
        return ok ? "Opening " + name + "." : name + " didn't open. If it IS installed, the APK is outdated — reinstall the latest APK from Releases (the permission fix lives inside the APK).";
      }
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
  const about = document.getElementById("about");
  if (about && window.OliviaBridge && window.OliviaBridge.bridgeVersion) {
    try { about.textContent += " Bridge v" + window.OliviaBridge.bridgeVersion() + "."; } catch (e) {}
  }
})();
