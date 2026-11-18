// Lazy owner-stream conversion. Routes are independent of the private backend.
// Data, absolute owner paths, converted audio and cache metadata remain ignored.
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const {spawn} = require('node:child_process');
const {catalog, read, PACKS} = require('./radio_streams');
const LOCAL_ONLY = path.join(__dirname, 'local-only');

// Keep registration and generated audio outside the archived asset tree. A
// development site can be a read-only alias shared by several source checkouts.
function locations(localOnly = LOCAL_ONLY) {
  return {configuration: path.join(localOnly, 'native-radio-owner.json'),
    legacyConfiguration: path.join(localOnly, 'site/game/radio/owner.json'),
    cache: path.join(localOnly, 'native-radio-cache'),
    custom: path.join(localOnly, 'site/game/radio/custom')};
}

function register(directory, options = {}) {
  const source = catalog(directory);
  const configuration = path.resolve(options.configuration || locations(options.localOnly).configuration);
  // Refuse existing files and linked ancestors before creating anything. In
  // particular, never write through a QA site's alias into an older checkout.
  let ancestor = path.parse(configuration).root;
  for (const component of configuration.slice(ancestor.length).split(path.sep)) {
    ancestor = path.join(ancestor, component);
    try { if (fs.lstatSync(ancestor).isSymbolicLink()) throw Error('Radio registration cannot use a linked path'); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
  fs.mkdirSync(path.dirname(configuration), {recursive: true});
  fs.writeFileSync(configuration, JSON.stringify({directory: source.directory}) + '\n', {mode: 0o600, flag: 'wx'});
  return {configuration, stations: source.stations.filter(value => value.length).length,
    tracks: source.stations.flat().length, adverts: source.adverts.length, audioCopied: false};
}

function create(options = {}) {
  const local = locations(options.localOnly);
  const cache = options.cache || local.cache;
  const decoder = options.decoder || process.env.ZGTA_RADIO_DECODER;
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
    // An explicit registration is authoritative. Only the default lookup keeps
    // compatibility with older installations; an invalid new file never falls
    // back to another owner's source.
    const configuration = options.configuration || (fs.existsSync(local.configuration) ? local.configuration : local.legacyConfiguration);
    if (!fs.existsSync(configuration)) return null;
    const stat = fs.statSync(configuration);
    if (!stat.isFile() || stat.size > 16384) throw Error('Invalid owner radio registration');
    const signature = `${configuration}:${stat.ino}:${stat.ctimeMs}:${stat.mtimeMs}:${stat.size}`;
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
    const customPath = options.customDirectory || local.custom;
    const overrides = new Set([...PACKS, 'USER']);
    const songs = options.includeCustom !== false && fs.existsSync(customPath) ? fs.readdirSync(customPath).filter(name =>
      /\.(mp3|m4a|aac|wav)$/i.test(name) && !name.startsWith('.') && !overrides.has(name.replace(/\.[^.]+$/, '').toUpperCase()))
      .sort().slice(0, 2000).map(name => ({name: name.replace(/\.[^.]+$/, ''),
        url: '/game/radio/custom/' + encodeURIComponent(name)})) : [];
    return {version: 1, stations: source ? source.stations.map(station => station.map(item)) : [],
      adverts: source ? source.adverts.map(item) : [], songs};
  }
  async function converted(track) {
    const stat = fs.statSync(track.file);
    const tool = decoder ? fs.statSync(decoder) : null;
    if (tool && !tool.isFile()) throw Error('Invalid native radio decoder');
    const key = crypto.createHash('sha256').update(JSON.stringify([
      track.file, stat.size, stat.mtimeMs, track.offset, track.size,
      decoder ? ['native-float-wav-1', decoder, tool.size, tool.mtimeMs] : 'float-wav-1'])).digest('hex');
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
        if (!decoder) {
          const descriptor = fs.openSync(input, 'w', 0o600);
          try {
            for (let start = 0; start < track.size - 8068; start += 1024 * 1024) {
              const bytes = read(track, start, Math.min(track.size - 8068, start + 1024 * 1024));
              let written = 0;
              while (written < bytes.length) written += fs.writeSync(descriptor, bytes, written, bytes.length-written);
            }
          } finally { fs.closeSync(descriptor); }
        }
        await new Promise((resolve, reject) => {
          const command = decoder || options.python || process.env.ZGTA_PYTHON || process.env.PYTHON || 'python3';
          const args = decoder ? [track.file, String(track.offset), String(track.size), partial] :
            [path.join(__dirname, 'prepare_native_radio_audio.py'), input, partial];
          const child = spawn(command, args,
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
  const [directory, flag, configuration, ...extra] = process.argv.slice(2);
  if (!directory || extra.length || (flag && (flag !== '--configuration' || !configuration)))
    throw Error('Usage: node native_radio_server.js /absolute/owner/game/directory [--configuration /absolute/private/owner.json]');
  console.log(JSON.stringify(register(directory, {configuration})));
}
module.exports = {create, register, locations};
