/* Calendrier des réunions en PDF (une page par mois), commun au CRM et à l'espace membre.
   calendrierPdf({mois:[{k:"2026-12"}], reunions:[{date,heure,statut,groupe,ville,type}], evenements:[{date,genre,titre,heure}], portee, couleur(ville)}) → Blob */
const CAL_MOIS=["Janvier","Février","Mars","Avril","Mai","Juin","Juillet","Août","Septembre","Octobre","Novembre","Décembre"];
function calPdfLib(){if(window.PDFLib)return Promise.resolve(window.PDFLib);return window._calPdfP=window._calPdfP||new Promise((ok,ko)=>{const sc=document.createElement("script");sc.src="https://cdn.jsdelivr.net/npm/pdf-lib@1.17.1/dist/pdf-lib.min.js";sc.onload=()=>ok(window.PDFLib);sc.onerror=()=>{window._calPdfP=null;ko(new Error("pdf-lib"))};document.head.appendChild(sc)})}
function calPdfSur(t){return String(t||"").replace(/[‘’]/g,"'").replace(/[“”]/g,'"').replace(/[–—]/g,"-").replace(/[^\x20-\x7E\u00A0-\u00FF]/g,"")}
function calPdfJour(iso){const [y,m,d]=String(iso).split("-").map(Number);return new Date(y,m-1,d)}
function calPdfCouleur(v){const P=["#D81B3F","#2E5AA8","#2E7D4F","#C8962C","#7A4FB0","#3D9BC4","#B5651D","#5B7FA3"];let h=0;for(const ch of String(v||""))h=(h*31+ch.charCodeAt(0))>>>0;return P[h%P.length]}
async function calendrierPdf(o){const mois=o.mois,L=await calPdfLib(),doc=await L.PDFDocument.create(),f=await doc.embedFont(L.StandardFonts.Helvetica),fb=await doc.embedFont(L.StandardFonts.HelveticaBold);
  const W=842,H=595,MX=30,rouge=L.rgb(.847,.106,.247),noir=L.rgb(.106,.078,.086),gris=L.rgb(.45,.43,.45),clair=L.rgb(.72,.70,.71),fond=L.rgb(.972,.957,.949),ombre=L.rgb(.925,.905,.895),blanc=L.rgb(1,1,1),rose=L.rgb(.992,.93,.94),filetF=L.rgb(.60,.57,.58),filetC=L.rgb(.80,.78,.78);
  const sur=t=>calPdfSur(String(t==null?"":t).replace(/œ/g,"oe").replace(/Œ/g,"OE").replace(/…/g,"...")).replace(/\s+/g," ").trim();
  const hex=h=>{const m=/^#?([0-9a-f]{6})$/i.exec(h||"");if(!m)return gris;const n=parseInt(m[1],16);return L.rgb((n>>16)/255,((n>>8)&255)/255,(n&255)/255)};
  const coupe=(t,font,sz,lg)=>{t=sur(t);if(font.widthOfTextAtSize(t,sz)<=lg)return t;while(t.length>1&&font.widthOfTextAtSize(t+"...",sz)>lg)t=t.slice(0,-1);return t.trim()+"..."};
  /* rectangle aux coins arrondis : (x, y) = coin bas gauche, comme drawRectangle */
  const rond=(p,x,y,w,h,r,o)=>{r=Math.min(r,w/2,h/2);p.drawSvgPath(`M ${r} 0 H ${w-r} Q ${w} 0 ${w} ${r} V ${h-r} Q ${w} ${h} ${w-r} ${h} H ${r} Q 0 ${h} 0 ${h-r} V ${r} Q 0 0 ${r} 0 Z`,{x,y:y+h,...o})};
  let logo=null;try{logo=await doc.embedPng(await (await fetch("logo-proteine.png")).arrayBuffer())}catch(e){}
  const R=o.reunions||[],EVS=o.evenements||[],portee=sur(o.portee||""),JN=["Lundi","Mardi","Mercredi","Jeudi","Vendredi","Samedi","Dimanche"];
  mois.forEach(mo=>{const p=doc.addPage([W,H]),[y,m]=mo.k.split("-").map(Number),l=R.filter(r=>r.date.slice(0,7)===mo.k),actives=l.filter(r=>r.statut!=="annulee");
    const ev=EVS.filter(e=>e.date.slice(0,7)===mo.k),we=l.concat(ev).some(r=>{const w=calPdfJour(r.date).getDay();return w===0||w===6}),NC=we?7:5;
    p.drawRectangle({x:0,y:0,width:W,height:H,color:fond});
    /* en-tête : le mois en grand, un trait rouge, le logo à droite */
    const tm=sur(CAL_MOIS[m-1]),an=String(y);p.drawText(tm,{x:MX,y:H-58,size:38,font:fb,color:rouge});p.drawText(an,{x:MX+fb.widthOfTextAtSize(tm,38)+10,y:H-58,size:38,font:f,color:clair});
    rond(p,MX,H-72,46,4,2,{color:rouge});
    const ng=new Set(actives.map(r=>r.groupe)).size,st=sur("Calendrier des réunions · "+portee+" · "+actives.length+" réunion"+(actives.length>1?"s":"")+" dans "+ng+" groupe"+(ng>1?"s":""));p.drawText(st,{x:MX+56,y:H-73,size:10,font:f,color:gris});
    if(logo){const lh=40,lw=logo.width*lh/logo.height;p.drawImage(logo,{x:W-MX-lw,y:H-66,width:lw,height:lh})}
    /* grille : une carte par jour, sans traits */
    const nb=new Date(y,m,0).getDate(),sem=[];let cur=null;
    for(let j=1;j<=nb;j++){const d=new Date(y,m-1,j),col=(d.getDay()+6)%7;if(!cur||col===0){cur=new Array(7).fill(null);sem.push(cur)}cur[col]=j}
    const lignes=sem.filter(s=>s.slice(0,NC).some(x=>x)),top=H-92,bas=44,eh=16,G=6,GH=top-eh-bas,CW=(W-2*MX-G*(NC-1))/NC,RH=(GH-G*(lignes.length-1))/lignes.length;
    for(let c=0;c<NC;c++){const t=JN[c].toUpperCase();p.drawText(t,{x:MX+c*(CW+G)+4,y:top-eh+5,size:7.5,font:fb,color:gris})}
    lignes.forEach((s,ri)=>{const y0=top-eh-ri*(RH+G)-RH;for(let c=0;c<NC;c++){const j=s[c],x0=MX+c*(CW+G);if(!j)continue;
      const iso=mo.k+"-"+String(j).padStart(2,"0"),E=l.filter(r=>r.date===iso),EV=ev.filter(e=>e.date===iso),plein=E.length||EV.length;
      if(plein){rond(p,x0+1.5,y0-2,CW,RH,9,{color:ombre});rond(p,x0,y0,CW,RH,9,{color:blanc,borderColor:filetF,borderWidth:1.1})}else rond(p,x0,y0,CW,RH,9,{borderColor:filetC,borderWidth:.9});
      const n=String(j);if(plein){p.drawCircle({x:x0+15,y:y0+RH-15,size:9,color:rouge});p.drawText(n,{x:x0+15-fb.widthOfTextAtSize(n,9.5)/2,y:y0+RH-18.4,size:9.5,font:fb,color:blanc})}else p.drawText(n,{x:x0+10,y:y0+RH-18,size:9.5,font:fb,color:gris});
      let yy=y0+RH-36;
      EV.forEach(e=>{if(E.length&&RH<100){rond(p,x0+6,yy-4,CW-12,13,6.5,{color:rouge});p.drawText(coupe(e.titre,fb,6.8,CW-26),{x:x0+13,y:yy-.4,size:6.8,font:fb,color:blanc});yy-=17;return}rond(p,x0+6,yy-15,CW-12,25,7,{color:rouge});p.drawText(coupe(e.genre.toUpperCase()+(e.heure?" · "+e.heure:""),fb,5.8,CW-26),{x:x0+13,y:yy+1,size:5.8,font:fb,color:rose});p.drawText(coupe(e.titre,fb,7.6,CW-26),{x:x0+13,y:yy-9,size:7.6,font:fb,color:blanc});yy-=30});
      /* une réunion = pastille de la ville, groupe en gras, type dessous quand la place le permet */
      const dispo=yy-(y0+5),deux=E.length*19<=dispo+8,lh=deux?19:E.length*11<=dispo+4?11:9.4,sz=lh<10?6.8:7.6,max=Math.max(1,Math.floor((dispo+lh-6)/lh));
      E.slice(0,E.length>max?max-1:max).forEach((r,i)=>{const an=r.statut==="annulee",y1=yy-i*lh,h=r.heure?r.heure.slice(0,5).replace(/^0/,"").replace(":","h").replace(/h00$/,"h"):"";
        p.drawCircle({x:x0+10,y:y1+2.6,size:2.8,color:an?clair:hex(o.couleur(r.ville))});
        const g=coupe(r.groupe,fb,sz,CW-22-(deux?0:0)),lg=fb.widthOfTextAtSize(g,sz);p.drawText(g,{x:x0+17,y:y1,size:sz,font:fb,color:an?gris:noir});
        const sous=[h,an?"annulée":r.type].filter(Boolean).join(" · ");
        if(deux)p.drawText(coupe(sous,f,6.6,CW-22),{x:x0+17,y:y1-8,size:6.6,font:f,color:gris});
        else{const reste=CW-22-lg-4;if(reste>26)p.drawText(coupe("· "+sous,f,sz,reste),{x:x0+17+lg+3,y:y1,size:sz,font:f,color:gris})}});
      if(E.length>max)p.drawText("+ "+(E.length-max+1)+" autres",{x:x0+17,y:yy-(max-1)*lh,size:sz,font:f,color:gris})}});
    /* légende et pied */
    let lx=MX;[...new Set(l.map(r=>r.ville).filter(Boolean))].sort().forEach(v=>{const t=sur(v);p.drawCircle({x:lx+3.5,y:27.5,size:3.5,color:hex(o.couleur(v))});p.drawText(t,{x:lx+11,y:24.5,size:8.5,font:f,color:noir});lx+=11+f.widthOfTextAtSize(t,8.5)+16});
    const pied=sur("Club d'Affaires Protéine Maroc · établi le "+new Date().toLocaleDateString("fr-FR"));p.drawText(pied,{x:W-MX-f.widthOfTextAtSize(pied,8),y:24.5,size:8,font:f,color:gris})});
  return new Blob([await doc.save()],{type:"application/pdf"})}
