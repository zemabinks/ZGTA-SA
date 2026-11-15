#!/usr/bin/env node
'use strict';
// Server ownership, economy validation, real shop coordinates and restart checks.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {create} = require('./weapon_inventory');
const catalog = JSON.parse(fs.readFileSync(path.join(__dirname,
  'local-only', 'selfhost', 'weapon-catalog.json'), 'utf8'));
const store = create(catalog);
assert.equal(catalog.items.length, 16);
assert.equal(catalog.shops.length, 11);
const shop = catalog.shops.find(item => item.id === 'ammu-nation-market');
assert.deepEqual(shop.door, [1368.35, -1279.06, 12.55]);
const near = {x: shop.door[0], y: shop.door[1], z: shop.door[2], walking: true};
const far = {...near, x: near.x+100};
let now = 1_700_000_000_000;
const player = {cash: 2000000, health: 100, armour: 0};
assert.equal(store.state(player, near, now).selected, 0);
assert.equal(player.inventory.revision, 0, 'fresh inventories start at revision zero');
assert.throws(() => store.action(player, 'weapon.select', {weapon: 22}, near, now), /not in your inventory/);
const before = player.cash;
for (const point of [far, {...near, z: 1000}, {...near, walking: false}])
  assert.throws(() => store.action(player, 'weapon.buy', {weapon: 22}, point, now), /within 8 m|Leave your vehicle/);
assert.equal(player.cash, before);
for (const bad of [{weapon: '22'}, {weapon: 999}, {weapon: 22, packs: 0},
  {weapon: 22, packs: 21}, {weapon: 22, packs: 1.5}])
  assert.throws(() => store.action(player, 'weapon.buy', bad, near, now));
assert.equal(player.cash, before);
const poor = {cash: 999, health: 100};
assert.throws(() => store.action(poor, 'weapon.buy', {weapon: 22}, near, now), /need \$1000/);
assert.equal(poor.cash, 999);
store.action(player, 'weapon.buy', {weapon: 22}, near, now);
assert.equal(player.cash, before-1000);
assert.deepEqual(player.inventory.weapons['22'], {clip: 17, rest: 43});
assert.equal(player.inventory.selected, 22);
assert.equal(player.inventory.revision, 1, 'successful purchase increments the revision');
assert.equal(store.acceptShot(player, 24, now).ok, false);
assert.equal(player.inventory.revision, 1, 'rejected shot must not change revision');
assert.equal(player.inventory.weapons['22'].clip, 17);
assert.equal(store.acceptShot(player, 22, now).ok, true);
assert.equal(player.inventory.revision, 2, 'accepted shot increments revision');
assert.equal(store.acceptShot(player, 22, now+10).ok, true, 'Fresh two-event transport credit was unavailable');
assert.equal(player.inventory.weapons['22'].clip, 15);
assert.equal(player.inventory.revision, 3);
assert.equal(store.acceptShot(player, 22, now+10).ok, false, 'Transport burst exceeded two events');
assert.equal(player.inventory.revision, 3, 'fire interval rejection leaves revision unchanged');
const gap = Math.max(80, (catalog.items.find(item => item.id === 22).stats.loop[1] -
  catalog.items.find(item => item.id === 22).stats.loop[0])/30*1000);
for (let index = 0; index < 15; index++) {
  now += gap+1;
  assert.equal(store.acceptShot(player, 22, now).ok, true);
}
now += gap+1;
assert.equal(store.acceptShot(player, 22, now).ok, false);
const beforeReload = player.inventory.revision;
store.action(player, 'weapon.reload', {}, near, now);
assert.equal(player.inventory.revision, beforeReload+1, 'starting reload increments revision');
const finish = player.inventory.reload.until;
assert.equal(store.acceptShot(player, 22, now+100).ok, false);
assert.equal(store.tick(player, finish-1), false);
assert.equal(player.inventory.weapons['22'].clip, 0);
const restored = JSON.parse(JSON.stringify(player));
const restarted = create(catalog);
assert.equal(restarted.tick(restored, finish+1), true);
assert.deepEqual(restored.inventory.weapons['22'], {clip: 17, rest: 26});
assert.equal(restored.inventory.reload, null);
assert.equal(restored.inventory.revision, player.inventory.revision+1, 'reload completion increments persisted revision');
const stableRevision = restored.inventory.revision;
restarted.state(restored, near, finish+2);
assert.equal(restored.inventory.revision, stableRevision, 'reading settled inventory does not increment revision');
store.action(player, 'weapon.select', {weapon: 0}, near, finish+2);
assert.equal(player.inventory.reload, null);
assert.equal(store.acceptShot(player, 22, finish+3).ok, false);
now = finish+1000;
store.action(player, 'weapon.buy', {weapon: 23}, near, now);
assert.equal(player.inventory.weapons['22'], undefined, 'pistols share one archived slot');
assert.equal(player.inventory.selected, 23);
const sawnoff = catalog.items.find(item => item.id === 26);
const cashBefore = player.cash;
store.action(player, 'weapon.buy', {weapon: 26, packs: 2}, near, now);
assert.equal(cashBefore-player.cash, sawnoff.price+sawnoff.refill);
assert.equal(player.inventory.weapons['26'].clip+player.inventory.weapons['26'].rest, sawnoff.ammo*2);
const nextCash = player.cash;
store.action(player, 'weapon.buy', {weapon: 26}, near, now);
assert.equal(nextCash-player.cash, sawnoff.refill);
store.action(player, 'weapon.buy', {weapon: 48}, near, now);
assert.equal(player.armour, 100);
assert.throws(() => store.action(player, 'weapon.buy', {weapon: 48}, near, now), /already full/);
player.passive = true;
assert.equal(store.acceptShot(player, 26, now+10000).ok, false);
player.passive = false; player.health = 0;
assert.equal(store.acceptShot(player, 26, now+10000).ok, false);
assert.throws(() => store.action(player, 'weapon.buy', {weapon: 22}, near, now), /Respawn/);
const corrupted = {cash: 2000, inventory: {selected: 22,
  weapons: {'22': {clip: 1e9, rest: 1e9}, '999': {clip: 10, rest: 10}},
  reload: {weapon: 22, until: now+1e10}, lastShotAt: now+1e10}};
const sanitized = store.ensure(corrupted, now);
assert.equal(sanitized.weapons['22'].clip, 17);
assert.equal(sanitized.weapons['22'].clip+sanitized.weapons['22'].rest, 9999);
assert.equal(sanitized.weapons['999'], undefined);
assert.equal(sanitized.reload, null);
assert.equal(sanitized.lastShotAt, 0);
const capped = {cash: 1000, health: 100, inventory: {selected: 22,
  weapons: {'22': {clip: 17, rest: 9981}}}};
store.action(capped, 'weapon.buy', {weapon: 22, packs: 20}, near, now);
assert.equal(capped.cash, 0, 'only one pack can be charged near the ammunition cap');
assert.equal(capped.inventory.weapons['22'].clip+capped.inventory.weapons['22'].rest, 9999);
assert.throws(() => store.action(capped, 'weapon.buy', {weapon: 22}, near, now), /maximum ammunition/);
assert.equal(capped.cash, 0);
const finalRound = {cash: 2000, health: 100, inventory: {revision: 8, selected: 22,
  weapons: {'22': {clip: 1, rest: 0}}}};
assert.equal(store.acceptShot(finalRound, 22, now).ok, true);
const emptyState = store.state(finalRound, near, now);
assert.equal(emptyState.selected, 22, 'firing the final round must not unequip the weapon');
assert.equal(emptyState.weapons.find(item => item.id === 22).clip, 0);
assert.equal(emptyState.weapons.find(item => item.id === 22).rest, 0);
assert.equal(emptyState.catalog.find(item => item.id === 22).owned, true);
assert.equal(emptyState.revision, 9);
assert.equal(store.acceptShot(finalRound, 22, now+10000).ok, false);
assert.equal(finalRound.inventory.revision, 9, 'empty weapon rejection must not change the revision');
assert.equal(JSON.parse(JSON.stringify(finalRound)).inventory.weapons['22'].clip, 0);
store.action(finalRound, 'weapon.buy', {weapon: 22}, near, now+10001);
assert.equal(finalRound.inventory.selected, 22);
assert.equal(finalRound.inventory.weapons['22'].rest, 60, 'buying ammunition for an empty magazine preserves the magazine until reload');
const state = store.state(restored, near, now);
assert.equal(state.nearestShop.within, true);
assert(state.shops.some(item => item.id === shop.id));
assert.equal(state.catalog.find(item => item.id === 22).nativeSupported, true);
assert.equal(state.catalog.find(item => item.id === 16).nativeSupported, true);
assert.equal(state.catalog.find(item => item.id === 39).nativeSupported, true);
assert.equal(state.revision, restored.inventory.revision);
assert.equal(JSON.parse(JSON.stringify(restored)).inventory.revision, state.revision);
console.log('PASS: archived gun shops, purchase/refill prices, slot replacement, owned ammo, fire cadence, reload, armour, restart and invalid-request rejection');
