// Vanity AI Coach proxy: holds the Anthropic API key so the app never ships it.
// The app sends its request body plus an access code; the proxy checks the code,
// enforces a daily limit per person, pins the model, and forwards to Claude.

const UPSTREAM = "https://api.anthropic.com/v1/messages";
const MODEL = "claude-opus-5-5";
const MAX_TOKENS = 16000;
const FORWARDED_HEADERS = ["anthropic-version", "anthropic-beta"];

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method !== "POST" || url.pathname !== "/v1/messages") {
      return error(404, "not_found", "Unknown route.");
    }

    const person = personFor(request.headers.get("x-vanity-code"), env.ACCESS_CODES);
    if (!person) return error(401, "authentication_error", "Invalid access code.");

    let body;
    try {
      body = await request.json();
    } catch {
      return error(400, "invalid_request_error", "Body must be JSON.");
    }
    // Only the coach's own request shape gets through, so a leaked code can't run arbitrary jobs.
    body.model = MODEL;
    body.max_tokens = Math.min(Number(body.max_tokens) || MAX_TOKENS, MAX_TOKENS);
    delete body.stream;

    const limit = Number(env.DAILY_LIMIT) || 10;
    const counterKey = `${person}:${new Date().toISOString().slice(0, 10)}`;
    const used = Number(await env.USAGE?.get(counterKey)) || 0;
    if (used >= limit) {
      return error(429, "rate_limit_error", `Daily coach limit of ${limit} reached. Try again tomorrow.`);
    }

    const headers = { "content-type": "application/json", "x-api-key": env.ANTHROPIC_API_KEY };
    for (const name of FORWARDED_HEADERS) {
      const value = request.headers.get(name);
      if (value) headers[name] = value;
    }
    const upstream = await fetch(UPSTREAM, { method: "POST", headers, body: JSON.stringify(body) });
    if (upstream.ok) {
      await env.USAGE?.put(counterKey, String(used + 1), { expirationTtl: 2 * 86400 });
    }
    return new Response(upstream.body, {
      status: upstream.status,
      headers: { "content-type": upstream.headers.get("content-type") ?? "application/json" },
    });
  },
};

function personFor(code, accessCodes = "") {
  if (!code) return null;
  for (const pair of accessCodes.split(",")) {
    const [name, value] = pair.trim().split(":");
    if (name && value && timingSafeEqual(value, code)) return name;
  }
  return null;
}

function timingSafeEqual(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function error(status, type, message) {
  return Response.json({ type: "error", error: { type, message } }, { status });
}
