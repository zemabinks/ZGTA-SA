// SPDX-License-Identifier: AGPL-3.0-only
'use strict';

// Independently authored task policy. Original scripts, fingerprints, offsets,
// symbol bindings and private plans are supplied separately by the owner.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const vm = require('node:vm');

const PROFILE = 'zgta-browser-original-tasks-v1';
const MAX_SOURCE = 2 * 1024 * 1024;
const MAX_PLAN = 128 * 1024;
const KINDS = new Set([
  'declare-associations-float32', 'initialize-completion-capability-false',
  'mark-ordinary-landing-owner', 'capture-logical-gait-weights',
  'choose-launch-side-float32', 'complete-ordinary-landing-and-clear-owner',
]);
const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const validHash = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
function requireValue(condition, message) {
  if (!condition) throw new Error('Browser task policy: ' + message);
}
function identifier(value) {
  requireValue(typeof value === 'string' && value.length <= 80 &&
    /^[A-Za-z_$][A-Za-z0-9_$]*$/.test(value) &&
    !new Set(['__proto__', 'prototype', 'constructor', 'eval', 'arguments',
      'this', 'null', 'true', 'false', 'let', 'const', 'var', 'function',
      'return', 'class', 'new', 'default', 'delete', 'await', 'yield']).has(value), 'invalid symbol binding');
  return value;
}
function emit(kind, bindings, rows) {
  const p = bindings.phase, a = bindings.actionOwner, t = bindings.landingKind;
  const table = bindings.associationTable, cache = bindings.newAssociationState;
  const flag = bindings.newOwnerCapability;
  switch (kind) {
    case 'declare-associations-float32':
      return `,${cache}=new Float32Array(3)`;
    case 'initialize-completion-capability-false':
      return `,${flag}:false`;
    case 'mark-ordinary-landing-owner':
      return `,${a}.${flag}=["land","fallLand","collapse"].includes(${t})`;
    case 'capture-logical-gait-weights':
      // Each row contains a prepared positive-duration clip handle and its
      // own logical association weight. Equal clip handles remain separate.
      return rows.map((index, slot) => {
        const row = `${table}[${index}]`;
        return `${cache}[${slot}]=(${row}&&${row}[0]&&Number.isFinite(${row}[1])&&${row}[1]>0)?${row}[1]:0;`;
      }).join('');
    case 'choose-launch-side-float32': {
      const w = cache + '_weight', threshold = cache + '_threshold', q = cache + '_phase';
      return `(()=>{let ${w}=${cache}[2],${threshold}=Math.fround(0.3),${q}=0;` +
        `if(${w}<${threshold})${w}=${cache}[1];if(${w}<${threshold})${w}=${cache}[0];` +
        `if(${w}>${threshold}){${q}=Math.fround(Math.fround(${p})+Math.fround(0.367));` +
        `if(${q}>1)${q}=Math.fround(${q}-1);}` +
        `return ${q}>=0.5?"launchR":"launch";})()`;
    }
    case 'complete-ordinary-landing-and-clear-owner':
      // This expression runs only inside the host's already-qualified
      // retirement condition, after the current root displacement finishes.
      return `(${a}.${flag}===true&&(${p}=0),${a}=null)`;
    default: throw new Error('Browser task policy: unknown payload kind');
  }
}

function applyPinnedPolicy(source, plan) {
  requireValue(Buffer.isBuffer(source) && source.length > 0 && source.length <= MAX_SOURCE, 'source size');
  requireValue(plan && plan.schema === 1 && plan.profile === PROFILE && plan.enabled === true, 'plan profile');
  requireValue(plan.source && Number.isSafeInteger(plan.source.bytes) && plan.source.bytes === source.length &&
    validHash(plan.source.sha256) && digest(source) === plan.source.sha256, 'source identity');
  requireValue(source.every(byte => byte < 128), 'only pinned ASCII classic scripts are supported');
  const factory = plan.factory;
  requireValue(factory && Number.isSafeInteger(factory.byteStart) && Number.isSafeInteger(factory.byteEnd) &&
    factory.byteStart >= 0 && factory.byteStart < factory.byteEnd && factory.byteEnd <= source.length &&
    validHash(factory.sha256) && digest(source.subarray(factory.byteStart, factory.byteEnd)) === factory.sha256,
  'factory identity');
  const bindings = {};
  for (const key of ['phase','associationTable','actionOwner','landingKind','newAssociationState','newOwnerCapability'])
    bindings[key] = identifier(plan.bindings?.[key]);
  requireValue(new Set(Object.values(bindings)).size === 6, 'symbol bindings must be distinct');
  const body = source.subarray(factory.byteStart, factory.byteEnd).toString('ascii');
  for (const name of [bindings.newAssociationState, bindings.newOwnerCapability])
    requireValue(!body.includes(name), 'new owner state collides with source');
  requireValue(Array.isArray(plan.logicalRows) && plan.logicalRows.length === 3, 'logical rows');
  const rows = ['walk','run','sprint'].map(kind => {
    const matches = plan.logicalRows.filter(row => row?.kind === kind);
    requireValue(matches.length === 1 && Number.isSafeInteger(matches[0].index) &&
      matches[0].index >= 0 && matches[0].index <= 63, 'logical row identity');
    return matches[0].index;
  });
  requireValue(new Set(rows).size === 3, 'logical associations cannot share a row');
  requireValue(Array.isArray(plan.edits) && plan.edits.length === KINDS.size &&
    new Set(plan.edits.map(edit => edit?.payloadKind)).size === KINDS.size, 'complete policy edit set');
  const edits = plan.edits.map(edit => {
    requireValue(edit && KINDS.has(edit.payloadKind) && Number.isSafeInteger(edit.originalByteStart) &&
      Number.isSafeInteger(edit.originalByteEnd) && edit.originalByteStart >= factory.byteStart &&
      edit.originalByteStart <= edit.originalByteEnd && edit.originalByteEnd <= factory.byteEnd &&
      validHash(edit.expectedOriginalSpanSHA256), 'edit bounds or kind');
    requireValue(digest(source.subarray(edit.originalByteStart, edit.originalByteEnd)) === edit.expectedOriginalSpanSHA256,
      'edit span identity');
    return {start:edit.originalByteStart, end:edit.originalByteEnd, payload:Buffer.from(emit(edit.payloadKind, bindings, rows))};
  }).sort((a,b) => a.start - b.start);
  for (let i=1; i<edits.length; i++)
    requireValue(edits[i-1].end <= edits[i].start && edits[i-1].start !== edits[i].start, 'overlapping edits');
  const parts = []; let cursor = 0;
  for (const edit of edits) {parts.push(source.subarray(cursor,edit.start),edit.payload);cursor=edit.end;}
  parts.push(source.subarray(cursor));
  const output = Buffer.concat(parts);
  requireValue(output.length <= MAX_SOURCE + 64 * 1024, 'output size');
  // Parse only; never execute owner code in the server process.
  new vm.Script(output.toString('ascii'), {filename:'owner-browser-task-policy.js'});
  return output;
}

function create({siteRoot, configuration}) {
  if (!configuration) return {matches:()=>false};
  const configInfo = fs.lstatSync(configuration);
  requireValue(configInfo.isFile() && !configInfo.isSymbolicLink() && configInfo.size <= MAX_PLAN, 'private plan file');
  const plan = JSON.parse(fs.readFileSync(configuration,'utf8'));
  requireValue(plan?.enabled === true && typeof plan.source?.path === 'string', 'explicit enabled owner source');
  const root = fs.realpathSync(siteRoot), target = fs.realpathSync(plan.source.path);
  const relative = path.relative(root,target);
  requireValue(relative && relative !== '..' && !relative.startsWith('..' + path.sep) && !path.isAbsolute(relative), 'owner source is outside site root');
  const route = path.resolve(siteRoot,relative), declared = path.resolve(plan.source.path);
  function read() {
    requireValue(fs.realpathSync(siteRoot) === root && fs.realpathSync(route) === target, 'owner source path changed');
    const info = fs.lstatSync(target);
    requireValue(info.isFile() && !info.isSymbolicLink() && info.size <= MAX_SOURCE, 'owner source file');
    return applyPinnedPolicy(fs.readFileSync(target),plan);
  }
  read(); // A configured mismatched plan prevents startup rather than drifting.
  return {
    // Keep matching the configured route after deletion/replacement, so drift
    // fails closed instead of falling through to ordinary unpatched serving.
    matches(filename) {return [route,target,declared].includes(path.resolve(filename));},
    read,
  };
}

module.exports = {PROFILE, applyPinnedPolicy, create};
