# ULLAH

Voice-enabled Hinglish AI coding agent Android app.

## How to use

1. Run `./start-ullah.sh` in Termux.
2. Open `http://127.0.0.1:8080` in Chrome on your phone.
3. Or install the APK (see below).

## APK (Android App)

The `.github/workflows/build-apk.yml` builds a debug APK on every push to `main`.

1. Go to the **Actions** tab on GitHub.
2. Click the latest "Build APK" run.
3. Download the `app-debug` artifact (requires login).
4. Unzip and install `app-debug.apk` on your phone.
5. Grant Microphone permission when asked.

## Notes

- Requires OmniRoute gateway running on `127.0.0.1:20128`.
- Termux must be running for the app to connect.
