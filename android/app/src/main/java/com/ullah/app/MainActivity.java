package com.ullah.app;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Bundle;
import android.speech.tts.TextToSpeech;
import android.webkit.JavascriptInterface;
import android.webkit.PermissionRequest;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import java.util.Locale;

public class MainActivity extends Activity implements TextToSpeech.OnInitListener {

    private WebView web;
    private TextToSpeech tts;
    private boolean ttsReady = false;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        tts = new TextToSpeech(this, this);

        web = new WebView(this);
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);          // localStorage for chat history
        s.setMediaPlaybackRequiresUserGesture(false);

        web.setWebViewClient(new WebViewClient());

        // Let the WebView page request the mic (needed for voice input).
        web.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onPermissionRequest(final PermissionRequest request) {
                runOnUiThread(() -> request.grant(request.getResources()));
            }
        });

        // JARVIS bridge: foreground app = allowed to speak + open apps
        web.addJavascriptInterface(new Bridge(), "OliviaBridge");

        requestPermissions(new String[]{Manifest.permission.RECORD_AUDIO}, 1);

        setContentView(web);
        web.loadUrl("http://127.0.0.1:8080");
    }

    @Override
    public void onInit(int status) {
        ttsReady = (status == TextToSpeech.SUCCESS);
        if (ttsReady) {
            tts.setLanguage(Locale.ENGLISH);
            tts.setSpeechRate(1.0f);
        }
    }

    private static Locale localeFor(String code) {
        if (code == null) return Locale.US;
        String c = code.toLowerCase();
        if (c.startsWith("hi")) return new Locale("hi", "IN");
        if (c.startsWith("ur")) return new Locale("ur");
        if (c.startsWith("it")) return Locale.ITALY;
        if (c.startsWith("en")) return Locale.US;
        return Locale.US;
    }

    public class Bridge {
        @JavascriptInterface
        public String bridgeVersion() {
            return "17";
        }

        @JavascriptInterface
        public boolean ttsReady() {
            return ttsReady;
        }

        @JavascriptInterface
        public boolean speak(String text, String lang) {
            if (!ttsReady || tts == null) return false;
            int r = tts.setLanguage(localeFor(lang));
            if (r == TextToSpeech.LANG_NOT_SUPPORTED || r == TextToSpeech.LANG_MISSING_DATA) {
                r = tts.setLanguage(new Locale("hi", "IN"));   // best available voice for Roman Urdu/Hinglish
            }
            if (r == TextToSpeech.LANG_NOT_SUPPORTED || r == TextToSpeech.LANG_MISSING_DATA) {
                tts.setLanguage(Locale.US);
            }
            tts.speak(text, TextToSpeech.QUEUE_ADD, null, "olivia-" + System.currentTimeMillis());
            return true;
        }

        @JavascriptInterface
        public void stopSpeak() {
            if (tts != null) tts.stop();
        }

        @JavascriptInterface
        public boolean openApp(String pkg) {
            try {
                Intent i = getPackageManager().getLaunchIntentForPackage(pkg);
                if (i == null) return false;
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                startActivity(i);
                return true;
            } catch (Exception e) {
                return false;
            }
        }

        @JavascriptInterface
        public boolean openUrl(String url) {
            try {
                Intent i = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                startActivity(i);
                return true;
            } catch (Exception e) {
                return false;
            }
        }
    }

    @Override
    public void onBackPressed() {
        if (web != null && web.canGoBack()) {
            web.goBack();
        } else {
            super.onBackPressed();
        }
    }

    @Override
    protected void onDestroy() {
        if (tts != null) tts.shutdown();
        if (web != null) web.destroy();
        super.onDestroy();
    }
}
