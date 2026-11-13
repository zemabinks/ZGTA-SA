#!/usr/bin/env node
// Exercise the browser HUD and automatic checkpoint requests without game assets.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname, 'local_gameplay.js'), 'utf8');
const base = {connected: true, name: 'Route tester', cash: 0, xp: 0,
  position: {x: 0, y: 0}, onFoot: false, driving: true,
  drivingVehicle: 'loaner-1', race: null, job: null, turfs: [],
  exploration: {tracked: null}};

async function run(firstState, nextState = firstState) {
  const elements = new Map();
  const actions = [];
  let state = firstState;
  class FakeElement {
    constructor(tag) {this.tagName = tag; this.style = {}; this.dataset = {};
      this.children = []; this.hidden = false; this.isConnected = true;}
    append(...children) {this.children.push(...children);}
    addEventListener() {}
    setAttribute() {}
  }
  const document = {getElementById: id => elements.get(id) || null,
    createElement: tag => {
      const item = new FakeElement(tag);
      Object.defineProperty(item, 'id', {set(value) {this._id = value; elements.set(value, this);},
        get() {return this._id;}});
      return item;
    },
    head: {append() {}}, body: {append() {}}, documentElement: {},
    exitPointerLock() {}};
  const context = {document, window: {addEventListener() {}},
    MutationObserver: class {observe() {}},
    setInterval() {},
    fetch: async (url, options) => {
      if (url === '/api/local/state') return {ok: true, json: async () => state};
      assert.equal(url, '/api/local/action');
      const action = JSON.parse(options.body).action;
      actions.push(action);
      state = nextState;
      return {ok: true, json: async () => ({state, message: 'Checkpoint passed.'})};
    }};
  vm.runInNewContext(source, context, {filename: 'local_gameplay.js'});
  await new Promise(resolve => setImmediate(resolve));
  await new Promise(resolve => setImmediate(resolve));
  return {actions, waypoint: elements.get('zgta-waypoint'),
    label: elements.get('zgta-waypoint-label')};
}

(async () => {
  const pizza = {id: 'pizza', mode: 'checkpoints', started: 1234, index: 1,
    total: 3, remaining: 8, radius: 12, secondsLeft: 100,
    vehicleId: 'loaner-1', target: {x: 8, y: 0, name: 'First delivery'}};
  const second = {...pizza, index: 2, remaining: 90,
    target: {x: 90, y: 0, name: 'Second delivery'}};
  const success = await run({...base, job: pizza}, {...base, job: second});
  assert.deepEqual(success.actions, ['job.checkpoint']);
  assert.equal(success.waypoint.hidden, false);
  assert.match(success.label.textContent, /Second delivery · 90 m E/);
  assert.deepEqual((await run({...base, drivingVehicle: 'another-car', job: pizza})).actions, []);
  assert.deepEqual((await run({...base, onFoot: true, driving: false, job: pizza})).actions, []);
  assert.deepEqual((await run({...base, job: {...pizza, remaining: 50}})).actions, []);
  const race = {stage: 'running', joined: true, started: 4321, index: 3, total: 3,
    remaining: 8, radius: 12, secondsLeft: 100,
    target: {x: 8, y: 0, name: 'Finish line'}};
  assert.deepEqual((await run({...base, race}, {...base, race: null})).actions,
    ['race.finish']);
  console.log('PASS: route HUD and automatic checkpoint, vehicle, distance and race gates');
})().catch(error => {console.error(error); process.exitCode = 1;});
