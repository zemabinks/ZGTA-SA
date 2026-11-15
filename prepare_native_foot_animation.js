#!/usr/bin/env node
// Execute the archived public animation definitions, writing data locally only.
const fs = require('node:fs');
const path = require('node:path');
const {createHash} = require('node:crypto');
const {archivedModules} = require('./smoke_vehicle_dynamics');

async function main() {
  const load = archivedModules(), global = load.factories[49368].constructor('return globalThis')();
  const Bytes = load.factories[49368].constructor('return Uint8Array')();
  const site = path.join(__dirname,'local-only/site'), game = path.join(site,'game');
  global.fetch = async url => {
    const file = path.join(site,String(url).split('?')[0]);
    if (!fs.existsSync(file)) return {ok:false};
    const bytes = fs.readFileSync(file);
    return {ok:true,json:async()=>JSON.parse(bytes.toString()),arrayBuffer:async()=>{
      const array = new Bytes(bytes.length); array.set(bytes); return array.buffer;
    }};
  };
  global.setTimeout = setTimeout; global.clearTimeout = clearTimeout;
  const api = load(49368), weapons = load(60662), blocks = JSON.parse(fs.readFileSync(path.join(game,'world/anims.json'))).blocks;
  const data = await api.av(), byClip = new Map([...data.clips].map(([name,clip])=>[clip,'ped/'+name]));
  for (const block of Object.keys(blocks)) if (block !== 'ped') {
    for (const [name,clip] of await api.nN(block)) byClip.set(clip,block+'/'+name);
  }
  const named = clip => {
    if (clip == null) return null;
    const name = byClip.get(clip);
    if (!name) throw Error('Original animation definition references an unknown clip '+clip.name);
    return name;
  };
  const definitions = [];
  for (const item of weapons.Mc) {
    const original = await weapons.OP(item.id);
    if (!original) continue;
    const entry = {...original};
    entry.flags = item.flags;
    entry.use = item.use;
    entry.aims = item.aims;
    entry.clips = original.clips ? Object.fromEntries(Object.entries(original.clips).map(([key,clip])=>[key,named(clip)])) : null;
    if (original.swings) entry.swings = original.swings.map(value=>({...value,clip:named(value.clip)}));
    for (const key of ['moving','ground']) if (original[key]) entry[key] = {...original[key],clip:named(original[key].clip)};
    // JSON cannot encode Infinity; a missing breakout means no breakout.
    if (!Number.isFinite(entry.breakout)) delete entry.breakout;
    definitions.push(entry);
  }
  const source = {};
  for (const filename of fs.readdirSync(path.join(site,'_next/static/chunks'))) {
    if (!filename.endsWith('.js')) continue;
    const bytes = fs.readFileSync(path.join(site,'_next/static/chunks',filename)), text = bytes.toString();
    if (text.includes('49368:(') || text.includes('60662:(')) source[filename] = createHash('sha256').update(bytes).digest('hex');
  }
  const output = path.join(game,'native/foot-animation.json');
  fs.mkdirSync(path.dirname(output),{recursive:true});
  fs.writeFileSync(output,JSON.stringify({version:1,weapons:definitions,source})+'\n',{mode:0o600});
  console.log(`Prepared ${definitions.length} exact public weapon animation definitions in ignored local data`);
}
if (require.main === module) main().catch(error=>{console.error(error.stack);process.exitCode=1});
module.exports = {main};
