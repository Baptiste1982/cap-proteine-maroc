/* CAP Protéine Maroc — le CRM écrit l'état des leads dans ce classeur.
   Installation : Extensions → Apps Script, coller ce fichier, remplacer JETON,
   Déployer → Nouveau déploiement → Application Web (exécuter en tant que : moi ; accès : tout le monde),
   puis donner l'URL /exec à Alix (elle la range dans le CRM, table reglages). */
const JETON = 'A_REMPLACER';
const COL_SUIVI = 'Suivi CRM';
function norm(t){return String(t||'').normalize('NFD').replace(/[̀-ͯ]/g,'').toLowerCase().replace(/[^a-z0-9]+/g,' ').trim()}
function doPost(e){
  let d={};try{d=JSON.parse(e.postData.contents)}catch(x){return rep({ok:false,err:'json'})}
  if(d.jeton!==JETON)return rep({ok:false,err:'jeton'});
  const sh=SpreadsheetApp.getActive().getSheetByName(d.feuille||'Rabat');if(!sh)return rep({ok:false,err:'feuille'});
  const v=sh.getDataRange().getValues();if(!v.length)return rep({ok:false,err:'vide'});
  let ligneTitre=0;for(let i=0;i<Math.min(5,v.length);i++){if(v[i].filter(String).length>=3){ligneTitre=i;break}}
  const titres=v[ligneTitre].map(String);let c=titres.indexOf(COL_SUIVI);
  if(c<0){c=titres.length;sh.getRange(ligneTitre+1,c+1).setValue(COL_SUIVI).setFontWeight('bold')}
  const cible=norm(d.nom);let r=-1;
  for(let i=ligneTitre+1;i<v.length;i++){if(norm(v[i][1])===cible){r=i;break}}
  if(r<0)for(let i=ligneTitre+1;i<v.length;i++){if(v[i].some(x=>norm(x)===cible)){r=i;break}}
  if(r<0)return rep({ok:false,err:'nom introuvable'});
  sh.getRange(r+1,c+1).setValue(d.suivi||'');
  return rep({ok:true,ligne:r+1});
}
function rep(o){return ContentService.createTextOutput(JSON.stringify(o)).setMimeType(ContentService.MimeType.JSON)}

/* ── v1.21 : remontée automatique des leads vers le CRM ──────────────────────────────────────────
   Toutes les 15 minutes, chaque onglet de FEUILLES est lu et ses lignes sont envoyées au CRM.
   Le CRM ne crée que les leads qu'il ne connaît pas encore (même nom, ou même mobile) et envoie
   une notification sur le téléphone de JB. Installation : exécuter une fois la fonction installer(). */
const FEUILLES = ['Rabat'];
const CRM_RPC = 'https://xsppsqjigdgaybmowzaq.supabase.co/rest/v1/rpc/cap_leads_recevoir';
const CRM_CLE = 'sb_publishable_2uW0CfYvPRJ8TsJw_aNNhA_l7_UQjL7';
function lignesDe(sh){
  const v=sh.getDataRange().getDisplayValues();let h=-1;
  for(let i=0;i<Math.min(8,v.length);i++){if(v[i].some(x=>norm(x)==='source')){h=i;break}}
  if(h<0)return [];
  const t=v[h].map(norm),col=(...m)=>t.findIndex(x=>m.some(k=>x.indexOf(k)===0));
  const cS=col('source'),cP=col('prospect'),cPr=col('prenom'),cN=t.indexOf('nom'),cSp=col('specialite'),cR=col('reorientation'),cC=col('commantaire','commentaire'),cL=col('lien','linkedin');
  const cT=[col('phone'),col('numero de telephone'),col('telephone')].filter(x=>x>=0);
  const out=[];
  for(let i=h+1;i<v.length;i++){const r=v[i];
    const nom=cP>=0?r[cP]:[cPr>=0?r[cPr]:'',cN>=0?r[cN]:''].join(' ');
    if(!String(nom).trim())continue;
    const tel=cT.map(c=>r[c]).find(x=>String(x).replace(/\D/g,'').length>=9)||'';
    out.push({nom:String(nom).trim(),source:cS>=0?r[cS]:'',specialite:cSp>=0?r[cSp]:'',telephone:tel,linkedin:cL>=0&&/^https?:/.test(r[cL])?r[cL]:'',
      commentaire:[cR>=0?r[cR]:'',cC>=0?r[cC]:''].filter(String).join(' · ')});
  }
  return out;
}
function envoyerLeads(){
  const ss=SpreadsheetApp.getActive();const rapport=[];
  FEUILLES.forEach(f=>{const sh=ss.getSheetByName(f);if(!sh)return;
    const r=UrlFetchApp.fetch(CRM_RPC,{method:'post',contentType:'application/json',muteHttpExceptions:true,
      headers:{apikey:CRM_CLE,Authorization:'Bearer '+CRM_CLE},payload:JSON.stringify({p_jeton:JETON,p_feuille:f,p_lignes:lignesDe(sh)})});
    rapport.push(f+' : '+r.getResponseCode()+' '+r.getContentText().slice(0,200));});
  Logger.log(rapport.join('\n'));return rapport.join('\n');
}
function installer(){
  ScriptApp.getProjectTriggers().filter(t=>t.getHandlerFunction()==='envoyerLeads').forEach(t=>ScriptApp.deleteTrigger(t));
  ScriptApp.newTrigger('envoyerLeads').timeBased().everyMinutes(15).create();
  return envoyerLeads();
}
