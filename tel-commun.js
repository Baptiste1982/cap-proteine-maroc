/* v1.26 : un seul format d'affichage des téléphones, partout (CRM, espace membre).
   Repris de la règle du CRM Atelier Design : indicatif + numéro national groupé, Maroc par défaut.
   telAff('0661234567') → '+212 6 61 23 45 67' ; telAff('+33 6 57 76 26 40') → '+33 6 57 76 26 40'.
   Le numéro enregistré n'est jamais modifié : seul l'affichage est normalisé. */
(function(){
  const PAYS=[["212",[1,2,2,2,2]],["213",[1,2,2,2,2]],["216",[2,3,3]],["33",[1,2,2,2,2]],["32",[3,2,2,2]],["34",[3,3,3]],["39",[3,4,3]],["41",[2,3,2,2]],["49",[3,4,4]],["44",[4,3,3]],
    ["351",[3,3,3]],["352",[3,3,3]],["353",[2,3,4]],["31",[2,4,4]],["1",[3,3,4]],["971",[1,3,4]],["966",[2,3,4]],["974",[4,4]],["961",[1,3,3]],["20",[2,4,4]],["90",[3,3,4]],
    ["86",[3,4,4]],["91",[4,3,3]],["81",[2,4,4]],["221",[2,3,2,2]],["225",[2,2,2,2,2]],["237",[1,2,2,2,2]]].sort((a,b)=>b[0].length-a[0].length);
  const grp=(d,g)=>{if(d.length===g.reduce((s,n)=>s+n,0)){let i=0;return g.map(n=>{const p=d.slice(i,i+n);i+=n;return p}).join(" ")}
    const o=[];for(let i=d.length;i>0;i-=2)o.unshift(d.slice(Math.max(0,i-2),i));return o.join(" ")};
  function telE164(raw){let n=String(raw||"").replace(/[^\d+]/g,"");if(!n)return"";n=n.replace(/(?!^)\+/g,"");
    if(n.startsWith("+"))return n;if(n.startsWith("00"))return"+"+n.slice(2);
    if(n.startsWith("212")&&n.length===12)return"+"+n;if(n.startsWith("0"))return"+212"+n.slice(1);if(n.length===9)return"+212"+n;
    return n.length>=10?"+"+n:""}
  function telAff(raw){const e=telE164(raw);if(!e)return String(raw||"").trim();const d=e.slice(1);
    for(const [cc,g] of PAYS)if(d.startsWith(cc)){const nat=d.slice(cc.length).replace(/^0+(?=\d{8})/,"");return nat?`+${cc} ${grp(nat,g)}`:`+${cc}`}
    return `+${d.slice(0,3)} ${grp(d.slice(3),[2,2,2,2,2])}`.trim()}
  window.telAff=telAff;window.telE164=telE164;
})();

/* v1.69 : aller chercher une personne dans le carnet d'adresses du téléphone.
   Android (Chrome) : le sélecteur de contacts du téléphone s'ouvre. iPhone : Safari ne donne pas accès au carnet ;
   on importe alors une fiche contact (.vcf) partagée depuis l'appli Contacts.
   contactChoisir(cb) appelle cb({nom, tel, email, entreprise, fonction}) ; rien si la personne annule. */
(function(){
  const direct=()=>{try{return "contacts" in navigator&&"select" in navigator.contacts}catch(e){return false}};
  function vcf(t){const o={nom:"",tel:"",email:"",entreprise:"",fonction:""};
    String(t||"").replace(/\r\n[ \t]/g,"").split(/\r?\n/).forEach(l=>{const i=l.indexOf(":");if(i<0)return;const k=l.slice(0,i).toUpperCase().split(";")[0].replace(/^ITEM\d+\./,""),v=l.slice(i+1).replace(/\\,/g,",").replace(/\\n/gi," ").trim();if(!v)return;
      if(k==="FN")o.nom=v;else if(k==="N"&&!o.nom){const p=v.split(";");o.nom=[p[1],p[0]].filter(Boolean).join(" ").trim()}
      else if(k==="TEL"&&!o.tel)o.tel=v;else if(k==="EMAIL"&&!o.email)o.email=v;else if(k==="ORG"&&!o.entreprise)o.entreprise=v.split(";")[0];else if(k==="TITLE"&&!o.fonction)o.fonction=v});
    return o}
  async function contactChoisir(cb){
    if(direct()){try{const r=await navigator.contacts.select(["name","tel","email"],{multiple:false});const c=r&&r[0];if(c)cb({nom:(c.name&&c.name[0])||"",tel:(c.tel&&c.tel[0])||"",email:(c.email&&c.email[0])||"",entreprise:"",fonction:""})}catch(e){}return}
    const i=document.createElement("input");i.type="file";i.accept=".vcf,text/vcard,text/x-vcard,text/directory";i.style.display="none";
    i.onchange=async()=>{const f=i.files&&i.files[0];i.remove();if(!f)return;try{const o=vcf(await f.text());if(o.nom||o.tel)cb(o);else cb(null)}catch(e){cb(null)}};
    document.body.appendChild(i);i.click()}
  window.contactChoisir=contactChoisir;window.contactDirect=direct;window.contactVcf=vcf;
  window.contactLib=()=>direct()?"Choisir dans mes contacts":"Importer une fiche contact";
  window.contactAide=()=>direct()?"":"Sur iPhone : ouvre Contacts, « Partager le contact », « Enregistrer dans Fichiers », puis choisis la fiche ici.";
})();
