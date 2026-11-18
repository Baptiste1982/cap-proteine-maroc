/* Lancement (v1.11.0) : « le réseau se connecte », joué à chaque ouverture du CRM et de l'espace membre, pendant
   que les données se chargent (proposition C validée par JB le 17/11/2026, « un poil plus lente »).
   Des points arrivent des bords, se relient et convergent vers le centre ; le globe Protéine s'allume quand ils se
   rejoignent. Lancement.jouer() au début du chargement, Lancement.fin() quand l'appli est prête : l'écran reste au
   moins DUREE ms, puis s'efface en fondu. Mouvement réduit : le logo seul, sans animation.
   Désactivé sous un navigateur piloté (bancs de test), sauf si localStorage « cap-lancement » vaut « force ». */
const Lancement=(()=>{
  const DUREE=3900,ARRIVEE=1.45,CONVERGE=.9,LOGO=2.05; /* v1.17.0 : un quart plus lent (JB) */
  const COUL=["#E0324E","#D81B3F","#8FB0D1","#E9D9B0","#FFFFFF"];
  let el=null,t0=0,raf=0,finDemandee=false;
  const actif=()=>{let f=null;try{f=localStorage.getItem("cap-lancement")}catch(e){}
    if(f==="off")return false;if(window.top!==window)return false;try{if(sessionStorage.getItem("cap-lanc-skip")){sessionStorage.removeItem("cap-lanc-skip");return false}}catch(e){}if(navigator.webdriver&&f!=="force")return false;return true};
  function jouer(){
    if(el||!actif())return;
    const reduit=matchMedia("(prefers-reduced-motion: reduce)").matches;finDemandee=false;
    el=document.createElement("div");el.id="lancement";el.setAttribute("role","status");el.setAttribute("aria-label","Chargement de Protéine");
    document.documentElement.classList.add("lanc-on"); // v1.31 : plein écran, la barre de défilement ne se voit plus pendant l'ouverture
    el.innerHTML=`<style>
      html.lanc-on{scrollbar-color:transparent transparent;background:#17181A}html.lanc-on::-webkit-scrollbar-thumb{background:transparent}
      #lancement{position:fixed;inset:0;width:100vw;z-index:100000;background:#17181A;display:flex;align-items:center;justify-content:center;transition:opacity .75s ease}
      #lancement.part{opacity:0;pointer-events:none}#lancement canvas{position:absolute;inset:0;width:100%;height:100%}
      #lancement .lg{position:relative;z-index:2;width:136px;height:136px;border-radius:50%;background:#fff;overflow:hidden;opacity:0;transform:scale(.4)}
      #lancement .lg img{width:100%;height:100%;display:block}#lancement .lg.on{animation:lcPop .55s cubic-bezier(.2,1.5,.4,1) forwards,lcHalo 1.1s .3s ease-out}
      #lancement .nm{position:absolute;z-index:2;left:0;right:0;top:calc(50% + 88px);text-align:center;display:flex;flex-direction:column;gap:3px;opacity:0;transform:translateY(10px);font-family:"Bricolage Grotesque",Inter,system-ui,sans-serif;color:#F2EEED}
      #lancement .nm small{font:700 11px Inter,system-ui,sans-serif;letter-spacing:.16em;text-transform:uppercase;color:#B9B2B3}#lancement .nm b{font-size:21px;font-weight:700}
      #lancement .nm.on{animation:lcMonte .5s ease-out forwards}
      @keyframes lcPop{to{opacity:1;transform:scale(1)}}@keyframes lcHalo{0%{box-shadow:0 0 0 0 rgba(224,50,78,.55)}100%{box-shadow:0 0 0 50px rgba(224,50,78,0)}}
      @keyframes lcMonte{to{opacity:1;transform:none}}</style>
      <canvas aria-hidden="true"></canvas><div class="lg"><img src="logo-globe-192.png" alt=""></div><div class="nm"><small>Club d'Affaires</small><b>Protéine Rabat et Région</b></div>`;
    (document.body||document.documentElement).appendChild(el);t0=performance.now();
    const lg=el.querySelector(".lg"),nm=el.querySelector(".nm");
    if(reduit){lg.style.opacity=1;lg.style.transform="none";nm.style.opacity=1;nm.style.transform="none";return}
    const cv=el.querySelector("canvas"),d=devicePixelRatio||1,W=innerWidth,H=innerHeight;cv.width=W*d;cv.height=H*d;const g=cv.getContext("2d");g.scale(d,d);
    const cx=W/2,cy=H/2,N=Math.min(34,Math.max(22,Math.round(W/40))),pts=[];
    for(let i=0;i<N;i++){const a=Math.random()*Math.PI*2,R=Math.max(W,H)*(.6+Math.random()*.25),orb=70+Math.random()*Math.min(120,W*.18),ao=a+Math.random()*.6;
      pts.push({sx:cx+Math.cos(a)*R,sy:cy+Math.sin(a)*R,ox:cx+Math.cos(ao)*orb,oy:cy+Math.sin(ao)*orb*1.1,c:COUL[i%4]})}
    const ease=p=>1-Math.pow(1-p,3);let pose=false;
    (function boucle(t){
      if(!el)return;const e=(t-t0)/1000;g.clearRect(0,0,W,H);
      const p1=Math.min(1,e/ARRIVEE),p2=Math.max(0,Math.min(1,(e-ARRIVEE)/CONVERGE));
      // Après l'apparition du logo, le réseau se resserre jusqu'au centre et s'efface : il ne reste que le logo.
      const p3=Math.max(0,Math.min(1,(e-LOGO)/.9)),k=.6+.4*ease(p3);g.globalAlpha=1-ease(p3);
      const pos=pts.map(p=>{const x1=p.sx+(p.ox-p.sx)*ease(p1),y1=p.sy+(p.oy-p.sy)*ease(p1);const q=ease(p2)*k;return{x:x1+(cx-x1)*q,y:y1+(cy-y1)*q,c:p.c}});
      g.lineWidth=1;
      for(let i=0;i<N;i++)for(let j=i+1;j<N;j++){const dd=Math.hypot(pos[i].x-pos[j].x,pos[i].y-pos[j].y);
        if(dd<80){g.strokeStyle="rgba(143,176,209,"+(.35*(1-dd/80))+")";g.beginPath();g.moveTo(pos[i].x,pos[i].y);g.lineTo(pos[j].x,pos[j].y);g.stroke()}}
      if(p1>=1)for(const q of pos){g.strokeStyle="rgba(224,50,78,"+(.28*p2)+")";g.beginPath();g.moveTo(q.x,q.y);g.lineTo(cx,cy);g.stroke()}
      for(const q of pos){g.fillStyle=q.c;g.beginPath();g.arc(q.x,q.y,3.2,0,7);g.fill()}
      g.globalAlpha=1;
      if(e>LOGO&&!pose){pose=true;lg.classList.add("on");setTimeout(()=>nm.classList.add("on"),480)}
      raf=requestAnimationFrame(boucle);
    })(t0);
  }
  function fin(){
    if(!el||finDemandee)return;finDemandee=true;
    const reste=Math.max(0,DUREE-(performance.now()-t0));
    setTimeout(()=>{if(!el)return;el.classList.add("part");const x=el;el=null;setTimeout(()=>{cancelAnimationFrame(raf);x.remove();document.documentElement.classList.remove("lanc-on")},800)},reste);
  }
  return {jouer,fin,actif};
})();
