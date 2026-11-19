#!/usr/bin/env node
'use strict';
const assert = require('node:assert/strict');
const {create} = require('../../local_projectiles');
const close = (a, b, epsilon = 1e-6) => assert(Math.abs(a-b) <= epsilon, `${a} differs from ${b}`);
let now = 100000;
let people = [{id: 'owner', position: [0, 0, 0], health: 100},
  {id: 'near', position: [0, 0, 0], health: 100},
  {id: 'far', position: [100, 0, 0], health: 100}];
let events = [], hits = [];
const world = create({clock: () => now, players: () => people, ground: () => 0,
  onEvent: event => events.push(event), onHit: (target, damage, event) => hits.push({target: target.id, damage, event})});
for (const [owner, weapon, origin, direction] of [
  ['missing', 16, [0, 0, 1], [1, 0, 0]],
  ['owner', 22, [0, 0, 1], [1, 0, 0]],
  ['owner', 16, [1000, 0, 1], [1, 0, 0]],
  ['owner', 16, [NaN, 0, 1], [1, 0, 0]],
  ['owner', 16, [0, 0, 1], [0, 0, 0]],
  ['owner', 16, [0, 0, 1], [Infinity, 0, 0]],
  ['owner', 16, [0, 0, 1], [Number.MAX_VALUE, Number.MAX_VALUE, Number.MAX_VALUE]],
]) assert.equal(world.launch(owner, weapon, origin, direction).ok, false);
assert.equal(events.length, 0, 'invalid requests cannot create events');
const grenade = world.launch('owner', 16, [0, 0, 1], [5, 0, 0]);
assert.equal(grenade.ok, true);
assert.deepEqual(grenade.projectile.velocity, [17, 0, 4.5]);
assert.equal(world.launch('owner', 16, [0, 0, 1], [1, 0, 0]).ok, false, 'cadence rejects repeated launch');
assert.equal(world.tick(Infinity).ok, false);
assert.equal(world.tick(-1).ok, false);
assert.equal(world.tick(5).ok, false);
world.tick(0.1);
let state = world.snapshot()[0];
close(state.position[0], 1.7);
close(state.velocity[2], 2.7);
state.position[0] = 999;
assert(world.snapshot()[0].position[0] < 2, 'snapshots cannot mutate authoritative position');
for (let index = 0; index < 17; index++) world.tick(0.1);
assert(!events.some(event => event.type === 'blast'), 'grenade cannot explode before its fuse');
const trajectory = world.snapshot()[0].position;
people[1].position = [trajectory[0], trajectory[1], 0];
for (let index = 0; index < 3; index++) world.tick(0.1);
assert.equal(world.size, 0);
const explosion = events.find(event => event.type === 'blast');
assert(explosion);
assert.equal(explosion.weapon, 16);
assert.equal(explosion.radius, 9);
assert.equal(explosion.maximumDamage, 82.5);
assert(hits.some(hit => hit.target === 'near'));
assert(!hits.some(hit => hit.target === 'far'));
for (const hit of hits) {
  const target = people.find(target => target.id === hit.target);
  const centre = target.position.map((value, index) => value+(index === 2 ? 0.9 : 0));
  const distance = Math.hypot(...centre.map((value, index) => value-explosion.position[index]));
  close(hit.damage, 82.5*(1-distance/9));
}
assert(events.some(event => event.type === 'bounce'), 'ground hook produces bounces');
const hitCount = hits.length;
world.tick(1); world.detonate('owner');
assert.equal(hits.length, hitCount, 'expired projectiles cannot deal damage twice');

// Satchels stick to geometry; only their authenticated owner can detonate them.
let satchelEvents = [], satchelHits = [];
people = [{id: 'a', position: [0, 0, 0], health: 100},
  {id: 'b', position: [3, 0, 0], health: 100},
  {id: 'c', position: [3, 0, 0], health: 100, dimension: 'private-home'},
  {id: 'safe', position: [3, 0, 0], health: 100, passive: true}];
const satchels = create({clock: () => now, players: () => people,
  trace: (origin, direction, length) => {
    if (direction[0] > 0 && origin[0] < 2 && (2-origin[0])/direction[0] <= length)
      return {distance: (2-origin[0])/direction[0], normal: [-1, 0, 0]};
    return null;
  }, onEvent: event => satchelEvents.push(event), onHit: (target, damage) => satchelHits.push({id: target.id, damage})});
assert.equal(satchels.launch('a', 39, [0, 0, 1], [1, 0, 0]).ok, true);
for (let index = 0; index < 5; index++) satchels.tick(0.1);
assert.equal(satchels.snapshot()[0].stuck, true);
assert.equal(satchels.detonate('b'), 0);
assert.equal(satchels.size, 1);
assert.equal(satchels.detonate('a'), 1);
assert.equal(satchels.size, 0);
assert.equal(satchels.detonate('a'), 0);
assert(satchelHits.some(hit => hit.id === 'a'), 'self damage remains possible');
assert(!satchelHits.some(hit => hit.id === 'b'), 'a solid wall occludes the local server blast');
assert(!satchelHits.some(hit => hit.id === 'c'), 'other dimensions cannot receive a blast');
assert(!satchelHits.some(hit => hit.id === 'safe'), 'passive players cannot receive a blast');
assert.equal(satchelEvents.filter(event => event.type === 'blast').length, 1);

// Rockets impact real geometry or another player; a client cannot supply a
// claimed victim/damage amount or invoke an untracked arbitrary explosion.
let rocketEvents = [], rocketHits = [];
people = [{id: 'a', position: [0, 0, 0], health: 100},
  {id: 'victim', position: [4, 0, 0], health: 100}];
const rockets = create({clock: () => now, players: () => people,
  onEvent: event => rocketEvents.push(event), onHit: (target, damage) => rocketHits.push({id: target.id, damage})});
assert.equal(rockets.explode, undefined);
assert.equal(rockets.launch('a', 35, [0, 0, 0.9], [1, 0, 0]).ok, true);
close(Math.hypot(...rockets.snapshot()[0].velocity), 65);
rockets.tick(0.1);
assert.equal(rockets.size, 0);
assert.equal(rocketEvents.find(event => event.type === 'blast').radius, 10);
assert(rocketHits.some(hit => hit.id === 'victim' && hit.damage > 0));

// Satchel timeouts are quiet, and active counts are bounded per owner.
let expired = [];
const limits = create({clock: () => now, onEvent: event => expired.push(event), stats: {39: {loop: [0, 1]}}});
for (let index = 0; index < 24; index++) {
  assert.equal(limits.launch('a', 39, [0, 0, 1], [1, 0, 0]).ok, true); now += 100;
}
assert.equal(limits.launch('a', 39, [0, 0, 1], [1, 0, 0]).ok, false);
// Keep them in bounds with a floor rather than letting them fall out of world.
const expiry = create({clock: () => now, ground: () => 0, onEvent: event => expired.push(event)});
assert.equal(expiry.launch('a', 39, [0, 0, 1], [1, 0, 0]).ok, true);
for (let index = 0; index < 121; index++) expiry.tick(1);
assert.equal(expiry.size, 0);
assert(!expired.some(event => event.type === 'blast'));
assert(expired.some(event => event.type === 'expire'));
let unavailableHits = [], unavailableEvents = [];
const unavailable = create({clock: () => now, players: () => people,
  trace: () => null, complete: () => false,
  onHit: (target, damage) => unavailableHits.push({target, damage}),
  onEvent: event => unavailableEvents.push(event)});
assert.equal(unavailable.launch('a', 35, [0, 0, 0.9], [1, 0, 0]).ok, true);
unavailable.tick(0.1);
assert.equal(unavailable.size, 0, 'a missing collision cell cannot be treated as a clear trajectory');
assert.equal(unavailableHits.length, 0);
assert(!unavailableEvents.some(event => event.type === 'blast'));
assert(unavailableEvents.some(event => event.type === 'expire' && event.reason === 'collision data unavailable'));
limits.clear('a'); assert.equal(limits.size, 0);
console.log('PASS: authoritative projectile origins, cadence, gravity, fuse, bounce, satchel ownership, blast falloff, walls, dimensions, rockets, expiry and limits');
