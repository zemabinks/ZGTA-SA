#!/usr/bin/env node
// Compare the native sample-clock program against the actual archived closure.
const fs = require('node:fs'), path = require('node:path');
const {archivedRadio} = require('../../tools/assets/prepare_native_radio');
function generate() {
  const {program, timeline} = archivedRadio();
  const cases = [], cursors = [];
  for (const day of [0, 1, 20_000, 20_772]) for (let station = 0; station < 12; station++) {
    const pieces = timeline.day(station, day);
    cases.push({station, day, pieces});
    for (const fraction of [0, 0.000001, 0.03, 0.25, 0.5, 0.7, 0.999999]) {
      const milliseconds = day * 86_400_000 + fraction * 86_400_000;
      const cursor = timeline.at(station, milliseconds);
      cursors.push({milliseconds, cursor, after: timeline.after(cursor)});
    }
    const cursor = timeline.at(station, day * 86_400_000 + 86_400_000 - 0.01);
    cursors.push({milliseconds: day * 86_400_000 + 86_400_000 - 0.01, cursor, after: timeline.after(cursor)});
  }
  const directory = path.join(require('node:path').resolve(__dirname, '../..'), 'local-only/radio-fixtures');
  fs.mkdirSync(directory, {recursive: true});
  fs.writeFileSync(path.join(directory, 'program.json'), JSON.stringify(program), {mode: 0o600});
  fs.writeFileSync(path.join(directory, 'timeline.json'), JSON.stringify({cases, cursors}), {mode: 0o600});
  console.log(JSON.stringify({days: cases.length, pieces: cases.reduce((n,c) => n+c.pieces.length,0), cursors: cursors.length}));
}
if (require.main === module) generate();
module.exports = {generate};
