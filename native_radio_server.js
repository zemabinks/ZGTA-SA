// Lazy owner-stream conversion. Routes are independent of the private backend.
// Data, absolute owner paths, converted audio and cache metadata remain ignored.
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const {spawn} = require('node:child_process');
const {catalog, read, PACKS} = require('./radio_streams');
const ROOT = path.join(__dirname, 'local-only/site/game/radio');
const CONFIG = path.join(ROOT, 'owner.json');
const CACHE = path.join(ROOT, 'native-cache');

function create(options = {}) {
  const configuration = options.configuration || CONFIG, cache = options.cache || CACHE;
  let current = null, stamp = null;
  const pending = new Map();
  let active = 0;
  const waiters = [];
  async function acquire() {
    if (active < 2) { active++; return; }
    await new Promise(resolve => waiters.push(resolve));
  }
  function release() { const next = waiters.shift(); if (next) next(); else active--; }
  function prune(retained) {
    const budget = options.cacheBytes ?? 2 * 1024 * 1024 * 1024;
    const files = fs.readdirSync(cache).filter(name => name.endsWith('.wav')).map(name => {
      const file = path.join(cache,name), stat = fs.statSync(file);
      return {file, size:stat.size, at:stat.mtimeMs};
    }).sort((a,b) => a.at-b.at);
    let total = files.reduce((size,file) => size+file.size,0);
    for (const file of files) if (total > budget && file.file !== retained) {
      try { fs.unlinkSync(file.file); total -= file.size; } catch {}
    }
  }
  function load() {
    if (!fs.existsSync(configuration)) return null;
    const stat = fs.statSync(configuration), signature = `${stat.mtimeMs}:${stat.size}`;
    if (stamp === signature) return current;
    const config = JSON.parse(fs.readFileSync(configuration, 'utf8'));
    if (typeof config.directory !== 'string' || !path.isAbsolute(config.directory)) throw Error('Invalid owner radio directory');
    current = catalog(config.directory); stamp = signature;
    return current;
  }
  function tracks() {
    const source = load();
    return source ? [...source.stations.flat(), ...source.adverts] : [];
  }
  function index() {
    const source = load();
    const versions = new Map();
    const item = track => {
      if (!versions.has(track.file)) {
        const stat = fs.statSync(track.file);
        versions.set(track.file, `${stat.size}:${stat.mtimeMs}`);
      }
      const revision = crypto.createHash('sha256').update(`${versions.get(track.file)}:${track.offset}:${track.size}`).digest('hex').slice(0, 24);
      return {id: track.id, url: `/game/radio/native/track/${track.id}.wav?v=${revision}`};
    };
    const customPath = path.join(ROOT, 'custom');
    const overrides = new Set([...PACKS, 'USER']);
    const songs = fs.existsSync(customPath) ? fs.readdirSync(customPath).filter(name =>
      /\.(mp3|m4a|aac|wav)$/i.test(name) && !name.startsWith('.') && !overrides.has(name.replace(/\.[^.]+$/, '').toUpperCase()))
      .sort().slice(0, 2000).map(name => ({name: name.replace(/\.[^.]+$/, ''),
        url: '/game/radio/custom/' + encodeURIComponent(name)})) : [];
    return {version: 1, stations: source ? source.stations.map(station => station.map(item)) : [],
      adverts: source ? source.adverts.map(item) : [], songs};
  }
  async function converted(track) {
    const stat = fs.statSync(track.file);
    const key = crypto.createHash('sha256').update(JSON.stringify([
      track.file, stat.size, stat.mtimeMs, track.offset, track.size, 'float-wav-1'])).digest('hex');
    const output = path.join(cache, key + '.wav');
    if (fs.existsSync(output)) { const now = new Date(); fs.utimesSync(output,now,now); return output; }
    if (pending.has(key)) return pending.get(key);
    const operation = (async () => {
      await acquire();
      const input = path.join(cache, key + '.ogg'), partial = output + '.partial';
      try {
        fs.mkdirSync(cache, {recursive: true});
        const currentStat = fs.statSync(track.file);
        if (currentStat.size !== stat.size || currentStat.mtimeMs !== stat.mtimeMs) throw Error('Owner radio file changed before decoding');
        const descriptor = fs.openSync(input, 'w', 0o600);
        try {
          for (let start = 0; start < track.size - 8068; start += 1024 * 1024) {
            const bytes = read(track, start, Math.min(track.size - 8068, start + 1024 * 1024));
            let written = 0;
            while (written < bytes.length) written += fs.writeSync(descriptor, bytes, written, bytes.length-written);
          }
        } finally { fs.closeSync(descriptor); }
        await new Promise((resolve, reject) => {
          const child = spawn(options.python || 'python3', [path.join(__dirname, 'prepare_native_radio_audio.py'), input, partial],
            {stdio: ['ignore', 'pipe', 'pipe']});
          let errors = '', metadata = '';
          child.stdout.on('data', data => { metadata = (metadata + data).slice(-8192); });
          child.stderr.on('data', data => { errors = (errors + data).slice(-8192); });
          child.on('error', reject);
          child.on('close', code => code === 0 ? resolve(metadata) : reject(Error('Owner stream decode failed: ' + errors)));
        });
        const finalStat = fs.statSync(track.file);
        if (finalStat.size !== stat.size || finalStat.mtimeMs !== stat.mtimeMs) throw Error('Owner radio file changed during decoding');
        fs.chmodSync(partial, 0o600); fs.renameSync(partial, output);
        prune(output);
        return output;
      } finally {
        for (const file of [input, partial]) try { fs.unlinkSync(file); } catch {}
        release();
      }
    })();
    pending.set(key, operation);
    try { return await operation; } finally { pending.delete(key); }
  }
  async function handle(req, res, pathname) {
    if (pathname !== '/game/radio/native/index' && !/^\/game\/radio\/native\/track\/\d+\.wav$/.test(pathname)) return false;
    if (!['GET','HEAD'].includes(req.method)) { res.writeHead(405); res.end(); return true; }
    try {
      if (pathname.endsWith('/index')) {
        const bytes = Buffer.from(JSON.stringify(index()));
        res.writeHead(200, {'content-type':'application/json', 'cache-control':'no-store', 'content-length':bytes.length});
        res.end(req.method === 'HEAD' ? undefined : bytes); return true;
      }
      const id = Number(pathname.match(/\/(\d+)\.wav$/)[1]), track = tracks().find(item => item.id === id);
      if (!track) { res.writeHead(404); res.end(); return true; }
      const file = await converted(track), size = fs.statSync(file).size;
      let start = 0, end = size - 1, code = 200;
      if (req.headers.range) {
        const range = /^bytes=(\d+)-(\d*)$/.exec(req.headers.range);
        if (!range || Number(range[1]) >= size || (range[2] && Number(range[2]) < Number(range[1]))) {
          res.writeHead(416, {'content-range':`bytes */${size}`}); res.end(); return true;
        }
        start = Number(range[1]); end = range[2] ? Math.min(size - 1, Number(range[2])) : size - 1; code = 206;
      }
      const headers = {'content-type':'audio/wav', 'accept-ranges':'bytes', 'content-length':end - start + 1,
        'cache-control':'private, max-age=31536000, immutable'};
      if (code === 206) headers['content-range'] = `bytes ${start}-${end}/${size}`;
      res.writeHead(code, headers);
      if (req.method === 'HEAD') res.end();
      else fs.createReadStream(file, {start,end}).on('error', () => res.destroy()).pipe(res);
      return true;
    } catch (error) {
      // Do not expose the owner's absolute filenames or decoder traceback to LAN clients.
      options.onError?.(error);
      if (!res.headersSent) res.writeHead(503, {'content-type':'text/plain'});
      res.end('Owner radio audio is unavailable'); return true;
    }
  }
  return {handle, index, converted, tracks};
}
if (require.main === module) {
  const directory = process.argv[2];
  if (!directory) throw Error('Usage: node native_radio_server.js /absolute/owner/game/directory');
  const source = catalog(directory);
  fs.mkdirSync(ROOT, {recursive: true});
  fs.writeFileSync(CONFIG, JSON.stringify({directory: source.directory}), {mode: 0o600});
  console.log(JSON.stringify({stations: source.stations.filter(value => value.length).length,
    tracks: source.stations.flat().length, adverts: source.adverts.length, audioCopied: false}));
}
module.exports = {create};
