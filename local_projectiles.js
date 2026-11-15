'use strict';

// Authoritative local projectile simulation. Motion/fuse/radial damage values
// follow public client cY/kf/kg/kw in the archived 9737 chunk, translated to GTA
// x/east,y/north,z/up. Server origin checks, limits, cadence and blast occlusion
// are local validation policies; publisher server rules are unavailable.
const fs = require('node:fs');
const path = require('node:path');
const ROCKETS = new Set([19, 20, 35, 36]);
const LOBS = new Set([16, 17, 18, 39]);
const RADIUS = {16: 9, 18: 6, 19: 10, 20: 10, 35: 10, 36: 10, 39: 9};
const DAMAGE = {16: 82.5, 18: 16.5, 19: 82.5, 20: 82.5, 35: 82.5, 36: 82.5, 39: 82.5};
const LIFETIME = {16: 2, 17: 20, 18: 6, 19: 5, 20: 5, 35: 5, 36: 5, 39: 120};
const MAX_PROJECTILES = 256;
const MAX_PER_OWNER = 24;
const magnitude = value => Math.hypot(...value);
const valid = value => Array.isArray(value) && value.length === 3 && value.every(Number.isFinite);
const bounded = value => valid(value) && Math.abs(value[0]) <= 6000 && Math.abs(value[1]) <= 6000 && value[2] >= -200 && value[2] <= 2000;
const add = (a, b) => a.map((value, index) => value+b[index]);
const subtract = (a, b) => a.map((value, index) => value-b[index]);
const scale = (a, amount) => a.map(value => value*amount);
const dot = (a, b) => a.reduce((sum, value, index) => sum+value*b[index], 0);
const unit = value => {
  const length = valid(value) ? magnitude(value) : 0;
  return Number.isFinite(length) && length > 0.0001 ? scale(value, 1/length) : null;
};
const ownerID = owner => (typeof owner === 'string' || Number.isSafeInteger(owner)) && String(owner).length > 0 && String(owner).length <= 64 ? String(owner) : null;
const rounded = value => value.map(component => Math.floor(component*100+0.5)/100);

function create(options = {}) {
  const clock = typeof options.clock === 'function' ? options.clock : Date.now;
  const people = typeof options.players === 'function' ? options.players : () => [];
  const trace = typeof options.trace === 'function' ? options.trace : null;
  const ground = typeof options.ground === 'function' ? options.ground : null;
  const onHit = typeof options.onHit === 'function' ? options.onHit : () => {};
  const onEvent = typeof options.onEvent === 'function' ? options.onEvent : () => {};
  const tracksOwners = typeof options.players === 'function';
  const projectiles = new Map(), lastLaunch = new Map();
  let nextID = 1;
  let stats = options.stats || {};
  if (!options.stats) {
    try { stats = JSON.parse(fs.readFileSync(path.join(__dirname, 'local-only', 'site', 'game', 'native', 'weapons.json'), 'utf8')).stats || {}; }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
  }

  function targets() {
    const values = people();
    return (Array.isArray(values) ? values : []).filter(value =>
      value && ownerID(value.id) !== null && bounded(value.position));
  }
  function actor(id) { return targets().find(value => String(value.id) === id); }
  function copy(projectile) {
    return {...projectile, position: [...projectile.position], velocity: [...projectile.velocity]};
  }
  function emit(type, projectile, extra = {}) {
    onEvent({type, ...copy(projectile), ...extra});
  }
  function interval(weapon) {
    const loop = stats[String(weapon)]?.loop;
    return Array.isArray(loop) && loop.length > 1 ? Math.max(80,
      Math.min(5000, (loop[1]-loop[0])/30*1000)) : 350;
  }
  function contact(origin, direction, distance) {
    if (!trace) return null;
    const hit = trace([...origin], [...direction], distance);
    if (typeof options.complete === 'function' && options.complete() === false) return {incomplete: true};
    if (!hit || !Number.isFinite(hit.distance) || hit.distance < 0 || hit.distance > distance) return null;
    return {distance: hit.distance, normal: unit(hit.normal) || scale(direction, -1), targetID: hit.targetID};
  }

  function launch(owner, weapon, origin, direction) {
    const id = ownerID(owner), way = unit(direction);
    const reject = reason => ({ok: false, reason});
    if (id === null) return reject('Invalid projectile owner.');
    if (!Number.isInteger(weapon) || (!ROCKETS.has(weapon) && !LOBS.has(weapon))) return reject('Unsupported projectile weapon.');
    if (!bounded(origin) || !way) return reject('Invalid projectile origin or direction.');
    const source = actor(id);
    if (tracksOwners && !source) return reject('Projectile owner is not in the game.');
    if (source && (source.passive === true || (source.health !== undefined && source.health <= 0))) return reject('Projectile owner cannot attack.');
    if (source && magnitude(subtract(origin, add(source.position, [0, 0, 0.9]))) > 3.5) return reject('Projectile origin is too far from its owner.');
    if (projectiles.size >= MAX_PROJECTILES || [...projectiles.values()].filter(value => value.owner === id).length >= MAX_PER_OWNER)
      return reject('Too many active projectiles.');
    const now = clock(), previous = lastLaunch.get(id);
    if (!Number.isFinite(now) || (previous !== undefined && now-previous < interval(weapon))) return reject('Projectile fire interval has not elapsed.');
    lastLaunch.set(id, now);
    const rocket = ROCKETS.has(weapon);
    let velocity = rocket ? scale(way, 65) : add(scale(way, 17), [0, 0, 4.5]);
    if (weapon === 39) velocity = scale(velocity, 0.6);
    const projectile = {id: `projectile-${nextID++}`, owner: id, weapon,
      position: [...origin], velocity, age: 0, lifetime: LIFETIME[weapon],
      rocket, stuck: false, lying: false, dimension: source?.dimension ?? null};
    projectiles.set(projectile.id, projectile);
    emit('launch', projectile);
    return {ok: true, id: projectile.id, projectile: copy(projectile)};
  }

  function explode(projectile) {
    // Only an already tracked projectile can reach this private function.
    const position = rounded(projectile.position), radius = RADIUS[projectile.weapon] || 0;
    const maximumDamage = DAMAGE[projectile.weapon] || 0;
    const event = {type: 'blast', id: projectile.id, owner: projectile.owner,
      weapon: projectile.weapon, position, radius, maximumDamage,
      dimension: projectile.dimension};
    onEvent({...event, position: [...position]});
    if (!radius) return;
    for (const target of targets()) {
      if (target.passive === true || (target.health !== undefined && target.health <= 0) ||
          (target.dimension ?? null) !== projectile.dimension) continue;
      const centre = add(target.position, [0, 0, 0.9]);
      const offset = subtract(centre, position), distance = magnitude(offset);
      if (distance >= radius) continue;
      if (trace && options.blastOcclusion !== false && distance > 0.1) {
        const way = unit(offset);
        const obstruction = contact(add(position, scale(way, 0.05)), way, Math.max(0, distance-0.1));
        if (obstruction?.incomplete || (obstruction && String(obstruction.targetID) !== String(target.id))) continue;
      }
      const damage = maximumDamage*(1-distance/radius);
      if (damage > 0) onHit(target, damage, {...event, position: [...position]});
    }
  }

  function detonate(owner) {
    const id = ownerID(owner);
    if (id === null) return 0;
    const source = actor(id);
    if (tracksOwners && (!source || source.passive === true || (source.health !== undefined && source.health <= 0))) return 0;
    let detonated = 0;
    for (const projectile of [...projectiles.values()]) {
      if (projectile.owner !== id || projectile.weapon !== 39) continue;
      projectiles.delete(projectile.id);
      explode(projectile); detonated++;
    }
    return detonated;
  }

  function step(delta) {
    for (const projectile of [...projectiles.values()]) {
      if (!projectiles.has(projectile.id)) continue;
      projectile.age += delta;
      if (projectile.age >= projectile.lifetime) {
        projectiles.delete(projectile.id);
        if (projectile.weapon !== 17 && projectile.weapon !== 39) explode(projectile);
        else emit('expire', projectile);
        continue;
      }
      if (projectile.stuck || projectile.lying) continue;
      if (!projectile.rocket) projectile.velocity[2] -= 18*delta;
      const speed = magnitude(projectile.velocity);
      if (speed < 0.0001) continue;
      const way = scale(projectile.velocity, 1/speed), distance = speed*delta;
      let hit = contact(projectile.position, way, distance+0.05);
      if (hit?.incomplete) {
        projectiles.delete(projectile.id); emit('expire', projectile, {reason: 'collision data unavailable'}); continue;
      }
      const next = add(projectile.position, scale(way, distance));
      if (ground && way[2] < 0) {
        const height = ground(next[0], next[1], projectile.position[2]+0.1);
        if (typeof options.complete === 'function' && options.complete() === false) {
          projectiles.delete(projectile.id); emit('expire', projectile, {reason: 'collision data unavailable'}); continue;
        }
        if (Number.isFinite(height) && height <= projectile.position[2]+0.1 && next[2] <= height) {
          const along = Math.max(0, (height-projectile.position[2])/way[2]);
          if (along <= distance+0.05 && (!hit || along < hit.distance))
            hit = {distance: along, normal: [0, 0, 1]};
        }
      }
      if (projectile.rocket || projectile.weapon === 18) {
        const radius = projectile.rocket ? 0.96 : 0.5;
        for (const target of targets()) {
          if (String(target.id) === projectile.owner || (target.dimension ?? null) !== projectile.dimension ||
              target.health !== undefined && target.health <= 0) continue;
          const offset = subtract(add(target.position, [0, 0, 0.9]), projectile.position);
          const along = Math.max(0, Math.min(distance, dot(offset, way)));
          if (magnitude(subtract(scale(way, along), offset)) < radius && (!hit || along < hit.distance))
            hit = {distance: along, normal: scale(way, -1), targetID: target.id};
        }
      }
      if (hit) {
        const backoff = projectile.rocket ? 0.1 : 0.05;
        projectile.position = add(projectile.position, scale(way, Math.max(0, hit.distance-backoff)));
        if (projectile.rocket || projectile.weapon === 18) {
          projectiles.delete(projectile.id); explode(projectile); continue;
        }
        if (projectile.weapon === 39) {
          projectile.stuck = true; projectile.velocity = [0, 0, 0]; emit('stick', projectile); continue;
        }
        const normal = hit.normal;
        projectile.velocity = scale(subtract(projectile.velocity,
          scale(normal, 2*dot(projectile.velocity, normal))), 0.35);
        if (magnitude(projectile.velocity) < 1.2 && normal[2] > 0.6 && hit.targetID === undefined) {
          projectile.lying = true; projectile.velocity = [0, 0, 0];
        }
        emit('bounce', projectile);
      } else projectile.position = next;
      if (!bounded(projectile.position)) {
        projectiles.delete(projectile.id); emit('expire', projectile, {reason: 'world bounds'});
      }
    }
  }

  function tick(delta) {
    if (!Number.isFinite(delta) || delta <= 0 || delta > 1)
      return {ok: false, reason: 'Projectile tick must be finite, positive, and no greater than one second.'};
    // A bounded fixed substep prevents tunnelling and stabilizes bounces when
    // the host timer has a slow frame. Never trust a client-supplied delta.
    const steps = Math.ceil(delta/(1/60)), slice = delta/steps;
    for (let index = 0; index < steps; index++) step(slice);
    return {ok: true, active: projectiles.size};
  }

  function snapshot() { return [...projectiles.values()].map(copy); }
  function clear(owner = null) {
    const id = owner === null ? null : ownerID(owner);
    if (owner !== null && id === null) return;
    for (const [key, projectile] of projectiles) if (id === null || projectile.owner === id) projectiles.delete(key);
    if (id === null) lastLaunch.clear(); else lastLaunch.delete(id);
  }
  return {launch, tick, detonate, snapshot, state: snapshot, clear,
    get size() { return projectiles.size; }};
}
module.exports = {create};
