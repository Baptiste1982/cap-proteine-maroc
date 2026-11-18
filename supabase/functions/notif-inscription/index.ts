// v1.76.0 — un membre d'un AUTRE groupe répond « Je viens » à une réunion → notification à l'animateur du groupe qui reçoit.
// Appelée par le déclencheur reunion_reponses_notifier. verify_jwt:false : la fonction ne fait confiance qu'à la base
// (la réponse doit exister, dater de moins de 15 min et ne pas avoir été annoncée : réservation atomique de notifie_le).
import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import webpush from "npm:web-push@3.6.7";

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const VAPID_PUBLIC = "BAKkMOISOmM62avwTzeE81_l592rvg9O-AiLBct4eGf7Xovoy_OswNK0lnQ0yokt6VDoRkL927x4LS5bFYnWbZM";
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { "Content-Type": "application/json" } });

async function envoyer(userIds: string[], payload: Record<string, string>) {
  if (!userIds.length) return 0;
  const { data: cle, error } = await sb.rpc("cap_vapid_private");
  if (error || !cle) throw new Error("cle_vapid_absente");
  webpush.setVapidDetails("https://cap-proteine-maroc.vercel.app", VAPID_PUBLIC, cle as string);
  const { data: abos } = await sb.from("push_abonnements").select("id, endpoint, p256dh, auth").in("user_id", userIds);
  let n = 0;
  for (const s of abos || []) {
    try {
      await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, JSON.stringify(payload), { TTL: 86400 });
      n++;
    } catch (e) {
      const code = (e as { statusCode?: number }).statusCode;
      if (code === 404 || code === 410) await sb.from("push_abonnements").delete().eq("id", s.id);
    }
  }
  return n;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "methode" }, 405);
  let id = "";
  try { id = String((await req.json()).id || ""); } catch { return json({ error: "corps" }, 400); }
  if (!/^[0-9a-f-]{36}$/.test(id)) return json({ error: "parametres" }, 400);
  const depuis = new Date(Date.now() - 15 * 60e3).toISOString();
  try {
    const { data: rows, error } = await sb.from("reunion_reponses")
      .update({ notifie_le: new Date().toISOString() })
      .eq("id", id).eq("reponse", "oui").is("notifie_le", null).gt("maj_le", depuis)
      .select("id, reunion_id, membre_id");
    if (error) return json({ error: error.message }, 500);
    if (!rows?.length) return json({ ok: true, envoyes: 0, raison: "deja_notifie_ou_ancien" });
    const rr = rows[0];
    const { data: mb } = await sb.from("membres").select("nom, club_id, user_id, clubs(nom)").eq("id", rr.membre_id).maybeSingle();
    const { data: r } = await sb.from("reunions").select("id, date, club_id, clubs(nom, animateur_id)").eq("id", rr.reunion_id).maybeSingle();
    const cr = (r as any)?.clubs || {}, cm = (mb as any)?.clubs || {};
    if (!mb || !r || mb.club_id === r.club_id || !cr.animateur_id) return json({ ok: true, envoyes: 0, raison: "meme_groupe_ou_sans_animateur" });
    const { data: profs } = await sb.from("profiles").select("id").eq("animateur_id", cr.animateur_id);
    const ids = (profs || []).map((p) => p.id as string).filter((u) => u !== mb.user_id);
    const date = r.date ? new Date(r.date + "T12:00:00").toLocaleDateString("fr-FR", { day: "numeric", month: "long" }) : "";
    const n = await envoyer(ids, {
      title: "✋ " + (mb.nom || "Un membre") + " vient à ta réunion",
      body: "Membre de " + (cm.nom || "un autre groupe") + " · " + (cr.nom || "").replace(/^CAP\s+/, "") + (date ? " le " + date : ""),
      url: "/?reunion=" + r.id, tag: "insc-mb-" + rr.id,
    });
    return json({ ok: true, envoyes: n });
  } catch (e) {
    return json({ error: String((e as Error)?.message || e) }, 500);
  }
});
