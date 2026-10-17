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
