# JALVI AI 2.0 — Gemini Worker setup

This Worker is the server-side bridge between the Android app and Gemini. The Gemini API key must remain a Cloudflare Worker secret; never place it in Flutter code, the APK, GitHub, screenshots, or chat.

## Before deployment

A parent/guardian should manage the Google AI Studio and Cloudflare accounts, review the providers' current age, privacy, and usage terms, and approve any billing or paid usage. Do not add a payment method just to test this project. Use an eligible free-tier model/project if Google offers it.

## Deploy

Run these commands from this `worker/` directory on a computer with Node.js and Wrangler installed:

1. `npx wrangler login`
2. `npx wrangler deploy`
3. Set the Gemini API key as a server-side secret: `npx wrangler secret put GEMINI_API_KEY`
4. Create a long random app token and set it as a server-side secret: `npx wrangler secret put APP_TOKEN`

Do not paste either secret into GitHub or chat. The app token is a basic access gate, not a substitute for account authentication; it can be extracted from a client app. Keep the Worker private to intended use and monitor usage.

The Worker uses `gemini-3.8-flash` by default. The model can be changed with the `GEMINI_MODEL` Worker variable if the selected Google project does not have access to it.

## Connect the Android app

1. Open JALVI AI 2.0 → Settings.
2. Enter the deployed Worker HTTPS URL (the `*.workers.dev` address).
3. Enter the same APP_TOKEN value that was set as the Cloudflare secret.
4. Save.
5. Test a normal question first, then a harmless local command such as “battery kitni hai?”

Opening the Worker URL in a browser should return a small JSON health response. A POST request from the app requires the app token.

## Supported actions

The Worker can request only: `torch_on`, `torch_off`, `battery`, `time`, `sms_read`, `open_app`, and `open_dialer`. The app allow-lists supported app packages. Dialer only opens the dialer; it does not place a call. SMS reading requires Android SMS permission.

## Limitations and safety

- Deploying the Android APK does not deploy this Worker.
- API quotas, free-tier eligibility, model availability, and pricing can change. Check Google's official Gemini API docs.
- The app currently uses tap-to-talk; always-on wake-word/background listening is not implemented.
- SMS access is sensitive and requires explicit Android permission. Only enable it if genuinely needed.
- No action should be considered tested until it has been tried on the target phone.
