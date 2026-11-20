// Agenda par abonnement (v1.122) : GET /functions/v1/agenda?j=<jeton> rend un calendrier .ics avec les PSA et les réunions
// de la personne. Google Agenda, Apple et Outlook relisent cette adresse tout seuls (toutes les quelques heures).
const url = Deno.env.get('SUPABASE_URL')!, anon = Deno.env.get('SUPABASE_ANON_KEY')!;
const p2 = (n: number) => String(n).padStart(2, '0');
const z = (d: Date) => d.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
const e = (t: unknown) => String(t ?? '').replace(/\\/g, '\\\\').replace(/([,;])/g, '\\$1').replace(/\r?\n/g, '\\n');
const plier = (l: string) => { const o: string[] = []; let s = l; while (s.length > 72) { o.push(s.slice(0, 72)); s = ' ' + s.slice(72); } o.push(s); return o.join('\r\n'); };
const TYPES: Record<string, string> = { SI: "Session d'information", RL: 'Réunion de lancement' };
const FORMATS: Record<string, string> = { business: 'Réunion business', conference: 'Réunion thématique', visite: "Visite d'entreprise" };
const MODES: Record<string, string> = { visio: 'En ligne', presentiel: 'Sur place', telephone: 'Téléphone' };

Deno.serve(async (req) => {
  const j = new URL(req.url).searchParams.get('j') || '';
  if (!/^[0-9a-f-]{36}$/i.test(j)) return new Response('Adresse d\'agenda invalide', { status: 400 });
  const r = await fetch(url + '/rest/v1/rpc/cap_agenda_flux', { method: 'POST', headers: { apikey: anon, Authorization: 'Bearer ' + anon, 'Content-Type': 'application/json' }, body: JSON.stringify({ p_jeton: j }) });
  const d = await r.json().catch(() => null);
  if (!r.ok || !d?.ok) return new Response('Agenda introuvable', { status: 404 });
  const L: string[] = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//CAP Proteine Maroc//CRM//FR', 'CALSCALE:GREGORIAN', 'METHOD:PUBLISH', 'X-WR-CALNAME:CAP Protéine', 'X-WR-TIMEZONE:Africa/Casablanca', 'REFRESH-INTERVAL;VALUE=DURATION:PT1H', 'X-PUBLISHED-TTL:PT1H'];
  const stamp = z(new Date());
  for (const c of d.psa || []) {
    const a = new Date(c.debut), f = new Date(a.getTime() + (c.duree || 30) * 60000);
    L.push('BEGIN:VEVENT', 'UID:psa-' + c.id + '@cap-proteine', 'DTSTAMP:' + stamp, 'DTSTART:' + z(a), 'DTEND:' + z(f), 'SUMMARY:' + e('PSA' + (c.avec ? ' · ' + c.avec : '')),
      'DESCRIPTION:' + e(['Point sur activité' + (c.avec ? ' avec ' + c.avec : ''), MODES[c.mode] || '', c.lien ? 'Lien de la réunion : ' + c.lien : ''].filter(Boolean).join('\n')));
    if (c.lieu || c.lien) L.push('LOCATION:' + e(c.lieu || c.lien));
    L.push('BEGIN:VALARM', 'TRIGGER:-PT30M', 'ACTION:DISPLAY', 'DESCRIPTION:PSA', 'END:VALARM', 'END:VEVENT');
  }
  for (const m of d.reunions || []) {
    const jour = String(m.date).replace(/-/g, ''), titre = (m.format ? FORMATS[m.format] : TYPES[m.type]) || 'Réunion';
    L.push('BEGIN:VEVENT', 'UID:reunion-' + m.id + '@cap-proteine', 'DTSTAMP:' + stamp);
    if (/^\d{1,2}:\d{2}/.test(m.heure || '')) { const [h, mi] = String(m.heure).split(':').map(Number), hf = h + 2;
      L.push('DTSTART;TZID=Africa/Casablanca:' + jour + 'T' + p2(h) + p2(mi) + '00', 'DTEND;TZID=Africa/Casablanca:' + jour + 'T' + p2(Math.min(hf, 23)) + p2(mi) + '00');
    } else { const s = new Date(m.date + 'T12:00:00Z'); s.setUTCDate(s.getUTCDate() + 1); L.push('DTSTART;VALUE=DATE:' + jour, 'DTEND;VALUE=DATE:' + s.toISOString().slice(0, 10).replace(/-/g, '')); }
    L.push('SUMMARY:' + e(titre + ' · ' + String(m.groupe || '').replace(/^CAP\s+/, '')), 'DESCRIPTION:' + e([m.groupe, m.theme, m.heure ? '' : 'Heure à préciser'].filter(Boolean).join('\n')));
    if (m.lieu) L.push('LOCATION:' + e([m.lieu, /^https?:/i.test(m.adresse || '') ? '' : m.adresse].filter(Boolean).join(', ')));
    L.push('END:VEVENT');
  }
  L.push('END:VCALENDAR');
  return new Response(L.map(plier).join('\r\n') + '\r\n', { headers: { 'Content-Type': 'text/calendar; charset=utf-8', 'Cache-Control': 'no-cache, max-age=0', 'Content-Disposition': 'inline; filename="cap-proteine.ics"' } });
});
