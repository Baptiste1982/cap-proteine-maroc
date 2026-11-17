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
