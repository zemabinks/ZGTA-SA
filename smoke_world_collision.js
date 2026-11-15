#!/usr/bin/env node
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {WorldCollision, CollisionCell} = require('./world_collision');

function mesh(triangles, surfaces = null, materials = null) {
  const vertices = triangles.flat(), count = triangles.length, padded = Math.ceil(count / 4) * 4;
  const header = Buffer.alloc(16 + vertices.length * 12 + count * 12 + (surfaces ? padded : 0) + (materials ? padded : 0));
  header.writeUInt32LE(0x324c4353); header.writeUInt32LE(vertices.length, 4); header.writeUInt32LE(count, 8);
  header.writeUInt32LE(materials ? 1 : 0, 12);
  vertices.forEach((point, n) => point.forEach((value, axis) => header.writeFloatLE(value, 16 + n * 12 + axis * 4)));
  for (let n = 0; n < count * 3; n++) header.writeUInt32LE(n, 16 + vertices.length * 12 + n * 4);
  if (surfaces) Buffer.from(surfaces).copy(header, 16 + vertices.length * 12 + count * 12);
  if (materials) Buffer.from(materials).copy(header, 16 + vertices.length * 12 + count * 12 + padded);
  return header;
}
function close(actual, expected, tolerance = 0.00001) { assert(Math.abs(actual - expected) <= tolerance, `${actual} != ${expected}`); }

// Triangle winding, slope/height, very large terrain, surface/material bytes,
// and malformed archives are checked without relying on a live server.
const large = new CollisionCell(mesh([[[0, 0, 0], [900, 0, 0], [0, 900, 0]]], [3], [19]));
assert.equal(large.large.length, 1, 'oversized terrain must remain queryable');
close(large.height(200, 200, 1, 2), 0);
const hit = large.intersect(0, [200, 200, 10], [0, 0, -1], 20);
close(hit.distance, 10); assert.deepEqual(hit.normal, [0, 0, 1]);
assert.equal(hit.surface, 3); assert.equal(hit.material, 19);
assert.equal(large.intersect(0, [1000, 1000, 10], [0, 0, -1], 20), null);
assert.throws(() => new CollisionCell(Buffer.alloc(16)), /header/);
assert.equal(new CollisionCell(mesh([])).height(0, 0, 1, 2), null, 'a valid empty archive member is complete empty geometry');
assert.throws(() => new CollisionCell(mesh([[[0, 0, 0], [1, 0, 0], [0, 1, 0]]]).subarray(0, 20)), /Truncated/);
const corrupt = mesh([[[0, 0, 0], [1, 0, 0], [0, 1, 0]]]); corrupt.writeUInt32LE(999, 52);
assert.throws(() => new CollisionCell(corrupt), /index/);

const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'zgta-world-col-'));
try {
  const index = {detail: {size: 375, grid: 8, origin: 0,
    cells: Array.from({length: 8}, (_, cell) => ({cell}))}, inside: {cells: [{cell: 1}]}};
  fs.writeFileSync(path.join(temporary, 'index.json'), JSON.stringify(index));
  const floor = cell => [[[cell * 375, 0, 0], [(cell + 1) * 375, 0, 0], [cell * 375, 375, 0]],
    [[(cell + 1) * 375, 0, 0], [(cell + 1) * 375, 375, 0], [cell * 375, 375, 0]]];
  for (let n = 0; n < 8; n++) {
    const triangles = floor(n);
    if (n === 1) triangles.push([[376, 0, 0], [376, 100, 0], [376, 0, 100]]);
    fs.writeFileSync(path.join(temporary, `c${n}.col.bin`), mesh(triangles));
  }
  fs.writeFileSync(path.join(temporary, 'i1.col.bin'), mesh([[[375, 0, 800], [750, 0, 800], [375, 375, 800]]]));
  const world = new WorldCollision({root: temporary, cacheSize: 6});
  const across = world.trace([370, 20, 10], [1, 0, 0], 20);
  close(across.distance, 6); assert.deepEqual(across.normal, [-1, 0, 0]);
  assert.equal(world.lineOfSight([370, 20, 10], [390, 20, 10]), false, 'wall in next375m cell blocks');
  assert.equal(world.lineOfSight([370, 200, 10], [390, 200, 10]), true, 'empty cross-cell ray is clear');
  close(world.height(400, 20, 801, 2), 800, 0.0001);
  close(world.trace([400, 20, 810], [0, 0, -1], 20).distance, 10);
  assert.equal(world.completeAt([10, 400, 10]), false, 'missing source cell is unavailable');
  assert.equal(world.lineOfSight([10, 400, 10], [20, 400, 10]), false, 'missing collision must fail closed');
  assert.equal(world.trace([0, 0, 0], [0, 0, 0], 10), null);
  assert.equal(world.lastQueryComplete, false);
  for (let n = 0; n < 8; n++) assert(world.completeAt([n * 375 + 10, 10, 10]));
  assert.equal(world.cacheEntries, 6, 'LRU remains bounded after moving through eight source cells');
} finally { fs.rmSync(temporary, {recursive: true, force: true}); }

// Independent known floor values from actual archived SCL2 triangles. These
// also cover airport triangles larger than the former native150m cutoff.
const world = new WorldCollision();
for (const [point, expected] of [
  [[1480, -1738, 13.5], 12.546875],
  [[1570, -2460, 13.65], 12.5546875],
  [[-1700, -200, 14.25], 13.1484375],
  [[1492, 1250, 10.92], 9.8203125],
]) {
  close(world.height(...point, 5), expected, 0.0001);
  const down = world.trace(point, [0, 0, -1], 10);
  assert(down && world.lastQueryComplete);
  close(down.distance, point[2] - expected, 0.0001);
  assert(down.normal[2] > 0.99);
}
assert(world.completeAt([-1312.5, -937.5, 1000]), 'actual empty i84 is available geometry, not a missing archive');
console.log('PASS: SCL2 floors/rays, real airport ground, cross-cell wall, interiors, materials, oversized triangles, malformed input and bounded LRU');
