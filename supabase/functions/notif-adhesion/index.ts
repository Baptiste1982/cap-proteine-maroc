// Notification web push à l'arrivée d'une adhésion (appelée par le déclencheur de la base).
// verify_jwt:false — la fonction ne fait confiance qu'à la base : l'adhésion doit exister,
// dater de moins de 15 min et ne pas avoir été notifiée (réservation atomique de notifiee_le).
import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import webpush from "npm:web-push@3.6.7";

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
webpush.setVapidDetails(
  Deno.env.get("VAPID_SUBJECT") ?? "https://cap-proteine-maroc.vercel.app",
  Deno.env.get("VAPID_PUBLIC")!,
  Deno.env.get("VAPID_PRIVATE")!,
);
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "methode" }, 405);
  let id = "";
  try { id = String((await req.json()).id || ""); } catch { return json({ error: "corps" }, 400); }
  if (!/^[0-9a-f-]{36}$/.test(id)) return json({ error: "id" }, 400);

  const depuis = new Date(Date.now() - 15 * 60e3).toISOString();
  const { data: rows, error } = await sb.from("adhesions")
    .update({ notifiee_le: new Date().toISOString() })
    .eq("id", id).is("notifiee_le", null).gt("created_at", depuis)
    .select("id, ref, data");
  if (error) return json({ error: error.message }, 500);
  if (!rows?.length) return json({ ok: true, envoyes: 0, raison: "deja_notifiee_ou_ancienne" });
  const a = rows[0] as { id: string; ref: string | null; data: Record<string, string> };

  // Destinataires : direction (superadmin, national, zone) + l'animateur du club du lien.
  const { data: profs } = await sb.from("profiles").select("id, role, animateur_id");
  let animClub: string | null = null, nomClub = "";
  if (a.ref) {
    const { data: c } = await sb.from("clubs").select("nom, animateur_id").eq("id", a.ref).maybeSingle();
    if (c) { animClub = c.animateur_id; nomClub = (c.nom || "").replace(/^CAP\s+/, ""); }
  }
  const ids = (profs || []).filter((p) =>
    ["superadmin", "directeur_national", "directeur"].includes(p.role) || (animClub && p.animateur_id === animClub)
  ).map((p) => p.id);
  if (!ids.length) return json({ ok: true, envoyes: 0 });
  const { data: abos } = await sb.from("push_abonnements").select("id, endpoint, p256dh, auth").in("user_id", ids);

  const nom = [a.data?.m_prenom, a.data?.m_nom].filter(Boolean).join(" ");
  const payload = JSON.stringify({
    title: "📝 Nouvelle adhésion",
    body: [a.data?.ent_nom, nom].filter(Boolean).join(" · ") + (nomClub ? " — " + nomClub : ""),
    url: "/?adh=" + a.id,
    tag: "adh-" + a.id,
  });
  let envoyes = 0;
  for (const s of abos || []) {
    try {
      await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, payload, { TTL: 86400 });
      envoyes++;
    } catch (e) {
      const code = (e as { statusCode?: number }).statusCode;
      if (code === 404 || code === 410) await sb.from("push_abonnements").delete().eq("id", s.id); // appareil désabonné
    }
  }
  return json({ ok: true, envoyes });
});
