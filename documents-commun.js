/* Documents du réseau (v1.10.0) : ce qui est commun à l'espace de gestion (documents.html), à la page de lien
   partagé (doc.html) et à l'espace membre. Typologie de chaque fichier et aperçu adapté à son type. */
const DOC_SB_URL="https://xsppsqjigdgaybmowzaq.supabase.co";
const DOC_BUCKET="reseau";
const DOC_TYPES={
  pdf:{lib:"PDF",coul:"#B0122E",fond:"#F8E9EC"},
  xls:{lib:"Excel",coul:"#1D6B3A",fond:"#E6F2EA"},
  doc:{lib:"Word",coul:"#2B579A",fond:"#E7EEF8"},
  ppt:{lib:"Présentation",coul:"#C2501C",fond:"#FBEDE4"},
  img:{lib:"Image",coul:"#6B3FA0",fond:"#F0E9F8"},
  video:{lib:"Vidéo",coul:"#8A0E24",fond:"#F5E6E9"},
  audio:{lib:"Audio",coul:"#5B7FA3",fond:"#E8EEF4"},
  zip:{lib:"Archive",coul:"#6B5420",fond:"#F4ECD8"},
  txt:{lib:"Texte",coul:"#5E5054",fond:"#F1EDEE"},
  autre:{lib:"Fichier",coul:"#5E5054",fond:"#F1EDEE"}};
function docType(nom,mime){
  const e=String(nom||"").toLowerCase().split(".").pop(),m=String(mime||"").toLowerCase();
  if(e==="pdf"||m.includes("pdf"))return "pdf";
  if(["xls","xlsx","xlsm","ods","csv"].includes(e)||m.includes("spreadsheet")||m.includes("excel"))return e==="csv"?"txt":"xls";
  if(["doc","docx","odt","rtf"].includes(e)||m.includes("word"))return "doc";
  if(["ppt","pptx","pps","ppsx","odp","key"].includes(e)||m.includes("presentation")||m.includes("powerpoint"))return "ppt";
  if(["jpg","jpeg","png","gif","webp","svg","heic","avif"].includes(e)||m.startsWith("image/"))return "img";
  if(["mp4","mov","webm","m4v","avi"].includes(e)||m.startsWith("video/"))return "video";
  if(["mp3","m4a","wav","ogg","aac"].includes(e)||m.startsWith("audio/"))return "audio";
  if(["zip","rar","7z","gz"].includes(e))return "zip";
  if(["txt","md","json"].includes(e)||m.startsWith("text/"))return "txt";
  return "autre";
}
const docExt=n=>{const p=String(n||"").split(".");return p.length>1?p.pop().toUpperCase().slice(0,4):""};
function docTaille(o){o=Number(o)||0;if(o<1024)return o+" o";if(o<1048576)return Math.round(o/1024)+" Ko";return (o/1048576).toFixed(o<10485760?1:0).replace(".",",")+" Mo"}
const docUrl=chemin=>DOC_SB_URL+"/storage/v1/object/public/"+DOC_BUCKET+"/"+String(chemin).split("/").map(encodeURIComponent).join("/");
const DOC_SITE=/^(localhost|127\.|192\.168\.)/.test(location.hostname)?location.origin:"https://cap-proteine-maroc.vercel.app"; // un lien partagé part toujours du site public
const docLien=id=>DOC_SITE+"/doc.html?d="+id;
const docEsc=s=>String(s??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
/* Pastille de type : le format en lettres sur la couleur du type, comme une étiquette de fichier. */
function docPastille(d,taille){
  const k=docType(d.nom_fichier,d.type_mime),t=DOC_TYPES[k],x=docExt(d.nom_fichier)||t.lib.slice(0,3).toUpperCase(),s=taille||44;
  return `<span class="dp" style="width:${s}px;height:${Math.round(s*1.2)}px;background:${t.fond};color:${t.coul};border-color:${t.coul}33" aria-hidden="true"><svg viewBox="0 0 24 28" width="${Math.round(s*.46)}" height="${Math.round(s*.54)}" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><path d="M4 2h11l5 5v19H4z"/><path d="M15 2v5h5"/></svg><b style="font-size:${Math.max(9,Math.round(s*.22))}px">${docEsc(x)}</b></span>`;
}
/* L'aperçu d'un fichier selon son type. `petit` = l'aperçu qui apparaît au survol. */
function docApercu(d,petit){
  const k=docType(d.nom_fichier,d.type_mime),u=docUrl(d.chemin);
  if(k==="pdf")return `<iframe class="ap-f" src="${docEsc(u)}#toolbar=${petit?0:1}&navpanes=0&view=FitH" title="Aperçu de ${docEsc(d.titre)}" loading="lazy"></iframe>`;
  if(k==="img")return `<img class="ap-i" src="${docEsc(u)}" alt="${docEsc(d.titre)}" loading="lazy">`;
  if(k==="video")return `<video class="ap-i" src="${docEsc(u)}" ${petit?"muted autoplay loop playsinline":"controls playsinline"} preload="metadata"></video>`;
  if(k==="audio")return `<div class="ap-v">${docPastille(d,64)}<audio src="${docEsc(u)}" controls preload="metadata" style="width:90%"></audio></div>`;
  if(k==="xls"||k==="doc"||k==="ppt")return `<iframe class="ap-f" src="https://view.officeapps.live.com/op/embed.aspx?src=${encodeURIComponent(u)}" title="Aperçu de ${docEsc(d.titre)}" loading="lazy"></iframe>`;
  if(k==="txt")return `<pre class="ap-t" data-texte="${docEsc(u)}">Chargement…</pre>`;
  return `<div class="ap-v">${docPastille(d,72)}<span>Pas d'aperçu pour ce type de fichier.<br>Ouvre-le ou télécharge-le.</span></div>`;
}
/* Les aperçus texte se remplissent après coup. */
function docRemplirTextes(racine){(racine||document).querySelectorAll("pre[data-texte]").forEach(async p=>{
  try{const t=await (await fetch(p.dataset.texte)).text();p.textContent=t.slice(0,6000)+(t.length>6000?"\n…":"")}catch(e){p.textContent="Aperçu indisponible."}p.removeAttribute("data-texte")})}
const DOC_CSS=`
.dp{display:inline-flex;flex-direction:column;align-items:center;justify-content:center;gap:2px;border-radius:9px;border:1.5px solid;flex-shrink:0;font-family:Inter,system-ui,sans-serif}
.dp b{font-weight:800;letter-spacing:.02em;line-height:1}
.ap-f{width:100%;height:100%;border:0;background:#fff;display:block}
.ap-i{width:100%;height:100%;object-fit:contain;background:#1B1416;display:block}
.ap-t{margin:0;width:100%;height:100%;overflow:auto;background:#fff;color:#1B1416;font:12.5px/1.5 ui-monospace,Menlo,monospace;padding:14px;white-space:pre-wrap;box-sizing:border-box}
.ap-v{width:100%;height:100%;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:14px;text-align:center;color:#5E5054;font-size:14px;background:#FAF6F4;padding:20px;box-sizing:border-box}`;
