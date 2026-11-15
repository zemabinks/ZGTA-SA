// Server geometry queries over the owner's ignored SCL2 archive.
// GTA coordinates are x/y horizontally and z up. No game data is embedded.
'use strict';
const fs = require('node:fs');
const path = require('node:path');

const vector = value => Array.isArray(value) && value.length === 3 && value.every(Number.isFinite);
const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
const minus = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];

class CollisionCell {
  constructor(input) {
    const bytes = Buffer.isBuffer(input) ? input : Buffer.from(input);
    if (bytes.length < 16 || bytes.readUInt32LE(0) !== 0x324c4353) throw new Error('Invalid SCL2 header');
    const vertices = bytes.readUInt32LE(4), triangles = bytes.readUInt32LE(8), flags = bytes.readUInt32LE(12);
    if (vertices >= 1_000_000 || triangles >= 1_000_000 || (!vertices && triangles)) throw new Error('Invalid SCL2 counts');
    const indexOffset = 16 + vertices * 12, surfaceOffset = indexOffset + triangles * 12;
    if (surfaceOffset > bytes.length) throw new Error('Truncated SCL2 geometry');
    this.points = new Float32Array(vertices * 3);
    this.indices = new Uint32Array(triangles * 3);
    this.normals = new Float32Array(triangles * 3);
    this.buckets = new Map();
    this.large = [];
    for (let i = 0; i < this.points.length; i++) {
      const value = bytes.readFloatLE(16 + i * 4);
      if (!Number.isFinite(value) || Math.abs(value) > 1_000_000) throw new Error('Invalid SCL2 vertex');
      this.points[i] = value;
    }
    for (let i = 0; i < this.indices.length; i++) {
      const index = bytes.readUInt32LE(indexOffset + i * 4);
      if (index >= vertices) throw new Error('Invalid SCL2 vertex index');
      this.indices[i] = index;
    }
    const padded = Math.ceil(triangles / 4) * 4;
    this.surface = bytes.length >= surfaceOffset + triangles ? Uint8Array.from(bytes.subarray(surfaceOffset, surfaceOffset + triangles)) : null;
    this.material = (flags & 1) && bytes.length >= surfaceOffset + 2 * padded ?
      Uint8Array.from(bytes.subarray(surfaceOffset + padded, surfaceOffset + padded + triangles)) : null;
    for (let i = 0; i < triangles; i++) {
      const [a, b, c] = this.triangle(i);
      const normal = cross(minus(b, a), minus(c, a)), length = Math.hypot(...normal);
      if (length * length <= 0.00001) continue;
      this.normals.set(normal.map(n => n / length), i * 3);
      const x0 = Math.floor(Math.min(a[0], b[0], c[0]) / 10), x1 = Math.floor(Math.max(a[0], b[0], c[0]) / 10);
      const y0 = Math.floor(Math.min(a[1], b[1], c[1]) / 10), y1 = Math.floor(Math.max(a[1], b[1], c[1]) / 10);
      // Retain oversized airport/terrain triangles without allocating a huge
      // bucket rectangle. They are always considered for this source cell.
      if ((x1 - x0 + 1) * (y1 - y0 + 1) > 4096) { this.large.push(i); continue; }
      for (let x = x0; x <= x1; x++) for (let y = y0; y <= y1; y++) {
        const key = `${x},${y}`;
        if (!this.buckets.has(key)) this.buckets.set(key, []);
        this.buckets.get(key).push(i);
      }
    }
  }

  triangle(number) {
    return [0, 1, 2].map(offset => {
      const at = this.indices[number * 3 + offset] * 3;
      return [this.points[at], this.points[at + 1], this.points[at + 2]];
    });
  }

  candidates(x, y) { return [...(this.buckets.get(`${Math.floor(x / 10)},${Math.floor(y / 10)}`) || []), ...this.large]; }

  intersect(number, origin, direction, limit) {
    const [a, b, c] = this.triangle(number), edge1 = minus(b, a), edge2 = minus(c, a);
    const p = cross(direction, edge2), determinant = dot(edge1, p);
    if (Math.abs(determinant) < 0.000001) return null;
    const inverse = 1 / determinant, delta = minus(origin, a), u = dot(delta, p) * inverse;
    if (u < -0.000001 || u > 1.000001) return null;
    const q = cross(delta, edge1), v = dot(direction, q) * inverse;
    if (v < -0.000001 || u + v > 1.000001) return null;
    const distance = dot(edge2, q) * inverse;
    if (distance < -0.000001 || distance > limit + 0.000001) return null;
    const normal = Array.from(this.normals.subarray(number * 3, number * 3 + 3));
    if (dot(normal, direction) > 0) for (let i = 0; i < 3; i++) normal[i] *= -1;
    return {distance: Math.max(0, distance), normal: normal.map(n => n === 0 ? 0 : n),
      surface: this.surface?.[number] ?? 2, material: this.material?.[number] ?? -1};
  }

  height(x, y, near, maxDrop) {
    let best = null;
    for (const number of this.candidates(x, y)) {
      if (Math.abs(this.normals[number * 3 + 2]) <= 0.35) continue;
      const [a, b, c] = this.triangle(number);
      const denominator = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1]);
      if (Math.abs(denominator) < 0.0001) continue;
      const u = ((b[1] - c[1]) * (x - c[0]) + (c[0] - b[0]) * (y - c[1])) / denominator;
      const v = ((c[1] - a[1]) * (x - c[0]) + (a[0] - c[0]) * (y - c[1])) / denominator;
      if (u < -0.002 || v < -0.002 || 1 - u - v < -0.002) continue;
      const z = u * a[2] + v * b[2] + (1 - u - v) * c[2];
      if (z <= near + 1.5 && z >= near - maxDrop && (best === null || z > best)) best = z;
    }
    return best;
  }
}

class WorldCollision {
  constructor(options = {}) {
    this.root = options.root || path.join(__dirname, 'local-only', 'site', 'game', 'world');
    this.cacheLimit = Math.max(1, Math.min(8, Number.isInteger(options.cacheSize) ? options.cacheSize : 6));
    this.maxDistance = Math.max(1, Math.min(10000, options.maxDistance || 2000));
    this.cache = new Map();
    this.lastQueryComplete = false;
    this.loads = 0;
    this.failures = new Map();
    let index = options.index;
    if (!index) {
      try { index = JSON.parse(fs.readFileSync(path.join(this.root, 'index.json'), 'utf8')); }
      catch { index = {}; }
    }
    this.size = Number.isFinite(index.detail?.size) && index.detail.size > 0 ? index.detail.size : 375;
    this.grid = Number.isInteger(index.detail?.grid) && index.detail.grid > 0 ? index.detail.grid : 16;
    this.origin = Number.isFinite(index.detail?.origin) ? index.detail.origin : -3000;
    this.outside = Array.isArray(index.detail?.cells) ? new Set(index.detail.cells.filter(Boolean).map(row => row.cell)) : null;
    this.inside = Array.isArray(index.inside?.cells) ? new Set(index.inside.cells.filter(Boolean).map(row => row.cell)) : null;
  }

  get cacheEntries() { return this.cache.size; }

  cellName(point) {
    let x = Math.floor((point[0] - this.origin) / this.size), y = Math.floor((point[1] - this.origin) / this.size);
    if (point[0] === this.origin + this.size * this.grid) x = this.grid - 1;
    if (point[1] === this.origin + this.size * this.grid) y = this.grid - 1;
    if (x < 0 || y < 0 || x >= this.grid || y >= this.grid) return null;
    const number = y * this.grid + x, indoor = point[2] > 700;
    if ((indoor ? this.inside : this.outside)?.has(number) === false) return null;
    return `${indoor ? 'i' : 'c'}${number}`;
  }

  load(name) {
    if (!name) return null;
    if (this.cache.has(name)) {
      const value = this.cache.get(name); this.cache.delete(name); this.cache.set(name, value); return value;
    }
    // Retry missing/corrupt archive members after a brief interval, allowing
    // a running server to recover when its owner completes the archive.
    if (Date.now() - (this.failures.get(name) || 0) < 5000) return null;
    let cell;
    try { cell = new CollisionCell(fs.readFileSync(path.join(this.root, `${name}.col.bin`))); }
    catch { this.failures.set(name, Date.now()); return null; }
    this.loads++;
    this.failures.delete(name);
    this.cache.set(name, cell);
    while (this.cache.size > this.cacheLimit) this.cache.delete(this.cache.keys().next().value);
    return cell;
  }

  completeAt(point) { return vector(point) && !!this.load(this.cellName(point)); }

  height(x, y, near, maxDrop = 0.8) {
    this.lastQueryComplete = false;
    if (![x, y, near, maxDrop].every(Number.isFinite) || maxDrop < 0) return null;
    const cell = this.load(this.cellName([x, y, near]));
    if (!cell) return null;
    this.lastQueryComplete = true;
    return cell.height(x, y, near, maxDrop);
  }

  trace(origin, direction, distance) {
    this.lastQueryComplete = false;
    if (!vector(origin) || !vector(direction) || !Number.isFinite(distance) || distance <= 0 || distance > this.maxDistance) return null;
    const length = Math.hypot(...direction);
    if (length < 0.000001) return null;
    const unit = direction.map(n => n / length), cuts = [0, distance];
    // Splitting at both spatial and source-cell edges covers narrow corner
    // crossings and the375m edge that falls inside a10m spatial bucket.
    for (let axis = 0; axis < 2; axis++) for (const [step, base] of [[10, 0], [this.size, this.origin]]) {
      if (Math.abs(unit[axis]) < 0.000001) continue;
      const finish = origin[axis] + unit[axis] * distance;
      const lo = Math.ceil((Math.min(origin[axis], finish) - base) / step);
      const hi = Math.floor((Math.max(origin[axis], finish) - base) / step);
      for (let cell = lo; cell <= hi; cell++) {
        const at = (base + cell * step - origin[axis]) / unit[axis];
        if (at > 0 && at < distance) cuts.push(at);
      }
    }
    if (Math.abs(unit[2]) > 0.000001) {
      const indoorEdge = (700 - origin[2]) / unit[2];
      if (indoorEdge > 0 && indoorEdge < distance) cuts.push(indoorEdge);
    }
    cuts.sort((a, b) => a - b);
    let nearest = null, complete = true;
    const checked = new Map();
    const visit = at => {
      const point = origin.map((n, i) => n + unit[i] * at), name = this.cellName(point), cell = this.load(name);
      if (!cell) { complete = false; return; }
      if (!checked.has(name)) checked.set(name, new Set());
      const seen = checked.get(name);
      for (const triangle of cell.candidates(point[0], point[1])) {
        if (seen.has(triangle)) continue;
        seen.add(triangle);
        const contact = cell.intersect(triangle, origin, unit, nearest?.distance ?? distance);
        if (contact && (!nearest || contact.distance < nearest.distance)) nearest = contact;
      }
    };
    visit(0);
    for (let i = 1; i < cuts.length; i++) if (cuts[i] - cuts[i - 1] > 0.000001) visit((cuts[i] + cuts[i - 1]) / 2);
    visit(distance);
    this.lastQueryComplete = complete;
    return nearest;
  }

  lineOfSight(from, to) {
    if (!vector(from) || !vector(to)) return false;
    const difference = minus(to, from), distance = Math.hypot(...difference);
    if (distance < 0.000001) return this.completeAt(from);
    const contact = this.trace(from, difference, distance);
    return this.lastQueryComplete && contact === null;
  }
}

const world = new WorldCollision();
module.exports = {
  WorldCollision, CollisionCell,
  trace: world.trace.bind(world), height: world.height.bind(world),
  lineOfSight: world.lineOfSight.bind(world), completeAt: world.completeAt.bind(world),
  get lastQueryComplete() { return world.lastQueryComplete; },
  get cacheEntries() { return world.cacheEntries; },
};
