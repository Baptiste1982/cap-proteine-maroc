/* v1.73 : « Comment installer l'appli sur mon téléphone ». Guide animé, en surimpression, commun au CRM et à l'espace membre.
   Il s'ouvre SUR la page à installer (c'est la page affichée que le téléphone met sur l'écran d'accueil) :
   lien membre.html#installer, /?installer, ou le « ? » des écrans de connexion.
   Installer.ouvrir() · Installer.fermer() · Installer.deja() (déjà ouverte comme une appli) · Installer.auto() (ouvre si le lien le demande). */
(function(){
  const ua=navigator.userAgent||"";
  const iOS=/iPhone|iPad|iPod/i.test(ua)||(/Macintosh/i.test(ua)&&navigator.maxTouchPoints>1);
  const android=/Android/i.test(ua);
  const chromeIOS=/CriOS|FxiOS|EdgiOS/i.test(ua);
  let invite=null; // Android : le téléphone propose l'installation directe
  window.addEventListener("beforeinstallprompt",e=>{e.preventDefault();invite=e;const b=document.getElementById("ins-direct");if(b)b.hidden=false});
  const deja=()=>{try{return matchMedia("(display-mode: standalone)").matches||navigator.standalone===true}catch(e){return false}};
  const PART='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 15V3M8 7l4-4 4 4M5 12v7a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-7"/></svg>';
  const PTS='<svg viewBox="0 0 24 24" fill="currentColor"><circle cx="12" cy="5" r="2"/><circle cx="12" cy="12" r="2"/><circle cx="12" cy="19" r="2"/></svg>';
  const ICO='<img class="ins-ico" src="icone-192.png?v=2" alt="">';
  const PAGE='<div class="ins-page">'+ICO+'<b>CAP Protéine</b><p>Club d\'Affaires Protéine</p><span class="ins-champ"></span><span class="ins-champ"></span><span class="ins-cta"></span></div>';
  // v1.77 : dernière étape — activer les notifications (recommandation reçue, message, document…)
  const MEMBRE=/membre\.html/.test(location.pathname);
  const NOTIF=["Active les notifications",(MEMBRE?"Ouvre l'appli par son icône, puis Moi → Notifications → Activer.":"Ouvre l'appli par son icône, puis la cloche en haut → Activer.")+(MEMBRE?" Tu es prévenu dès qu'une recommandation arrive.":" Tu es prévenu des inscriptions, des demandes et des recommandations.")];
  const BANN='<div class="ins-notif" data-notif><b>CAP Protéine</b><span>'+(MEMBRE?"Karim t\'a recommandé un contact":"Nouvel inscrit à ta réunion")+'</span></div>';
  const ACC='<div class="ins-acc" data-acc>'+BANN+'<span class="ins-app"><i></i>Appli</span>'.repeat(7)+'<span class="ins-app cap" data-cap><i>'+ICO+'</i>CAP Protéine</span></div>';
  const lig=(t,fort,d)=>'<div class="ins-lg"'+(d?' data-c="'+d+'"':'')+'><span>'+(fort?'<b>'+t+'</b>':t)+'</span></div>';
  function guide(os){
    if(os==="ios"){const haut=chromeIOS;
      return {html:'<div class="ins-barre"><span class="ins-url">cap-proteine-maroc.vercel.app</span>'+(haut?'<span class="ins-bt" data-c="1">'+PART+'</span>':'')+'</div>'+PAGE+
        (haut?'':'<div class="ins-bas"><span class="ins-bt g">‹</span><span class="ins-bt g">›</span><span class="ins-bt" data-c="1">'+PART+'</span><span class="ins-bt g">▢</span></div>')+
        '<div class="ins-voile" data-vo></div><div class="ins-feuille" data-fe><h4>cap-proteine-maroc.vercel.app</h4>'+lig("Copier")+lig("Ajouter aux favoris")+lig("Sur l'écran d'accueil",1,2)+lig("Imprimer")+'</div>'+
        '<div class="ins-conf" data-co>'+ICO+'<b>CAP Protéine</b><span class="ins-ok" data-c="3">Ajouter</span></div>'+ACC,
       pas:[["Tu es sur la bonne page","Garde cette page ouverte"+(haut?".":" dans Safari.")],
            ["Touche le bouton de partage",haut?"Le carré avec la flèche vers le haut, en haut à droite.":"Le carré avec la flèche vers le haut, en bas de l'écran."],
            ["Choisis « Sur l'écran d'accueil »","Fais défiler la liste vers le bas si tu ne le vois pas."],
            ["Touche « Ajouter »","En haut à droite de la fenêtre."],
            ["C'est fait","L'icône CAP Protéine est sur ton téléphone, comme une appli."],NOTIF]}}
    return {html:'<div class="ins-barre"><span class="ins-url">cap-proteine-maroc.vercel.app</span><span class="ins-bt n" data-c="1">'+PTS+'</span></div>'+PAGE+
        '<div class="ins-voile" data-vo></div><div class="ins-menu" data-fe>'+lig("Nouvel onglet")+lig("Favoris")+lig("Ajouter à l'écran d'accueil",1,2)+lig("Paramètres")+'</div>'+
        '<div class="ins-conf" data-co>'+ICO+'<b>Installer l\'appli ?</b><span class="ins-ok" data-c="3">Installer</span></div>'+ACC,
       pas:[["Tu es sur la bonne page","Garde cette page ouverte dans Chrome."],
            ["Touche les trois points","En haut à droite de l'écran."],
            ["Choisis « Ajouter à l'écran d'accueil »","Selon le téléphone, la ligne s'appelle « Installer l'application »."],
            ["Touche « Installer »","Le téléphone te demande de confirmer."],
            ["C'est fait","L'icône CAP Protéine est sur ton téléphone, comme une appli."],NOTIF]}}
  const CSS=`#ins-o{position:fixed;inset:0;z-index:100000;background:rgba(10,11,13,.9);-webkit-backdrop-filter:blur(8px);backdrop-filter:blur(8px);display:flex;align-items:flex-start;justify-content:center;overflow-y:auto;padding:max(14px,env(safe-area-inset-top,0px)) 16px max(18px,env(safe-area-inset-bottom,0px));color:#F2F1EF;font-family:Inter,system-ui,sans-serif}
#ins-o *{box-sizing:border-box}
.ins-b{width:min(100%,400px);display:flex;flex-direction:column;align-items:center;gap:10px;margin:auto 0}
.ins-tete{align-self:stretch;display:flex;align-items:flex-start;justify-content:space-between;gap:12px}
.ins-tete h2{margin:0;font:800 19px/1.15 "Bricolage Grotesque",system-ui,sans-serif;color:#fff}
.ins-tete p{margin:4px 0 0;font-size:13px;color:#A7A9AE}
.ins-x{flex:none;width:40px;height:40px;border-radius:50%;border:1px solid #4A4C52;background:#222326;color:#fff;font-size:17px;cursor:pointer}
.ins-seg{display:inline-flex;border:1px solid #36383C;border-radius:999px;padding:3px;background:#222326}
.ins-seg button{border:0;background:transparent;color:#A7A9AE;font:600 13px Inter,system-ui,sans-serif;padding:8px 16px;border-radius:999px;cursor:pointer}
.ins-seg button[aria-pressed=true]{background:#D81B3F;color:#fff}
.ins-telw{flex:none;width:calc(250px*var(--k,1));height:calc(500px*var(--k,1))}.ins-tel{width:250px;height:500px;transform:scale(var(--k,1));transform-origin:top left;border-radius:36px;background:#000;border:2px solid #4A4C52;padding:8px}
.ins-ecran{position:relative;height:100%;border-radius:29px;overflow:hidden;background:#F4F2F0;color:#1B1416;font-size:11px;text-align:left}
.ins-barre{display:flex;align-items:center;gap:6px;padding:9px 8px 7px;background:#E7E5E3;border-bottom:1px solid #D2D0CE}
.ins-url{flex:1;background:#fff;border-radius:999px;padding:5px 9px;font-size:9px;color:#55585E;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.ins-bt{flex:none;width:26px;height:26px;border-radius:8px;display:grid;place-items:center;color:#1F6FEB}.ins-bt.g{color:#8B8D93}.ins-bt.n{color:#3C3F45}.ins-bt svg{width:17px;height:17px}
.ins-page{padding:16px 12px;display:flex;flex-direction:column;gap:8px;align-items:center;text-align:center}
.ins-ico{width:52px;height:52px;border-radius:13px;display:block;background:#fff;box-shadow:0 4px 12px rgba(0,0,0,.14)}
.ins-page b{font:800 14px "Bricolage Grotesque",system-ui,sans-serif}.ins-page p{margin:0;color:#6A6C72;font-size:10px}
.ins-champ{width:100%;height:26px;border-radius:8px;background:#fff;border:1px solid #DAD8D6}.ins-cta{width:100%;height:28px;border-radius:8px;background:#D81B3F}
.ins-bas{position:absolute;left:0;right:0;bottom:0;display:flex;justify-content:space-around;align-items:center;padding:7px 6px 12px;background:#E7E5E3;border-top:1px solid #D2D0CE}
.ins-cible{box-shadow:0 0 0 3px #D81B3F;border-radius:9px;animation:insPulse 1.1s ease-in-out infinite}
@keyframes insPulse{50%{box-shadow:0 0 0 9px rgba(216,27,63,.25)}}
.ins-feuille{position:absolute;left:0;right:0;bottom:0;background:#fff;border-radius:16px 16px 0 0;padding:10px 8px 14px;box-shadow:0 -10px 30px rgba(0,0,0,.25);transform:translateY(105%);transition:transform .45s cubic-bezier(.2,.8,.2,1)}
.ins-feuille.on{transform:none}.ins-feuille h4{margin:0 0 6px;font:600 9.5px Inter,system-ui,sans-serif;color:#6A6C72;text-align:center}
.ins-lg{padding:8px 9px;border-radius:9px;font-size:11px;border-bottom:1px solid #EEECEA}.ins-lg:last-child{border-bottom:0}
.ins-menu{position:absolute;right:6px;top:40px;width:172px;background:#fff;border-radius:11px;box-shadow:0 12px 30px rgba(0,0,0,.3);padding:5px;opacity:0;transform:scale(.9);transform-origin:top right;transition:.3s}.ins-menu.on{opacity:1;transform:none}
.ins-voile{position:absolute;inset:0;background:rgba(0,0,0,.35);opacity:0;transition:opacity .3s;pointer-events:none}.ins-voile.on{opacity:1}
.ins-conf{position:absolute;left:12px;right:12px;top:50%;transform:translateY(-50%) scale(.9);background:#fff;border-radius:14px;padding:12px;display:flex;flex-direction:column;gap:8px;align-items:center;opacity:0;transition:.3s;text-align:center}.ins-conf.on{opacity:1;transform:translateY(-50%)}
.ins-conf b{font-size:12px}.ins-ok{align-self:stretch;text-align:center;padding:8px;border-radius:8px;background:#1F6FEB;color:#fff;font-weight:700}
.ins-acc{position:absolute;inset:0;background:linear-gradient(160deg,#2B3A55,#5B3B52 60%,#8A3A44);display:grid;grid-template-columns:repeat(4,1fr);gap:14px 8px;padding:38px 14px;align-content:start;opacity:0;transition:opacity .5s;pointer-events:none}.ins-acc.on{opacity:1}
.ins-notif{position:absolute;left:8px;right:8px;top:8px;grid-column:1/-1;background:rgba(255,255,255,.96);color:#1B1416;border-radius:13px;padding:8px 10px;display:flex;flex-direction:column;gap:1px;font-size:9.5px;text-align:left;box-shadow:0 8px 22px rgba(0,0,0,.35);transform:translateY(-130%);transition:transform .5s cubic-bezier(.2,.9,.3,1.1)}.ins-notif.on{transform:none}.ins-notif b{font-size:9px;color:#D81B3F}
.ins-app{display:flex;flex-direction:column;align-items:center;gap:3px;font-size:7.5px;color:#fff;text-align:center}.ins-app i{width:38px;height:38px;border-radius:10px;background:rgba(255,255,255,.22);display:block;overflow:hidden}
.ins-app.cap i{background:#fff}.ins-app.cap .ins-ico{width:38px;height:38px;border-radius:10px;box-shadow:none}.ins-app.cap.pose i{animation:insPose .6s cubic-bezier(.2,1.4,.4,1) both}
@keyframes insPose{from{transform:scale(0)}}
.ins-leg{min-height:58px;text-align:center}.ins-leg b{display:block;font:600 16px/1.25 "Bricolage Grotesque",system-ui,sans-serif;color:#fff}.ins-leg span{color:#A7A9AE;font-size:13.5px;line-height:1.4}
.ins-pas{display:flex;gap:6px;align-items:center}.ins-pas button{width:26px;height:8px;border-radius:999px;border:0;background:#36383C;cursor:pointer;padding:0}.ins-pas button[aria-current=true]{background:#D81B3F}
.ins-pas .ins-lect{width:auto;height:auto;background:none;color:#A7A9AE;font:600 12.5px Inter,system-ui,sans-serif;padding:6px 8px;margin-left:4px}
.ins-act{align-self:stretch;display:flex;flex-direction:column;gap:8px}
.ins-act button{min-height:46px;border-radius:13px;border:1px solid #4A4C52;background:transparent;color:#fff;font:700 15px Inter,system-ui,sans-serif;cursor:pointer}
.ins-act button.p{background:#D81B3F;border-color:#D81B3F}
.ins-note{font-size:12.5px;color:#A7A9AE;text-align:center;margin:0}
#ins-o button:focus-visible{outline:2px solid #8FB0D1;outline-offset:2px}
@media(prefers-reduced-motion:reduce){.ins-notif{transition:none}.ins-cible,.ins-app.cap.pose i{animation:none}.ins-feuille,.ins-menu,.ins-conf,.ins-acc,.ins-voile{transition:none}}`;
  let os=iOS?"ios":"and",pas=0,joue=true,min=null,G=null;
  const q=s=>document.querySelector("#ins-o "+s);
  function etat(){const l=q(".ins-lect");if(l)l.textContent=joue?"❚❚ Pause":"▶ Lecture"}
  function aller(i){pas=i;clearTimeout(min);if(!document.getElementById("ins-o"))return;const p=G.pas[i];q("[data-lt]").textContent=(i+1)+". "+p[0];q("[data-ls]").textContent=p[1];
    document.querySelectorAll("#ins-o .ins-pas [data-i]").forEach((b,k)=>b.setAttribute("aria-current",k===i));
    document.querySelectorAll("#ins-o [data-c]").forEach(e=>e.classList.toggle("ins-cible",Number(e.dataset.c)===i));
    q("[data-fe]").classList.toggle("on",i===2);q("[data-vo]").classList.toggle("on",i===2||i===3);q("[data-co]").classList.toggle("on",i===3);
    q("[data-acc]").classList.toggle("on",i>=4);const c=q("[data-cap]");c.classList.remove("pose");if(i===4){void c.offsetWidth;c.classList.add("pose")}
    q("[data-notif]").classList.toggle("on",i===5);
    etat();if(joue)min=setTimeout(()=>aller((pas+1)%G.pas.length),i>=4?3600:2800)}
  function dessiner(){G=guide(os);q(".ins-ecran").innerHTML=G.html;
    q("[data-os=ios]").setAttribute("aria-pressed",os==="ios");q("[data-os=and]").setAttribute("aria-pressed",os==="and");
    q(".ins-pas").innerHTML=G.pas.map((_,i)=>'<button type="button" data-i="'+i+'" aria-label="Étape '+(i+1)+'"></button>').join("")+'<button type="button" class="ins-lect"></button>';
    document.querySelectorAll("#ins-o .ins-pas [data-i]").forEach(b=>b.onclick=()=>{joue=false;aller(Number(b.dataset.i))});
    q(".ins-lect").onclick=()=>{joue=!joue;if(joue)aller((pas+1)%G.pas.length);else etat()};aller(0)}
  // le téléphone dessiné se réduit pour que tout le guide tienne dans l'écran, sans défiler
  function caler(){const o=document.getElementById("ins-o");if(!o)return;const k=Math.max(.5,Math.min(1,(innerHeight-330)/500,innerWidth*.7/250));o.style.setProperty("--k",k.toFixed(3))}
  function fermer(){window.removeEventListener("resize",caler);clearTimeout(min);const o=document.getElementById("ins-o");if(o)o.remove();document.removeEventListener("keydown",touche)}
  function touche(e){if(e.key==="Escape")fermer()}
  function ouvrir(force){
    fermer();if(force==="ios"||force==="and")os=force;if(!document.getElementById("ins-css")){const s=document.createElement("style");s.id="ins-css";s.textContent=CSS;document.head.appendChild(s)}
    const d=document.createElement("div");d.id="ins-o";d.setAttribute("role","dialog");d.setAttribute("aria-modal","true");d.setAttribute("aria-label","Installer l'appli sur mon téléphone");
    const ordi=!iOS&&!android;
    d.innerHTML='<div class="ins-b"><div class="ins-tete"><div><h2>'+(deja()?"L'appli est déjà installée":"Installer l'appli sur ton téléphone")+'</h2><p>'+(deja()?"Tu l'as ouverte depuis ton écran d'accueil. Voici les gestes, pour les montrer à quelqu'un.":ordi?"Ouvre cette page sur ton téléphone, puis suis les gestes ci-dessous.":"30 secondes, une seule fois. Ensuite tu l'ouvres comme une appli.")+'</p></div><button type="button" class="ins-x" aria-label="Fermer">✕</button></div>'+
      '<div class="ins-seg" role="group" aria-label="Type de téléphone"><button type="button" data-os="ios">iPhone</button><button type="button" data-os="and">Android</button></div>'+
      '<div class="ins-telw"><div class="ins-tel"><div class="ins-ecran" aria-hidden="true"></div></div></div>'+
      '<div class="ins-leg" aria-live="polite"><b data-lt></b><span data-ls></span></div><div class="ins-pas"></div>'+
      '<div class="ins-act"><button type="button" class="p" id="ins-direct"'+(invite?"":" hidden")+'>Installer maintenant</button></div>'+
      (iOS&&!deja()?'<p class="ins-note">Si le bouton de partage n\'apparaît pas, ouvre cette page dans Safari.</p>':"")+'</div>';
    document.body.appendChild(d);
    q(".ins-x").onclick=fermer;caler();window.addEventListener("resize",caler);d.onclick=e=>{if(e.target===d)fermer()};
    q("[data-os=ios]").onclick=()=>{os="ios";joue=true;dessiner()};q("[data-os=and]").onclick=()=>{os="and";joue=true;dessiner()};
    q("#ins-direct").onclick=async()=>{if(!invite)return;try{invite.prompt();await invite.userChoice}catch(e){}invite=null;fermer()};
    document.addEventListener("keydown",touche);
    try{joue=!matchMedia("(prefers-reduced-motion: reduce)").matches}catch(e){joue=true}
    dessiner();
  }
  function auto(){try{if(location.hash==="#installer"||/[?&]installer\b/.test(location.search)){
      // on retire le repère de l'adresse : c'est cette adresse que le téléphone garde sur l'écran d'accueil
      history.replaceState(null,"",location.pathname);if(!deja())ouvrir();return true}}catch(e){}return false}
  window.Installer={ouvrir,fermer,deja,auto,lien:"Comment installer l'appli sur mon téléphone"};
})();
