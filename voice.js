// ULLAH voice — Web Speech API (sunna + bolna). Vanilla JS.
(function () {
  const micBtn = document.getElementById("mic");
  const langBtn = document.getElementById("lang");
  const stopBtn = document.getElementById("stopspk");
  const convBox = document.getElementById("conv");
  const statusEl = document.getElementById("vstatus");
  const transcriptEl = document.getElementById("transcript");

  const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  let lang = localStorage.getItem("ullah.lang") || "hi-IN";
  let rec = null;
  let listening = false;
  let convMode = localStorage.getItem("ullah.conv") === "1";
  let spokeDuringTurn = false; // did we speak via TTS this reply?

  function setStatus(t) { statusEl.textContent = t; }
  function setTranscript(t) {
    transcriptEl.textContent = t;
    transcriptEl.style.display = t ? "block" : "none";
  }

  /* ---------- language ---------- */
  function applyLang() {
    langBtn.textContent = lang;
    langBtn.classList.toggle("on", lang === "hi-IN");
    localStorage.setItem("ullah.lang", lang);
  }
  langBtn.addEventListener("click", () => {
    lang = lang === "hi-IN" ? "en-US" : "hi-IN";
    applyLang();
    if (rec) rec.lang = lang;
    setStatus("lang: " + lang);
  });

  /* ---------- speech out (bolna) ---------- */
  const synth = window.speechSynthesis;
  function pickVoice(code) {
    const vs = synth.getVoices();
    if (!vs.length) return null;
    const want = code.slice(0, 2).toLowerCase();
    return (
      vs.find((v) => v.lang && v.lang.toLowerCase().startsWith(want)) ||
      vs.find((v) => /hindi|en-in/i.test(v.name)) ||
      vs.find((v) => v.default) ||
      vs[0]
    );
  }
  // strip markdown/code so we don't read symbols aloud
  function speakable(text) {
    return text
      .replace(/```[\s\S]*?```/g, " (code block) ")
      .replace(/`([^`]+)`/g, "$1")
      .replace(/[*_#>|]/g, "")
      .replace(/\[(.*?)\]\(.*?\)/g, "$1")
      .replace(/\s+/g, " ")
      .trim()
      .slice(0, 600);
  }
  function speak(text) {
    if (!synth) return;
    const clean = speakable(text);
    if (!clean) return onSpeakEnd();
    synth.cancel();
    const u = new SpeechSynthesisUtterance(clean);
    const v = pickVoice(lang);
    if (v) u.voice = v;
    u.lang = lang;
    u.rate = 1;
    u.onend = onSpeakEnd;
    u.onerror = onSpeakEnd;
    spokeDuringTurn = true;
    setStatus("bol raha hai...");
    synth.speak(u);
  }
  function onSpeakEnd() {
    setStatus(convMode ? "suno..." : "voice ready");
    if (convMode) {
      // small delay so mic doesn't catch the tail of TTS
      setTimeout(() => startListen(), 400);
    }
  }
  stopBtn.addEventListener("click", () => {
    if (synth) synth.cancel();
    setStatus("stopped");
  });

  /* ---------- speech in (sunna) ---------- */
  if (!SR) {
    micBtn.disabled = true;
    setStatus("mic not supported (use Chrome)");
    return;
  }
  rec = new SR();
  rec.lang = lang;
  rec.interimResults = true;
  rec.continuous = false;

  function startListen() {
    if (listening || (window.ullah && window.ullah.isBusy && window.ullah.isBusy())) return;
    try { rec.start(); } catch { /* already started */ }
  }
  function stopListen() {
    try { rec.stop(); } catch {}
  }

  micBtn.addEventListener("click", () => {
    if (listening) stopListen();
    else startListen();
  });

  rec.onstart = () => {
    listening = true;
    micBtn.classList.add("listening");
    micBtn.textContent = "● Sun raha...";
    setStatus("suno...");
  };
  rec.onerror = (e) => {
    listening = false;
    micBtn.classList.remove("listening");
    micBtn.textContent = "🎙 Mic";
    const m = {
      "not-allowed": "Mic permission denied — Chrome me Settings > Site settings > Microphone allow karo.",
      "service-not-allowed": "Speech service blocked (need internet).",
      "no-speech": "Kuch sunai nahi diya — phir bolo.",
      "audio-capture": "No mic found.",
      network: "Speech network error.",
    }[e.error] || ("Mic error: " + e.error);
    setStatus(m);
  };
  rec.onend = () => {
    listening = false;
    micBtn.classList.remove("listening");
    micBtn.textContent = "🎙 Mic";
    if (!spokeDuringTurn) setStatus(convMode ? "suno..." : "voice ready");
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
      const send = finalText.trim();
      finalText = "";
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
    setStatus(convMode ? "baat-cheet ON — bolna shuru karo" : "voice ready");
    if (convMode) startListen();
    else stopListen();
  });

  // when a reply finishes, speak it; onSpeakEnd re-opens the mic if convMode
  if (window.ullah) window.ullah.onReply = (text) => speak(text);

  applyLang();
  if (synth) synth.getVoices(); // warm up voice list
  setStatus("voice ready");
  if (convMode) setTimeout(startListen, 600);
})();
