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
  let speakingUntil = 0;   // mic lock: Olivia bolte waqt + margin tak mic band (echo-loop killer)
  let lastSpoken = "";     // last reply text, echo self-match ke liye

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

  /* ---------- gesture prime: unlock WebView TTS on first tap ---------- */
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

  function bridgeSpeak(clean) {
    try {
      if (!window.OliviaBridge || !window.OliviaBridge.speak) return false;
      const ok = window.OliviaBridge.speak(clean.slice(0, 500), LANGS[langName].tts);
      if (ok) {
        setStatus("speaking (app TTS)...");
        const ms = Math.min(20000, Math.max(1500, (clean.split(/\s+/).length / 2.5) * 1000 + 800));
        speakingUntil = Date.now() + ms + 2500;   // estimate + safety margin
        lastSpoken = clean;
        setTimeout(onSpeakEnd, ms);
        return true;
      }
    } catch (e) {}
    return false;
  }

  function deviceSpeak(clean) {
    if (bridgeSpeak(clean)) return;
    setStatus("speaking (device TTS)...");
    fetch("./api/act", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: "speak", text: clean.slice(0, 500), lang: LANGS[langName].tts }),
    })
      .then((r) => r.json())
      .then((j) => {
        if (!j.ok) { browserSpeak(clean); return; }
        // estimate speaking time, then reopen the mic
        const ms = Math.min(20000, Math.max(1500, (clean.split(/\s+/).length / 2.5) * 1000 + 800));
        speakingUntil = Date.now() + ms + 2500;
        lastSpoken = clean;
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
    speakingUntil = Date.now() + Math.min(30000, (clean.split(/\s+/).length / 2.5) * 1000 + 2500);
    lastSpoken = clean;
    let done = 0;
    spokeDuringTurn = true;
    document.body.classList.add("speaking");
    setStatus("speaking... [" + (v ? v.lang : "no-voice") + "]");
    let tries = 0;
    const go = () => {
      tries++;
      if (!voices.length && synth && tries < 4) { setTimeout(go, 400); return; }  // voices can arrive late
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
    speakingUntil = 0;   // pressing Stop releases the mic lock immediately
    if (synth) { try { synth.cancel(); } catch (e) {} }
    stopResumeWatch();
    fetch("./api/act", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ action: "stop_speak" }) }).catch(() => {});
    try { if (window.OliviaBridge && window.OliviaBridge.stopSpeak) window.OliviaBridge.stopSpeak(); } catch (e) {}
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
    setStatus("voices: " + (voices.length || (synth ? synth.getVoices().length : 0)) + " | testing...");
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
    if (Date.now() < speakingUntil) return;   // Olivia is still speaking — mic locked (echo-loop killer)
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
    // hard blocks (permission/service/hardware) must not trigger an endless restart loop
    const hard = e.error === "not-allowed" || e.error === "service-not-allowed" || e.error === "audio-capture";
    if (convMode && !hard) setTimeout(startListen, 600);
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
    if (convMode) setTimeout(startListen, 300);   // hands-free: keep the mic open
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
      // echo guard: Olivia ki apni awaaz mic ne sun li to discard (self-reply loop breaker)
      const low = send.toLowerCase();
      const SELF = /^(i can open|opening |battery at|system report|it's |today is |hello there|zip ready|sms sent|saved |pressed |scrolled |tapped |speaking|voices?:|language:)/;
      const prev = lastSpoken.toLowerCase().replace(/[^a-z0-9 ]/g, "").slice(0, 25);
      const cur = low.replace(/[^a-z0-9 ]/g, "").slice(0, 25);
      if (SELF.test(low) || (prev && cur && cur === prev)) {
        setTranscript("");
        if (convMode) setTimeout(startListen, 300);
        return;
      }
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
