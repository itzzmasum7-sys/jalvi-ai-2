# Feature status

| Feature | Status |
|---|---|
| Dark assistant dashboard | Implemented |
| Manual voice input | Implemented through device speech recognizer |
| Text-to-speech | Implemented using device TTS |
| Hindi/English/Urdu locale selection | UI/config included; available voices depend on Android TTS engine |
| Basic local command routing | Implemented; device testing required |
| Gemini Worker source | Present in `worker/src/index.js`; not deployed until a Cloudflare account owner deploys it |
| Gemini API connection in app | Client code present; requires deployed Worker URL and APP_TOKEN in Settings |
| Recent SMS reading | Native inbox query; requires granted READ_SMS permission |
| “Padho / Agla / Pichhla / Ruko / Dobara” | Basic reading flow implemented |
| Open YouTube/WhatsApp/Instagram/Camera | Package launch intents implemented |
| Torch | Native camera torch bridge implemented |
| Battery percentage | Implemented |
| Dialer | Opens Android dialer; does not place a call automatically |
| True always-on “Jarvis” wake word | Not implemented |
| Background listening foreground service | Not implemented |
| Contact-name resolution for SMS | Not implemented |
| Contacts lookup / call history | Not implemented |
| Gallery semantic search | Not implemented |
| Media seek/session controls | Not implemented |
| WhatsApp private message access | Not implemented |
| Notification reader | Not implemented |
| Personal memory database | Not implemented |
| Cloud Worker deployment and secrets | Requires account owner action; not deployed by GitHub build |
| APK | Built by GitHub Actions only after a successful Android workflow run |
