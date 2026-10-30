// Notifications de l'espace membre (v0.25.0), appelée par les déclencheurs de la base.
//   type "message" : nouveau message direct → appareils du destinataire (ouvre la conversation).
//   type "invite"  : invité proposé par un membre → appareils de l'animateur du club et de la direction.
//   type "reco"    : recommandation d'affaires reçue (v0.26.0) → appareils de celui qui la reçoit.
//   type "reco_suivi" : la recommandation avance (contact, devis, signée…) → appareils de celui qui l'a donnée.
// verify_jwt:false — la fonction ne fait confiance qu'à la base : la ligne doit exister, dater de moins de
// 15 min et ne pas avoir été notifiée (réservation atomique de notifie_le).
import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import webpush from "npm:web-push@3.6.7";

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const VAPID_PUBLIC = "BAKkMOISOmM62avwTzeE81_l592rvg9O-AiLBct4eGf7Xovoy_OswNK0lnQ0yokt6VDoRkL927x4LS5bFYnWbZM";
let vapidPret = false;
async function initVapid() {
  if (vapidPret) return true;
  const { data, error } = await sb.rpc("cap_vapid_private");
  if (error || !data) return false;
  webpush.setVapidDetails("https://cap-proteine-maroc.vercel.app", VAPID_PUBLIC, data as string);
  return (vapidPret = true);
}
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { "Content-Type": "application/json" } });
const court = (t: string, n: number) => (t.length > n ? t.slice(0, n - 1) + "…" : t);

async function envoyer(userIds: string[], payload: Record<string, string>) {
  if (!userIds.length) return 0;
  if (!(await initVapid())) throw new Error("cle_vapid_absente");
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

const ETAPE: Record<string, string> = { envoyee: "envoyée", contact: "contact pris", devis: "devis envoyé", signee: "affaire signée 🎉", sans_suite: "sans suite" };
const mad = (n: number) => new Intl.NumberFormat("fr-FR").format(Math.round(n)).replace(/\u202f|\u00a0/g, " ") + " MAD";

async function reco(type: string, id: string, depuis: string) {
  let r: Record<string, any> | undefined;
  if (type === "reco") {
    const { data, error } = await sb.from("recommandations").update({ notifie_le: new Date().toISOString() })
      .eq("id", id).is("notifie_le", null).gt("cree_le", depuis).select("id, de, a, contact_nom, contact_entreprise, besoin");
    if (error) throw new Error(error.message);
    r = data?.[0];
  } else {
    const { data: cur } = await sb.from("recommandations").select("statut").eq("id", id).gt("maj_le", depuis).maybeSingle();
    if (!cur || cur.statut === "envoyee") return { ok: true, envoyes: 0 };
    const { data, error } = await sb.from("recommandations").update({ suivi_notifie: cur.statut })
      .eq("id", id).eq("statut", cur.statut).or(`suivi_notifie.is.null,suivi_notifie.neq.${cur.statut}`)
      .select("id, de, a, contact_nom, statut, montant");
    if (error) throw new Error(error.message);
    r = data?.[0];
  }
  if (!r) return { ok: true, envoyes: 0, raison: "deja_notifie_ou_ancien" };
  const { data: gens } = await sb.from("membres").select("id, nom, user_id").in("id", [r.de, r.a]);
  const de = gens?.find((g) => g.id === r!.de), a = gens?.find((g) => g.id === r!.a);
  const cible = type === "reco" ? a : de, autre = type === "reco" ? de : a;
  if (!cible?.user_id) return { ok: true, envoyes: 0 };
  const n = await envoyer([cible.user_id], type === "reco"
    ? { title: "🤝 Recommandation de " + (autre?.nom || "un membre"), body: court([r.contact_nom, r.contact_entreprise, r.besoin].filter(Boolean).join(" · "), 140), url: "/membre.html#r=recues", tag: "reco-" + r.id }
    : { title: "🤝 " + r.contact_nom + " : " + (ETAPE[r.statut] || r.statut), body: (autre?.nom || "Le membre") + " a fait avancer ta recommandation" + (r.statut === "signee" && r.montant ? " — " + mad(Number(r.montant)) : "") + ".", url: "/membre.html#r=donnees", tag: "reco-" + r.id });
  return { ok: true, envoyes: n };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "methode" }, 405);
  let type = "", id = "";
  try { const b = await req.json(); type = String(b.type || ""); id = String(b.id || ""); } catch { return json({ error: "corps" }, 400); }
  if (!/^[0-9a-f-]{36}$/.test(id) || !["message", "invite", "reco", "reco_suivi"].includes(type)) return json({ error: "parametres" }, 400);
  const depuis = new Date(Date.now() - 15 * 60e3).toISOString();
  try {
    if (type === "message") {
      const { data: rows, error } = await sb.from("messages_membres")
        .update({ notifie_le: new Date().toISOString() })
        .eq("id", id).is("notifie_le", null).gt("cree_le", depuis)
        .select("id, de, a, texte");
      if (error) return json({ error: error.message }, 500);
      if (!rows?.length) return json({ ok: true, envoyes: 0, raison: "deja_notifie_ou_ancien" });
      const m = rows[0];
      const { data: gens } = await sb.from("membres").select("id, nom, user_id").in("id", [m.de, m.a]);
      const de = gens?.find((g) => g.id === m.de), a = gens?.find((g) => g.id === m.a);
      if (!a?.user_id) return json({ ok: true, envoyes: 0 });
      const n = await envoyer([a.user_id], {
        title: "💬 " + (de?.nom || "Un membre"), body: court(m.texte, 140),
        url: "/membre.html#c=" + m.de, tag: "msg-" + m.de,
      });
      return json({ ok: true, envoyes: n });
    }
    if (type === "reco" || type === "reco_suivi") return json(await reco(type, id, depuis));
    // invite
    const { data: rows, error } = await sb.from("invites")
      .update({ notifie_le: new Date().toISOString() })
      .eq("id", id).is("notifie_le", null).not("propose_par", "is", null).gt("created_at", depuis)
      .select("id, nom, entreprise, metier, invite_par, reunion_id");
    if (error) return json({ error: error.message }, 500);
    if (!rows?.length) return json({ ok: true, envoyes: 0, raison: "deja_notifie_ou_ancien" });
    const i = rows[0];
    const { data: r } = await sb.from("reunions").select("date, club_id, clubs(nom, ville, animateur_id)").eq("id", i.reunion_id).maybeSingle();
    const c = (r as any)?.clubs || {};
    const { data: profs } = await sb.from("profiles").select("id, role, animateur_id");
    const ids = (profs || []).filter((p) =>
      ["superadmin", "directeur_national"].includes(p.role) || (c.animateur_id && p.animateur_id === c.animateur_id)
    ).map((p) => p.id);
    const date = r?.date ? new Date(r.date + "T12:00:00").toLocaleDateString("fr-FR", { day: "numeric", month: "long" }) : "";
    const n = await envoyer(ids, {
      title: "🙋 Invité proposé par " + (i.invite_par || "un membre"),
      body: [i.nom, i.entreprise || i.metier].filter(Boolean).join(" · ") + " — " + (c.nom || "").replace(/^CAP\s+/, "") + (date ? " le " + date : ""),
      url: "/?reunion=" + i.reunion_id, tag: "inv-" + i.id,
    });
    return json({ ok: true, envoyes: n });
  } catch (e) {
    return json({ error: String((e as Error)?.message || e) }, 500);
  }
});
