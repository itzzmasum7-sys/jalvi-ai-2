const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, X-App-Token",
  "Content-Type": "application/json; charset=utf-8",
};

function json(data, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: CORS_HEADERS });
}

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS_HEADERS });
    if (request.method !== "POST") return json({ error: "POST only" }, 405);
    if (!env.GEMINI_API_KEY || !env.APP_TOKEN) return json({ error: "Server secrets are not configured" }, 503);
    if (request.headers.get("X-App-Token") !== env.APP_TOKEN) return json({ error: "Unauthorized" }, 401);

    let input;
    try { input = await request.json(); } catch { return json({ error: "Invalid JSON" }, 400); }
    const message = String(input.message || "").slice(0, 4000);
    if (!message.trim()) return json({ error: "Message is required" }, 400);
    const history = Array.isArray(input.history) ? input.history.slice(-8).map(x => String(x).slice(0, 500)).join("\n") : "";

    const systemInstruction = [
      "You are JARVIS, a helpful Android personal assistant. Reply naturally in Hindi, Hinglish, or English and keep replies concise.",
      "Allowed actions only: torch_on, torch_off, battery, time, sms_read, open_app, open_dialer.",
      "For open_app, target must be exactly one of: whatsapp, youtube, instagram, camera.",
      "For normal conversation use action none. Return ONLY JSON with keys reply, action, target.",
      "Never claim an action succeeded; the phone app executes it and reports the result.",
      "If ambiguous, ask a clarifying question and use action none. Never ask for passwords or OTPs.",
      "Never initiate calls. open_dialer only opens the dialer for the user to confirm.",
    ].join(" ");

    const model = env.GEMINI_MODEL || "gemini-3.8-flash";
    const endpoint = "https://generativelanguage.googleapis.com/v1beta/models/" + encodeURIComponent(model) + ":generateContent";
    const upstream = await fetch(endpoint, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": env.GEMINI_API_KEY },
      body: JSON.stringify({
        system_instruction: { parts: [{ text: systemInstruction }] },
        contents: [{ role: "user", parts: [{ text: "Recent conversation:\n" + history + "\n\nLatest message:\n" + message }] }],
        generationConfig: { responseMimeType: "application/json", temperature: 0.35, maxOutputTokens: 400 },
      }),
    });
    if (!upstream.ok) return json({ error: "AI provider request failed", status: upstream.status }, 502);
    const result = await upstream.json();
    const raw = result.candidates?.[0]?.content?.parts?.map(p => p.text || "").join("") || "";
    try {
      const parsed = JSON.parse(raw);
      const allowed = new Set(["none", "torch_on", "torch_off", "battery", "time", "sms_read", "open_app", "open_dialer"]);
      const action = allowed.has(parsed.action) ? parsed.action : "none";
      const apps = new Set(["whatsapp", "youtube", "instagram", "camera"]);
      const target = action === "open_app" && apps.has(String(parsed.target).toLowerCase()) ? String(parsed.target).toLowerCase() : "";
      return json({ reply: String(parsed.reply || "Ji, bataiye.").slice(0, 1200), action, target });
    } catch {
      return json({ reply: "Mujhe jawab samajhne mein dikkat hui. Dobara boliye.", action: "none", target: "" });
    }
  },
};