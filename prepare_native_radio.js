#!/usr/bin/env node
// Extract the archived public radio program without publishing game data.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const {archivedModules} = require('./smoke_vehicle_dynamics');
const hash = value => crypto.createHash('sha256').update(value).digest('hex');

function expression(source, start) {
  let depth = 0, quote = null, escaped = false;
  for (let i = start; i < source.length; i++) {
    const c = source[i];
    if (quote) {
      if (escaped) escaped = false;
      else if (c === '\\') escaped = true;
      else if (c === quote) quote = null;
      continue;
    }
    if ('\"\'`'.includes(c)) { quote = c; continue; }
    if ('([{'.includes(c)) depth++;
    else if (')]}'.includes(c)) { if (--depth < 0) return source.slice(start, i); }
    if (depth === 0 && (c === ',' || c === ';')) return source.slice(start, i);
  }
  throw Error('Unterminated radio expression');
}

function archivedRadio() {
  const load = archivedModules(), source = load.factories[19737].toString();
  const marker = source.indexOf('function mY(');
  const value = name => {
    const at = source.lastIndexOf(name + '=', marker);
    if (at < 0) throw Error('Archived radio field missing: ' + name);
    return vm.runInNewContext('(' + expression(source, at + name.length + 1) + ')', {}, {timeout: 1000});
  };
  const program = {version: 1, ...value('mb'), vehicleDefaults: value('my'),
    stationNames: value('mR'), rain: value('mv'), sun: value('mj'), fog: value('mk'),
    stationRegions: value('mM'), talkShowGroups: value('mS'), weather: load(93265).k8};
  const at = source.indexOf('l=function(e,t)', marker) + 2;
  const closure = expression(source, at);
  if (!closure.startsWith('function(e,t)') || !closure.endsWith('(mb,mx.k8)'))
    throw Error('Archived radio program boundary changed');
  const core = closure.slice(0, -'(mb,mx.k8)'.length);
  const timeline = Function('mS', 'mv', 'mj', 'mk', 'mM', 'return (' + core + ');')(
    program.talkShowGroups, program.rain, program.sun, program.fog, program.stationRegions)(program, program.weather);
  program.provenance = {source: 'public module19737.mY / mb / my; weather module93265.k8',
    moduleSHA256: hash(source), timelineSHA256: hash(core), musicIncluded: false};
  return {program, timeline};
}

function prepare(output = path.join(__dirname, 'local-only/site/game/native/radio.program.json')) {
  const {program} = archivedRadio();
  fs.mkdirSync(path.dirname(output), {recursive: true});
  fs.writeFileSync(output, JSON.stringify(program), {mode: 0o600});
  console.log(JSON.stringify({rate: program.rate, samples: program.samples.length,
    stations: program.stations.length, vehicles: Object.keys(program.vehicleDefaults).length,
    musicIncluded: false, output}));
  return program;
}
if (require.main === module) prepare(process.argv[2]);
module.exports = {archivedRadio, prepare};
