# JALVI AI 2.0 — Android project starter

**Assistant name:** Jarvis  
**App name:** JALVI AI 2.0  
**Stack:** Flutter + native Android Kotlin  
**Languages planned:** Hindi, English, Urdu

## Important delivery status

This is a buildable **starter project**, not a finished implementation of every item in the master specification. It includes a working Flutter interface, speech input/output hooks, local voice-command routing, and native Android bridges for selected actions. Advanced integrations (reliable always-on wake word, SMS inbox access on every Android version, notification access, WhatsApp private-chat reading, cloud AI, calendar sync, and broad UI automation) require additional permissions, service setup, testing, and in some cases external credentials.

An APK is not included because this build environment does not have Flutter, the Android SDK, or Gradle installed. Build the APK on a computer with Flutter and Android SDK installed by following the steps below.

## 1. Requirements

- Flutter SDK installed
- Android SDK + Android Studio command-line tools
- JDK 17 or compatible version required by your installed Flutter/Android Gradle Plugin
- Android phone with USB debugging enabled (optional for testing)

## 2. Build

From this folder:

```bash
flutter pub get
flutter create --platforms=android --org com.jalvi.ai --project-name jalvi_ai .
```

The `flutter create` command may regenerate platform scaffolding. If it does, restore these project files from this archive:
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/kotlin/com/jalvi/ai/jalvi_ai/MainActivity.kt`
- `lib/main.dart`

Then run:

```bash
flutter pub get
flutter run
```

Build a release APK:

```bash
flutter build apk --release
```

APK output:
`build/app/outputs/flutter-apk/app-release.apk`

## 3. Permissions

The Android manifest declares permissions used by the current starter. Android runtime permission prompts are still required where applicable. SMS access is sensitive and may be restricted by Google Play policy. This project is intended for personal testing/sideloading unless its distribution model and permissions meet Play policy.

## 4. Current working starter features

- Dark JALVI dashboard
- Speech-to-text command input (when Android speech recognition is available)
- Text-to-speech response
- Manual microphone control
- Local command routing for:
  - “Jarvis” / greeting
  - “Padho” / read recent SMS (after READ_SMS permission)
  - “Agla”, “Pichhla”, “Ruko”, “Dobara padho”
  - “Torch on/off”
  - “Battery kitni hai?”
  - Open selected apps by supported package name
  - Call a contact via Android dialer (confirmation through dialer UI)
- Native Kotlin method channel

## 5. Not yet implemented

- True offline always-on wake-word engine. A production wake-word engine needs a supported model/SDK and its licensing/activation configuration. The app does not secretly listen in the background.
- Full contacts lookup, full call history, media-session seek control, gallery semantic search, notification reading, WhatsApp private-message reading, and all system toggles.
- Online AI backend. Do not put a private API key in the Android app. Add a server-side API endpoint before enabling cloud AI.
- Production-grade encryption, backup, automated tests, and Play Store compliance review.

## 6. Privacy

- Microphone is used only after the user taps the microphone button in this starter.
- SMS is read only after the user explicitly asks and grants permission.
- “Padho” starts reading the retrieved messages aloud.
- No SMS contents are uploaded to a server by this starter.
- Calls are opened through the Android dialer; the user confirms/places the call.
