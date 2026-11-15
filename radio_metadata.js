// Independent owner-stream Ogg/Vorbis metadata parser. No game data is bundled.
const fs = require('node:fs');
const {KEY, HEADER} = require('./radio_streams');

function inspect(track) {
  const length = track.size - HEADER;
  if (!Number.isSafeInteger(length) || length <= 0 || length > 64 * 1024 * 1024)
    throw Error('Owner Ogg metadata scan exceeds its64MiB compressed-track bound');
  // Parse from one bounded compressed record. Reopening/reading tiny page
  // headers over thousands of seeks is needlessly costly on owner disk images.
  const fd = fs.openSync(track.file, 'r'), encoded = Buffer.alloc(length);
  try {
    let received = 0;
    while (received < length) {
      const count = fs.readSync(fd, encoded, received, length-received, track.offset+HEADER+received);
      if (!count) throw Error('Owner Ogg file changed');
      received += count;
    }
  } finally {fs.closeSync(fd);}
  function bytes(relative, count) {
    if (!Number.isSafeInteger(relative) || relative < 0 || count < 0 || relative + count > length)
      throw Error('Invalid owner Ogg page bounds');
    const offset = track.offset + HEADER + relative, buffer = Buffer.from(encoded.subarray(relative, relative+count));
    for (let i = 0; i < count; i++) buffer[i] ^= KEY[(offset + i) & 15];
    return buffer;
  }
  {
    let cursor = 0, pages = 0, serial, rate, channels;
    while (cursor < length && pages < 100000) {
      const header = bytes(cursor, 27);
      if (header.toString('ascii', 0, 4) !== 'OggS' || header[4] !== 0)
        throw Error('Invalid owner Ogg page');
      const thisSerial = header.readUInt32LE(14), sequence = header.readUInt32LE(18);
      if (pages === 0) serial = thisSerial;
      if (serial !== thisSerial || sequence !== pages) throw Error('Discontinuous owner Ogg stream');
      const lacing = bytes(cursor + 27, header[26]);
      const payload = [...lacing].reduce((sum, value) => sum + value, 0);
      const pageSize = 27 + lacing.length + payload;
      if (cursor + pageSize > length) throw Error('Incomplete owner Ogg page');
      if (pages === 0) {
        const ident = bytes(cursor + 27 + lacing.length, Math.min(payload, 30));
        if (ident.length < 30 || !ident.subarray(0, 7).equals(Buffer.from([1,118,111,114,98,105,115])))
          throw Error('Owner stream is not Vorbis');
        channels = ident[11]; rate = ident.readUInt32LE(12);
      }
      cursor += pageSize; pages++;
      if (header[5] & 4) {
        const granule = header.readBigUInt64LE(6);
        if (granule > BigInt(Number.MAX_SAFE_INTEGER) || cursor !== length)
          throw Error('Invalid owner Ogg end/sample count');
        return {frames: Number(granule), rate, channels, pages, payloadBytes: length};
      }
    }
    throw Error('Owner Ogg stream has no end page');
  }
}

module.exports = {inspect};
