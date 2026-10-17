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
