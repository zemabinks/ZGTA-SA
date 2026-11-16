'use strict';
// Independent authority for ephemeral, driver-owned trailer/tow links. Imported
// model anchors stay in local-only; no game data is embedded in this module.
const finite3=v=>Array.isArray(v)&&v.length===3&&v.every(Number.isFinite);
const model=v=>Number(String(v?.row?.[2]||'').split('.')[0]);
const position=v=>v?.row?.slice(3,6);
const healthy=v=>v&&Array.isArray(v.row)&&finite3(position(v))&&Number.isFinite(v.row[9])&&v.row[9]>0;
// Body packets round translation/angles. This server-only margin absorbs the
// observed wire anchor error (8.3mm in the retained actual-encoder probe); the
// native candidate controller keeps its original .4/.5/1m tests unchanged.
const WIRE_ANCHOR_TOLERANCE=.02;
function rotate(local,heading,pitch,roll){
  const [x,y,z]=local,ch=Math.cos(heading),sh=Math.sin(heading),cp=Math.cos(pitch),sp=Math.sin(pitch),cr=Math.cos(roll),sr=Math.sin(roll);
  const rx=cr*x-sr*y,ry=sr*x+cr*y,py=cp*ry-sp*z,pz=sp*ry+cp*z;
  return [ch*rx+sh*pz,py,-sh*rx+ch*pz];
}
function worldAnchor(vehicle,anchor){
  if(!finite3(anchor)||!finite3(position(vehicle))||!vehicle.row.slice(6,9).every(Number.isFinite))return null;
  // Wire rows contain physics BODY origins in GTA axes. Heading/roll already
  // carry the protocol signs; YXZ rotation is Ry(h)*Rx(p)*Rz(r).
  const v=rotate(anchor,...vehicle.row.slice(6,9));
  return [vehicle.row[3]+v[0],vehicle.row[5]+v[1],-vehicle.row[4]+v[2]];
}
function create(catalog={}){
  const models=new Map();
  if(catalog.version===1)for(const row of Object.values(catalog.models||{})){
    if(!Number.isInteger(row?.id)||typeof row.kind!=='string'||!finite3(row.minimum)||!finite3(row.frontAnchor)||
       !Array.isArray(row.targets)||!row.targets.every(Number.isInteger)||
       row.rearAnchor!==null&&!finite3(row.rearAnchor)||row.trailerAnchor!==null&&!finite3(row.trailerAnchor))continue;
    models.set(row.id,row);
  }
  const links=new Map(),cooldown=new Map();let revision=0;
  const occupied=(id,peers)=>[...peers].some(p=>p.ready&&p.state?.vehicle===id&&(p.state.driving===true||p.state.passenger===true));
  function rootOf(id){
    const seen=new Set();let parent=id;
    for(;;){if(seen.has(parent))return null;seen.add(parent);const link=[...links.values()].find(l=>l.trailer===parent);if(!link)return parent;parent=link.parent;}
  }
  function driver(peer,root,vehicles,peers){
    const vehicle=vehicles.get(root);
    return !!(peer.ready&&[...peers].includes(peer)&&peer.player?.health>0&&!peer.player.insideHome&&
      peer.state?.driving===true&&peer.state.vehicle===root&&model({row:[0,0,peer.state.car]})===model(vehicle)&&healthy(vehicle)&&
      (!vehicle.missionOwner||vehicle.missionOwner===peer.player));
  }
  function pruneCooldown(now){for(const [peer,release]of cooldown)if(release.until<=now)cooldown.delete(peer);}
  function removeTree(parent,now){
    const link=links.get(parent);if(!link)return false;
    removeTree(link.trailer,now);links.delete(parent);
    // The source excludes the last released TARGET, rather than preventing
    // this tractor from attaching to every other nearby trailer.
    if(link.kind==='trailer')cooldown.set(link.owner,{id:link.trailer,until:now+2500});
    revision++;pruneCooldown(now);return true;
  }
  function snapshot(){return {revision,links:[...links.values()].map(({parent,trailer,kind})=>({parent,trailer,kind})).sort((a,b)=>a.parent.localeCompare(b.parent))};}
  function request({peer,parent,trailer,kind,vehicles,peers,now=Date.now()}){
    const reject=message=>({accepted:false,message});
    if(!Number.isFinite(now)||typeof parent!=='string'||parent.length>64||
       trailer!==null&&(typeof trailer!=='string'||trailer.length>64))return reject('Invalid coupling request.');
    const root=rootOf(parent);if(root===null||!driver(peer,root,vehicles,peers))return reject('Only the current driver can change this coupling.');
    const source=vehicles.get(parent),definition=models.get(model(source));
    if(!healthy(source)||!definition)return reject('Coupling data is unavailable for this vehicle.');
    const existing=links.get(parent);
    if(trailer===null){if(existing&&existing.owner!==peer)return reject('Coupling belongs to another driver.');removeTree(parent,now);return {accepted:true};}
    kind=kind??(definition.working?.tow?'tow':'trailer');
    if(!['trailer','tow'].includes(kind))return reject('Invalid coupling type.');
    if(existing){return existing.trailer===trailer&&existing.kind===kind&&existing.owner===peer?
      {accepted:true}:reject('Release the existing coupling first.');}
    pruneCooldown(now);if(cooldown.get(peer)?.id===trailer)return reject('Trailer coupling is cooling down.');
    const target=vehicles.get(trailer),targetDefinition=models.get(model(target));
    if(parent===trailer||trailer===root||!healthy(target)||!targetDefinition||occupied(trailer,peers)||
       target.missionOwner&&target.missionOwner!==peer.player)return reject('Target vehicle is unavailable.');
    if([...links.values()].some(l=>l.trailer===trailer)||links.has(trailer))return reject('Target vehicle is already claimed by a coupling.');
    let anchor,targetAnchor;
    if(kind==='tow'){
      if(parent!==root||!definition.working?.tow||definition.working.available===false||targetDefinition.kind!=='car')return reject('This vehicle cannot tow that target.');
      const work=Number.isFinite(source.row[16])?source.row[16]:0;
      if(work!==2500)return reject('Lower the tow bar before attaching.');
      anchor=[0,1-work/5000,1.05-definition.minimum[1]];targetAnchor=targetDefinition.frontAnchor;
    }else{
      if(!finite3(definition.rearAnchor)||!finite3(targetDefinition.trailerAnchor)||!definition.targets.includes(model(target)))return reject('These trailer types cannot be coupled.');
      let count=0,id=root;const seen=new Set();
      while(links.has(id)){
        if(seen.has(id))return reject('Coupling cycle.');
        if(links.get(id).kind!=='trailer')return reject('A towed vehicle cannot pull a trailer chain.');
        seen.add(id);count++;id=links.get(id).trailer;
      }
      if(count>=2||id!==parent)return reject('The trailer chain is full or belongs to another root.');
      anchor=definition.rearAnchor;targetAnchor=targetDefinition.trailerAnchor;
    }
    const a=worldAnchor(source,anchor),b=worldAnchor(target,targetAnchor);
    if(!a||!b||Math.hypot(a[0]-b[0],a[2]-b[2])>(kind==='tow'?.5:.4)+WIRE_ANCHOR_TOLERANCE||Math.abs(a[1]-b[1])>1+WIRE_ANCHOR_TOLERANCE)return reject('Move the attachment points closer together.');
    links.set(parent,{parent,trailer,kind,owner:peer,root});revision++;
    return {accepted:true};
  }
  function prune(vehicles,peers,now=Date.now()){
    let changed=false;
    for(const link of [...links.values()]){
      if(!driver(link.owner,link.root,vehicles,peers)||!healthy(vehicles.get(link.parent))||!healthy(vehicles.get(link.trailer))||occupied(link.trailer,peers))changed=removeTree(link.parent,now)||changed;
    }
    return changed;
  }
  function releasePeer(peer,now=Date.now()){let changed=false;for(const l of [...links.values()])if(l.owner===peer)changed=removeTree(l.parent,now)||changed;cooldown.delete(peer);return changed;}
  function removeVehicle(id,now=Date.now()){let changed=false;for(const l of [...links.values()])if(l.parent===id||l.trailer===id)changed=removeTree(l.parent,now)||changed;for(const [peer,release]of cooldown)if(release.id===id)cooldown.delete(peer);return changed;}
  function canMove(peer,id){const link=[...links.values()].find(l=>l.trailer===id);return !link||link.owner===peer;}
  return {enabled:models.size>0,snapshot,request,prune,releasePeer,removeVehicle,canMove,rootOf};
}
module.exports={create,rotate,worldAnchor};
