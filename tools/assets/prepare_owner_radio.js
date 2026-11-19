#!/usr/bin/env node
// Produce an owner-local full-recording program without changing the archived
// compatibility program. The existing native JSON loader needs no App change.
const fs = require('node:fs'), path = require('node:path');
const {catalog} = require('../../radio_streams');
const {inspect} = require('../../radio_metadata');

function corrected(program, directory) {
  const output = structuredClone(program), source = catalog(directory);
  const tracks = [...source.stations.flat(), ...source.adverts], changed = [];
  for (const track of tracks) {
    const value = inspect(track);
    if (value.rate !== program.rate || ![1, 2].includes(value.channels) ||
        !Number.isSafeInteger(value.frames) || value.frames <= 0 || value.frames > 86400 * value.rate ||
        track.id >= output.samples.length) throw Error('Unsupported owner radio format/index');
    if (value.frames !== output.samples[track.id]) changed.push(track.id);
    output.samples[track.id] = value.frames;
  }
  output.provenance = {...output.provenance, musicIncluded: false,
    sampleCounts: {source:'Owner-provided complete Ogg end granules', tracks: tracks.length, changed: changed.length}};
  return {program: output, tracks: tracks.length, changed};
}

if (require.main === module) {
  const [programFile, ownerDirectory, outputFile] = process.argv.slice(2);
  if (!programFile || !ownerDirectory || !outputFile) throw Error('Usage: tools/assets/prepare_owner_radio.js compatibility-program.json owner-directory output-program.json');
  if (path.resolve(programFile) === path.resolve(outputFile)) throw Error('Preserve the compatibility program; choose a different output path');
  const result = corrected(JSON.parse(fs.readFileSync(programFile, 'utf8')), ownerDirectory);
  fs.mkdirSync(path.dirname(outputFile), {recursive:true});
  // Exclusive creation also protects the compatibility input through a
  // differently named symlink/hardlink, and never replaces an existing asset.
  fs.writeFileSync(outputFile, JSON.stringify(result.program), {mode:0o600, flag:'wx'});
  console.log(JSON.stringify({tracks:result.tracks, changed:result.changed.length, output:outputFile, audioCopied:false}));
}
module.exports = {corrected};
