// Jarvis: the room iPad's AI assistant (Supabase Edge Function).
// Keeps the Gemini key secret: the iPad sends what was said + live room info,
// this asks Gemini and sends back a short spoken answer + actions for the iPad to do.
// Needs one secret: GEMINI_API_KEY   (optional: GEMINI_MODEL)

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const KEY = Deno.env.get("GEMINI_API_KEY") ?? "";
let MODEL = Deno.env.get("GEMINI_MODEL") ?? "gemini-flash-latest";
const API = "https://generativelanguage.googleapis.com/v1beta";

const SYSTEM = `You are Jarvis, the voice assistant on the iPad in Adam's bedroom.
The family: Adam (teenager, gamer, does Brazilian Jiu-Jitsu), his Dad, his brother Noam and sister Jade. Dad speaks French.
Your answers are read out loud, so:
- Keep them short: 1 to 3 sentences, natural and friendly, like a smart butler. No lists, no markdown, no emoji.
- Answer in the language the person used (English or French).
- Say times the way people say them (e.g. "half past five", "17h30" in French).
Use the live info below for the time, date, weather, prayer times, room mode, PC state, alarms and timers. Never invent them.
You can DO things with your tools:
- set_mode: room modes. gaming = wake PC, sign in Adam, open Chrome + Call of Duty. study = PC on with Chrome. sleep = put the PC to sleep. adam = PC on in Adam's account. dad = PC on in Dad's account. none = clear the mode.
- pc_action: single PC actions (ready, cod, chrome, sleep, dad = switch to Dad's account and start Mortal Shell, study).
- set_alarm / delete_alarms, set_timer / cancel_timers.
- send_kitchen_message: sends a text to the kitchen iPad (Dad sees it and it is read out). Write it as coming from Adam, in the language Adam asked in.
When you use a tool, also say in a few words what you did. If something is unclear, ask one short question.`;

const tools = [{
  functionDeclarations: [
    { name: "set_mode", description: "Change the room mode (also controls the PC).",
      parameters: { type: "OBJECT", properties: { mode: { type: "STRING", enum: ["gaming", "study", "sleep", "adam", "dad", "none"] } }, required: ["mode"] } },
    { name: "pc_action", description: "Do one action on the PC.",
      parameters: { type: "OBJECT", properties: { action: { type: "STRING", enum: ["ready", "cod", "chrome", "sleep", "dad", "study"] } }, required: ["action"] } },
    { name: "set_alarm", description: "Set a daily alarm on the room iPad.",
      parameters: { type: "OBJECT", properties: { time: { type: "STRING", description: "24-hour HH:MM" }, label: { type: "STRING" } }, required: ["time"] } },
    { name: "delete_alarms", description: "Delete all alarms.", parameters: { type: "OBJECT", properties: {} } },
    { name: "set_timer", description: "Start a countdown timer.",
      parameters: { type: "OBJECT", properties: { minutes: { type: "NUMBER" }, label: { type: "STRING" } }, required: ["minutes"] } },
    { name: "cancel_timers", description: "Stop all running timers.", parameters: { type: "OBJECT", properties: {} } },
    { name: "send_kitchen_message", description: "Send a short text message to the kitchen iPad.",
      parameters: { type: "OBJECT", properties: { text: { type: "STRING" } }, required: ["text"] } },
  ],
}];

const json = (o: unknown) => new Response(JSON.stringify(o), { headers: { ...CORS, "Content-Type": "application/json" } });

async function gemini(body: unknown) {
  return await fetch(`${API}/models/${MODEL}:generateContent`, {
    method: "POST", headers: { "Content-Type": "application/json", "x-goog-api-key": KEY }, body: JSON.stringify(body),
  });
}

// if the model name stops working, pick the newest "flash" model this key can use
async function pickModel(): Promise<string> {
  const r = await fetch(`${API}/models?pageSize=200`, { headers: { "x-goog-api-key": KEY } });
  const j = await r.json();
  const names: string[] = (j.models ?? [])
    .filter((m: any) => (m.supportedGenerationMethods ?? []).includes("generateContent"))
    .map((m: any) => String(m.name).replace("models/", ""));
  const flash = names.filter((n) => /flash/.test(n) && !/(image|tts|audio|live|exp|lite|preview)/.test(n)).sort().reverse();
  return flash[0] ?? names[0] ?? MODEL;
}

function said(a: { name: string; args: any }) {
  const g = a.args ?? {};
  switch (a.name) {
    case "set_mode": return g.mode === "none" ? "Mode cleared." : `${g.mode} mode, on it.`;
    case "pc_action": return "Done, I've told the PC.";
    case "set_alarm": return `Alarm set for ${g.time}.`;
    case "delete_alarms": return "All alarms deleted.";
    case "set_timer": return `Timer started for ${g.minutes} minutes.`;
    case "cancel_timers": return "Timers cancelled.";
    case "send_kitchen_message": return "Message sent to the kitchen.";
  }
  return "Done.";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    if (!KEY) return json({ reply: "My Gemini key isn't set up yet.", actions: [] });
    const { text, history = [], ctx = {} } = await req.json();
    const q = String(text ?? "").trim();
    if (!q || q.length > 1000) return json({ reply: "Sorry, I didn't catch that.", actions: [] });

    const contents = [
      ...(Array.isArray(history) ? history : []).slice(-8).map((h: any) => ({
        role: h.role === "ai" ? "model" : "user", parts: [{ text: String(h.text ?? "").slice(0, 1500) }],
      })),
      { role: "user", parts: [{ text: q }] },
    ];
    const body = {
      systemInstruction: { parts: [{ text: SYSTEM + "\n\nLIVE INFO (from the iPad, right now):\n" + JSON.stringify(ctx).slice(0, 6000) }] },
      contents, tools, generationConfig: { temperature: 0.6 },
    };

    let r = await gemini(body);
    if (r.status === 404 || r.status === 400) {           // model name gone / not allowed: find another
      const before = MODEL; MODEL = await pickModel();
      if (MODEL !== before) r = await gemini(body);
    }
    if (r.status === 429) return json({ reply: "I've hit my free limit for now. Try again in a minute.", actions: [] });
    if (!r.ok) return json({ reply: "My AI service had a problem (" + r.status + ").", actions: [], detail: (await r.text()).slice(0, 300) });

    const j = await r.json();
    const parts: any[] = j?.candidates?.[0]?.content?.parts ?? [];
    const actions = parts.filter((p) => p.functionCall).map((p) => ({ name: p.functionCall.name, args: p.functionCall.args ?? {} }));
    let reply = parts.filter((p) => p.text && !p.thought).map((p) => p.text).join(" ").trim();
    if (!reply) reply = actions.length ? actions.map(said).join(" ") : "Sorry, I don't have an answer for that.";
    return json({ reply, actions, model: MODEL });
  } catch (e) {
    return json({ reply: "Something went wrong on my side.", actions: [], detail: String(e) });
  }
});
