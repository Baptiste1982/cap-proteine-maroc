// v1.78.0 — rappels automatiques aux membres, une fois par jour (pg_cron « rappels-membres », 17 h au Maroc).
//   1. Réunion de demain : notification aux membres du groupe qui ont un espace membre
//      (« tu viens ? » sans réponse, « à demain » s'ils ont dit oui, rien s'ils ont dit non).
//   2. Recommandation reçue restée « envoyée » depuis plus de 7 jours : une relance au receveur, une seule fois.
// Appel : en-tête x-suivi-jeton (coffre national_suivi_jeton). verify_jwt:false. { essai:true } = compte sans rien envoyer.
import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import webpush from "npm:web-push@3.6.7";

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const VAPID_PUBLIC = "BAKkMOISOmM62avwTzeE81_l592rvg9O-AiLBct4eGf7Xovoy_OswNK0lnQ0yokt6VDoRkL927x4LS5bFYnWbZM";
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { "Content-Type": "application/json" } });

let pret = false;
async function envoyer(userIds: string[], payload: Record<string, string>) {
  if (!userIds.length) return 0;
  if (!pret) {
    const { data: cle, error } = await sb.rpc("cap_vapid_private");
    if (error || !cle) throw new Error("cle_vapid_absente");
    webpush.setVapidDetails("https://cap-proteine-maroc.vercel.app", VAPID_PUBLIC, cle as string);
    pret = true;
  }
  const { data: abos } = await sb.from("push_abonnements").select("id, endpoint, p256dh, auth").in("user_id", userIds);
  let n = 0;
  for (const s of abos || []) {
    try {
      await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, JSON.stringify(payload), { TTL: 43200 });
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
  const jeton = req.headers.get("x-suivi-jeton") || "";
  const { data: okJ } = await sb.rpc("cap_national_jeton_ok", { p: jeton });
  if (okJ !== true) return json({ error: "Non autorisé" }, 401);
  const body = await req.json().catch(() => ({}));
  const essai = !!body.essai;
  try {
    // Demain, à l'heure du Maroc.
    const demain = new Intl.DateTimeFormat("en-CA", { timeZone: "Africa/Casablanca" }).format(new Date(Date.now() + 86400e3));
    const out = { demain, reunions: 0, rappels: 0, recos: 0, relances: 0 };

    // 1. Réunions de demain.
    let q = sb.from("reunions").select("id, heure, club_id, type, format, archivee_le, clubs(nom), lieux(nom)")
      .eq("date", demain).in("statut", ["planifiee", "confirmee"]).is("archivee_le", null).is("rappel_membres_le", null);
    const { data: reus, error: e1 } = await q;
    if (e1) throw new Error(e1.message);
    for (const r of reus || []) {
      out.reunions++;
      if (!essai) {
        const { data: pris } = await sb.from("reunions").update({ rappel_membres_le: new Date().toISOString() }).eq("id", r.id).is("rappel_membres_le", null).select("id");
        if (!pris?.length) continue;
      }
      const { data: mbs } = await sb.from("membres").select("id, user_id").eq("club_id", r.club_id).not("user_id", "is", null);
      const { data: reps } = await sb.from("reunion_reponses").select("membre_id, reponse").eq("reunion_id", r.id);
      const rep = new Map((reps || []).map((x) => [x.membre_id, x.reponse]));
      const h = r.heure ? String(r.heure).slice(0, 5).replace(":", " h ").replace(/ 00$/, "") : "";
      const lieu = (r as any).lieux?.nom, grp = String((r as any).clubs?.nom || "").replace(/^CAP\s+/, "");
      const ou = [h ? "à " + h : "", lieu ? "· " + lieu : ""].filter(Boolean).join(" ");
      const sans = (mbs || []).filter((m) => !rep.has(m.id)).map((m) => m.user_id as string);
      const oui = (mbs || []).filter((m) => rep.get(m.id) === "oui").map((m) => m.user_id as string);
      if (essai) { out.rappels += sans.length + oui.length; continue; }
      out.rappels += await envoyer([...new Set(sans)], { title: "Réunion demain " + ou, body: grp + " · Tu viens ? Réponds en un geste.", url: "/membre.html", tag: "rappel-" + r.id });
      out.rappels += await envoyer([...new Set(oui)], { title: "À demain " + ou, body: grp + " · Tu as dit que tu venais. Pense à tes recommandations.", url: "/membre.html", tag: "rappel-" + r.id });
    }

    // 2. Recommandations qui dorment.
    const avant = new Date(Date.now() - 7 * 86400e3).toISOString();
    const { data: recos, error: e2 } = await sb.from("recommandations").select("id, a, de, objet")
      .eq("statut", "envoyee").lt("cree_le", avant).is("relance_notif_le", null).limit(200);
    if (e2) throw new Error(e2.message);
    for (const k of recos || []) {
      out.recos++;
      if (essai) continue;
      const { data: pris } = await sb.from("recommandations").update({ relance_notif_le: new Date().toISOString() }).eq("id", k.id).eq("statut", "envoyee").is("relance_notif_le", null).select("id");
      if (!pris?.length) continue;
      const { data: m } = await sb.from("membres").select("id, nom, user_id").in("id", [k.a, k.de].filter(Boolean));
      const a = (m || []).find((x) => x.id === k.a), de = (m || []).find((x) => x.id === k.de);
      if (!a?.user_id) continue;
      out.relances += await envoyer([a.user_id as string], {
        title: "Une recommandation t'attend",
        body: (de?.nom ? de.nom + " t'a recommandé" : "Tu as reçu une recommandation") + (k.objet ? " : " + String(k.objet).slice(0, 60) : "") + ". As-tu pu appeler ?",
        url: "/membre.html#r=recues", tag: "reco-relance-" + k.id,
      });
    }
    return json({ ok: true, essai, ...out });
  } catch (e) {
    return json({ error: String((e as Error)?.message || e) }, 500);
  }
});
