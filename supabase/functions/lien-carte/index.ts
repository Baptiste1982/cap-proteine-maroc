// v0.30.0 — Déplie un lien court de carte (maps.app.goo.gl, goo.gl/maps, waze.com/ul/…) pour y lire la position GPS.
// verify_jwt:true : appelée par le CRM avec la session de l'équipe. Ne suit que des hôtes de cartes connus.
const CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...CORS, "Content-Type": "application/json" } });
const OK = /^(maps\.app\.goo\.gl|goo\.gl|g\.co|(www\.)?google\.[a-z.]+|maps\.google\.[a-z.]+|(www\.)?waze\.com|consent\.google\.com)$/i;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  let url = "";
  try { url = String((await req.json()).url || "").trim(); } catch { return json({ error: "corps" }, 400); }
  let u: URL;
  try { u = new URL(url); } catch { return json({ error: "lien" }, 400); }
  if (!OK.test(u.hostname)) return json({ error: "hote" }, 400);
  try {
    for (let i = 0; i < 6; i++) {
      const r = await fetch(u.toString(), { redirect: "manual", headers: { "User-Agent": "Mozilla/5.0" } });
      const loc = r.headers.get("location");
      if (!loc || r.status < 300 || r.status >= 400) {
        // Certaines pages renvoient la position dans le corps (balise meta ou lien « @lat,lng »).
        const txt = r.status === 200 ? (await r.text()).slice(0, 200000) : "";
        let lat: number | null = null, lng: number | null = null, approx = false;
        const a = u.toString().match(/!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)/) || txt.match(/!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)/)
          || txt.match(/center=(-?\d{1,2}\.\d+)%2C(-?\d{1,3}\.\d+)/) || txt.match(/@(-?\d{1,2}\.\d+),(-?\d{1,3}\.\d+)/);
        if (a) { lat = Number(a[1]); lng = Number(a[2]); }
        else {
          // État initial de la carte Google : [[[zoom, longitude, latitude]
          const b = txt.match(/APP_INITIALIZATION_STATE=\[\[\[(-?\d+(?:\.\d+)?),(-?\d+\.\d+),(-?\d+\.\d+)\]/);
          if (b) { lng = Number(b[2]); lat = Number(b[3]); approx = true; }
        }
        return json({ ok: true, url: u.toString(), lat, lng, approx });
      }
      const n = new URL(loc, u);
      // La page de consentement Google porte la vraie adresse dans « continue ».
      if (/consent\.google/.test(n.hostname) && n.searchParams.get("continue")) { u = new URL(n.searchParams.get("continue")!); continue; }
      if (!OK.test(n.hostname)) return json({ ok: true, url: n.toString() });
      u = n;
    }
    return json({ ok: true, url: u.toString() });
  } catch (e) {
    return json({ error: String((e as Error)?.message || e) }, 502);
  }
});
