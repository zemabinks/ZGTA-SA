'use strict';

// Independent server-owned inventory for the locally archived gun shop.
// Prices, packs, slots, capacities and entrances are extracted local game data.
// Access radius, initial unarmed loadout, reload timing and server validation
// are local policies; the publisher's private inventory server is unavailable.
const fs = require('node:fs');
const path = require('node:path');
const CATALOG_FILE = path.join(__dirname, 'local-only', 'selfhost', 'weapon-catalog.json');
const MAX_AMMO = 9999;
const SHOP_RADIUS = 8;
const MAX_PACKS = 20;
const NATIVE_PROJECTILES = new Set([16, 17, 18, 35, 36, 39]);
const NATIVE_AREA_EFFECTS = new Set([37, 41, 42]);

function create(catalog = {}, options = {}) {
  const items = (Array.isArray(catalog.items) ? catalog.items : []).filter(item =>
    Number.isInteger(item.id) && Number.isInteger(item.ammo) && item.ammo > 0 &&
    Number.isSafeInteger(item.price) && item.price >= 0 && typeof item.name === 'string');
  const byID = new Map(items.map(item => [item.id, item]));
  const timings = new Map();
  let timingRows = options.timingDefinitions;
  if (timingRows === undefined) {
    try { timingRows = JSON.parse(fs.readFileSync(path.join(__dirname,'local-only/site/game/native/foot-animation.json'),'utf8')).weapons; }
    catch (error) {
      timingRows=[];
      if (error.code !== 'ENOENT') console.warn('Native weapon timing unavailable; using bounded weapon-stat cadence.');
    }
  }
  for (const row of Array.isArray(timingRows) ? timingRows : []) {
    if (!Number.isInteger(row?.id) || !['gun','stream','launch','throw','melee'].includes(row.use)) continue;
    const loops=[row.loop?.every,row.crouched?.every].filter(n=>Number.isFinite(n)&&n>0&&n<=5);
    if (!loops.length) continue;
    const stream=row.use==='stream'||row.continuous===true;
    const intervalMs=stream&&row.continuous===true ? 20:Math.max(20,Math.min(...loops)*1000/(row.twin===true?2:1));
    // Display catch-up groups fixed-tick events even for a fast ordinary gun.
    // Admit one 15Hz batch plus a phase/jitter token, bounded to five credits.
    // Streams retain their existing five-credit policy. Refill remains the
    // canonical interval; no client timestamp or claimed elapsed time is used.
    const frameCredit=Math.max(2,Math.min(5,Math.ceil((1000/15)/intervalMs)+1));
    timings.set(row.id,{intervalMs,capacity:stream?5:frameCredit,use:row.use,twin:row.twin===true,source:'animation'});
  }
  const rates = new WeakMap();
  const sequences = new WeakMap();
  const armourID = Number.isInteger(catalog.armourID) ? catalog.armourID : 48;
  const shops = (Array.isArray(catalog.shops) ? catalog.shops : []).filter(shop =>
    typeof shop.id === 'string' && typeof shop.name === 'string' &&
    Array.isArray(shop.door) && shop.door.length >= 3 && shop.door.slice(0, 3).every(Number.isFinite));
  const count = (value, maximum = MAX_AMMO) => Number.isFinite(value) ?
    Math.max(0, Math.min(maximum, Math.floor(value))) : 0;
  const capacity = item => Math.max(1, Math.min(MAX_AMMO, count(item.capacity) || 1));
  const reloadMs = item => capacity(item) <= 2 ? 1200 : 1800;
  const intervalMs = item => {
    const timing=timings.get(item?.id ?? 0);if(timing)return timing.intervalMs;
    const loop = item?.stats?.loop;
    return Array.isArray(loop) && loop.length > 1 ?
      Math.max(80, Math.min(5000, (loop[1] - loop[0]) / 30 * 1000)) : 350;
  };
  const cadence = id => timings.get(id) || {intervalMs:intervalMs(byID.get(id)),capacity:2,use:'fallback',twin:false,source:'stats'};

  function bump(inventory) {
    inventory.revision = Math.min(Number.MAX_SAFE_INTEGER, inventory.revision + 1);
  }

  function ensure(player, now = Date.now()) {
    const saved = player.inventory && typeof player.inventory === 'object' ? player.inventory : {};
    const raw = saved.weapons && typeof saved.weapons === 'object' ? saved.weapons : {};
    const weapons = {};
    const slots = new Map();
    for (const [key, rounds] of Object.entries(raw)) {
      const id = Number(key), item = byID.get(id);
      if (!item || id === armourID || !rounds || typeof rounds !== 'object') continue;
      const clip = count(rounds.clip, capacity(item));
      const rest = count(rounds.rest, MAX_AMMO - clip);
      if (Number.isInteger(item.slot) && item.slot >= 0) {
        const previous = slots.get(item.slot);
        if (previous !== undefined) delete weapons[String(previous)];
        slots.set(item.slot, id);
      }
      weapons[String(id)] = {clip, rest};
    }
    let selected = Number.isInteger(saved.selected) && weapons[String(saved.selected)] ? saved.selected : 0;
    const reload = saved.reload && typeof saved.reload === 'object' &&
      saved.reload.weapon === selected && selected !== 0 &&
      Number.isFinite(saved.reload.until) && saved.reload.until > 0 &&
      saved.reload.until <= now + 10000 ? {weapon: selected, until: saved.reload.until} : null;
    const lastShotAt = Number.isFinite(saved.lastShotAt) && saved.lastShotAt <= now &&
      saved.lastShotAt >= now - 10000 ? saved.lastShotAt : 0;
    const revision = count(saved.revision, Number.MAX_SAFE_INTEGER);
    player.inventory = {version: 1, revision, selected, weapons, reload, lastShotAt};
    return player.inventory;
  }

  function tick(player, now = Date.now()) {
    const inventory = ensure(player, now);
    const pending = inventory.reload;
    if (!pending || pending.until > now) return false;
    const item = byID.get(pending.weapon), ammo = inventory.weapons[String(pending.weapon)];
    inventory.reload = null;
    bump(inventory);
    if (!item || !ammo) return true;
    const transfer = Math.min(capacity(item) - ammo.clip, ammo.rest);
    ammo.clip += transfer; ammo.rest -= transfer;
    return true;
  }

  function nearestShop(pos) {
    if (!pos || ![pos.x, pos.y, pos.z].every(Number.isFinite)) return null;
    let best = null;
    for (const shop of shops) {
      for (const [where, point] of [['entrance', shop.door], ['counter', shop.counter]]) {
        if (!Array.isArray(point) || point.length < 3 || !point.every(Number.isFinite)) continue;
        const distance = Math.hypot(pos.x-point[0], pos.y-point[1], pos.z-point[2]);
        if (!best || distance < best.distance)
          best = {id: shop.id, name: shop.name, kind: shop.kind,
            x: shop.door[0], y: shop.door[1], z: shop.door[2], where,
            distance, within: distance <= SHOP_RADIUS};
      }
    }
    return best;
  }

  function quote(item, ammo, packs = 1) {
    const total = ammo ? ammo.clip + ammo.rest : 0;
    let price = 0;
    for (let index = 0; index < packs; index++)
      price += Number.isSafeInteger(item.refill) && (total > 0 || index > 0) ? item.refill : item.price;
    return price;
  }

  function state(player, pos = null, now = Date.now()) {
    tick(player, now);
    const inventory = player.inventory;
    const weapons = [{id: 0, name: 'Fists', slot: 0, clip: 0, rest: 0, capacity: 0,
      fire: 'MELEE', selected: inventory.selected === 0}];
    for (const [key, ammo] of Object.entries(inventory.weapons)) {
      const item = byID.get(Number(key));
      weapons.push({id: item.id, name: item.name, slot: item.slot, ...ammo,
        capacity: capacity(item), fire: item.fire,
        selected: inventory.selected === item.id, reloadMs: reloadMs(item)});
    }
    return {revision: inventory.revision, selected: inventory.selected, weapons,
      reload: inventory.reload ? {weapon: inventory.reload.weapon, until: inventory.reload.until,
        remainingMs: Math.max(0, inventory.reload.until - now)} : null,
      nearestShop: nearestShop(pos),
      catalog: items.map(item => ({id: item.id, name: item.name, ammo: item.ammo,
        price: item.price, refill: item.refill || null,
        nextPrice: quote(item, inventory.weapons[String(item.id)]),
        slot: item.slot, capacity: item.id === armourID ? 0 : capacity(item),
        fire: item.fire, owned: !!inventory.weapons[String(item.id)],
        nativeSupported: item.id === armourID || item.fire === 'INSTANT_HIT' ||
          (item.fire === 'PROJECTILE' && NATIVE_PROJECTILES.has(item.id)) ||
          (item.fire === 'AREA_EFFECT' && NATIVE_AREA_EFFECTS.has(item.id)),
        totalAmmo: item.id === armourID ? count(player.armour, 100) :
          (inventory.weapons[String(item.id)]?.clip || 0) + (inventory.weapons[String(item.id)]?.rest || 0)})),
      shops: shops.map(shop => ({id: shop.id, name: shop.name, x: shop.door[0],
        y: shop.door[1], z: shop.door[2], icon: shop.icon || 'radar_ammugun'}))};
  }

  function action(player, name, input = {}, pos = null, now = Date.now()) {
    if (!['weapon.buy', 'weapon.select', 'weapon.reload'].includes(name))
      throw new Error('Unknown weapon inventory action.');
    tick(player, now);
    const inventory = player.inventory;
    if (player.health !== undefined && player.health <= 0) throw new Error('Respawn before using weapons.');
    let message;
    if (name === 'weapon.select') {
      const id = input.weapon ?? input.id;
      if (!Number.isInteger(id) || (id !== 0 && !inventory.weapons[String(id)]))
        throw new Error('That weapon is not in your inventory.');
      inventory.selected = id; inventory.reload = null;
      message = id === 0 ? 'Fists selected.' : `${byID.get(id).name} selected.`;
    } else if (name === 'weapon.reload') {
      const id = inventory.selected, item = byID.get(id), ammo = inventory.weapons[String(id)];
      if (!item || !ammo) throw new Error('Select a loaded weapon before reloading.');
      if (inventory.reload) throw new Error('That weapon is already reloading.');
      if (ammo.clip >= capacity(item)) throw new Error('The magazine is already full.');
      if (ammo.rest <= 0) throw new Error('There is no reserve ammunition.');
      inventory.reload = {weapon: id, until: now + reloadMs(item)};
      message = `Reloading ${item.name}.`;
    } else {
      if (!items.length) throw new Error('Weapon shop data is unavailable. Run tools/assets/prepare_native_weapons.py on the Mac.');
      const shop = nearestShop(pos);
      if (!shop?.within) throw new Error('Stand within 8 m of an Ammu-Nation entrance or counter.');
      if (!(pos.walking === true || pos.peer?.state?.walking === true))
        throw new Error('Leave your vehicle before buying weapons.');
      const id = input.weapon ?? input.id;
      const item = byID.get(id);
      if (!Number.isInteger(id) || !item) throw new Error('Choose a listed weapon shop item.');
      let packs = input.packs ?? input.quantity ?? 1;
      if (!Number.isInteger(packs) || packs < 1 || packs > MAX_PACKS)
        throw new Error('Choose between 1 and 20 ammunition packs.');
      let cost;
      if (id === armourID) {
        if (packs !== 1) throw new Error('Body armour is bought one vest at a time.');
        if (count(player.armour, 100) >= 100) throw new Error('Body armour is already full.');
        cost = item.price;
      } else {
        const ammo = inventory.weapons[String(id)];
        const total = (ammo?.clip || 0) + (ammo?.rest || 0);
        if (total >= MAX_AMMO) throw new Error('That weapon already has the maximum ammunition.');
        packs = Math.min(packs, Math.ceil((MAX_AMMO-total) / item.ammo));
        cost = quote(item, ammo, packs);
      }
      if (!Number.isSafeInteger(player.cash) || player.cash < cost)
        throw new Error(`You need $${cost} for that purchase.`);
      // Validate every input before spending money or replacing a slot.
      player.cash -= cost;
      if (id === armourID) player.armour = 100;
      else {
        const existing = inventory.weapons[String(id)];
        for (const key of Object.keys(inventory.weapons))
          if (Number(key) !== id && byID.get(Number(key))?.slot === item.slot) delete inventory.weapons[key];
        const total = Math.min(MAX_AMMO, (existing?.clip || 0) + (existing?.rest || 0) + item.ammo*packs);
        const clip = existing?.clip ?? Math.min(capacity(item), total);
        inventory.weapons[String(id)] = {clip, rest: total-clip};
        inventory.selected = id; inventory.reload = null;
      }
      message = `${item.name} bought at ${shop.name} for $${cost}${id === armourID ? '.' : ` (${packs} pack${packs === 1 ? '' : 's'}).`}`;
    }
    bump(inventory);
    return {message, changed: true, inventory: state(player, pos, now)};
  }

  function acceptShot(player, id, now = Date.now(), context = {}) {
    tick(player, now);
    const inventory = player.inventory;
    const reject = reason => ({ok: false, reason});
    if (!Number.isInteger(id) || id !== inventory.selected) return reject('Select that weapon first.');
    if (player.health !== undefined && player.health <= 0) return reject('Respawn before using weapons.');
    if (player.passive === true) return reject('Passive mode prevents weapon use.');
    const item = id === 0 ? null : byID.get(id);
    if (id !== 0 && (!item || !inventory.weapons[String(id)])) return reject('Weapon not owned.');
    if (inventory.reload) return reject('Weapon is reloading.');
    const ammo = inventory.weapons[String(id)];
    if (id !== 0 && ammo.clip <= 0) return reject('Weapon is empty. Reload or buy ammunition.');
    if (!Number.isFinite(now)) return reject('Invalid weapon clock.');
    const sequence=context.sequence;
    if (sequence!==undefined && (!Number.isSafeInteger(sequence)||sequence<0)) return reject('Invalid shot sequence.');
    const timing=cadence(id),interval=timing.intervalMs;
    let rate=rates.get(player);
    if (!rate) {
      // Fresh traffic may already contain grouped animation events. Starting
      // partly empty rejects valid first-cycle fire solely from arrival jitter.
      // A persisted last shot still preserves its elapsed-time cooldown.
      rate={at:now,interval,credit:inventory.lastShotAt ? Math.min(timing.capacity,Math.max(0,now-inventory.lastShotAt)/interval):timing.capacity};
      rates.set(player,rate);
    }
    const scope=context.sequenceScope && typeof context.sequenceScope==='object' ? context.sequenceScope:player;
    if (sequence!==undefined && sequence<=(sequences.get(scope) ?? -1)) return reject('Shot sequence already consumed.');
    // Server-time token credit permits bounded render/network catch-up while
    // retaining the canonical long-term rate. Switching weapons carries time
    // credit across, rather than granting a free shot on every selection.
    rate.credit=Math.min(timing.capacity,(rate.credit*rate.interval+Math.max(0,now-rate.at))/interval);
    rate.at=Math.max(rate.at,now);rate.interval=interval;
    if (rate.credit<1-1e-8) return reject('Weapon fire interval has not elapsed.');
    rate.credit=Math.max(0,rate.credit-1);
    if (sequence!==undefined) sequences.set(scope,sequence);
    inventory.lastShotAt = now;
    if (ammo) ammo.clip--;
    bump(inventory);
    return {ok: true, changed: true, revision: inventory.revision, weapon: id,
      clip: ammo?.clip || 0, rest: ammo?.rest || 0};
  }

  function ordinaryRange(id, presentation=false) {
    const item=byID.get(id),range=item?.stats?.range;
    if(!item||item.fire!=='INSTANT_HIT'||!Number.isFinite(range)||range<=0)return 0;
    // The scoped native ray uses800m plus its camera offset. Retain the
    // existing15m origin allowance. Other damage stays catalog-bounded.
    const damageRange=Math.max(id===34?815:0,Math.min(2000,range));
    // Camera-to-muzzle presentation can extend past the damage distance;
    // accepting its tracer must not grant a longer damaging hit.
    return damageRange+(presentation?32:0);
  }

  // Opt-in ordinary fire uses one inventory emission and a bounded set of
  // target groups. Metadata comes from this server's catalog, never the client.
  function ordinaryGroups(id, values) {
    const item=byID.get(id),stats=item?.stats;
    if (!Number.isInteger(id)||!((id>=22&&id<=34)||id===38)||!item || item.fire!=='INSTANT_HIT' || !Number.isInteger(stats?.pellets) ||
        stats.pellets<1 || stats.pellets>100 || !Number.isFinite(stats.damage) ||
        stats.damage<=0 || stats.damage>1000 || !Number.isFinite(stats.range) || stats.range<=0 ||
        !Array.isArray(values) || values.length<1 || values.length>stats.pellets) return null;
    const point=p=>Array.isArray(p)&&p.length===3&&p.every(v=>Number.isFinite(v)&&Math.abs(v)<=10000);
    const targets=new Set(),groups=[];let pellets=0;
    for (const value of values) {
      if (!value || !point(value.o) || !point(value.h) || !Number.isInteger(value.ht) || value.ht<0 || value.ht>4) return null;
      const n=value.n===undefined?1:value.n;
      if (!Number.isInteger(n)||n<1||(pellets+=n)>stats.pellets ||
          Math.hypot(...value.h.map((v,i)=>v-value.o[i]))>ordinaryRange(id,true)+0.05) return null;
      const group={o:[...value.o],h:[...value.h],ht:value.ht,n};
      if (value.ht>=1&&value.ht<=3) {
        if (typeof value.id!=='string'||!value.id.length||value.id.length>64) return null;
        const key=value.ht+':'+value.id;if(targets.has(key))return null;targets.add(key);group.id=value.id;
      } else if(value.id!==undefined)return null;
      if(value.bp!==undefined){if(value.ht!==1||!Number.isInteger(value.bp)||value.bp<1||value.bp>9)return null;group.bp=value.bp;}
      if(value.wh!==undefined){if(![2,3].includes(value.ht)||!Number.isInteger(value.wh)||value.wh<0||value.wh>3)return null;group.wh=value.wh;}
      groups.push(group);
    }
    return {groups,damage:stats.damage};
  }

  return {ensure, tick, state, action, acceptShot, cadence, nearestShop, quote, ordinaryGroups, ordinaryRange,
    catalog: {items, shops, armourID}, SHOP_RADIUS, MAX_AMMO};
}

// Independent decision rule. Extracted weapon profiles remain owner-local.
// Heading is the browser wire heading; GTA horizontal axes are X/Y.
function createParry(profiles = []) {
  const weapons = new Map((Array.isArray(profiles) ? profiles : []).filter(row =>
    Number.isInteger(row?.id) && row.id >= 0 && row.id <= 15).map(row => [row.id,row]));
  return function parries(weapon, defenderWeapon, state, attacker, defender) {
    if (weapon === 9 || !weapons.has(weapon) || weapons.get(defenderWeapon)?.blocks !== true ||
        state?.walking !== true || !Number.isInteger(state.act) || (state.act & 63) !== 28 ||
        (state.down ?? 0) !== 0 || !Number.isFinite(state.heading) ||
        ![attacker?.x,attacker?.y,defender?.x,defender?.y].every(Number.isFinite)) return false;
    // Preserve the source physics-axis subtraction, including signed zero
    // when attacker and defender occupy exactly the same horizontal point.
    const dz = -attacker.y-(-defender.y);
    const angle = Math.atan2(-(attacker.x-defender.x),-dz)-state.heading;
    const tau = 2*Math.PI, wrapped = ((angle+Math.PI)%tau+tau)%tau-Math.PI;
    return Math.abs(wrapped) < Math.PI/4;
  };
}

let catalog = {};
try { catalog = JSON.parse(fs.readFileSync(CATALOG_FILE, 'utf8')); }
catch (error) { if (error.code !== 'ENOENT') throw error; }
module.exports = Object.assign(create(catalog), {create,createParry});
