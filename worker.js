// Receives Pebble Index 01 webhooks, stores each transcription in D1,
// and serves notes newer than a given id to sync.sh.

export default {
  async fetch(request, env) {
    if (!authorized(request, env.AUTH_TOKEN)) {
      return new Response("unauthorized", { status: 401 });
    }

    const url = new URL(request.url);
    if (request.method === "POST" && url.pathname === "/") {
      return receive(request, env);
    }
    if (request.method === "GET" && url.pathname === "/notes") {
      return list(url, env);
    }
    return new Response("not found", { status: 404 });
  },
};

function authorized(request, token) {
  const enc = new TextEncoder();
  const supplied = enc.encode(request.headers.get("Authorization") ?? "");
  const expected = enc.encode(`Bearer ${token}`);
  // timingSafeEqual throws on mismatched lengths, so check that first.
  return supplied.byteLength === expected.byteLength &&
    crypto.subtle.timingSafeEqual(supplied, expected);
}

async function receive(request, env) {
  const form = await request.formData();
  if (form.get("test") === "true") {
    return new Response("ok");
  }

  // Tabs and newlines would break the line format sync.sh reads.
  const text = (form.get("transcription") ?? "").replace(/\s+/g, " ").trim();
  if (text) {
    const recordedAt = Number(form.get("recordedAt")) || Date.now();
    await env.DB.prepare("INSERT INTO notes (recorded_at, text) VALUES (?, ?)")
      .bind(recordedAt, text)
      .run();
  }
  return new Response("ok");
}

async function list(url, env) {
  const after = Number(url.searchParams.get("after")) || 0;
  const { results } = await env.DB.prepare(
    "SELECT id, recorded_at, text FROM notes WHERE id > ? ORDER BY id",
  ).bind(after).all();

  // One note per line: id<TAB>recorded_at_ms<TAB>text
  const body = results.map((r) => `${r.id}\t${r.recorded_at}\t${r.text}\n`).join("");
  return new Response(body, { headers: { "Content-Type": "text/plain; charset=utf-8" } });
}
