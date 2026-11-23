// Sonde de lecture du CRM national : a servi une fois le 23/11/2026, neutralisée.
Deno.serve(() => new Response(JSON.stringify({ error: 'Fonction retirée' }), { status: 410, headers: { 'Content-Type': 'application/json' } }));
