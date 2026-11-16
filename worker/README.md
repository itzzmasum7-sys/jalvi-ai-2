# JALVI AI 2.0 — AI brain setup

The Android app talks to this Worker. The Gemini API key stays on the server and must never be placed in the APK or committed to Git.

## Adult-managed setup

A parent/guardian should create and manage the Cloudflare account and Google AI Studio API key, review the provider's current age, privacy, and usage terms, and set usage limits where available.

1. From this `worker/` directory, deploy the Worker with Wrangler:
   `npx wrangler deploy`
2. Add server-side secrets (do not put their values in this repository):
   - `npx wrangler secret put GEMINI_API_KEY`
   - `npx wrangler secret put APP_TOKEN`
3. Use a long, randomly generated APP_TOKEN. Do not post it in chat or commit it.
4. In JALVI Settings, enter the deployed Worker HTTPS URL and the same APP_TOKEN.
5. Test ordinary chat first, then test one low-risk action such as battery or torch.

The Worker expects JSON:
`{ "message": "Hello", "language": "hi-IN", "history": [] }`

It returns JSON:
`{ "reply": "...", "action": "none", "target": "" }`

Supported action values are allow-listed in the Worker and Android app. The dialer action only opens the dialer; it never places a call. SMS reading requires Android SMS permission.

## Important

- The APK build does not deploy this Worker automatically.
- Gemini API usage may have quotas, availability limits, and data-handling terms that can change. Check the current official terms before enabling it.
- Do not share API keys, access tokens, OTPs, or passwords in chat.
- Background wake-word listening is not implemented in this version.
