#!/usr/bin/env node
// Isolated group membership, invitations, privacy, and disconnect check.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'zgta-parties-'));
try {
  fs.mkdirSync(path.join(temporary, 'local-only', 'selfhost'), {recursive: true});
  for (const file of ['selfhost_backend.js', 'optional_discord.js'])
    fs.copyFileSync(path.join(__dirname, file), path.join(temporary, file));
  const game = require(path.join(temporary, 'selfhost_backend.js'));
  const make = () => {
    const {player} = game.ensurePlayer({headers: {cookie: ''}}, {setHeader() {}});
    const sent = [];
    const peer = {player, ready: true, lastSeen: Date.now(),
      state: {walking: true, x: 1480, y: -1738, z: 13},
      send: message => sent.push(message)};
    game.peers.add(peer);
    return {player, peer, sent};
  };
  const [a, b, c, d, e] = Array.from({length: 5}, make);
  game.action(a.player, 'party.create', {});
  const party = game.partyOf(a.player);
  assert(party && party.leader === a.player);
  for (const member of [b, c, d]) {
    a.player.lastPartyInvite = 0;
    game.action(a.player, 'party.invite', {number: member.player.number});
    assert.equal(game.partyInvites.get(member.player).partyId, party.id);
    game.action(member.player, 'party.accept', {});
  }
  assert.equal(party.members.size, 4);
  a.player.lastPartyInvite = 0;
  assert.throws(() => game.action(a.player, 'party.invite',
    {number: e.player.number}), /full/);
  assert.throws(() => game.action(b.player, 'party.kick',
    {number: c.player.number}), /leader/);
  game.action(a.player, 'party.kick', {number: b.player.number});
  assert.equal(game.partyOf(b.player), null);
  game.action(c.player, 'party.chat', {text: 'team only'});
  assert(a.sent.some(packet => packet.t === 'note' && packet.text.includes('team only')));
  assert(d.sent.some(packet => packet.t === 'note' && packet.text.includes('team only')));
  assert(!b.sent.some(packet => packet.t === 'note' && packet.text.includes('team only')));
  assert(!e.sent.some(packet => packet.t === 'note' && packet.text.includes('team only')));
  game.action(a.player, 'party.leave', {});
  assert.equal(party.leader, c.player);
  c.player.lastPartyInvite = 0;
  game.action(c.player, 'party.invite', {number: e.player.number});
  game.partyInvites.get(e.player).expires = Date.now() - 1;
  assert.throws(() => game.action(e.player, 'party.accept', {}), /No active/);
  game.remove(c.peer);
  assert.equal(party.leader, d.player);
  game.remove(d.peer);
  assert.equal(game.parties.has(party.id), false);
  clearInterval(game.tick);
  console.log('PASS: group invites, capacity, leader controls, private chat, expiry, disconnect cleanup');
} finally {
  fs.rmSync(temporary, {recursive: true, force: true});
}
