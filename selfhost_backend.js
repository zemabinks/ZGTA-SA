// An independent, local-only starting point for the archived browser client.
// This intentionally implements a small, documented part of the live protocol.
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const OptionalDiscord = require('./optional_discord');

const MAX_FRAME = 64 * 1024;
const MAX_PEERS = 32;
const MAX_CASH = 100000000;
const RESPRAY_COST = 120;
const DISCORD_BONUS = 500;
const SUPPLIES = Object.freeze([
  {id: 'repair_kit', name: 'Repair kit', price: 125, capacity: 5},
  {id: 'paint_can', name: 'Paint can', price: 100, capacity: 5},
]);
const MISSION_RADIUS = 12;
const TAXI_STREAK_WINDOW_MS = 600000;
const TAXI_CLEAN_BONUS = 75;
const TAXI_QUICK_BONUS = 50;
const TAXI_STREAK_BONUS = 50;
const TAXI_CABS = Object.freeze([
  {model: 420, name: 'Taxi', level: 1, premium: 0, car: '420.6.1.0.'},
  {model: 438, name: 'Cabbie', level: 8, premium: 75, car: '438.6.1.0.'},
  {model: 409, name: 'Limousine', level: 20, premium: 200, car: '409.1.1.0.'},
]);
const MECHANIC_STAGES = Object.freeze(['engine', 'tyres', 'bodywork']);
const MECHANIC_STAGE_MS = 3000;
const TIME_TRIAL_MS = 180000;
const PATROL_MS = 240000;
const PIZZA_MS = 360000;
const TRUCKER_MS = 420000;
const PILOT_MS = 600000;
const PILOT_SMOOTH_BONUS = 150;
const PILOT_EARLY_BONUS = 100;
const PILOT_STREAK_BONUS = 500;
const FIRE_MS = 480000;
const FIRE_OFFSETS = Object.freeze([[0, 0], [18, 0], [-18, 0]]);
const HEIST_MS = 600000;
const HEIST_COOLDOWN_MS = 300000;
const HEIST_CREW_BONUS = 200;
const CONVOY_BONUS = 100;
const CONVOY_RADIUS = 80;
const CAR_THEFT_MS = 300000;
const MULTIPLAYER_RACE_MS = 300000;
const WANTED_DECAY_MS = 120000;
const PASSIVE_WAIT_MS = 120000;
const PARTY_INVITE_MS = 60000;
const PARTY_LIMIT = 4;
const TURF_CAPTURE_MS = 30000;
const GANG_SWITCH_MS = 600000;
const GANGS = Object.freeze([
  {id: 'green', name: 'Green Crew'},
  {id: 'violet', name: 'Violet Crew'},
  {id: 'gold', name: 'Gold Crew'},
]);
const TURFS = Object.freeze(['elcorona', 'willowfield', 'jefferson']);
const DISCOVERY_IDS = Object.freeze(['elcorona', 'willowfield', 'jefferson',
  'santamaria', 'mulholland', 'hashbury', 'queens', 'calton',
  'clownspocket', 'creek', 'fortcarson', 'angelpine']);
const DISCOVERY_PAY = 75;
const DISCOVERY_XP = 20;
const DISCOVERY_FINISH_PAY = 500;
const DISCOVERY_FINISH_XP = 100;
const WEAPON_DAMAGE = Object.freeze({0: 8, 1: 10, 2: 14, 3: 14, 4: 25,
  5: 16, 6: 18, 7: 20, 8: 18, 9: 30, 22: 18, 23: 20, 24: 40,
  25: 35, 26: 28, 27: 32, 28: 12, 29: 18, 30: 24, 31: 24,
  32: 14, 33: 36, 34: 70});
const JOBS = Object.freeze([
  {id: 'courier', name: 'Courier', pay: 250, distance: 38},
  {id: 'taxi', name: 'Taxi', pay: 300, distance: 48},
  {id: 'mechanic', name: 'Mechanic', pay: 350, distance: 55},
  {id: 'medic', name: 'Medic', pay: 350, distance: 55},
  {id: 'trial', name: 'Street time trial', pay: 450, distance: 75},
  {id: 'patrol', name: 'Police patrol', pay: 400, distance: 75},
  {id: 'pizza', name: 'Pizza delivery', pay: 400, distance: 75},
  {id: 'trucker', name: 'Freight delivery', pay: 500, distance: 90},
  {id: 'pilot', name: 'Pilot flight', pay: 700, distance: 120},
  {id: 'fire', name: 'Fire response', pay: 650, distance: 100},
  {id: 'heist', name: 'Getaway heist', pay: 900, distance: 100},
  {id: 'carthief', name: 'Getaway car', pay: 550, distance: 65},
]);
const CATALOG_FILE = path.join(__dirname, 'local-only', 'selfhost', 'client-catalog.json');
let clientCatalog = {vehicles: [], homes: []};
try { clientCatalog = JSON.parse(fs.readFileSync(CATALOG_FILE, 'utf8')); }
catch (error) { if (error.code !== 'ENOENT') console.error('Could not load local client catalog:', error.message); }
const STARTER_CARS = [
  {model: 410, name: 'Manana', price: 500, car: '410.52.39.0.', source: 'starter'},
  {model: 400, name: 'Landstalker', price: 900, car: '400.52.39.0.', source: 'starter'},
  {model: 560, name: 'Sultan', price: 2500, car: '560.52.39.0.', source: 'starter'},
];
const starterModels = new Set(STARTER_CARS.map(car => car.model));
const CAR_CATALOG = Object.freeze([...STARTER_CARS, ...(clientCatalog.vehicles || [])
  .filter(item => Number.isInteger(item.model) && Number.isSafeInteger(item.price) && item.price > 0 &&
    Array.isArray(item.dealers) && item.dealers.length > 0 &&
    ['car', 'bike', 'bicycle', 'quad', 'plane', 'helicopter'].includes(item.type) &&
    !starterModels.has(item.model))
  .map(item => ({model: item.model, name: String(item.name).slice(0, 80), price: item.price,
    car: `${item.model}.${Number.isInteger(item.colors?.[0]) ? item.colors[0] : 1}.` +
      `${Number.isInteger(item.colors?.[1]) ? item.colors[1] : 1}.0.`,
    type: item.type, dealers: item.dealers, source: 'archived'}))]);
const PILOT_AIRCRAFT = Object.freeze([
  {model: 593, name: 'Dodo', level: 1, premium: 0, radius: 70},
  {model: 511, name: 'Beagle', level: 4, premium: 150, radius: 75},
  {model: 487, name: 'Maverick', level: 8, premium: 300, radius: 70},
  {model: 519, name: 'Shamal', level: 12, premium: 500, radius: 85},
  {model: 553, name: 'Nevada', level: 18, premium: 650, radius: 95},
  {model: 417, name: 'Leviathan', level: 24, premium: 800, radius: 80},
  {model: 577, name: 'AT-400', level: 30, premium: 1200, radius: 130},
  {model: 592, name: 'Andromada', level: 40, premium: 1500, radius: 140},
]);
function pilotAircraft(model) { return PILOT_AIRCRAFT.find(item => item.model === model); }
function pilotLevel(player) { return Math.min(50, 1 + Math.floor((player.pilotFlights || 0) / 3)); }
function taxiCab(model) { return TAXI_CABS.find(item => item.model === model); }
function taxiLevel(player) { return Math.min(50, 1 + Math.floor((player.taxiFares || 0) / 3)); }
const HOME_CATALOG = Object.freeze([
  {id: 'starter', name: 'Starter apartment', price: 1500, source: 'starter'},
  {id: 'loft', name: 'City loft', price: 5000, source: 'starter'},
  ...(clientCatalog.homes || [])
    .filter(item => typeof item.key === 'string' && Number.isSafeInteger(item.price) && item.price > 0 &&
      Array.isArray(item.out) && item.out.length === 4 && item.out.every(Number.isFinite))
    .map(item => ({id: item.key, name: String(item.name).slice(0, 80), price: item.price,
      city: String(item.city || '').slice(0, 8), tier: String(item.tier || '').slice(0, 20),
      out: item.out, source: 'archived'})),
]);
// Local pilot routes begin on the visible runways, rather than at dealership
// doors. These points were checked against the archived map and SCL2 ground.
const PILOT_RUNWAYS = Object.freeze({
  ls: [1570, -2460, 12.55, Math.PI / 2],
  sf: [-1700, -200, 13.15, 0.69],
  lv: [1492, 1250, 9.82, 0],
  vm: [320, 2512, 15.56, 3 * Math.PI / 2],
});
const AIRPORTS = Object.freeze((clientCatalog.dealers || [])
  .filter(item => typeof item.key === 'string' && typeof item.air === 'string' &&
    Array.isArray(item.stand) && item.stand.length === 3 && item.stand.every(Number.isFinite))
  .map(item => ({id: item.air, dealer: item.key,
    name: String(item.name).slice(0, 80), stand: item.stand,
    runway: PILOT_RUNWAYS[item.air] || [...item.stand, 0]})));
const GROUND_DEALERS = Object.freeze((clientCatalog.dealers || [])
  .filter(item => typeof item.key === 'string' && !item.air &&
    Array.isArray(item.stand) && item.stand.length === 3 && item.stand.every(Number.isFinite))
  .map(item => ({id: item.key, name: String(item.name).slice(0, 80), stand: item.stand})));
function airportAt(id) { return AIRPORTS.find(airport => airport.id === id); }
function isAircraft(car) { return car?.type === 'plane' || car?.type === 'helicopter'; }
function nearestGroundDealer(pos) {
  if (!pos) return null;
  return GROUND_DEALERS.slice().sort((a, b) =>
    Math.hypot(pos.x - a.stand[0], pos.y - a.stand[1]) -
    Math.hypot(pos.x - b.stand[0], pos.y - b.stand[1]))[0] || null;
}
function groundDealerFor(pos, car) {
  if (!pos || !car?.dealers) return null;
  return GROUND_DEALERS.find(dealer => car.dealers.includes(dealer.id) &&
    Math.hypot(pos.x - dealer.stand[0], pos.y - dealer.stand[1]) <= 100) || null;
}
function nearestHangar(pos, car) {
  if (!pos) return null;
  return AIRPORTS.filter(airport => !car || car.dealers?.includes(airport.dealer))
    .sort((a, b) => Math.hypot(pos.x - a.stand[0], pos.y - a.stand[1]) -
      Math.hypot(pos.x - b.stand[0], pos.y - b.stand[1]))[0] || null;
}
function hangarFor(pos, car) {
  const hangar = nearestHangar(pos, car);
  return hangar && Math.hypot(pos.x - hangar.stand[0], pos.y - hangar.stand[1]) <= 100 ?
    hangar : null;
}
const STATE_FILE = path.join(__dirname, 'local-only', 'selfhost', 'players.json');
const DISCORD_CONFIG_FILE = path.join(__dirname, 'local-only', 'selfhost', 'discord-oauth.json');
let discordConfig = {};
try { discordConfig = JSON.parse(fs.readFileSync(DISCORD_CONFIG_FILE, 'utf8')); }
catch (error) { if (error.code !== 'ENOENT') throw error; }
const COOKIE = 'zgta_local';
const COOKIE_MAX_AGE = 365 * 24 * 60 * 60;
const JOIN_CODE = process.env.ZGTA_JOIN_CODE || (process.env.ZGTA_JOIN_CODE_FILE
  ? fs.readFileSync(process.env.ZGTA_JOIN_CODE_FILE, 'utf8').trim() : '');
if (JOIN_CODE && JOIN_CODE.length < 12) throw new Error('ZGTA_JOIN_CODE must be at least 12 characters.');
const ACCESS_TOKEN = JOIN_CODE ? crypto.createHmac('sha256', JOIN_CODE).update('ZGTA:SA local access v1').digest('hex') : '';

function json(res, status, body) {
  const data = Buffer.from(JSON.stringify(body));
  res.writeHead(status, {'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': data.length, 'Cache-Control': 'no-store'});
  res.end(data);
}

function readBody(req, limit = 16 * 1024) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', chunk => {
      size += chunk.length;
      if (size > limit) { reject(new Error('Request too large')); req.destroy(); }
      else chunks.push(chunk);
    });
    req.on('end', () => {
      try { resolve(JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}')); }
      catch { reject(new Error('Invalid JSON')); }
    });
    req.on('error', reject);
  });
}

function cookieId(req) {
  const match = /(?:^|;\s*)zgta_local=([0-9a-f]{32})(?:;|$)/.exec(req.headers.cookie || '');
  return match ? match[1] : null;
}

function safeName(value) {
  return String(value || '').trim().replace(/[^\p{L}\p{N} _.-]/gu, '').slice(0, 24);
}

function finite(value, fallback = 0) { return Number.isFinite(value) ? value : fallback; }
function limited(value, limit, fallback = 0) {
  return Number.isFinite(value) ? Math.max(-limit, Math.min(limit, value)) : fallback;
}
function rounded(value, fallback = 0) { return Math.round(finite(value, fallback) * 1000) / 1000; }
function money(value) { return Number.isSafeInteger(value) ? Math.max(0, Math.min(MAX_CASH, value)) : 0; }
function savedSupplies(value) {
  return Object.fromEntries(SUPPLIES.map(item => [item.id,
    Math.max(0, Math.min(item.capacity, Math.floor(finite(value?.[item.id]))))]));
}
function homeAt(id) { return HOME_CATALOG.find(home => home.id === id && home.out); }
function taxiQuickWindow(job) {
  const pickup = homeAt(job?.pickupHome), drop = homeAt(job?.drop);
  return pickup && drop ? Math.max(60000, Math.min(240000,
    Math.round(Math.hypot(pickup.out[0] - drop.out[0],
      pickup.out[1] - drop.out[1]) / 12) * 1000)) : 60000;
}
function fireSpot(job) {
  const home = homeAt(job?.incidentHome);
  const offset = FIRE_OFFSETS[job?.index];
  return home && offset ? [home.out[0] + offset[0], home.out[1] + offset[1], home.out[2]] : null;
}
function nearestHome(pos, minimum = 120, excluded = []) {
  return HOME_CATALOG.filter(home => home.out && !excluded.includes(home.id) &&
    Math.hypot(home.out[0] - pos.x, home.out[1] - pos.y) >= minimum)
    .sort((a, b) => Math.hypot(a.out[0] - pos.x, a.out[1] - pos.y) -
      Math.hypot(b.out[0] - pos.x, b.out[1] - pos.y))[0];
}
function missionId() { return `mission-${crypto.randomBytes(8).toString('hex')}`; }
function validMissionId(value) { return /^mission-[0-9a-f]{16}$/.test(value || ''); }
function savedGarage(value, cars) {
  return cars.map((_, slot) => {
    const item = Array.isArray(value) ? value[slot] : null;
    const position = Array.isArray(item?.position) && item.position.length === 4 &&
      item.position.every(Number.isFinite) && Math.abs(item.position[0]) <= 6000 &&
      Math.abs(item.position[1]) <= 6000 && item.position[2] >= -200 &&
      item.position[2] <= 1000 ? item.position.map(rounded) : null;
    const paint = Array.isArray(item?.paint) && item.paint.length === 2 &&
      item.paint.every(color => Number.isInteger(color) && color >= 0 && color <= 127) ?
      item.paint : null;
    return {health: Math.max(0, Math.min(1000, Math.round(finite(item?.health, 1000)))),
      damage: typeof item?.damage === 'string' ? item.damage.slice(0, 512) : '',
      active: item?.active === true && !!position, position, paint,
      parkedHome: homeAt(item?.parkedHome) ? item.parkedHome : null};
  });
}
function repairCost(entry) {
  return entry.health >= 1000 && !entry.damage ? 0 :
    Math.max(50, Math.ceil((1000 - entry.health) / 5));
}
function savedJob(value) {
  if (!value || !JOBS.some(job => job.id === value.id) ||
      !Number.isFinite(value.started) || Date.now() - value.started >= 86400000) return null;
  if (value.id === 'patrol' && Date.now() - value.started > PATROL_MS) return null;
  if (value.id === 'pizza' && Date.now() - value.started > PIZZA_MS) return null;
  if (value.id === 'trucker' && Date.now() - value.started > TRUCKER_MS) return null;
  if (value.id === 'pilot' && Date.now() - value.started > PILOT_MS) return null;
  if (value.id === 'fire' && Date.now() - value.started > FIRE_MS) return null;
  if (value.id === 'heist' && Date.now() - value.started > HEIST_MS) return null;
  if (value.id === 'pilot' && value.mode === 'flight') {
    const model = value.model === undefined ? 593 : value.model;
    if (!airportAt(value.from) || !airportAt(value.to) || value.from === value.to ||
        !validMissionId(value.vehicleId) || !pilotAircraft(model) ||
        !['takeoff', 'landing'].includes(value.stage)) return null;
    return {id: value.id, mode: 'flight', from: value.from, to: value.to,
      vehicleId: value.vehicleId, model, stage: value.stage, landingSince: null,
      minHealth: Math.max(0, Math.min(1000, finite(value.minHealth, 1000))),
      reportedHealth: value.reportedHealth === true,
      started: value.started};
  }
  if (value.id === 'pilot') return null;
  if (value.id === 'fire' && value.mode === 'fire') {
    if (!homeAt(value.incidentHome) || !validMissionId(value.vehicleId) ||
        !Array.isArray(value.station) || value.station.length !== 3 ||
        !value.station.every(Number.isFinite) ||
        !['respond', 'extinguish', 'rescue'].includes(value.stage) ||
        !Number.isInteger(value.index) || value.index < 0 || value.index > FIRE_OFFSETS.length ||
        (value.stage === 'rescue' && value.index !== FIRE_OFFSETS.length) ||
        (value.stage === 'extinguish' && value.index >= FIRE_OFFSETS.length)) return null;
    return {id: value.id, mode: 'fire', incidentHome: value.incidentHome,
      vehicleId: value.vehicleId, station: value.station, stage: value.stage,
      index: value.index, started: value.started};
  }
  if (value.id === 'fire') return null;
  if (value.id === 'heist' && value.mode === 'heist') {
    if (!homeAt(value.site) || !homeAt(value.drop) || value.site === value.drop ||
        !validMissionId(value.vehicleId) ||
        !Array.isArray(value.station) || value.station.length !== 3 ||
        !value.station.every(Number.isFinite) ||
        !['plan', 'escape'].includes(value.stage)) return null;
    return {id: value.id, mode: 'heist', site: value.site, drop: value.drop,
      station: value.station, vehicleId: value.vehicleId, stage: value.stage,
      crewIds: [...new Set(Array.isArray(value.crewIds) ? value.crewIds.filter(id =>
        typeof id === 'string' && /^[0-9a-f]{32}$/.test(id)).slice(0, 3) : [])],
      started: value.started};
  }
  if (value.id === 'heist') return null;
  if (['courier', 'taxi', 'medic', 'carthief', 'trucker'].includes(value.id) && value.mode === 'route') {
    if ((value.id === 'courier' && (!Array.isArray(value.pickup) || value.pickup.length !== 2 ||
        !value.pickup.every(Number.isFinite))) ||
        (value.id !== 'courier' && !homeAt(value.pickupHome)) ||
        (value.id !== 'medic' && !homeAt(value.drop)) ||
        (value.id === 'medic' && (!Array.isArray(value.station) || value.station.length !== 3 ||
          !value.station.every(Number.isFinite) || !validMissionId(value.vehicleId))) ||
        (value.id === 'taxi' && (!Array.isArray(value.station) || value.station.length !== 3 ||
          !value.station.every(Number.isFinite) || !validMissionId(value.vehicleId))) ||
        (value.id === 'carthief' && !validMissionId(value.vehicleId)) ||
        (value.id === 'trucker' && (!validMissionId(value.vehicleId) ||
          !Array.isArray(value.station) || value.station.length !== 3 ||
          !value.station.every(Number.isFinite))) ||
        !['pickup', 'delivery'].includes(value.stage)) return null;
    return {id: value.id, mode: 'route',
      ...(value.id === 'courier' ? {pickup: value.pickup} : {pickupHome: value.pickupHome}),
      ...(value.id === 'medic' ? {station: value.station, vehicleId: value.vehicleId} : {drop: value.drop}),
      ...(value.id === 'taxi' ? {station: value.station, vehicleId: value.vehicleId,
        model: taxiCab(value.model)?.model || 420,
        shiftFares: Math.max(0, Math.min(999, Math.floor(finite(value.shiftFares)))),
        pickedUpAt: value.stage === 'delivery' && Number.isFinite(value.pickedUpAt) ?
          Math.max(value.started, value.pickedUpAt) : null,
        minHealth: Math.max(0, Math.min(1000, finite(value.minHealth, 1000))),
        reportedHealth: value.reportedHealth === true} : {}),
      ...(value.id === 'carthief' ? {vehicleId: value.vehicleId} : {}),
      ...(value.id === 'trucker' ? {vehicleId: value.vehicleId, station: value.station,
        bonusAwarded: value.bonusAwarded === true} : {}),
      stage: value.stage, started: value.started};
  }
  if (value.id === 'mechanic' && value.mode === 'service') {
    if (!homeAt(value.targetHome) || !validMissionId(value.vehicleId)) return null;
    return {id: value.id, mode: 'service', targetHome: value.targetHome,
      vehicleId: value.vehicleId,
      repairStep: Number.isInteger(value.repairStep) && value.repairStep >= 0 &&
        value.repairStep <= MECHANIC_STAGES.length ? value.repairStep : 0,
      repairProgress: Math.max(0, Math.min(MECHANIC_STAGE_MS - 1,
        finite(value.repairProgress))),
      started: value.started};
  }
  if (['trial', 'patrol', 'pizza'].includes(value.id) && value.mode === 'checkpoints') {
    if (!Array.isArray(value.points) || value.points.length !== 3 ||
        !value.points.every(homeAt) || new Set(value.points).size !== 3 ||
        !Number.isInteger(value.index) || value.index < 0 || value.index > 2 ||
        (['patrol', 'pizza'].includes(value.id) && (!validMissionId(value.vehicleId) ||
          !Array.isArray(value.station) || value.station.length !== 3 ||
          !value.station.every(Number.isFinite)))) return null;
    return {id: value.id, mode: 'checkpoints', points: value.points,
      index: value.index, started: value.started,
      ...(['patrol', 'pizza'].includes(value.id) ?
        {vehicleId: value.vehicleId, station: value.station} : {})};
  }
  const goal = JOBS.find(job => job.id === value.id).distance;
  return {id: value.id, goal, progress: Math.max(0, Math.min(goal,
    finite(value.progress))), started: value.started};
}

class LocalGame {
  get requiresJoinCode() { return !!JOIN_CODE; }

  constructor() {
    this.discord = new OptionalDiscord(discordConfig);
    this.players = new Map();
    this.peers = new Set();
    this.vehicles = new Map();
    this.nextVehicle = 1;
    this.race = null;
    this.parties = new Map();
    this.partyInvites = new Map();
    this.chat = [];
    this.chatSequence = 0;
    this.nextNumber = 1;
    this.lastPoliceTick = 0;
    this.lastTurfTick = 0;
    this.territories = Object.fromEntries(TURFS.map(id => [id, null]));
    this.turfCaptures = new Map();
    try {
      const data = JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
      for (const id of TURFS) if (GANGS.some(gang => gang.id === data.territories?.[id]))
        this.territories[id] = data.territories[id];
      for (const [id, value] of Object.entries(data.players || {})) {
        if (!/^[0-9a-f]{32}$/.test(id)) continue;
        const cars = Array.isArray(value.cars) ? value.cars.filter(car =>
          CAR_CATALOG.some(item => item.model === car)).slice(0, 12) : [];
        this.players.set(id, {number: this.nextNumber++, name: safeName(value.name) || 'Local player',
          cash: money(value.cash), xp: money(value.xp), jobsDone: money(value.jobsDone),
          pilotFlights: money(value.pilotFlights), pilotStreak:
            value.job?.id === 'pilot' && !savedJob(value.job) ? 0 : money(value.pilotStreak),
          taxiFares: money(value.taxiFares), taxiStreak: money(value.taxiStreak),
          taxiLastFareAt: Math.max(0, finite(value.taxiLastFareAt)),
          heistCooldownUntil: Math.max(0, finite(value.heistCooldownUntil)),
          racesFinished: money(value.racesFinished), racesWon: money(value.racesWon),
          health: Math.max(1, Math.min(100, Math.round(finite(value.health, 100)))),
          armour: Math.max(0, Math.min(100, Math.round(finite(value.armour)))),
          wanted: Math.max(0, Math.min(6, Math.round(finite(value.wanted)))),
          wantedUntil: finite(value.wantedUntil), passive: value.passive === true,
          passiveWaitUntil: finite(value.passiveWaitUntil),
          kills: money(value.kills), deaths: money(value.deaths), arrests: money(value.arrests),
          policeDuty: savedJob(value.job)?.id === 'patrol',
          gang: GANGS.some(gang => gang.id === value.gang) ? value.gang : null,
          gangSwitchUntil: finite(value.gangSwitchUntil), turfCaptures: money(value.turfCaptures),
          discoveries: [...new Set(Array.isArray(value.discoveries) ?
            value.discoveries.filter(id => DISCOVERY_IDS.includes(id)) : [])],
          trackedDiscovery: DISCOVERY_IDS.includes(value.trackedDiscovery) ?
            value.trackedDiscovery : null,
          supplies: savedSupplies(value.supplies),
          cars, garage: savedGarage(value.garage, cars),
          homes: Array.isArray(value.homes) ? value.homes.filter(home => HOME_CATALOG.some(item => item.id === home)).slice(0, 32) : [],
          job: savedJob(value.job),
          discord: value.discord && /^\d{17,22}$/.test(String(value.discord.id || '')) ?
            {id: String(value.discord.id), name: safeName(value.discord.name) || 'Discord player',
              bonusClaimed: value.discord.bonusClaimed === true} : null,
          settings: value.settings && typeof value.settings === 'object' ? value.settings : {}});
      }
    } catch (error) { if (error.code !== 'ENOENT') console.error('Could not load local players:', error.message); }
    for (const player of this.players.values()) {
      for (let slot = 0; slot < player.garage.length; slot++)
        if (player.garage[slot].active) this.addOwnedVehicle(player, slot);
      if (player.job?.vehicleId) this.addMissionVehicle(player);
    }
    this.saveTimer = null;
    this.tick = setInterval(() => this.broadcastPositions(), 200);
    this.tick.unref();
  }

  save() {
    if (this.saveTimer) return;
    this.saveTimer = setTimeout(() => {
      this.saveTimer = null;
      try { this.flushSync(); }
      catch (error) { console.error('Could not save local players:', error.message); }
    }, 300);
    this.saveTimer.unref();
  }

  flushSync() {
    if (this.saveTimer) {clearTimeout(this.saveTimer); this.saveTimer = null;}
    const players = Object.fromEntries([...this.players].map(([id, p]) =>
      [id, {name: p.name, cash: p.cash, xp: p.xp, jobsDone: p.jobsDone,
        pilotFlights: p.pilotFlights, pilotStreak: p.pilotStreak,
        taxiFares: p.taxiFares, taxiStreak: p.taxiStreak,
        taxiLastFareAt: p.taxiLastFareAt,
        heistCooldownUntil: p.heistCooldownUntil,
        racesFinished: p.racesFinished, racesWon: p.racesWon,
        health: p.health, armour: p.armour, wanted: p.wanted,
        wantedUntil: p.wantedUntil, passive: p.passive,
        passiveWaitUntil: p.passiveWaitUntil,
        kills: p.kills, deaths: p.deaths, arrests: p.arrests,
        gang: p.gang, gangSwitchUntil: p.gangSwitchUntil, turfCaptures: p.turfCaptures,
        discoveries: p.discoveries, trackedDiscovery: p.trackedDiscovery,
        supplies: p.supplies,
        cars: p.cars, garage: p.garage, homes: p.homes, job: p.job,
        discord: p.discord, settings: p.settings}]));
    fs.mkdirSync(path.dirname(STATE_FILE), {recursive: true});
    fs.writeFileSync(STATE_FILE + '.partial', JSON.stringify({version: 1,
      territories: this.territories, players}, null, 2) + '\n', {mode: 0o600});
    fs.renameSync(STATE_FILE + '.partial', STATE_FILE);
  }

  ensurePlayer(req, res) {
    let id = cookieId(req);
    if (!id || !this.players.has(id)) {
      id = crypto.randomBytes(16).toString('hex');
      this.players.set(id, {number: this.nextNumber++, name: `Local ${this.nextNumber - 1}`,
        cash: 0, xp: 0, jobsDone: 0, pilotFlights: 0, pilotStreak: 0,
        taxiFares: 0, taxiStreak: 0, taxiLastFareAt: 0,
        heistCooldownUntil: 0,
        racesFinished: 0, racesWon: 0,
        health: 100, armour: 0, wanted: 0, wantedUntil: 0, passive: false,
        passiveWaitUntil: 0, kills: 0, deaths: 0, arrests: 0, policeDuty: false,
        gang: null, gangSwitchUntil: 0, turfCaptures: 0,
        discoveries: [], trackedDiscovery: null,
        supplies: savedSupplies(),
        cars: [], garage: [], homes: [], job: null,
        discord: null, settings: {}});
      this.save();
    }
    const secure = req.headers['x-forwarded-proto'] === 'https' ? '; Secure' : '';
    if (res) res.setHeader('Set-Cookie',
      `${COOKIE}=${id}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${COOKIE_MAX_AGE}${secure}`);
    return {id, player: this.players.get(id)};
  }

  authorized(req) {
    if (!JOIN_CODE) return true;
    const remote = req.socket.remoteAddress;
    const localSocket = remote === '127.0.0.1' || remote === '::1' || remote === '::ffff:127.0.0.1';
    const localHost = /^((127\.0\.0\.1)|(localhost)):\d+$/.test(req.headers.host || '');
    // A local reverse proxy is still a remote visitor. Do not let a rewritten
    // loopback Host header bypass the access code.
    if (localSocket && localHost && !req.headers['x-forwarded-for'] &&
        !req.headers['x-forwarded-proto']) return true;
    const match = /(?:^|;\s*)zgta_access=([0-9a-f]{64})(?:;|$)/.exec(req.headers.cookie || '');
    return !!match && crypto.timingSafeEqual(Buffer.from(match[1], 'hex'), Buffer.from(ACCESS_TOKEN, 'hex'));
  }

  position(player) {
    const peer = [...this.peers].find(item => item.player === player && item.ready &&
      Date.now() - item.lastSeen < 10000 && item.state &&
      (item.state.walking === true || item.state.driving === true) &&
      Number.isFinite(item.state.x) && Number.isFinite(item.state.y));
    return peer ? {x: peer.state.x, y: peer.state.y,
      z: finite(peer.state.z, 13), peer} : null;
  }

  partyOf(player) {
    return [...this.parties.values()].find(party => party.members.has(player)) || null;
  }

  partyView(player) {
    const party = this.partyOf(player);
    const invite = this.partyInvites.get(player);
    if (invite && (Date.now() >= invite.expires ||
        !this.parties.get(invite.partyId)?.members.has(invite.from)))
      this.partyInvites.delete(player);
    const activeInvite = this.partyInvites.get(player);
    return {you: player.number, group: party ? {id: party.id, leader: party.leader.name,
      leaderNumber: party.leader.number,
      isLeader: party.leader === player,
      members: [...party.members].map(member => ({number: member.number,
        name: member.name, online: [...this.peers].some(peer => peer.ready && peer.player === member)}))} : null,
    invite: activeInvite ? {from: activeInvite.from.name,
      secondsLeft: Math.max(0, Math.ceil((activeInvite.expires - Date.now()) / 1000))} : null,
    candidates: [...this.peers].filter(peer => peer.ready && peer.player !== player &&
      !this.partyOf(peer.player)).map(peer => ({number: peer.player.number,
      name: peer.player.name}))};
  }

  leaveParty(player) {
    const party = this.partyOf(player);
    if (!party) return false;
    party.members.delete(player);
    this.partyInvites.delete(player);
    for (const [target, invite] of this.partyInvites)
      if (invite.from === player) this.partyInvites.delete(target);
    if (party.members.size === 0) {
      this.parties.delete(party.id);
      for (const [target, invite] of this.partyInvites)
        if (invite.partyId === party.id) this.partyInvites.delete(target);
    } else {
      if (party.leader === player) party.leader = party.members.values().next().value;
      for (const member of party.members) this.note(member,
        `${player.name} left the group. ${party.leader.name} is the leader.`);
    }
    return true;
  }

  removeRaceCar(member) {
    if (!member?.carId || !this.vehicles.delete(member.carId)) return;
    for (const peer of this.peers) if (peer.ready) peer.send({t: 'vgone', id: member.carId});
    member.carId = null;
  }

  finishRaceIfDone() {
    const race = this.race;
    if (!race || race.stage !== 'running' ||
        [...race.members.values()].some(member => !member.finishedAt && !member.left)) return;
    race.stage = 'finished';
    race.finishedAt = Date.now();
    for (const member of race.members.values()) this.removeRaceCar(member);
    for (const player of race.members.keys()) this.note(player, 'The multiplayer race has ended. Results are in F6.');
  }

  expireRace() {
    const race = this.race;
    if (!race) return;
    if (race.stage === 'lobby' && Date.now() - race.created > 600000) {
      this.race = null;
    } else if (race.stage === 'running' && Date.now() - race.started > MULTIPLAYER_RACE_MS) {
      for (const member of race.members.values()) if (!member.finishedAt) {
        member.left = true;
        this.removeRaceCar(member);
      }
      this.finishRaceIfDone();
    }
  }

  raceView(player, pos) {
    this.expireRace();
    const race = this.race;
    if (!race) return null;
    const member = race.members.get(player);
    const home = member && race.stage === 'running' && !member.finishedAt && !member.left ?
      homeAt(race.points[member.index]) : null;
    const target = home ? {x: rounded(home.out[0]), y: rounded(home.out[1]), name: home.name} : null;
    return {stage: race.stage, started: race.started, host: race.host.name, isHost: race.host === player,
      joined: !!member, start: {x: race.start[0], y: race.start[1]},
      startDistance: pos ? Math.ceil(Math.hypot(pos.x - race.start[0], pos.y - race.start[1])) : null,
      players: [...race.members].map(([racer, entry]) => ({name: racer.name,
        status: entry.finishedAt ? `#${entry.place}` : entry.left ? 'DNF' :
          race.stage === 'lobby' ? 'ready' : 'racing'})),
      index: home ? member.index + 1 : null, total: race.points.length,
      target, remaining: target && pos ? Math.ceil(Math.hypot(pos.x - target.x, pos.y - target.y)) : null,
      radius: MISSION_RADIUS,
      secondsLeft: race.stage === 'running' ?
        Math.max(0, Math.ceil((MULTIPLAYER_RACE_MS - (Date.now() - race.started)) / 1000)) : null,
      results: race.results.map(result => ({name: result.name, place: result.place,
        seconds: result.seconds, pay: result.pay}))};
  }

  wantedPacket(player) {
    return {t: 'wanted', l: player.wanted, p: 0, h: player.wanted, s: null};
  }

  setWanted(player, level) {
    player.wanted = Math.max(0, Math.min(6, Math.round(level)));
    if (player.wanted > 0) player.policeDuty = false;
    player.wantedUntil = player.wanted ? Date.now() + WANTED_DECAY_MS : 0;
    for (const peer of this.peers) if (peer.ready && peer.player === player)
      peer.send(this.wantedPacket(player));
    this.save();
  }

  policeTick() {
    const now = Date.now();
    if (now - this.lastPoliceTick < 5000) return;
    this.lastPoliceTick = now;
    for (const player of this.players.values())
      if (player.wanted > 0 && now > player.wantedUntil)
        this.setWanted(player, player.wanted - 1);
  }

  turfTick() {
    const now = Date.now();
    if (now - this.lastTurfTick < 1000) return;
    this.lastTurfTick = now;
    for (const [id, capture] of this.turfCaptures) {
      const home = homeAt(id);
      const leader = this.position(capture.player);
      if (!home || !leader || leader.peer.state.walking !== true ||
          capture.player.health <= 0 || capture.player.passive ||
          capture.player.gang !== capture.gang ||
          Math.hypot(leader.x - home.out[0], leader.y - home.out[1]) > 20) {
        this.turfCaptures.delete(id);
        this.note(capture.player, `${home?.name || id} capture cancelled.`);
        continue;
      }
      const contested = [...this.peers].some(peer => peer.ready &&
        peer.player.gang && peer.player.gang !== capture.gang &&
        peer.player.health > 0 && !peer.player.passive && (() => {
          const at = this.position(peer.player);
          return at && Math.hypot(at.x - home.out[0], at.y - home.out[1]) <= 25;
        })());
      capture.contested = contested;
      if (contested) {capture.lastTick = now; continue;}
      capture.progress += Math.max(0, Math.min(1500, now - capture.lastTick));
      capture.lastTick = now;
      if (capture.progress < TURF_CAPTURE_MS) continue;
      this.turfCaptures.delete(id);
      this.territories[id] = capture.gang;
      const rewarded = new Set();
      for (const peer of this.peers) {
        const player = peer.player;
        const at = this.position(player);
        if (!peer.ready || !at || rewarded.has(player) || player.gang !== capture.gang ||
            Math.hypot(at.x - home.out[0], at.y - home.out[1]) > 25) continue;
        rewarded.add(player);
        player.cash = money(player.cash + 200);
        player.xp = money(player.xp + 40);
        player.turfCaptures = money(player.turfCaptures + 1);
        this.updatePlayer(player);
        this.note(player, `${home.name} captured for ${GANGS.find(gang => gang.id === capture.gang).name}: +$200, +40 XP.`);
      }
      this.save();
      for (const peer of this.peers) if (peer.ready)
        peer.send({t: 'note', text: `${home.name} is now controlled by ${GANGS.find(gang => gang.id === capture.gang).name}.`});
    }
  }

  handleShot(peer, message) {
    const point = value => Array.isArray(value) && value.length === 3 &&
      value.every(Number.isFinite) && value.every(n => Math.abs(n) <= 10000);
    const position = this.position(peer.player);
    if (!Number.isInteger(message.w) || message.w < 0 || message.w > 46 ||
        !point(message.o) || !point(message.h) || !position ||
        peer.player.passive) return;
    if (Math.hypot(message.o[0] - position.x, message.o[1] - position.y,
      message.o[2] - position.z) > 15 ||
      Math.hypot(message.h[0] - message.o[0], message.h[1] - message.o[1],
        message.h[2] - message.o[2]) > 200) return;
    const now = Date.now();
    if (now - (peer.lastShotAt || 0) < 70) return;
    peer.lastShotAt = now;
    peer.lastWeapon = message.w;
    peer.lastShotHit = message.h;
    const shot = {t: 'shot', from: String(peer.player.number), w: message.w,
      o: message.o, h: message.h, ht: Number.isInteger(message.ht) ?
        Math.max(0, Math.min(10, message.ht)) : 0};
    if (typeof message.id === 'string' && message.id.length <= 64) shot.id = message.id;
    if (Number.isInteger(message.bp)) shot.bp = message.bp;
    for (const other of this.peers) if (other !== peer && other.ready) other.send(shot);
  }

  handleHit(peer, message) {
    const target = [...this.peers].find(other => other.ready &&
      String(other.player.number) === message.to);
    const from = this.position(peer.player);
    const to = target && this.position(target.player);
    if (!from || !to || !target || target === peer ||
        peer.player.passive || target.player.passive || target.player.health <= 0) return;
    const weapon = Date.now() - (peer.lastShotAt || 0) <= 2000 ? peer.lastWeapon :
      Number.isInteger(peer.state?.weapon) ? peer.state.weapon : 0;
    const damage = WEAPON_DAMAGE[weapon];
    if (!damage) return;
    const distance = Math.hypot(from.x - to.x, from.y - to.y);
    const gun = weapon >= 22;
    if (distance > (gun ? 90 : 4) ||
        (gun && (Date.now() - (peer.lastShotAt || 0) > 2000 || peer.lastWeapon !== weapon ||
          !peer.lastShotHit || Math.hypot(peer.lastShotHit[0] - to.x,
            peer.lastShotHit[1] - to.y, peer.lastShotHit[2] - to.z) > 8))) return;
    const now = Date.now();
    if (now - (peer.lastHitAt || 0) < (gun ? 90 : 300)) return;
    peer.lastHitAt = now;
    const victim = target.player;
    const absorbed = Math.min(victim.armour, damage);
    victim.armour -= absorbed;
    victim.health = Math.max(0, victim.health - (damage - absorbed));
    target.send({t: 'hit', from: String(peer.player.number), w: weapon, d: damage});
    this.setWanted(peer.player, Math.max(1, peer.player.wanted + 1));
    if (victim.health === 0) {
      victim.deaths = money(victim.deaths + 1);
      victim.lastDeath = now;
      victim.policeDuty = false;
      this.abortHeist(victim, 'you were defeated');
      peer.player.kills = money(peer.player.kills + 1);
      const feed = {t: 'kill', vn: victim.name, kn: peer.player.name,
        v: String(peer.player.number), w: weapon};
      for (const other of this.peers) if (other.ready) other.send(feed);
      this.note(victim, 'You were defeated. Respawn to rejoin the world.');
    }
    this.save();
  }

  gameplayState(player) {
    const pos = this.position(player);
    const nearHangar = nearestHangar(pos);
    const active = player.job;
    let objective = null;
    if (active?.mode === 'route') {
      const pickupHome = active.id === 'courier' ? null : homeAt(active.pickupHome);
      const dropHome = active.id === 'medic' ? null : homeAt(active.drop);
      const target = active.stage === 'pickup' ?
        (active.id === 'courier' ? active.pickup : pickupHome?.out) :
        (active.id === 'medic' ? active.station : dropHome?.out);
      if (target) objective = {mode: 'route', stage: active.stage,
        target: {x: rounded(target[0]), y: rounded(target[1]),
          name: active.stage === 'pickup' ? (pickupHome?.name || 'Package pickup') :
            (dropHome?.name || 'Aid station')},
        remaining: pos ? Math.ceil(Math.hypot(pos.x - target[0], pos.y - target[1])) : null,
        radius: MISSION_RADIUS,
        ...(['carthief', 'trucker'].includes(active.id) ? {secondsLeft:
          Math.max(0, Math.ceil(((active.id === 'trucker' ? TRUCKER_MS : CAR_THEFT_MS) -
            (Date.now() - active.started)) / 1000))} : {})};
    } else if (active?.mode === 'flight') {
      const from = airportAt(active.from);
      const to = airportAt(active.to);
      const aircraft = pilotAircraft(active.model || 593);
      if (from && to) objective = {mode: 'flight', stage: active.stage,
        from: from.name, plane: aircraft?.name || 'Dodo', model: aircraft?.model || 593,
        target: {x: rounded(to.runway[0]), y: rounded(to.runway[1]), name: to.name},
        remaining: pos ? Math.ceil(Math.hypot(pos.x - to.runway[0], pos.y - to.runway[1])) : null,
        altitude: pos ? Math.max(0, Math.round(pos.z - from.runway[2])) : null,
        takeoffAltitude: 35, radius: aircraft?.radius || 70,
        smoothEligible: active.reportedHealth && active.minHealth >= 950,
        earlyEligible: PILOT_MS - (Date.now() - active.started) >= 120000,
        landingReady: !!active.landingSince && Date.now() - active.landingSince >= 2000,
        landingSeconds: active.landingSince ? Math.max(0,
          Math.ceil((2000 - (Date.now() - active.landingSince)) / 1000)) : 2,
        secondsLeft: Math.max(0, Math.ceil((PILOT_MS -
          (Date.now() - active.started)) / 1000))};
    } else if (active?.mode === 'fire') {
      const home = homeAt(active.incidentHome);
      const target = active.stage === 'extinguish' ? fireSpot(active) : home?.out;
      if (target) objective = {mode: 'fire', stage: active.stage,
        target: {x: rounded(target[0]), y: rounded(target[1]),
          name: `${active.stage === 'extinguish' ? `Fire ${active.index + 1} near` :
            active.stage === 'rescue' ? 'Rescue near' : 'Fire call near'} ${home.name}`},
        remaining: pos ? Math.ceil(Math.hypot(pos.x - target[0], pos.y - target[1])) : null,
        radius: active.stage === 'respond' ? 25 : active.stage === 'rescue' ? 10 : 8,
        index: active.index, total: FIRE_OFFSETS.length,
        secondsLeft: Math.max(0, Math.ceil((FIRE_MS -
          (Date.now() - active.started)) / 1000))};
    } else if (active?.mode === 'heist') {
      const home = homeAt(active.stage === 'plan' ? active.site : active.drop);
      if (home) objective = {mode: 'heist', stage: active.stage,
        target: {x: rounded(home.out[0]), y: rounded(home.out[1]),
          name: `${active.stage === 'plan' ? 'Robbery site' : 'Drop-off'} near ${home.name}`},
        remaining: pos ? Math.ceil(Math.hypot(pos.x - home.out[0],
          pos.y - home.out[1])) : null, radius: MISSION_RADIUS,
        wanted: player.wanted, crewBonus: HEIST_CREW_BONUS,
        crewCount: active.crewIds?.length || 0,
        secondsLeft: Math.max(0, Math.ceil((HEIST_MS -
          (Date.now() - active.started)) / 1000))};
    } else if (active?.mode === 'service') {
      const home = homeAt(active.targetHome);
      const vehicle = this.vehicles.get(active.vehicleId);
      const target = vehicle?.row || home?.out;
      if (target) {
        const x = vehicle ? target[3] : target[0], y = vehicle ? target[4] : target[1];
        objective = {mode: 'service', stage: 'repair',
          target: {x: rounded(x), y: rounded(y), name: `Roadside call near ${home.name}`},
          remaining: pos ? Math.ceil(Math.hypot(pos.x - x, pos.y - y)) : null,
          radius: 8, repairStep: active.repairStep || 0,
          repairTotal: MECHANIC_STAGES.length,
          repairPart: MECHANIC_STAGES[active.repairStep || 0] || 'finishing',
          repairProgress: Math.floor(100 * (active.repairProgress || 0) / MECHANIC_STAGE_MS)};
      }
    } else if (active?.mode === 'checkpoints') {
      const home = homeAt(active.points[active.index]);
      if (home) objective = {mode: 'checkpoints', stage: 'checkpoint',
        target: {x: rounded(home.out[0]), y: rounded(home.out[1]), name: home.name},
        remaining: pos ? Math.ceil(Math.hypot(pos.x - home.out[0], pos.y - home.out[1])) : null,
        radius: MISSION_RADIUS, index: active.index + 1, total: active.points.length,
        secondsLeft: Math.max(0, Math.ceil(((active.id === 'patrol' ? PATROL_MS :
          active.id === 'pizza' ? PIZZA_MS : TIME_TRIAL_MS) -
          (Date.now() - active.started)) / 1000))};
    }
    const suspects = player.policeDuty && pos ? [...this.peers]
      .filter(peer => peer.ready && peer.player !== player && peer.player.wanted > 0)
      .map(peer => ({player: peer.player, at: this.position(peer.player)}))
      .filter(item => item.at && Math.hypot(pos.x - item.at.x, pos.y - item.at.y) <= 30)
      .map(item => ({number: item.player.number, name: item.player.name,
        wanted: item.player.wanted,
        distance: Math.ceil(Math.hypot(pos.x - item.at.x, pos.y - item.at.y))})) : [];
    const nearbyPlayers = pos ? [...this.peers]
      .filter(peer => peer.ready && peer.player !== player)
      .map(peer => ({player: peer.player, at: this.position(peer.player)}))
      .filter(item => item.at && Math.hypot(pos.x - item.at.x, pos.y - item.at.y) <= 15)
      .map(item => ({number: item.player.number, name: item.player.name,
        distance: Math.ceil(Math.hypot(pos.x - item.at.x, pos.y - item.at.y)),
        onFoot: item.at.peer.state.walking === true})) : [];
    const leaderboard = [...this.players.values()].filter(entry => entry.xp > 0 ||
      [...this.peers].some(peer => peer.ready && peer.player === entry))
      .sort((a, b) => b.xp - a.xp ||
      b.jobsDone - a.jobsDone || a.number - b.number).slice(0, 10)
      .map((entry, index) => ({place: index + 1, name: entry.name, xp: entry.xp,
        jobsDone: entry.jobsDone, racesWon: entry.racesWon || 0,
        turfCaptures: entry.turfCaptures || 0}));
    const raceLeaders = [...this.players.values()]
      .filter(entry => (entry.racesFinished || 0) > 0)
      .sort((a, b) => (b.racesWon || 0) - (a.racesWon || 0) ||
        b.racesFinished - a.racesFinished || a.number - b.number)
      .slice(0, 10)
      .map((entry, index) => ({place: index + 1, name: entry.name,
        wins: entry.racesWon || 0, finishes: entry.racesFinished}));
    const turfs = TURFS.map(id => {
      const home = homeAt(id);
      if (!home) return null;
      const capture = this.turfCaptures.get(id);
      return {id, name: home.name, x: rounded(home.out[0]), y: rounded(home.out[1]),
        owner: this.territories[id], capturing: capture?.gang || null,
        capturingYou: capture?.player === player,
        progress: capture ? Math.floor(100 * capture.progress / TURF_CAPTURE_MS) : 0,
        contested: capture?.contested || false,
        distance: pos ? Math.ceil(Math.hypot(pos.x - home.out[0], pos.y - home.out[1])) : null};
    }).filter(Boolean);
    const discoveries = DISCOVERY_IDS.map(id => {
      const home = homeAt(id);
      if (!home) return null;
      return {id, name: home.name, city: home.city,
        x: rounded(home.out[0]), y: rounded(home.out[1]),
        found: player.discoveries.includes(id),
        distance: pos ? Math.ceil(Math.hypot(pos.x - home.out[0], pos.y - home.out[1])) : null};
    }).filter(Boolean);
    const tracked = discoveries.find(item => item.id === player.trackedDiscovery && !item.found) || null;
    const nearDealer = nearestGroundDealer(pos);
    const nearHome = pos ? player.homes.map(homeAt).filter(Boolean)
      .sort((a, b) => Math.hypot(pos.x - a.out[0], pos.y - a.out[1]) -
        Math.hypot(pos.x - b.out[0], pos.y - b.out[1]))[0] : null;
    return {name: player.name, cash: player.cash, xp: player.xp, jobsDone: player.jobsDone,
      pilot: {flights: player.pilotFlights || 0, streak: player.pilotStreak || 0,
        level: pilotLevel(player),
        aircraft: PILOT_AIRCRAFT.map(item => ({...item,
          unlocked: pilotLevel(player) >= item.level})),
        smoothBonus: PILOT_SMOOTH_BONUS, earlyBonus: PILOT_EARLY_BONUS,
        fifthBonus: PILOT_STREAK_BONUS},
      taxi: {fares: player.taxiFares || 0, streak: player.taxiStreak || 0,
        level: taxiLevel(player), cabs: TAXI_CABS.map(item => ({model: item.model,
          name: item.name, level: item.level, premium: item.premium,
          unlocked: taxiLevel(player) >= item.level})),
        cleanBonus: TAXI_CLEAN_BONUS, quickBonus: TAXI_QUICK_BONUS,
        streakBonus: TAXI_STREAK_BONUS},
      heistCooldown: Math.max(0, Math.ceil(((player.heistCooldownUntil || 0) -
        Date.now()) / 1000)),
      racesFinished: player.racesFinished || 0, racesWon: player.racesWon || 0,
      health: player.health, armour: player.armour, wanted: player.wanted,
      passive: player.passive, passiveWait: Math.max(0,
        Math.ceil((player.passiveWaitUntil - Date.now()) / 1000)),
      kills: player.kills, deaths: player.deaths, arrests: player.arrests,
      policeDuty: player.policeDuty, nearbyWanted: suspects,
      nearbyPlayers, leaderboard, raceLeaders,
      supplies: {...player.supplies},
      party: this.partyView(player),
      gang: player.gang, gangSwitchWait: Math.max(0,
        Math.ceil((player.gangSwitchUntil - Date.now()) / 1000)),
      turfCaptures: player.turfCaptures, gangs: GANGS, turfs,
      exploration: {found: player.discoveries.length, total: discoveries.length,
        tracked, items: discoveries, reward: DISCOVERY_PAY, finishReward: DISCOVERY_FINISH_PAY},
      discord: {available: this.discord.enabled, linked: !!player.discord,
        name: player.discord?.name || null, bonus: DISCORD_BONUS},
      connected: !!pos, position: pos ? {x: rounded(pos.x), y: rounded(pos.y)} : null,
      hangar: nearHangar ? {
        id: nearHangar.id, name: nearHangar.name,
        distance: Math.ceil(Math.hypot(pos.x - nearHangar.stand[0],
          pos.y - nearHangar.stand[1])),
        within: !!hangarFor(pos), x: nearHangar.stand[0],
        y: nearHangar.stand[1]} : null,
      dealer: nearDealer ? {id: nearDealer.id, name: nearDealer.name,
        distance: Math.ceil(Math.hypot(pos.x - nearDealer.stand[0],
          pos.y - nearDealer.stand[1])),
        within: Math.hypot(pos.x - nearDealer.stand[0],
          pos.y - nearDealer.stand[1]) <= 100,
        x: nearDealer.stand[0], y: nearDealer.stand[1]} : null,
      homeParking: nearHome ? {id: nearHome.id, name: nearHome.name,
        distance: Math.ceil(Math.hypot(pos.x - nearHome.out[0], pos.y - nearHome.out[1])),
        within: Math.hypot(pos.x - nearHome.out[0], pos.y - nearHome.out[1]) <= 25,
        occupied: player.garage.filter(entry => entry.parkedHome === nearHome.id).length,
        capacity: 2} : null,
      job: active ? {id: active.id, name: JOBS.find(job => job.id === active.id)?.name,
        vehicleId: active.vehicleId || null,
        inMarkedVehicle: !!(active.vehicleId && pos?.peer.state.driving === true &&
          pos.peer.state.vehicle === active.vehicleId),
        ...(objective || {goal: active.goal, progress: Math.floor(active.progress),
          remaining: Math.max(0, Math.ceil(active.goal - active.progress))}),
        ...(active.id === 'taxi' ? {fare: {base: 300,
          cab: taxiCab(active.model)?.name || 'Taxi',
          cabPremium: taxiCab(active.model)?.premium || 0,
          shiftFares: active.shiftFares || 0,
          cleanBonus: TAXI_CLEAN_BONUS, quickBonus: TAXI_QUICK_BONUS,
          quickSeconds: Math.ceil(taxiQuickWindow(active) / 1000),
          rideSeconds: active.pickedUpAt ? Math.max(0,
            Math.ceil((Date.now() - active.pickedUpAt) / 1000)) : 0,
          cleanEligible: active.reportedHealth === true &&
            active.minHealth >= 950 && player.wanted === 0,
          streak: player.taxiStreak || 0,
          streakBonus: player.taxiStreak > 0 &&
            Date.now() - player.taxiLastFareAt <= TAXI_STREAK_WINDOW_MS ?
              Math.min(5, player.taxiStreak) * TAXI_STREAK_BONUS : 0}} : {}),
        ...(active.id === 'trucker' ? {convoyBonusAwarded: active.bonusAwarded === true,
          convoyBonus: CONVOY_BONUS} : {}),
        started: active.started} : null,
      cars: player.cars.map(model => CAR_CATALOG.find(car => car.model === model)).filter(Boolean),
      garage: player.garage.map((entry, slot) => {
        const vehicle = this.ownedVehicle(player, slot);
        const location = vehicle?.row || entry.position;
        const x = vehicle ? location[3] : location?.[0];
        const y = vehicle ? location[4] : location?.[1];
        return {slot, active: !!vehicle, health: entry.health, paint: entry.paint,
          parkedHome: entry.parkedHome,
          parkedHomeName: homeAt(entry.parkedHome)?.name || null,
          repairCost: repairCost(entry), resprayCost: RESPRAY_COST,
          distance: pos && x !== undefined && y !== undefined ?
            Math.ceil(Math.hypot(pos.x - x, pos.y - y)) : null};
      }),
      onFoot: pos?.peer.state.walking === true,
      driving: pos?.peer.state.driving === true,
      drivingVehicle: typeof pos?.peer.state.vehicle === 'string' ?
        pos.peer.state.vehicle : null,
      race: this.raceView(player, pos),
      homes: player.homes.map(id => HOME_CATALOG.find(home => home.id === id)).filter(Boolean),
      catalog: {jobs: JOBS,
        supplies: SUPPLIES,
        cars: CAR_CATALOG.map(car => ({model: car.model, name: car.name,
          price: car.price, type: car.type, source: car.source,
          ...(car.source === 'archived' && !isAircraft(car) ?
            {dealers: car.dealers.filter(key => GROUND_DEALERS.some(dealer => dealer.id === key))} : {}),
          ...(isAircraft(car) ? {airports: AIRPORTS.filter(airport =>
            car.dealers?.includes(airport.dealer)).map(airport => airport.id)} : {})})),
        homes: HOME_CATALOG.map(({id, name, price, city, tier, source}) =>
          ({id, name, price, city, tier, source}))}};
  }

  note(player, text) {
    for (const peer of this.peers) if (peer.player === player && peer.ready)
      peer.send({t: 'note', text});
  }

  owned(player) {
    const cars = player.cars.map(model => CAR_CATALOG.find(car => car.model === model));
    return {t: 'owned', cars: cars.map((_, slot) => this.vehicleCode(player, slot)), out: [], login: true,
      worth: cars.map(car => car.price), stored: [], locked: [],
      rep: {level: 1 + Math.floor(player.xp / 1000)}, licence: true};
  }

  vehicleCode(player, slot) {
    const car = CAR_CATALOG.find(item => item.model === player.cars[slot]);
    const paint = player.garage[slot]?.paint;
    return paint ? `${car.model}.${paint[0]}.${paint[1]}.0.` : car.car;
  }

  homeStatus(player) {
    const originalHomes = player.homes.filter(id => HOME_CATALOG.some(home =>
      home.id === id && home.source === 'archived'));
    return {t: 'home', own: originalHomes, home: originalHomes[0] || null,
      spawn: false, most: 32, cars: {}, skins: [], stash: {}, friends: [], open: [],
      login: true, cash: player.cash};
  }

  updatePlayer(player) {
    this.save();
    for (const peer of this.peers) if (peer.player === player && peer.ready) {
      peer.send({t: 'cash', cash: player.cash});
      peer.send(this.owned(player));
      peer.send(this.homeStatus(player));
    }
  }

  addMissionVehicle(player) {
    const job = player.job;
    if (!job?.vehicleId) return;
    const mechanic = job.id === 'mechanic';
    const taxi = job.id === 'taxi';
    const thief = job.id === 'carthief';
    const trucker = job.id === 'trucker';
    const pilot = job.id === 'pilot';
    const pilotCode = pilot && job.model !== 593 ?
      CAR_CATALOG.find(item => item.model === job.model)?.car : '593.1.1.0.';
    const fire = job.id === 'fire';
    const heist = job.id === 'heist';
    const patrol = job.id === 'patrol';
    const pizza = job.id === 'pizza';
    const point = mechanic ? homeAt(job.targetHome)?.out :
      thief ? homeAt(job.pickupHome)?.out : pilot ? airportAt(job.from)?.runway : job.station;
    if (!point) return;
    const id = job.vehicleId;
    const row = [id, mechanic ? 'Roadside call' : thief ? 'Getaway car' : player.name,
      mechanic ? '410.52.39.0.' : thief ? '560.52.39.0.' :
        taxi ? taxiCab(job.model)?.car || '420.6.1.0.' :
        patrol ? '596.0.1.0.' : pizza ? '448.1.1.0.' :
          trucker ? '414.25.1.0.' : pilot ? pilotCode :
            fire ? '407.3.1.0.' : heist ? '560.52.39.0.' : '416.1.1.0.',
      rounded(point[0] + (pilot ? 0 : 4)), rounded(point[1] + (pilot ? 0 : 3)),
      rounded(point[2] + 1.1), pilot ? rounded(point[3]) : 0,
      0, 0, mechanic ? 350 : thief ? 800 : 1000, '', null];
    this.vehicles.set(id, {id, owner: null, missionOwner: player, row});
    for (const peer of this.peers) if (peer.ready) peer.send({t: 'spawned', v: row});
  }

  removeMissionVehicle(player) {
    const id = player.job?.vehicleId;
    if (!id || !this.vehicles.delete(id)) return;
    for (const peer of this.peers) if (peer.ready) peer.send({t: 'vgone', id});
  }

  abortHeist(player, reason) {
    if (player.job?.id !== 'heist' || player.job.stage !== 'escape') return false;
    this.removeMissionVehicle(player);
    player.job = null;
    this.save();
    this.note(player, `Heist failed: ${reason}. The bag was lost.`);
    return true;
  }

  discordStart(req, res) {
    if (!this.discord.enabled) return json(res, 404, {error: 'Discord linking is not configured.'});
    const id = cookieId(req);
    if (!id || !this.players.has(id)) return json(res, 401, {error: 'Enter the game first.'});
    if (req.headers.host !== this.discord.redirectHost)
      return json(res, 400, {error: 'Open the game at its configured Discord sign-in address.'});
    res.writeHead(302, {Location: this.discord.start(id), 'Cache-Control': 'no-store'});
    res.end();
  }

  async discordCallback(req, res) {
    if (!this.discord.enabled || req.headers.host !== this.discord.redirectHost)
      return json(res, 400, {error: 'Discord callback is unavailable here.'});
    const id = cookieId(req);
    if (!id || !this.players.has(id))
      return json(res, 400, {error: 'The game account cookie is missing. Start Discord linking again.'});
    try {
      const url = new URL(req.url, this.discord.redirectUri);
      const identity = await this.discord.finish({state: url.searchParams.get('state'),
        code: url.searchParams.get('code'), iss: url.searchParams.get('iss'), playerId: id});
      const current = this.players.get(id);
      const existing = [...this.players].find(([, player]) => player.discord?.id === identity.id);
      let accountId = id;
      if (existing && existing[0] !== id) accountId = existing[0];
      else {
        if (current.discord && current.discord.id !== identity.id)
          throw new Error('This game account is already linked to another Discord account.');
        const bonusClaimed = current.discord?.bonusClaimed === true;
        current.discord = {id: identity.id, name: safeName(identity.name) || 'Discord player',
          bonusClaimed: true};
        if (!bonusClaimed) current.cash = money(current.cash + DISCORD_BONUS);
        this.updatePlayer(current);
        this.flushSync();
      }
      const secure = new URL(this.discord.redirectUri).protocol === 'https:' ? '; Secure' : '';
      res.writeHead(302, {Location: '/', 'Cache-Control': 'no-store',
        'Set-Cookie': `${COOKIE}=${accountId}; Path=/; HttpOnly; SameSite=Lax${secure}`});
      res.end();
    } catch (error) {
      // OAuth codes, tokens, and secrets are intentionally absent from the response.
      const html = '<!doctype html><html lang="en"><meta charset="utf-8"><title>Discord sign-in failed</title>' +
        '<body style="font:16px system-ui;padding:2rem"><h1>Discord sign-in failed</h1>' +
        '<p>Return to the game and try again. Guest play is still available.</p><a href="/">Return to game</a></body></html>';
      res.writeHead(400, {'Content-Type': 'text/html; charset=utf-8',
        'Content-Length': Buffer.byteLength(html), 'Cache-Control': 'no-store'});
      res.end(html);
    }
  }

  ownedVehicle(player, slot) {
    return [...this.vehicles.values()].find(vehicle => vehicle.owner === player && vehicle.slot === slot);
  }

  assertVehicleUnoccupied(vehicle) {
    if (vehicle && [...this.peers].some(peer => peer.ready &&
        peer.state?.vehicle === vehicle.id &&
        (peer.state.driving === true || peer.state.passenger === true)))
      throw new Error('Wait until everyone leaves this vehicle.');
  }

  removeOwnedVehicle(vehicle) {
    if (!vehicle || !this.vehicles.delete(vehicle.id)) return;
    for (const peer of this.peers) if (peer.ready) peer.send({t: 'vgone', id: vehicle.id});
  }

  addOwnedVehicle(player, slot) {
    const car = CAR_CATALOG.find(item => item.model === player.cars[slot]);
    const entry = player.garage[slot];
    if (!car || !entry?.position) return null;
    const id = `local-${this.nextVehicle++}`;
    const [x, y, z, heading] = entry.position;
    const row = [id, player.name, this.vehicleCode(player, slot), x, y, z, heading, 0, 0,
      entry.health, entry.damage, null];
    const vehicle = {id, owner: player, slot, row, lastGarageSave: 0};
    this.vehicles.set(id, vehicle);
    for (const peer of this.peers) if (peer.ready) peer.send({t: 'spawned', v: row});
    return vehicle;
  }

  updateOwnedVehicle(peer, message) {
    if (typeof message.vehicle !== 'string') return;
    const vehicle = this.vehicles.get(message.vehicle);
    if (!vehicle || vehicle.owner !== peer.player || message.car !== vehicle.row[2]) return;
    const parked = message.walking === true && message.parked &&
      typeof message.parked === 'object' ? message.parked : null;
    const driving = message.driving === true;
    const report = parked || (driving ? message : null);
    if (!report || ![report.x, report.y, report.z].every(Number.isFinite) ||
        Math.abs(report.x) > 6000 || Math.abs(report.y) > 6000 ||
        report.z < -200 || report.z > 1000) return;
    const entry = peer.player.garage[vehicle.slot];
    const before = `${entry.health}:${entry.damage}`;
    const position = [rounded(report.x), rounded(report.y), rounded(report.z),
      rounded(report.heading)];
    vehicle.row[3] = position[0]; vehicle.row[4] = position[1];
    vehicle.row[5] = position[2]; vehicle.row[6] = position[3];
    vehicle.row[7] = rounded(report.pitch); vehicle.row[8] = rounded(report.roll);
    if (Number.isFinite(report.health))
      entry.health = Math.min(entry.health,
        Math.max(0, Math.min(1000, Math.round(report.health))));
    if (typeof report.damage === 'string' && report.damage)
      entry.damage = report.damage.slice(0, 512);
    vehicle.row[9] = entry.health; vehicle.row[10] = entry.damage;
    entry.position = position;
    if (parked || before !== `${entry.health}:${entry.damage}` ||
        Date.now() - vehicle.lastGarageSave > 5000) {
      vehicle.lastGarageSave = Date.now();
      this.save();
    }
  }

  updateMissionVehicle(peer, message) {
    if (typeof message.vehicle !== 'string') return;
    const vehicle = this.vehicles.get(message.vehicle);
    if (!vehicle || vehicle.missionOwner !== peer.player ||
        message.car !== vehicle.row[2]) return;
    const parked = message.walking === true && message.parked &&
      typeof message.parked === 'object' ? message.parked : null;
    const report = parked || (message.driving === true ? message : null);
    if (!report || ![report.x, report.y, report.z].every(Number.isFinite) ||
        Math.abs(report.x) > 6000 || Math.abs(report.y) > 6000 ||
        report.z < -200 || report.z > 1000) return;
    vehicle.row[3] = rounded(report.x);
    vehicle.row[4] = rounded(report.y);
    vehicle.row[5] = rounded(report.z);
    vehicle.row[6] = rounded(report.heading);
    vehicle.row[7] = rounded(report.pitch);
    vehicle.row[8] = rounded(report.roll);
    if (Number.isFinite(report.health))
      vehicle.row[9] = Math.max(0, Math.min(1000, Math.round(report.health)));
    if (parked) for (const other of this.peers)
      if (other.ready) other.send({t: 'spawned', v: vehicle.row});
  }

  spawnOwnedCar(player, slot) {
    const pos = this.position(player);
    if (!pos) throw new Error('Enter the game before spawning a car.');
    const car = CAR_CATALOG.find(item => item.model === player.cars[slot]);
    if (!car) throw new Error('That car is not in your garage.');
    const entry = player.garage[slot];
    const parkedHome = homeAt(entry.parkedHome);
    if (parkedHome && (!player.homes.includes(parkedHome.id) ||
        Math.hypot(pos.x - parkedHome.out[0], pos.y - parkedHome.out[1]) > 25))
      throw new Error(`Go to ${parkedHome.name} to retrieve this parked vehicle.`);
    const hangar = isAircraft(car) ? hangarFor(pos, car) : null;
    if (isAircraft(car) && !hangar)
      throw new Error('Go to an airport hangar to spawn this aircraft.');
    const old = this.ownedVehicle(player, slot);
    this.assertVehicleUnoccupied(old);
    const remaining = [...this.vehicles.values()].filter(vehicle =>
      vehicle.owner === player && vehicle !== old);
    if (remaining.length >= 3) this.assertVehicleUnoccupied(remaining[0]);
    if (old) this.removeOwnedVehicle(old);
    const mine = [...this.vehicles.values()].filter(vehicle => vehicle.owner === player);
    if (mine.length >= 3) {
      const oldest = mine[0];
      player.garage[oldest.slot].active = false;
      this.removeOwnedVehicle(oldest);
    }
    // Vehicle origins sit above their tyres. Ground-height origins can embed
    // the body in the map and make the physics engine launch it on entry.
    entry.position = hangar ?
      [rounded(hangar.stand[0] + 4), rounded(hangar.stand[1] + 3),
        rounded(hangar.stand[2] + 1.1), 0] :
      [rounded(pos.x + 4), rounded(pos.y + 3), rounded(pos.z + 1.1), 0];
    entry.active = true;
    entry.parkedHome = null;
    this.addOwnedVehicle(player, slot);
    this.save();
    return `${car.name} ${parkedHome ? 'retrieved' : old ? 'recalled' : 'spawned'} at ${hangar?.name || parkedHome?.name || 'your location'}.`;
  }

  action(player, action, input) {
    const pos = this.position(player);
    let message;
    this.expireRace();
    if (action === 'explore.track') {
      if (input.id === null) {
        player.trackedDiscovery = null;
        message = 'Exploration marker cleared.';
      } else {
        const home = DISCOVERY_IDS.includes(input.id) && homeAt(input.id);
        if (!home) throw new Error('Choose a listed discovery.');
        if (player.discoveries.includes(home.id)) throw new Error('You already found this location.');
        player.trackedDiscovery = home.id;
        message = `Tracking ${home.name}. Follow the objective box.`;
      }
      this.save();
    } else if (action === 'explore.claim') {
      const id = input.id || player.trackedDiscovery;
      const home = DISCOVERY_IDS.includes(id) && homeAt(id);
      if (!home) throw new Error('Choose a listed discovery to claim.');
      if (player.discoveries.includes(id)) throw new Error('You already found this location.');
      if (!pos || pos.peer.state.walking !== true ||
          Math.hypot(pos.x - home.out[0], pos.y - home.out[1]) > MISSION_RADIUS)
        throw new Error('Stand on foot within 12 m of the marked location.');
      player.discoveries.push(id);
      if (player.trackedDiscovery === id) player.trackedDiscovery = null;
      player.cash = money(player.cash + DISCOVERY_PAY);
      player.xp = money(player.xp + DISCOVERY_XP);
      const finished = player.discoveries.length === DISCOVERY_IDS.length;
      if (finished) {
        player.cash = money(player.cash + DISCOVERY_FINISH_PAY);
        player.xp = money(player.xp + DISCOVERY_FINISH_XP);
      }
      this.updatePlayer(player);
      message = `${home.name} discovered: +$${DISCOVERY_PAY}, +${DISCOVERY_XP} XP.` +
        (finished ? ` Trail complete: +$${DISCOVERY_FINISH_PAY}, +${DISCOVERY_FINISH_XP} XP bonus.` : '');
    } else if (action === 'party.create') {
      if (this.partyOf(player)) throw new Error('You are already in a group.');
      const id = crypto.randomBytes(6).toString('hex');
      this.parties.set(id, {id, leader: player, members: new Set([player])});
      message = 'Private group created. Invite another online player from F6.';
    } else if (action === 'party.invite') {
      const target = [...this.peers].find(peer => peer.ready && peer.player !== player &&
        peer.player.number === Number(input.number));
      if (!target || this.partyOf(target.player))
        throw new Error('Choose an online player who is not already in a group.');
      if (Date.now() - (player.lastPartyInvite || 0) < 1500)
        throw new Error('Wait before sending another group invitation.');
      if (this.partyInvites.has(target.player) &&
          this.partyInvites.get(target.player).expires > Date.now())
        throw new Error('That player already has a pending invitation.');
      let party = this.partyOf(player);
      if (party && party.leader !== player) throw new Error('Only the group leader can invite players.');
      if (party && party.members.size >= PARTY_LIMIT) throw new Error('Your group is full.');
      if (!party) {
        const id = crypto.randomBytes(6).toString('hex');
        party = {id, leader: player, members: new Set([player])};
        this.parties.set(id, party);
      }
      player.lastPartyInvite = Date.now();
      this.partyInvites.set(target.player, {partyId: party.id, from: player,
        expires: Date.now() + PARTY_INVITE_MS});
      this.note(target.player, `${player.name} invited you to a private group. Open F6 or type /party accept.`);
      message = `Group invitation sent to ${target.player.name}.`;
    } else if (action === 'party.accept') {
      const invite = this.partyInvites.get(player);
      const party = invite && this.parties.get(invite.partyId);
      if (!invite || !party || !party.members.has(invite.from) ||
          Date.now() >= invite.expires)
        throw new Error('No active group invitation.');
      if (this.partyOf(player)) throw new Error('Leave your current group first.');
      if (party.members.size >= PARTY_LIMIT) throw new Error('The group is full.');
      this.partyInvites.delete(player);
      party.members.add(player);
      for (const member of party.members) this.note(member,
        `${player.name} joined the group (${party.members.size}/${PARTY_LIMIT}).`);
      message = `Joined ${party.leader.name}'s group.`;
    } else if (action === 'party.decline') {
      if (!this.partyInvites.delete(player)) throw new Error('No group invitation to decline.');
      message = 'Group invitation declined.';
    } else if (action === 'party.leave') {
      if (!this.leaveParty(player)) throw new Error('You are not in a group.');
      message = 'Left the group.';
    } else if (action === 'party.kick') {
      const party = this.partyOf(player);
      const member = party && [...party.members].find(item =>
        item !== player && item.number === Number(input.number));
      if (!party || party.leader !== player || !member)
        throw new Error('Only the leader can remove a member of this group.');
      party.members.delete(member);
      this.note(member, `${player.name} removed you from the group.`);
      for (const remaining of party.members) this.note(remaining, `${member.name} left the group.`);
      message = `${member.name} removed from the group.`;
    } else if (action === 'party.chat') {
      const party = this.partyOf(player);
      if (!party) throw new Error('Join a group to use private chat.');
      const line = String(input.text || '').trim().slice(0, 160);
      if (!line) throw new Error('Write a message first.');
      if (Date.now() - (player.lastPartyChat || 0) < 800)
        throw new Error('Wait a moment before sending another group message.');
      player.lastPartyChat = Date.now();
      for (const member of party.members) this.note(member, `[Group] ${player.name}: ${line}`);
      message = 'Group message sent.';
    } else if (action === 'money.transfer') {
      const amount = Number(input.amount);
      if (!Number.isSafeInteger(amount) || amount < 1 || amount > 1000000)
        throw new Error('Choose a whole-dollar amount from $1 to $1,000,000.');
      if (player.cash < amount) throw new Error('You do not have enough cash.');
      const target = [...this.peers].find(peer => peer.ready && peer.player !== player &&
        peer.player.number === Number(input.number));
      const at = target && this.position(target.player);
      if (!pos || !at || Math.hypot(pos.x - at.x, pos.y - at.y) > 8)
        throw new Error('The other player must be within 8 m.');
      if (target.player.cash > MAX_CASH - amount)
        throw new Error('The other player cannot receive that much cash.');
      player.cash -= amount;
      target.player.cash += amount;
      this.updatePlayer(player);
      this.updatePlayer(target.player);
      this.note(target.player, `${player.name} gave you $${amount}.`);
      message = `Gave $${amount} to ${target.player.name}.`;
    } else if (action === 'supply.buy') {
      const item = SUPPLIES.find(entry => entry.id === input.item);
      if (!item) throw new Error('Choose a listed workshop supply.');
      const dealer = nearestGroundDealer(pos);
      if (!dealer || !pos || pos.peer.state.walking !== true ||
          Math.hypot(pos.x - dealer.stand[0], pos.y - dealer.stand[1]) > 100)
        throw new Error('Visit a ground dealership on foot to buy workshop supplies.');
      if (player.supplies[item.id] >= item.capacity)
        throw new Error(`You can carry only ${item.capacity} ${item.name.toLowerCase()}s.`);
      if (player.cash < item.price) throw new Error(`You need $${item.price}.`);
      player.cash -= item.price;
      player.supplies[item.id]++;
      message = `${item.name} bought at ${dealer.name} for $${item.price}.`;
      this.updatePlayer(player);
    } else if (action === 'supply.use') {
      const item = SUPPLIES.find(entry => entry.id === input.item);
      if (!item) throw new Error('Choose a listed workshop supply.');
      if (!player.supplies[item.id]) throw new Error(`You do not have a ${item.name.toLowerCase()}.`);
      const slot = Number(input.slot);
      if (!Number.isInteger(slot) || slot < 0 || slot >= player.cars.length)
        throw new Error('Choose one of your vehicles.');
      const vehicle = this.ownedVehicle(player, slot);
      if (!vehicle || !pos || pos.peer.state.walking !== true ||
          Math.hypot(pos.x - vehicle.row[3], pos.y - vehicle.row[4]) > 18)
        throw new Error('Stand on foot within 18 m of your active vehicle.');
      this.assertVehicleUnoccupied(vehicle);
      const entry = player.garage[slot];
      const car = CAR_CATALOG.find(value => value.model === player.cars[slot]);
      if (item.id === 'repair_kit') {
        if (!repairCost(entry)) throw new Error('This vehicle does not need repairs.');
        entry.health = 1000;
        entry.damage = '';
      } else {
        const previous = this.vehicleCode(player, slot);
        do entry.paint = [crypto.randomInt(128), crypto.randomInt(128)];
        while (this.vehicleCode(player, slot) === previous);
      }
      player.supplies[item.id]--;
      this.removeOwnedVehicle(vehicle);
      this.addOwnedVehicle(player, slot);
      message = `${item.name} used on ${car.name}.`;
      this.updatePlayer(player);
    } else if (action === 'supply.give') {
      const item = SUPPLIES.find(entry => entry.id === input.item);
      if (!item) throw new Error('Choose a listed workshop supply.');
      if (!player.supplies[item.id]) throw new Error(`You do not have a ${item.name.toLowerCase()}.`);
      const target = [...this.peers].find(peer => peer.ready && peer.player !== player &&
        peer.player.number === Number(input.number));
      const at = target && this.position(target.player);
      if (!pos || pos.peer.state.walking !== true || !at ||
          at.peer.state.walking !== true ||
          Math.hypot(pos.x - at.x, pos.y - at.y) > 8)
        throw new Error('Both players must stand on foot within 8 m.');
      if (target.player.supplies[item.id] >= item.capacity)
        throw new Error(`${target.player.name} cannot carry another ${item.name.toLowerCase()}.`);
      player.supplies[item.id]--;
      target.player.supplies[item.id]++;
      this.updatePlayer(player);
      this.updatePlayer(target.player);
      this.note(target.player, `${player.name} gave you a ${item.name.toLowerCase()}.`);
      message = `Gave a ${item.name.toLowerCase()} to ${target.player.name}.`;
    } else if (action === 'gang.join') {
      const gang = GANGS.find(item => item.id === input.gang);
      if (!gang) throw new Error('Choose a listed crew.');
      if (player.gang === gang.id) throw new Error('You are already in that crew.');
      if (Date.now() < player.gangSwitchUntil)
        throw new Error(`Wait ${Math.ceil((player.gangSwitchUntil - Date.now()) / 1000)} s before changing crew.`);
      if ([...this.turfCaptures.values()].some(capture => capture.player === player))
        throw new Error('Finish or leave your capture before changing crew.');
      player.gang = gang.id;
      player.gangSwitchUntil = Date.now() + GANG_SWITCH_MS;
      this.save();
      message = `Joined ${gang.name}.`;
    } else if (action === 'turf.start') {
      const id = input.turf;
      const home = TURFS.includes(id) && homeAt(id);
      if (!home) throw new Error('Unknown territory.');
      if (!player.gang) throw new Error('Join a crew first.');
      if (!pos || pos.peer.state.walking !== true || player.health <= 0 || player.passive ||
          Math.hypot(pos.x - home.out[0], pos.y - home.out[1]) > 20)
        throw new Error('Stand on foot within 20 m of the territory marker with passive mode off.');
      if (player.job || (this.race?.members.has(player) && this.race.stage !== 'finished'))
        throw new Error('Finish your job or race first.');
      if (this.territories[id] === player.gang) throw new Error('Your crew already controls this territory.');
      if (this.turfCaptures.has(id)) throw new Error('This territory is already being captured.');
      if ([...this.turfCaptures.values()].some(capture => capture.player === player))
        throw new Error('Finish your current capture first.');
      this.turfCaptures.set(id, {player, gang: player.gang, progress: 0,
        lastTick: Date.now(), contested: false});
      message = `Capturing ${home.name} for ${GANGS.find(gang => gang.id === player.gang).name}. Hold this position for 30 seconds.`;
    } else if (action === 'turf.leave') {
      const capture = [...this.turfCaptures].find(([, value]) => value.player === player);
      if (!capture) throw new Error('You are not capturing a territory.');
      this.turfCaptures.delete(capture[0]);
      message = 'Territory capture cancelled.';
    } else if (action === 'safety.passive') {
      if (!pos) throw new Error('Enter the world before changing passive mode.');
      if (player.passive) {
        player.passive = false;
        player.passiveWaitUntil = Date.now() + PASSIVE_WAIT_MS;
        message = 'Passive mode off. You can turn it on again in two minutes.';
      } else {
        if (player.wanted || player.policeDuty || ['carthief', 'heist'].includes(player.job?.id))
          throw new Error('Clear your wanted level, leave police duty, and finish the getaway first.');
        if (Date.now() < player.passiveWaitUntil)
          throw new Error(`Wait ${Math.ceil((player.passiveWaitUntil - Date.now()) / 1000)} s before enabling passive mode.`);
        player.passive = true;
        message = 'Passive mode on. You cannot hurt or be hurt by other players.';
      }
      for (const peer of this.peers) if (peer.ready && peer.player === player)
        peer.send({t: 'passive', on: player.passive,
          w: Math.max(0, Math.ceil((player.passiveWaitUntil - Date.now()) / 1000))});
      this.save();
    } else if (action === 'police.duty') {
      if (!pos) throw new Error('Enter the world before changing police duty.');
      if (player.policeDuty && player.job?.id === 'patrol')
        throw new Error('Finish or cancel your patrol before leaving police duty.');
      if (!player.policeDuty && (player.wanted || player.passive ||
          ['carthief', 'heist'].includes(player.job?.id)))
        throw new Error('Clear your wanted level, turn off passive mode, and finish the getaway first.');
      player.policeDuty = !player.policeDuty;
      message = player.policeDuty ? 'Police duty on. Arrest nearby wanted players from F6.' :
        'Police duty off.';
    } else if (action === 'police.arrest') {
      if (!player.policeDuty || !pos || pos.peer.state.walking !== true)
        throw new Error('Go on police duty and stand on foot to arrest someone.');
      const number = Number(input.number);
      const suspect = [...this.peers].find(peer => peer.ready &&
        peer.player !== player && peer.player.number === number);
      const at = suspect && this.position(suspect.player);
      if (!suspect || !at || suspect.player.wanted < 1 ||
          at.peer.state.walking !== true ||
          Math.hypot(pos.x - at.x, pos.y - at.y) > 4)
        throw new Error('The wanted player must be on foot within 4 m.');
      const level = suspect.player.wanted;
      const fine = Math.min(suspect.player.cash, 100 * level);
      const pay = 50 * level;
      suspect.player.cash -= fine;
      player.cash = money(player.cash + pay);
      player.arrests = money(player.arrests + 1);
      this.abortHeist(suspect.player, 'you were arrested');
      this.setWanted(suspect.player, 0);
      this.updatePlayer(suspect.player);
      this.updatePlayer(player);
      this.note(suspect.player, `Arrested by ${player.name}. Fine: $${fine}. Wanted level cleared.`);
      message = `Arrested ${suspect.player.name}: +$${pay}.`;
    } else if (action === 'race.create') {
      if (this.race && this.race.stage !== 'finished') throw new Error('A race lobby already exists.');
      if (!pos || player.job) throw new Error('Enter the game and finish your job before creating a race.');
      const points = [];
      let from = pos;
      for (let i = 0; i < 3; i++) {
        const home = nearestHome(from, 120, points);
        if (!home) throw new Error('Race checkpoints are unavailable.');
        points.push(home.id);
        from = {x: home.out[0], y: home.out[1]};
      }
      this.race = {host: player, members: new Map([[player,
        {index: 0, carId: null, finishedAt: null, left: false, place: null}]]),
      points, start: [rounded(pos.x), rounded(pos.y)], created: Date.now(),
      started: null, stage: 'lobby', results: []};
      message = 'Race lobby opened. Other players can join near the starting line in F6.';
      for (const peer of this.peers) if (peer.ready && peer.player !== player)
        peer.send({t: 'note', text: `${player.name} opened a multiplayer race. Press F6 to join.`});
    } else if (action === 'race.join') {
      const race = this.race;
      if (!race || race.stage !== 'lobby') throw new Error('No race lobby is open.');
      if (player.job) throw new Error('Finish your current job before joining a race.');
      if (race.members.has(player)) throw new Error('You already joined this race.');
      if (race.members.size >= 8) throw new Error('This race is full.');
      if (!pos || Math.hypot(pos.x - race.start[0], pos.y - race.start[1]) > 25)
        throw new Error('Go within 25 m of the race starting line to join.');
      race.members.set(player, {index: 0, carId: null, finishedAt: null, left: false, place: null});
      message = `Joined ${race.host.name}'s race. Wait for the host to start.`;
      this.note(race.host, `${player.name} joined your race (${race.members.size} players).`);
    } else if (action === 'race.start') {
      const race = this.race;
      if (!race || race.stage !== 'lobby' || race.host !== player)
        throw new Error('Only the host can start an open race lobby.');
      if (race.members.size < 2) throw new Error('At least two players must join the race.');
      for (const racer of race.members.keys()) {
        const at = this.position(racer);
        if (!at || Math.hypot(at.x - race.start[0], at.y - race.start[1]) > 25)
          throw new Error(`${racer.name} must be near the starting line.`);
      }
      race.stage = 'running'; race.started = Date.now();
      let lane = 0;
      for (const [racer, member] of race.members) {
        const at = this.position(racer);
        const id = missionId();
        const row = [id, racer.name, '410.52.39.0.', rounded(at.x + 4 + 4 * lane++),
          rounded(at.y + 3), rounded(at.z + 1.1), 0, 0, 0, 1000, '', null];
        member.carId = id;
        this.vehicles.set(id, {id, owner: null, missionOwner: racer, row});
        for (const peer of this.peers) if (peer.ready) peer.send({t: 'spawned', v: row});
        this.note(racer, 'Your loaner Manana spawned nearby. Drive through the three race checkpoints.');
      }
      message = 'Race started. Drive through three checkpoints within five minutes.';
    } else if (action === 'race.checkpoint' || action === 'race.finish') {
      const race = this.race;
      const member = race?.members.get(player);
      if (!race || race.stage !== 'running' || !member || member.finishedAt || member.left)
        throw new Error('You are not in an active race.');
      if (Date.now() - race.started > MULTIPLAYER_RACE_MS)
        throw new Error('The race has expired.');
      const final = member.index === race.points.length - 1;
      if ((action === 'race.finish') !== final)
        throw new Error(final ? 'Finish at the final checkpoint.' : 'Pass the next checkpoint first.');
      const home = homeAt(race.points[member.index]);
      if (!pos || pos.peer.state.driving !== true ||
          Math.hypot(pos.x - home.out[0], pos.y - home.out[1]) > MISSION_RADIUS)
        throw new Error('Drive within 12 m of your active race checkpoint.');
      if (!final) {
        member.index++;
        message = `Checkpoint ${member.index} passed. Next: ${homeAt(race.points[member.index]).name}.`;
      } else {
        if (Date.now() - race.started < 3000) throw new Error('The race started too recently.');
        const place = race.results.length + 1;
        const pay = place === 1 ? 600 : place === 2 ? 400 : 250;
        member.finishedAt = Date.now(); member.place = place;
        race.results.push({name: player.name, place,
          seconds: Math.round((member.finishedAt - race.started) / 1000), pay});
        player.cash = money(player.cash + pay);
        player.xp = money(player.xp + Math.round(pay / 5));
        player.racesFinished = money((player.racesFinished || 0) + 1);
        if (place === 1) player.racesWon = money((player.racesWon || 0) + 1);
        this.removeRaceCar(member);
        this.updatePlayer(player);
        this.finishRaceIfDone();
        message = `Race finish #${place}: +$${pay}.`;
      }
    } else if (action === 'race.leave') {
      const race = this.race;
      const member = race?.members.get(player);
      if (!race || !member || race.stage === 'finished') throw new Error('You are not in an active race.');
      if (race.stage === 'lobby') {
        if (race.host === player) this.race = null;
        else race.members.delete(player);
      } else {
        member.left = true;
        this.removeRaceCar(member);
        this.finishRaceIfDone();
      }
      message = race.host === player && race.stage === 'lobby' ? 'Race lobby cancelled.' : 'Left the race.';
    } else if (action === 'job.start') {
      const job = JOBS.find(item => item.id === input.job);
      if (!job) throw new Error('Unknown job.');
      if (!pos) throw new Error('Enter the game before starting a job.');
      if (player.job) throw new Error('Finish or cancel your current job first.');
      if (this.race && ['lobby', 'running'].includes(this.race.stage) &&
          this.race.members.has(player)) throw new Error('Leave or finish your race first.');
      if (job.id === 'courier' || job.id === 'taxi') {
        const nearest = nearestHome(pos);
        if (!nearest) throw new Error('Job destinations are unavailable.');
        if (job.id === 'courier') {
          player.job = {id: job.id, mode: 'route', pickup: [rounded(pos.x), rounded(pos.y)],
            drop: nearest.id, stage: 'pickup', started: Date.now()};
          message = 'Courier started. Collect the package here, then follow the objective box to the delivery address.';
        } else {
          const cab = taxiCab(input.model === undefined ? 420 : Number(input.model));
          if (!cab) throw new Error('Unknown taxi cab.');
          if (taxiLevel(player) < cab.level)
            throw new Error(`${cab.name} unlocks at taxi level ${cab.level}.`);
          const drop = nearestHome({x: nearest.out[0], y: nearest.out[1]}, 150, [nearest.id]);
          if (!drop) throw new Error('Taxi drop-off locations are unavailable.');
          if (Date.now() - player.taxiLastFareAt > TAXI_STREAK_WINDOW_MS)
            player.taxiStreak = 0;
          player.job = {id: job.id, mode: 'route', pickupHome: nearest.id,
            drop: drop.id, model: cab.model,
            station: [rounded(pos.x), rounded(pos.y), rounded(pos.z)],
            vehicleId: missionId(), pickedUpAt: null,
            minHealth: 1000, reportedHealth: false,
            shiftFares: 0,
            stage: 'pickup', started: Date.now()};
          this.addMissionVehicle(player);
          message = `Taxi fare started. Take the nearby marked cab to ${nearest.name} for pickup.`;
        }
      } else if (job.id === 'trucker') {
        const pickup = nearestHome(pos);
        const drop = pickup && nearestHome({x: pickup.out[0], y: pickup.out[1]}, 180, [pickup.id]);
        if (!pickup || !drop) throw new Error('Freight stops are unavailable.');
        player.job = {id: job.id, mode: 'route', pickupHome: pickup.id,
          drop: drop.id, station: [rounded(pos.x), rounded(pos.y), rounded(pos.z)],
          vehicleId: missionId(), stage: 'pickup', bonusAwarded: false,
          started: Date.now()};
        this.addMissionVehicle(player);
        message = `Freight delivery started. Take the nearby Mule to ${pickup.name} for cargo, then deliver it to ${drop.name} within seven minutes.`;
      } else if (job.id === 'pilot') {
        if (AIRPORTS.length < 2) throw new Error('Airport locations are unavailable.');
        const aircraft = pilotAircraft(input.model === undefined ? 593 : Number(input.model));
        if (!aircraft) throw new Error('Choose a listed pilot aircraft.');
        if (pilotLevel(player) < aircraft.level)
          throw new Error(`${aircraft.name} unlocks at pilot level ${aircraft.level}.`);
        if (aircraft.model !== 593 && !CAR_CATALOG.some(car => car.model === aircraft.model))
          throw new Error('That aircraft is unavailable in the local archive.');
        const from = [...AIRPORTS].sort((a, b) =>
          Math.hypot(pos.x - a.stand[0], pos.y - a.stand[1]) -
          Math.hypot(pos.x - b.stand[0], pos.y - b.stand[1]))[0];
        const to = AIRPORTS[(AIRPORTS.indexOf(from) + 1) % AIRPORTS.length];
        player.job = {id: job.id, mode: 'flight', from: from.id, to: to.id,
          vehicleId: missionId(), model: aircraft.model,
          stage: 'takeoff', landingSince: null,
          minHealth: 1000, reportedHealth: false,
          started: Date.now()};
        this.addMissionVehicle(player);
        pos.peer.send({t: 'tp', x: rounded(from.runway[0] - Math.sin(from.runway[3]) * 7),
          y: rounded(from.runway[1] - Math.cos(from.runway[3]) * 7),
          z: from.runway[2] + 1, h: from.runway[3], g: 1});
        message = `Pilot flight started on the ${from.name} runway. Board the marked ${aircraft.name}, climb 35 m, then land at ${to.name} within ten minutes.`;
      } else if (job.id === 'fire') {
        const home = nearestHome(pos, 180);
        if (!home) throw new Error('Fire call locations are unavailable.');
        player.job = {id: job.id, mode: 'fire', incidentHome: home.id,
          station: [rounded(pos.x), rounded(pos.y), rounded(pos.z)],
          vehicleId: missionId(), stage: 'respond', index: 0, started: Date.now()};
        this.addMissionVehicle(player);
        message = `Fire dispatch: take the marked fire truck to ${home.name} within eight minutes. Put out three fires and rescue the person on foot.`;
      } else if (job.id === 'heist') {
        if (player.passive || player.policeDuty || player.wanted)
          throw new Error('Leave passive mode and police duty, and clear your wanted level before a heist.');
        if (Date.now() < player.heistCooldownUntil)
          throw new Error(`Wait ${Math.ceil((player.heistCooldownUntil - Date.now()) / 1000)} s before another heist.`);
        const site = nearestHome(pos, 180);
        const drop = site && nearestHome({x: site.out[0], y: site.out[1]}, 300, [site.id]);
        if (!site || !drop) throw new Error('Heist route locations are unavailable.');
        player.job = {id: job.id, mode: 'heist', site: site.id, drop: drop.id,
          station: [rounded(pos.x), rounded(pos.y), rounded(pos.z)],
          vehicleId: missionId(), stage: 'plan', crewIds: [], started: Date.now()};
        this.addMissionVehicle(player);
        message = `Getaway heist started. Take the marked Sultan to the robbery site near ${site.name}, enter on foot, then escape to ${drop.name}.`;
      } else if (job.id === 'carthief') {
        if (player.passive || player.policeDuty)
          throw new Error('Turn off passive mode and leave police duty before starting a getaway.');
        const pickup = nearestHome(pos);
        const drop = pickup && nearestHome({x: pickup.out[0], y: pickup.out[1]}, 180, [pickup.id]);
        if (!pickup || !drop) throw new Error('Getaway locations are unavailable.');
        player.job = {id: job.id, mode: 'route', pickupHome: pickup.id,
          drop: drop.id, vehicleId: missionId(), stage: 'pickup', started: Date.now()};
        this.addMissionVehicle(player);
        message = `Getaway started. Steal the marked car at ${pickup.name} and deliver it to ${drop.name} within five minutes.`;
      } else if (job.id === 'mechanic') {
        const home = nearestHome(pos);
        if (!home) throw new Error('Roadside service locations are unavailable.');
        player.job = {id: job.id, mode: 'service', targetHome: home.id,
          vehicleId: missionId(), repairStep: 0, repairProgress: 0,
          repairTick: Date.now(), started: Date.now()};
        this.addMissionVehicle(player);
        message = `Roadside call started. Go to the broken-down car near ${home.name}; stand beside it on foot to fix its engine, tyres, and bodywork.`;
      } else if (job.id === 'medic') {
        const home = nearestHome(pos);
        if (!home) throw new Error('Patient locations are unavailable.');
        player.job = {id: job.id, mode: 'route', pickupHome: home.id,
          station: [rounded(pos.x), rounded(pos.y), rounded(pos.z)],
          vehicleId: missionId(), stage: 'pickup', started: Date.now()};
        this.addMissionVehicle(player);
        message = `Medical call started. An ambulance is nearby. Drive to the patient near ${home.name}.`;
      } else if (['trial', 'patrol', 'pizza'].includes(job.id)) {
        if (job.id === 'trial' && player.cars.length === 0)
          throw new Error('Own a car before entering the time trial.');
        if (job.id === 'patrol' && !player.policeDuty)
          throw new Error('Go on police duty before starting a patrol.');
        const points = [];
        let from = pos;
        for (let i = 0; i < 3; i++) {
          const home = nearestHome(from, 120, points);
          if (!home) throw new Error('Time trial checkpoints are unavailable.');
          points.push(home.id);
          from = {x: home.out[0], y: home.out[1]};
        }
        player.job = {id: job.id, mode: 'checkpoints', points,
          index: 0, started: Date.now(),
          ...(['patrol', 'pizza'].includes(job.id) ? {vehicleId: missionId(),
            station: [rounded(pos.x), rounded(pos.y), rounded(pos.z)]} : {})};
        if (job.id === 'patrol' || job.id === 'pizza') this.addMissionVehicle(player);
        message = job.id === 'patrol' ?
          `Patrol started. Take the nearby police car through three checkpoints within ${PATROL_MS / 60000} minutes.` :
          job.id === 'pizza' ?
            `Pizza delivery started. Take the nearby Pizzaboy scooter to three addresses within ${PIZZA_MS / 60000} minutes.` :
            `Street time trial started. Drive through three checkpoints within ${TIME_TRIAL_MS / 60000} minutes.`;
      } else {
        player.job = {id: job.id, goal: job.distance, progress: 0, started: Date.now()};
        message = `${job.name} started. Travel ${job.distance} m, then complete the task.`;
      }
      this.save();
    } else if (action === 'heist.rob') {
      const heist = player.job;
      if (heist?.mode !== 'heist' || heist.stage !== 'plan')
        throw new Error('No robbery is ready.');
      if (Date.now() - heist.started > HEIST_MS)
        throw new Error('The heist window closed. Cancel and start again.');
      const site = homeAt(heist.site);
      if (!pos || !site || pos.peer.state.walking !== true || player.health <= 0 ||
          Math.hypot(pos.x - site.out[0], pos.y - site.out[1]) > MISSION_RADIUS)
        throw new Error('Enter the marked robbery site on foot.');
      heist.stage = 'escape';
      const party = this.partyOf(player);
      heist.crewIds = party ? [...party.members].filter(member => {
        if (member === player) return false;
        const at = this.position(member);
        return at && Math.hypot(at.x - pos.x, at.y - pos.y) <= 30;
      }).map(member => [...this.players].find(([, entry]) => entry === member)?.[0])
        .filter(Boolean).slice(0, 3) : [];
      player.heistCooldownUntil = Date.now() + HEIST_COOLDOWN_MS;
      this.setWanted(player, Math.max(2, player.wanted));
      message = `Bag collected. Lose the police, then deliver it in the marked Sultan to ${homeAt(heist.drop).name}.`;
      this.save();
    } else if (action === 'job.respond' || action === 'job.extinguish') {
      const fire = player.job;
      if (fire?.mode !== 'fire') throw new Error('No active fire call.');
      if (Date.now() - fire.started > FIRE_MS)
        throw new Error('The fire call expired. Cancel and start again.');
      const truck = this.vehicles.get(fire.vehicleId);
      const inTruck = pos?.peer.state.driving === true &&
        pos.peer.state.vehicle === fire.vehicleId &&
        pos.peer.state.car === truck?.row[2];
      if (action === 'job.respond') {
        if (fire.stage !== 'respond') throw new Error('The fire truck has already arrived.');
        const home = homeAt(fire.incidentHome);
        if (!pos || !home || Math.hypot(pos.x - home.out[0], pos.y - home.out[1]) > 25 ||
            !inTruck) throw new Error('Drive the marked fire truck to the active call.');
        fire.stage = 'extinguish';
        message = `Arrived at ${home.name}. Extinguish the three fire spots with the truck or on foot.`;
      } else {
        if (fire.stage !== 'extinguish') throw new Error('No fire spot is ready.');
        const target = fireSpot(fire);
        const distance = pos && target ? Math.hypot(pos.x - target[0], pos.y - target[1]) : Infinity;
        if (!(inTruck && distance <= 23) &&
            !(pos?.peer.state.walking === true && distance <= 8))
          throw new Error('Get the marked fire truck within 23 m, or approach the fire on foot within 8 m.');
        fire.index++;
        if (fire.index === FIRE_OFFSETS.length) {
          fire.stage = 'rescue';
          message = 'All fires are out. Get out and rescue the person near the call location.';
        } else message = `Fire ${fire.index}/${FIRE_OFFSETS.length} out. Move to the next fire spot.`;
      }
      this.save();
    } else if (action === 'job.pickup') {
      if (!['courier', 'taxi', 'medic', 'carthief', 'trucker'].includes(player.job?.id) || player.job.mode !== 'route' ||
          player.job.stage !== 'pickup') throw new Error('No pickup is ready.');
      const pickup = player.job.id === 'courier' ? player.job.pickup :
        homeAt(player.job.pickupHome)?.out;
      if (!pos || !pickup || Math.hypot(pos.x - pickup[0], pos.y - pickup[1]) > MISSION_RADIUS)
        throw new Error('Travel to the pickup point.');
      if (player.job.id !== 'courier' && pos.peer.state.driving !== true)
        throw new Error('Drive the mission vehicle to the pickup point.');
      if (player.job.id === 'taxi' &&
          (pos.peer.state.vehicle !== player.job.vehicleId ||
            pos.peer.state.car !== this.vehicles.get(player.job.vehicleId)?.row[2]))
        throw new Error('Drive the marked cab to the passenger.');
      if (player.job.id === 'medic' &&
          (pos.peer.state.vehicle !== player.job.vehicleId ||
            pos.peer.state.car !== this.vehicles.get(player.job.vehicleId)?.row[2]))
        throw new Error('Drive the marked ambulance to the patient.');
      if (player.job.id === 'trucker') {
        if (Date.now() - player.job.started > TRUCKER_MS)
          throw new Error('The freight deadline passed. Cancel and start again.');
        if (pos.peer.state.vehicle !== player.job.vehicleId ||
            pos.peer.state.car !== this.vehicles.get(player.job.vehicleId)?.row[2])
          throw new Error('Drive the marked Mule to collect the cargo.');
      }
      if (player.job.id === 'carthief') {
        if (player.passive || player.policeDuty)
          throw new Error('Leave passive mode or police duty before taking the car.');
        if (Date.now() - player.job.started > CAR_THEFT_MS)
          throw new Error('The getaway expired. Cancel it and start again.');
        if (pos.peer.state.vehicle !== player.job.vehicleId ||
            pos.peer.state.car !== this.vehicles.get(player.job.vehicleId)?.row[2])
          throw new Error('Get in the marked getaway car.');
        this.setWanted(player, Math.max(2, player.wanted));
      }
      player.job.stage = 'delivery';
      if (player.job.id === 'taxi') player.job.pickedUpAt = Date.now();
      const home = homeAt(player.job.drop);
      message = player.job.id === 'courier' ? `Package collected. Deliver it to ${home.name}.` :
        player.job.id === 'taxi' ? `Passenger aboard. Drive to ${home.name}.` :
          player.job.id === 'trucker' ? `Cargo loaded. Deliver it to ${home.name} before time runs out.` :
          player.job.id === 'carthief' ? `Car taken. Drive to ${home.name} before time runs out.` :
            'Patient aboard. Return to the aid station.';
      this.save();
    } else if (action === 'job.checkpoint') {
      if (!['trial', 'patrol', 'pizza'].includes(player.job?.id) || player.job.mode !== 'checkpoints' ||
          player.job.index >= player.job.points.length - 1)
        throw new Error('No intermediate checkpoint is active.');
      if (Date.now() - player.job.started >
          (player.job.id === 'patrol' ? PATROL_MS :
            player.job.id === 'pizza' ? PIZZA_MS : TIME_TRIAL_MS))
        throw new Error('The route expired. Cancel it and start again.');
      const home = homeAt(player.job.points[player.job.index]);
      if (!pos || Math.hypot(pos.x - home.out[0], pos.y - home.out[1]) > MISSION_RADIUS ||
          pos.peer.state.driving !== true)
        throw new Error('Drive into the active checkpoint.');
      if (player.job.id === 'patrol' && (!player.policeDuty ||
          pos.peer.state.vehicle !== player.job.vehicleId ||
          pos.peer.state.car !== this.vehicles.get(player.job.vehicleId)?.row[2]))
        throw new Error('Drive the marked police car while on duty.');
      if (player.job.id === 'pizza' &&
          (pos.peer.state.vehicle !== player.job.vehicleId ||
            pos.peer.state.car !== this.vehicles.get(player.job.vehicleId)?.row[2]))
        throw new Error('Drive the marked Pizzaboy scooter.');
      player.job.index++;
      message = player.job.id === 'pizza' ?
        `Pizza ${player.job.index} delivered. Drive to ${homeAt(player.job.points[player.job.index]).name}.` :
        `Checkpoint ${player.job.index} passed. Drive to ${homeAt(player.job.points[player.job.index]).name}.`;
      this.save();
    } else if (action === 'job.complete') {
      if (!player.job) throw new Error('No active job.');
      if (!pos) throw new Error('Enter the game to complete this job.');
      if (Date.now() - player.job.started < 3000) throw new Error('The task started too recently.');
      if (player.job.mode === 'heist') {
        const drop = homeAt(player.job.drop);
        const car = this.vehicles.get(player.job.vehicleId);
        if (player.job.stage !== 'escape') throw new Error('Collect the bag first.');
        if (player.wanted > 0) throw new Error('Lose the police before delivering the bag.');
        if (!drop || Math.hypot(pos.x - drop.out[0], pos.y - drop.out[1]) > MISSION_RADIUS)
          throw new Error('Drive to the heist drop-off.');
        if (!car || pos.peer.state.driving !== true ||
            pos.peer.state.vehicle !== player.job.vehicleId ||
            pos.peer.state.car !== car.row[2])
          throw new Error('Deliver the bag in the marked Sultan.');
      } else if (player.job.mode === 'fire') {
        const home = homeAt(player.job.incidentHome);
        if (player.job.stage !== 'rescue') throw new Error('Put out all three fires first.');
        if (!home || Math.hypot(pos.x - home.out[0], pos.y - home.out[1]) > 10 ||
            pos.peer.state.walking !== true)
          throw new Error('Reach the rescue point on foot.');
      } else if (player.job.mode === 'route') {
        if (player.job.stage !== 'delivery') throw new Error('Complete the pickup first.');
        const home = homeAt(player.job.drop);
        const target = player.job.id === 'medic' ? player.job.station : home?.out;
        if (!target || Math.hypot(pos.x - target[0], pos.y - target[1]) > MISSION_RADIUS)
          throw new Error('Travel to the delivery destination.');
        if (player.job.id !== 'courier' && pos.peer.state.driving !== true)
          throw new Error('Finish the fare or medical call while driving.');
        if (player.job.id === 'taxi' &&
            (pos.peer.state.vehicle !== player.job.vehicleId ||
              pos.peer.state.car !== this.vehicles.get(player.job.vehicleId)?.row[2]))
          throw new Error('Drop off the passenger in the marked cab.');
        if (player.job.id === 'medic' &&
            (pos.peer.state.vehicle !== player.job.vehicleId ||
              pos.peer.state.car !== this.vehicles.get(player.job.vehicleId)?.row[2]))
          throw new Error('Return the patient in the marked ambulance.');
        if (player.job.id === 'carthief' &&
            (pos.peer.state.vehicle !== player.job.vehicleId ||
              pos.peer.state.car !== this.vehicles.get(player.job.vehicleId)?.row[2]))
          throw new Error('Deliver the marked getaway car.');
        if (player.job.id === 'trucker' &&
            (pos.peer.state.vehicle !== player.job.vehicleId ||
              pos.peer.state.car !== this.vehicles.get(player.job.vehicleId)?.row[2]))
          throw new Error('Deliver cargo in the marked Mule.');
      } else if (player.job.mode === 'flight') {
        const to = airportAt(player.job.to);
        const aircraft = pilotAircraft(player.job.model || 593);
        const plane = this.vehicles.get(player.job.vehicleId);
        if (player.job.stage !== 'landing')
          throw new Error('Take off in the marked plane before landing.');
        if (!to || !plane || pos.peer.state.driving !== true ||
            pos.peer.state.vehicle !== player.job.vehicleId ||
            pos.peer.state.car !== plane.row[2])
          throw new Error(`Land in the marked ${aircraft?.name || 'aircraft'}.`);
        if (Math.hypot(pos.x - to.runway[0], pos.y - to.runway[1]) > (aircraft?.radius || 70) ||
            Math.abs(pos.z - to.runway[2]) > 16 ||
            Math.abs(finite(pos.peer.state.speed)) > 1.5)
          throw new Error('Stop the plane on the destination apron.');
        if (!player.job.landingSince || Date.now() - player.job.landingSince < 2000)
          throw new Error('Hold the plane still for two seconds.');
      } else if (player.job.mode === 'service') {
        const vehicle = this.vehicles.get(player.job.vehicleId);
        if (!vehicle || Math.hypot(pos.x - vehicle.row[3], pos.y - vehicle.row[4]) > 8)
          throw new Error('Go to the stranded vehicle to repair it.');
        if (pos.peer.state.walking !== true)
          throw new Error('Get out and repair the vehicle on foot.');
        if ((player.job.repairStep || 0) < MECHANIC_STAGES.length)
          throw new Error('Keep working beside the vehicle until the engine, tyres, and bodywork are repaired.');
      } else if (player.job.mode === 'checkpoints') {
        const home = homeAt(player.job.points[player.job.index]);
        if (player.job.index !== player.job.points.length - 1 || !home ||
            Math.hypot(pos.x - home.out[0], pos.y - home.out[1]) > MISSION_RADIUS ||
            pos.peer.state.driving !== true)
          throw new Error('Drive through the final checkpoint.');
        if (player.job.id === 'patrol' && (!player.policeDuty ||
            pos.peer.state.vehicle !== player.job.vehicleId ||
            pos.peer.state.car !== this.vehicles.get(player.job.vehicleId)?.row[2]))
          throw new Error('Finish in the marked police car while on duty.');
        if (player.job.id === 'pizza' &&
            (pos.peer.state.vehicle !== player.job.vehicleId ||
              pos.peer.state.car !== this.vehicles.get(player.job.vehicleId)?.row[2]))
          throw new Error('Deliver the final pizza on the marked Pizzaboy scooter.');
      } else if (player.job.progress < player.job.goal)
        throw new Error(`Travel ${Math.ceil(player.job.goal - player.job.progress)} m more.`);
      const job = JOBS.find(item => item.id === player.job.id);
      if (job.id === 'trial' && Date.now() - player.job.started > TIME_TRIAL_MS)
        throw new Error('The time trial expired. Cancel it and start again.');
      if (job.id === 'patrol' && Date.now() - player.job.started > PATROL_MS)
        throw new Error('The patrol expired. Cancel it and start again.');
      if (job.id === 'pizza' && Date.now() - player.job.started > PIZZA_MS)
        throw new Error('The pizzas went cold. Cancel and start again.');
      if (job.id === 'carthief' && Date.now() - player.job.started > CAR_THEFT_MS)
        throw new Error('The getaway expired. Cancel it and start again.');
      if (job.id === 'trucker' && Date.now() - player.job.started > TRUCKER_MS)
        throw new Error('The freight deadline passed. Cancel and start again.');
      if (job.id === 'pilot' && Date.now() - player.job.started > PILOT_MS)
        throw new Error('The flight deadline passed. Cancel and start again.');
      if (job.id === 'fire' && Date.now() - player.job.started > FIRE_MS)
        throw new Error('The fire call expired. Cancel and start again.');
      if (job.id === 'heist' && Date.now() - player.job.started > HEIST_MS)
        throw new Error('The heist window closed. Cancel and start again.');
      let convoyBonus = 0;
      if (job.id === 'trucker' && !player.job.bonusAwarded) {
        const party = this.partyOf(player);
        const partners = party ? [...party.members].filter(other => {
          if (other === player || other.job?.id !== 'trucker' ||
              other.job.stage !== 'delivery' || other.job.bonusAwarded ||
              other.job.drop !== player.job.drop ||
              Date.now() - other.job.started > TRUCKER_MS) return false;
          const at = this.position(other);
          const vehicle = this.vehicles.get(other.job.vehicleId);
          return at && vehicle && at.peer.state.driving === true &&
            at.peer.state.vehicle === other.job.vehicleId &&
            at.peer.state.car === vehicle.row[2] &&
            Math.hypot(at.x - pos.x, at.y - pos.y) <= CONVOY_RADIUS;
        }) : [];
        if (partners.length) {
          convoyBonus = CONVOY_BONUS;
          player.job.bonusAwarded = true;
          for (const other of partners) {
            other.cash = money(other.cash + CONVOY_BONUS);
            other.xp = money(other.xp + CONVOY_BONUS / 5);
            other.job.bonusAwarded = true;
            this.updatePlayer(other);
            this.note(other, `Convoy bonus: +$${CONVOY_BONUS} for staying with the freight group.`);
          }
        }
      }
      let pilotBonus = 0;
      const pilotExtras = [];
      if (job.id === 'pilot') {
        const aircraft = pilotAircraft(player.job.model || 593);
        if (aircraft?.premium) {
          pilotBonus += aircraft.premium;
          pilotExtras.push(`${aircraft.name} aircraft`);
        }
        player.pilotFlights = money((player.pilotFlights || 0) + 1);
        player.pilotStreak = money((player.pilotStreak || 0) + 1);
        if (player.job.reportedHealth && player.job.minHealth >= 950) {
          pilotBonus += PILOT_SMOOTH_BONUS;
          pilotExtras.push('smooth flight');
        }
        if (PILOT_MS - (Date.now() - player.job.started) >= 120000) {
          pilotBonus += PILOT_EARLY_BONUS;
          pilotExtras.push('early landing');
        }
        if (player.pilotStreak % 5 === 0) {
          pilotBonus += PILOT_STREAK_BONUS;
          pilotExtras.push('fifth flight');
        }
      }
      let heistBonus = 0;
      if (job.id === 'heist') {
        const party = this.partyOf(player);
        const crew = party ? [...party.members].filter(member => {
          if (member === player || !player.job.crewIds.includes(
              [...this.players].find(([, entry]) => entry === member)?.[0])) return false;
          const at = this.position(member);
          return at && Math.hypot(at.x - pos.x, at.y - pos.y) <= 25;
        }) : [];
        if (crew.length) {
          heistBonus = HEIST_CREW_BONUS;
          for (const member of crew) {
            member.cash = money(member.cash + HEIST_CREW_BONUS);
            member.xp = money(member.xp + HEIST_CREW_BONUS / 5);
            this.updatePlayer(member);
            this.note(member, `Heist crew share: +$${HEIST_CREW_BONUS} for the nearby escape.`);
          }
        }
      }
      let taxiBonus = 0;
      const taxiExtras = [];
      if (job.id === 'taxi') {
        const cab = taxiCab(player.job.model) || TAXI_CABS[0];
        if (cab.premium) {
          taxiBonus += cab.premium;
          taxiExtras.push(`${cab.name} fare`);
        }
        const previousStreak = Date.now() - player.taxiLastFareAt <= TAXI_STREAK_WINDOW_MS ?
          player.taxiStreak : 0;
        if (player.job.reportedHealth && player.job.minHealth >= 950 && !player.wanted) {
          taxiBonus += TAXI_CLEAN_BONUS;
          taxiExtras.push('clean ride');
        }
        if (player.job.reportedHealth && player.job.pickedUpAt && !player.wanted &&
            Date.now() - player.job.pickedUpAt <= taxiQuickWindow(player.job)) {
          taxiBonus += TAXI_QUICK_BONUS;
          taxiExtras.push('quick ride');
        }
        if (previousStreak) {
          const streakPay = Math.min(5, previousStreak) * TAXI_STREAK_BONUS;
          taxiBonus += streakPay;
          taxiExtras.push(`${previousStreak + 1} fares in a row`);
        }
        player.taxiFares = money(player.taxiFares + 1);
        player.taxiStreak = Math.min(999, previousStreak + 1);
        player.taxiLastFareAt = Date.now();
      }
      player.cash = money(player.cash + job.pay + convoyBonus + pilotBonus + heistBonus + taxiBonus);
      player.xp = money(player.xp + Math.round(job.pay / 5) +
        (convoyBonus + pilotBonus + heistBonus + taxiBonus) / 5);
      player.jobsDone++;
      let nextTaxiPickup = null;
      if (job.id === 'taxi') {
        nextTaxiPickup = nearestHome(pos, 90, [player.job.drop]);
        const nextDrop = nextTaxiPickup && nearestHome(
          {x: nextTaxiPickup.out[0], y: nextTaxiPickup.out[1]}, 150,
          [nextTaxiPickup.id]);
        if (nextDrop) {
          player.job = {...player.job, pickupHome: nextTaxiPickup.id,
            drop: nextDrop.id, stage: 'pickup', started: Date.now(),
            pickedUpAt: null, minHealth: 1000, reportedHealth: false,
            shiftFares: Math.min(999, (player.job.shiftFares || 0) + 1)};
        } else nextTaxiPickup = null;
      }
      if (!nextTaxiPickup) {
        this.removeMissionVehicle(player);
        player.job = null;
      }
      message = `${job.name} complete: +$${job.pay}${convoyBonus ?
        ` and $${convoyBonus} convoy bonus` : ''}${pilotBonus ?
        ` and $${pilotBonus} pilot bonus (${pilotExtras.join(', ')})` : ''}${heistBonus ?
        ` and $${heistBonus} crew bonus` : ''}${taxiBonus ?
        ` and $${taxiBonus} taxi bonus (${taxiExtras.join(', ')})` : ''}. Balance: $${player.cash}.${nextTaxiPickup ?
        ` Next passenger near ${nextTaxiPickup.name}; keep driving the same cab, or cancel to end the shift.` : ''}`;
      this.updatePlayer(player);
    } else if (action === 'job.cancel') {
      if (!player.job) throw new Error('No active job.');
      if (player.job.id === 'taxi' && pos?.peer.state.driving === true &&
          pos.peer.state.vehicle === player.job.vehicleId)
        throw new Error('Get out of the marked cab before ending the shift.');
      if (player.job.id === 'pilot') player.pilotStreak = 0;
      if (player.job.id === 'taxi') player.taxiStreak = 0;
      this.removeMissionVehicle(player);
      player.job = null;
      message = 'Job cancelled.';
      this.save();
    } else if (action === 'car.buy') {
      const car = CAR_CATALOG.find(item => item.model === Number(input.model));
      if (!car) throw new Error('Unknown car.');
      if (isAircraft(car) && !hangarFor(pos, car))
        throw new Error('Go to an airport hangar that sells this aircraft to buy it.');
      if (car.source === 'archived' && !isAircraft(car) && !groundDealerFor(pos, car))
        throw new Error('Go to a dealership that sells this vehicle to buy it.');
      if (player.cars.length >= 12) throw new Error('Your garage is full.');
      if (player.cash < car.price) throw new Error(`You need $${car.price}.`);
      player.cash -= car.price;
      player.cars.push(car.model);
      player.garage.push({health: 1000, damage: '', active: false, position: null,
        paint: null, parkedHome: null});
      message = `${car.name} bought for $${car.price}. Open My Vehicles or spawn it here.`;
      this.updatePlayer(player);
    } else if (action === 'car.spawn') {
      const slot = Number(input.slot);
      if (!Number.isInteger(slot) || slot < 0 || slot >= player.cars.length)
        throw new Error('Choose a car in your garage.');
      message = this.spawnOwnedCar(player, slot);
    } else if (action === 'car.store' || action === 'car.repair' ||
        action === 'car.respray' || action === 'car.parkhome') {
      const slot = Number(input.slot);
      if (!Number.isInteger(slot) || slot < 0 || slot >= player.cars.length)
        throw new Error('Choose a car in your garage.');
      const vehicle = this.ownedVehicle(player, slot);
      if (!vehicle) throw new Error('Spawn this car first.');
      if (!pos || Math.hypot(pos.x - vehicle.row[3], pos.y - vehicle.row[4]) > 18)
        throw new Error('Stand near your car to manage it.');
      if (pos.peer.state.walking !== true)
        throw new Error('Get out of the car first.');
      this.assertVehicleUnoccupied(vehicle);
      const entry = player.garage[slot];
      const car = CAR_CATALOG.find(item => item.model === player.cars[slot]);
      if (action === 'car.parkhome') {
        if (isAircraft(car)) throw new Error('Aircraft must be stored at an airport hangar.');
        const home = player.homes.map(homeAt).filter(Boolean).find(item =>
          Math.hypot(pos.x - item.out[0], pos.y - item.out[1]) <= 25 &&
          Math.hypot(vehicle.row[3] - item.out[0], vehicle.row[4] - item.out[1]) <= 25);
        if (!home) throw new Error('Bring this car to the exterior of a home you own.');
        if (player.garage.filter(item => item.parkedHome === home.id).length >= 2)
          throw new Error('This property already has two parked vehicles.');
        entry.active = false;
        entry.parkedHome = home.id;
        entry.position = [rounded(vehicle.row[3]), rounded(vehicle.row[4]),
          rounded(vehicle.row[5]), rounded(vehicle.row[6])];
        this.removeOwnedVehicle(vehicle);
        message = `${car.name} parked at ${home.name}. Retrieve it from the property exterior.`;
        this.save();
      } else if (action === 'car.store') {
        entry.active = false;
        entry.parkedHome = null;
        this.removeOwnedVehicle(vehicle);
        message = `${car.name} stored. Its condition was saved.`;
        this.save();
      } else if (action === 'car.repair') {
        const cost = repairCost(entry);
        if (!cost) throw new Error('This car does not need repairs.');
        if (player.cash < cost) throw new Error(`You need $${cost} to repair it.`);
        player.cash -= cost;
        entry.health = 1000; entry.damage = '';
        this.removeOwnedVehicle(vehicle);
        this.addOwnedVehicle(player, slot);
        message = `${car.name} repaired for $${cost}.`;
        this.updatePlayer(player);
      } else {
        if (player.cash < RESPRAY_COST)
          throw new Error(`You need $${RESPRAY_COST} to respray it.`);
        const previous = this.vehicleCode(player, slot);
        do entry.paint = [crypto.randomInt(128), crypto.randomInt(128)];
        while (this.vehicleCode(player, slot) === previous);
        player.cash -= RESPRAY_COST;
        this.removeOwnedVehicle(vehicle);
        this.addOwnedVehicle(player, slot);
        message = `${car.name} resprayed for $${RESPRAY_COST}.`;
        this.updatePlayer(player);
      }
    } else if (action === 'home.buy') {
      const home = HOME_CATALOG.find(item => item.id === input.home);
      if (!home) throw new Error('Unknown home.');
      if (player.homes.includes(home.id)) throw new Error('You already own this home.');
      if (player.cash < home.price) throw new Error(`You need $${home.price}.`);
      player.cash -= home.price;
      player.homes.push(home.id);
      message = `${home.name} bought for $${home.price}.`;
      this.updatePlayer(player);
    } else if (action === 'home.visit') {
      const home = HOME_CATALOG.find(item => item.id === input.home);
      if (!home || !player.homes.includes(home.id)) throw new Error('You do not own this home.');
      if (!home.out) throw new Error('This starter home has no world entrance.');
      if (!pos) throw new Error('Enter the game before visiting your home.');
      pos.peer.send({t: 'tp', x: home.out[0], y: home.out[1], z: home.out[2],
        h: home.out[3], g: 1});
      message = `Travelling to ${home.name}.`;
    } else throw new Error('Unknown action.');
    this.note(player, message);
    return {ok: true, message, state: this.gameplayState(player)};
  }

  async join(req, res) {
    if (req.method === 'GET') {
      const content = Buffer.from(`<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Join ZGTA:SA</title><style>body{font:16px system-ui;background:#101114;color:white;max-width:28rem;margin:12vh auto;padding:1rem}input,button{font:inherit;padding:.7rem;border-radius:.4rem}input{width:100%;box-sizing:border-box}button{margin-top:1rem;cursor:pointer}p{line-height:1.5}</style><h1>Join ZGTA:SA</h1><p>Enter the access code from the person hosting this server.</p><form><input type="password" name="code" autocomplete="off" required><button>Join game</button></form><p id="message" role="status"></p><script>document.querySelector('form').onsubmit=async e=>{e.preventDefault();const r=await fetch('/api/local/join',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({code:e.target.code.value})});if(r.ok)location.href='/';else document.querySelector('#message').textContent='That code did not work.'}</script></html>`);
      res.writeHead(200, {'Content-Type': 'text/html; charset=utf-8', 'Content-Length': content.length,
        'Cache-Control': 'no-store'});
      return res.end(content);
    }
    if (req.method !== 'POST') return json(res, 405, {error: 'Method not allowed'});
    try {
      const body = await readBody(req, 2048);
      const proposed = crypto.createHmac('sha256', String(body.code || '')).update('ZGTA:SA local access v1').digest();
      if (!crypto.timingSafeEqual(proposed, Buffer.from(ACCESS_TOKEN, 'hex')))
        return json(res, 403, {error: 'Access code incorrect'});
      const secure = req.headers['x-forwarded-proto'] === 'https' ? '; Secure' : '';
      res.setHeader('Set-Cookie', `zgta_access=${ACCESS_TOKEN}; Path=/; HttpOnly; SameSite=Strict${secure}`);
      return json(res, 200, {joined: true});
    } catch (error) { return json(res, 400, {error: error.message}); }
  }

  async http(req, res) {
    const url = new URL(req.url, 'http://localhost');
    if (url.pathname === '/api/local/status' && req.method === 'GET')
      return json(res, 200, {selfhost: true, players: [...this.peers].filter(p => p.ready).length,
        discordLoginAvailable: this.discord.enabled,
        joinCodeRequired: !!JOIN_CODE, lanAccessible: process.env.BIND_HOST === '0.0.0.0',
        allowedHosts: (process.env.ZGTA_ALLOWED_HOSTS || '').split(',').filter(Boolean),
        features: ['local accounts', 'player positions', 'chat', 'local settings',
          'jobs and cash', 'garage ownership', 'home ownership', 'multiplayer races',
          'combat and passive mode', 'wanted levels and arrests', 'crews and territory',
          'cash transfers and leaderboard', 'private groups and group chat',
          'police patrol and pizza delivery missions',
          'saved exploration trail',
          'client catalogs']});
    if (url.pathname === '/api/local/diagnostics' && process.env.ZGTA_DEBUG_SELFHOST === '1') {
      const keys = ['x', 'y', 'z', 'at', 'position', 'car', 'walking', 'driving', 'heading',
        'pitch', 'roll', 'speed', 'steer', 'health', 'life', 'weapon', 'act', 'clock'];
      return json(res, 200, {peers: [...this.peers].map(p => ({ready: p.ready,
        stateKeys: Object.keys(p.state || {}),
        sample: Object.fromEntries(keys.filter(k => p.state && k in p.state).map(k => [k, p.state[k]]))}))});
    }
    const {id, player} = this.ensurePlayer(req, res);
    if (url.pathname === '/api/local/discord/start' && req.method === 'GET')
      return this.discordStart(req, res);
    if (url.pathname === '/api/local/state' && req.method === 'GET')
      return json(res, 200, this.gameplayState(player));
    if (url.pathname === '/api/local/action' && req.method === 'POST') {
      try {
        const body = await readBody(req, 2048);
        return json(res, 200, this.action(player, body.action, body));
      } catch (error) { return json(res, 400, {error: error.message}); }
    }
    if (url.pathname === '/api/auth/me' && req.method === 'GET')
      return json(res, 200, {id, name: player.name, username: player.name,
        loggedIn: true, available: true, rank: 'player', admin: false, local: true});
    if (url.pathname === '/api/auth/discord/login')
      return json(res, 409, {error: 'Local accounts are active; Discord is not required.'});
    if (url.pathname === '/api/settings') {
      if (req.method === 'GET') return json(res, 200, {settings: player.settings});
    }
    if (url.pathname.startsWith('/api/settings/')) {
      let key;
      try { key = decodeURIComponent(url.pathname.slice('/api/settings/'.length)); }
      catch { return json(res, 400, {error: 'Invalid setting'}); }
      if (!/^[a-zA-Z0-9_.-]{1,80}$/.test(key)) return json(res, 400, {error: 'Invalid setting'});
      if (req.method === 'PUT') {
        try { player.settings[key] = await readBody(req); this.save(); return json(res, 200, {ok: true}); }
        catch (error) { return json(res, 400, {error: error.message}); }
      }
      if (req.method === 'DELETE') { delete player.settings[key]; this.save(); return json(res, 200, {ok: true}); }
    }
    if (url.pathname === '/api/garage' && req.method === 'GET')
      return json(res, 200, {cars: this.gameplayState(player).cars});
    if (url.pathname === '/api/world/cars' && req.method === 'GET')
      return json(res, 200, {cars: [...this.vehicles.values()].map(vehicle => vehicle.row)});
    if (url.pathname === '/api/local/profile') {
      if (req.method === 'GET') return json(res, 200, {name: player.name, number: player.number});
      if (req.method === 'PUT') {
        try {
          const body = await readBody(req);
          const name = safeName(body.name);
          if (!name) return json(res, 400, {error: 'Enter a name'});
          player.name = name;
          this.save();
          for (const peer of this.peers) if (peer.player === player) peer.send({t: 'note', text: `Your local name is ${name}.`});
          return json(res, 200, {name, number: player.number});
        } catch (error) { return json(res, 400, {error: error.message}); }
      }
    }
    return json(res, 501, {error: 'This original-server feature is not implemented in self-hosted mode.'});
  }

  upgrade(req, socket, head) {
    if (!this.authorized(req)) {
      socket.end('HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n'); return;
    }
    if (new URL(req.url, 'http://localhost').pathname !== '/api/world/live' ||
        req.headers.upgrade?.toLowerCase() !== 'websocket' ||
        !/^[A-Za-z0-9+/]{22}==$/.test(req.headers['sec-websocket-key'] || '')) {
      socket.end('HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n'); return;
    }
    if (this.peers.size >= MAX_PEERS) {
      socket.end('HTTP/1.1 503 Service Unavailable\r\nConnection: close\r\n\r\n'); return;
    }
    const {id, player} = this.ensurePlayer(req);
    for (const old of this.peers) if (old.player === player) old.close();
    const accept = crypto.createHash('sha1').update(req.headers['sec-websocket-key'] +
      '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
    const secure = req.headers['x-forwarded-proto'] === 'https' ? '; Secure' : '';
    socket.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n' +
      `Sec-WebSocket-Accept: ${accept}\r\n` +
      `Set-Cookie: ${COOKIE}=${id}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${COOKIE_MAX_AGE}${secure}\r\n` + '\r\n');
    const peer = new Peer(socket, player, this);
    this.peers.add(peer);
    socket.on('data', bytes => peer.receive(bytes));
    socket.on('error', () => peer.close());
    socket.on('close', () => peer.close());
    if (head.length) peer.receive(head);
  }

  onMessage(peer, message) {
    if (!message || typeof message !== 'object') return;
    if (message.t === 'hi') {
      peer.ready = true;
      peer.send({t: 'hello', protocol: 38, time: Date.now(), day: {shift: 0, hold: null},
        weather: 0, account: true, admin: false, rank: 'player',
        spot: [1480, -1738, 13, 0],
        life: [peer.player.health, peer.player.armour], out: [1480, -1738],
        zombies: false, traffic: 0, peds: 0, party: 0});
      peer.send(this.fullState(peer));
      peer.send(this.owned(peer.player));
      peer.send(this.homeStatus(peer.player));
      peer.send({t: 'passive', on: peer.player.passive,
        w: Math.max(0, Math.ceil((peer.player.passiveWaitUntil - Date.now()) / 1000))});
      peer.send(this.wantedPacket(peer.player));
      return;
    }
    if (!peer.ready) return;
    if (message.t === 'ping') return peer.send({t: 'pong', c: message.c, s: Date.now()});
    if (message.t === 'shot') return this.handleShot(peer, message);
    if (message.t === 'hit') return this.handleHit(peer, message);
    if (message.t === 'me') {
      const previous = peer.state;
      if (peer.player.job && !peer.player.job.mode && previous && Date.now() - peer.lastSeen < 5000 &&
          (message.walking === true || message.driving === true) &&
          Number.isFinite(message.x) && Number.isFinite(message.y) &&
          Number.isFinite(previous.x) && Number.isFinite(previous.y)) {
        const step = Math.hypot(message.x - previous.x, message.y - previous.y);
        if (step >= 0.2 && step <= 10) {
          peer.player.job.progress = Math.min(peer.player.job.goal,
            peer.player.job.progress + step);
          this.save();
        }
      }
      peer.state = message;
      peer.lastSeen = Date.now();
      const flight = peer.player.job;
      if (flight?.mode === 'flight') {
        const plane = this.vehicles.get(flight.vehicleId);
        const aboard = message.driving === true && message.vehicle === flight.vehicleId &&
          message.car === plane?.row[2];
        const from = airportAt(flight.from), to = airportAt(flight.to);
        if (aboard && Number.isFinite(message.health) && message.health >= 0 &&
            message.health <= 1000) {
          const firstReport = !flight.reportedHealth;
          flight.reportedHealth = true;
          const health = Math.round(message.health);
          const damaged = health < flight.minHealth;
          if (damaged) flight.minHealth = health;
          if (firstReport || damaged) this.save();
        }
        if (aboard && from && to && Number.isFinite(message.z) &&
            flight.stage === 'takeoff' && message.z >= from.runway[2] + 35) {
          flight.stage = 'landing';
          this.save();
          this.note(peer.player, `Airborne. Land the marked ${pilotAircraft(flight.model || 593)?.name || 'aircraft'} at ${to.name}.`);
        }
        if (flight.stage === 'landing') {
          const stopped = aboard && to && [message.x, message.y, message.z].every(Number.isFinite) &&
            Math.hypot(message.x - to.runway[0], message.y - to.runway[1]) <=
              (pilotAircraft(flight.model || 593)?.radius || 70) &&
            Math.abs(message.z - to.runway[2]) <= 16 &&
            Math.abs(finite(message.speed)) <= 1.5;
          if (stopped) flight.landingSince ||= Date.now();
          else flight.landingSince = null;
        }
      }
      const fare = peer.player.job;
      if (fare?.id === 'taxi' && fare.mode === 'route' &&
          message.driving === true && message.vehicle === fare.vehicleId &&
          message.car === this.vehicles.get(fare.vehicleId)?.row[2] &&
          Number.isFinite(message.health) && message.health >= 0 &&
          message.health <= 1000) {
        fare.reportedHealth = true;
        const health = Math.round(message.health);
        if (health < fare.minHealth) fare.minHealth = health;
        this.save();
      }
      const reportedHealth = message.walking === true ? message.health :
        message.driving === true ? message.life : null;
      if (Number.isFinite(reportedHealth) && reportedHealth >= 0 && reportedHealth <= 100) {
        const health = Math.round(reportedHealth);
        if (health < peer.player.health) {
          peer.player.health = health;
          if (health === 0) {
            peer.player.deaths = money(peer.player.deaths + 1);
            peer.player.lastDeath = Date.now();
            this.abortHeist(peer.player, 'you were defeated');
          }
          this.save();
        } else if (peer.player.health === 0 && health > 0 &&
            Date.now() - (peer.player.lastDeath || 0) > 2000) {
          peer.player.health = health;
          this.save();
        }
      }
      this.updateOwnedVehicle(peer, message);
      this.updateMissionVehicle(peer, message);
      if (typeof message.say === 'string' && message.say.trim()) this.say(peer, message.say);
      return;
    }
    if (message.t === 'centre') {
      return peer.send({t: 'centre', open: !!message.open, jobs: JOBS.map(job => ({
        job: job.id, name: job.name, start: `/job ${job.id}`,
        marked: false, starts: [], spots: []}))});
    }
    if (message.t === 'spawn') {
      try {
        if (!Number.isInteger(message.own) || message.own < 0 ||
            message.own >= peer.player.cars.length ||
            this.vehicleCode(peer.player, message.own) !== message.car)
          throw new Error('Buy this car before spawning it.');
        this.spawnOwnedCar(peer.player, message.own);
      } catch (error) { peer.send({t: 'note', text: error.message}); }
      return;
    }
    if (message.t === 'enter' || message.t === 'jack') {
      const vehicle = this.vehicles.get(message.v);
      return peer.send({t: message.t, v: message.v,
        ok: !!vehicle && (!vehicle.missionOwner || vehicle.missionOwner === peer.player)});
    }
    if (message.t === 'who' && Array.isArray(message.ids))
      return peer.send({t: 'cars', c: [...this.peers].filter(p => p !== peer && message.ids.includes(String(p.player.number)))
        .map(p => this.row(p)).filter(Boolean)});
    if (message.t === 'board') return peer.send(this.board(peer));
    if (message.t === 'home') return peer.send(this.homeStatus(peer.player));
    if (message.t === 'tongue') return;
  }

  say(peer, raw) {
    const text = raw.trim().slice(0, 240);
    if (!text) return;
    if (text.startsWith('/name ')) {
      const name = safeName(text.slice(6));
      if (name) { peer.player.name = name; this.save(); peer.send({t: 'note', text: `Your local name is ${name}.`}); }
      return;
    }
    if (text === '/players') {
      peer.send(this.board(peer));
      peer.send({t: 'note', text: `${[...this.peers].filter(p => p.ready).length} local player(s) online.`});
      return;
    }
    if (text === '/party')
      return peer.send({t: 'note', text: 'Group commands: /party create, invite NUMBER, accept, decline, leave, kick NUMBER. Type /p MESSAGE for private group chat.'});
    if (text.startsWith('/party ') || text.startsWith('/p ')) {
      try {
        if (text.startsWith('/p ')) this.action(peer.player, 'party.chat', {text: text.slice(3)});
        else {
          const [command, number] = text.slice(7).trim().split(/\s+/, 2);
          if (!['create', 'invite', 'accept', 'decline', 'leave', 'kick'].includes(command))
            throw new Error('Unknown group command. Type /party for help.');
          this.action(peer.player, `party.${command}`, {number: Number(number)});
        }
      } catch (error) { peer.send({t: 'note', text: error.message}); }
      return;
    }
    if (text === '/owned' || text === '/mycars' || text === '/garage')
      return peer.send(this.owned(peer.player)), peer.send(this.homeStatus(peer.player));
    if (text === '/home' || text === '/home doors')
      return peer.send(this.homeStatus(peer.player));
    if (text.startsWith('/home ')) {
      peer.send({t: 'note', text: 'Property interiors and house actions are not available on this local server yet.'});
      return;
    }
    if (text === '/balance' || text === '/money')
      return peer.send({t: 'note', text: `Balance: $${peer.player.cash}. Jobs completed: ${peer.player.jobsDone}.`});
    if (text === '/supplies')
      return peer.send({t: 'note', text: `Workshop supplies: ${SUPPLIES.map(item =>
        `${item.name} ${peer.player.supplies[item.id]}/${item.capacity}`).join(', ')}. Buy at a ground dealership; use F6 or /buykit, /usekit SLOT, /givekit PLAYER, /buypaint, /usepaint SLOT, /givepaint PLAYER.`});
    if (text === '/discord')
      return peer.send({t: 'note', text: 'ZGTA:SA community: https://discord.gg/Cg39cguVUa. Joining is optional.'});
    if (text === '/jobs')
      return peer.send({t: 'note', text: `Local jobs: ${JOBS.map(job => `${job.id} ($${job.pay})`).join(', ')}. Type /job <name>.`});
    if (text === '/explore')
      return peer.send({t: 'note', text: 'Exploration: /explore track LOCATION, /explore claim, /explore clear. F6 lists every location.'});
    if (text.startsWith('/explore ')) {
      try {
        const command = text.slice(9).trim();
        if (command === 'claim') this.action(peer.player, 'explore.claim', {});
        else if (command === 'clear') this.action(peer.player, 'explore.track', {id: null});
        else if (command.startsWith('track '))
          this.action(peer.player, 'explore.track', {id: command.slice(6).trim()});
        else throw new Error('Type /explore for commands.');
      } catch (error) { peer.send({t: 'note', text: error.message}); }
      return;
    }
    if (text === '/wanted')
      return peer.send({t: 'note', text: `Wanted level: ${peer.player.wanted}/6. Passive mode: ${peer.player.passive ? 'on' : 'off'}.`});
    if (text === '/passive' || text === '/police' || text.startsWith('/arrest ')) {
      try {
        const action = text === '/passive' ? 'safety.passive' :
          text === '/police' ? 'police.duty' : 'police.arrest';
        this.action(peer.player, action,
          action === 'police.arrest' ? {number: Number(text.slice(8))} : {});
      } catch (error) { peer.send({t: 'note', text: error.message}); }
      return;
    }
    if (text === '/race')
      return peer.send({t: 'note', text: 'Race commands: /race create, join, start, checkpoint, finish, leave. F6 shows the current lobby and objectives.'});
    if (text.startsWith('/race ')) {
      try {
        const command = text.slice(6).trim();
        if (!['create', 'join', 'start', 'checkpoint', 'finish', 'leave'].includes(command))
          throw new Error('Unknown race command. Type /race for help.');
        this.action(peer.player, `race.${command}`, {});
      } catch (error) { peer.send({t: 'note', text: error.message}); }
      return;
    }
    if (text.startsWith('/job ') || ['/pickup', '/checkpoint', '/repair', '/deliver', '/finish', '/canceljob',
        '/respond', '/extinguish', '/rescue', '/rob'].includes(text) ||
        text.startsWith('/buycar ') || text.startsWith('/spawncar ') || text.startsWith('/storecar ') ||
        text.startsWith('/repaircar ') || text.startsWith('/respraycar ') ||
        ['/buykit', '/buypaint'].includes(text) ||
        text.startsWith('/usekit ') || text.startsWith('/givekit ') ||
        text.startsWith('/usepaint ') || text.startsWith('/givepaint ') ||
        text.startsWith('/buyhome ')) {
      try {
        const [command, value, extra] = text.slice(1).trim().split(/\s+/, 3);
        const actions = {job: ['job.start', {job: value,
          ...(value === 'pilot' && extra ? {model: Number(extra)} : {})}],
          rob: ['heist.rob', {}], pickup: ['job.pickup', {}],
          checkpoint: ['job.checkpoint', {}], repair: ['job.complete', {}],
          respond: ['job.respond', {}], extinguish: ['job.extinguish', {}],
          rescue: ['job.complete', {}],
          deliver: [peer.player.job?.id === 'pizza' && peer.player.job.index < 2 ?
            'job.checkpoint' : 'job.complete', {}], finish: ['job.complete', {}],
          canceljob: ['job.cancel', {}], buycar: ['car.buy', {model: value}],
          spawncar: ['car.spawn', {slot: Number(value) - 1}],
          storecar: ['car.store', {slot: Number(value) - 1}],
          repaircar: ['car.repair', {slot: Number(value) - 1}],
          respraycar: ['car.respray', {slot: Number(value) - 1}],
          buykit: ['supply.buy', {item: 'repair_kit'}],
          usekit: ['supply.use', {item: 'repair_kit', slot: Number(value) - 1}],
          givekit: ['supply.give', {item: 'repair_kit', number: Number(value)}],
          buypaint: ['supply.buy', {item: 'paint_can'}],
          usepaint: ['supply.use', {item: 'paint_can', slot: Number(value) - 1}],
          givepaint: ['supply.give', {item: 'paint_can', number: Number(value)}],
          buyhome: ['home.buy', {home: value}]};
        const [action, input] = actions[command];
        this.action(peer.player, action, input);
      } catch (error) { peer.send({t: 'note', text: error.message}); }
      return;
    }
    const line = [++this.chatSequence, peer.player.name, text, peer.player.number, 0, '', 0, ''];
    this.chat.push(line);
    if (this.chat.length > 100) this.chat.shift();
    for (const p of this.peers) if (p.ready) p.send({t: 'chat', lines: [line]});
  }

  row(peer) {
    const s = peer.state;
    if (!s || Date.now() - peer.lastSeen > 10000) return null;
    const driving = s.driving === true && typeof s.car === 'string';
    const walking = !driving && s.walking === true && Number.isInteger(s.skin);
    if (!driving && !walking) return null;
    const point = Array.isArray(s.at) ? s.at : Array.isArray(s.position) ? s.position : null;
    const x = finite(s.x, point ? finite(point[0]) : 1480);
    const y = finite(s.y, point ? finite(point[1]) : -1738);
    const z = finite(s.z, point ? finite(point[2]) : 13);
    const row = Array(50).fill(null);
    row[0] = String(peer.player.number);
    row[1] = peer.player.name;
    row[2] = driving ? s.car.slice(0, 64) : `s${s.skin}`;
    row[3] = rounded(x); row[4] = rounded(y); row[5] = rounded(z);
    row[6] = rounded(s.heading); row[7] = rounded(s.pitch); row[8] = rounded(s.roll);
    row[9] = rounded(limited(s.speed, 150)); row[10] = rounded(limited(s.steer, 1));
    row[11] = s.boost ? 1 : 0;
    row[12] = s.lights ? 1 : 0;
    row[13] = rounded(limited(s.vx, 150)); row[14] = rounded(limited(s.vy, 150));
    row[15] = rounded(limited(s.vz, 150));
    row[16] = Math.round(finite(s.clock, Date.now()));
    row[17] = typeof s.horn === 'boolean' ? Number(s.horn) : Number.isInteger(s.horn) ? s.horn & 3 : 0;
    row[18] = walking ? peer.player.health :
      Math.round(Math.max(0, Math.min(1000, finite(s.health, 1000))));
    row[19] = typeof s.damage === 'string' ? s.damage.slice(0, 512) : '';
    row[20] = rounded(limited(s.wx, 30)); row[21] = rounded(limited(s.wy, 30));
    row[22] = rounded(limited(s.wz, 30));
    row[23] = Math.round(Math.max(0, limited(s.lag, 2000)));
    row[24] = walking ? rounded(Math.max(0, limited(s.move, 3))) : 0;
    row[25] = walking && s.air ? 1 : 0;
    row[26] = s.crouch ? 1 : 0;
    row[27] = walking || (driving && s.aim !== undefined) ?
      (Number.isInteger(s.weapon) ? s.weapon : 0) : 0;
    row[28] = (walking || (driving && s.aim !== undefined)) && Number.isFinite(s.aim) ?
      rounded(limited(s.aim, 1.6)) : null;
    row[29] = (walking || (driving && s.aim !== undefined)) && Number.isFinite(s.shots) ?
      Math.max(0, s.shots) : 0;
    row[30] = Math.round(Math.max(0, Math.min(100, finite(s.armour))));
    row[31] = driving && Number.isInteger(s.skin) ? s.skin : 0;
    row[32] = Number.isInteger(s.act) ? s.act : 0;
    const riding = walking && typeof s.riding === 'string' ?
      [s.riding.slice(0, 64), Number.isInteger(s.seat) ? s.seat : 0] : null;
    row[33] = walking && !riding && typeof s.car === 'string' && s.parked &&
      typeof s.parked === 'object' ? [s.car.slice(0, 64),
        rounded(s.parked.x), rounded(s.parked.y), rounded(s.parked.z),
        rounded(s.parked.heading), rounded(s.parked.pitch), rounded(s.parked.roll),
        Math.round(finite(s.parked.health, 1000)),
        typeof s.parked.damage === 'string' ? s.parked.damage.slice(0, 512) : ''] : null;
    row[34] = riding;
    row[35] = typeof s.vehicle === 'string' ? s.vehicle.slice(0, 64) : null;
    row[36] = s.paused ? 1 : 0;
    row[37] = peer.player.number;
    row[38] = walking && !riding && Number.isInteger(s.down) ? s.down : 0;
    row[39] = walking && !riding && s.on && typeof s.on.v === 'string' ?
      [s.on.v.slice(0, 64), rounded(s.on.x), rounded(s.on.y), rounded(s.on.z)] : null;
    row[40] = driving && Number.isFinite(s.smoke) && s.smoke > 0 ? rounded(s.smoke) : null;
    row[41] = walking && !riding && typeof s.anim === 'string' ? s.anim.slice(0, 96) : null;
    row[42] = driving && Array.isArray(s.kit) ? s.kit.slice(0, 16).map(value => rounded(value)) : null;
    row[43] = driving ? peer.player.health : 0;
    return row;
  }

  fullState(peer) {
    return {t: 'all', protocol: 38, number: peer.player.number, world: 1,
      id: String(peer.player.number), you: peer.player.name, out: [1480, -1738],
      time: Date.now(), cash: peer.player.cash, cars: [...this.peers].filter(p => p !== peer).map(p => this.row(p)).filter(Boolean),
      chat: this.chat.slice(-50), vehicles: [...this.vehicles.values()].map(vehicle => vehicle.row),
      objects: [], boomboxes: [], dots: [], vdots: [], orders: []};
  }

  board(peer) {
    const online = [...this.peers].filter(p => p.ready);
    return {t: 'board', you: String(peer.player.number), players: online.length,
      rows: online.map(p => [String(p.player.number), p.player.name, 0, 0, p.player.number])};
  }

  mechanicTick() {
    const now = Date.now();
    for (const player of this.players.values()) {
      const job = player.job;
      if (job?.id !== 'mechanic' || job.mode !== 'service') continue;
      const previous = job.repairTick;
      job.repairTick = now;
      if (!previous) continue;
      const vehicle = this.vehicles.get(job.vehicleId);
      const pos = this.position(player);
      const besideCar = vehicle && pos && pos.peer.state.walking === true &&
        player.health > 0 && Math.hypot(pos.x - vehicle.row[3],
          pos.y - vehicle.row[4]) <= 8;
      if (!besideCar) {
        if (job.repairProgress) {job.repairProgress = 0; this.save();}
        continue;
      }
      if (job.repairStep >= MECHANIC_STAGES.length) {
        this.action(player, 'job.complete', {});
        continue;
      }
      job.repairProgress += Math.min(300, Math.max(0, now - previous));
      if (job.repairProgress >= MECHANIC_STAGE_MS) {
        const finished = MECHANIC_STAGES[job.repairStep];
        job.repairStep++;
        job.repairProgress = 0;
        this.note(player, `${finished[0].toUpperCase()}${finished.slice(1)} repaired${job.repairStep < MECHANIC_STAGES.length ?
          `. Now repair the ${MECHANIC_STAGES[job.repairStep]}.` : '. Roadside call complete.'}`);
      }
      this.save();
    }
  }

  broadcastPositions() {
    this.expireRace();
    this.policeTick();
    this.turfTick();
    this.mechanicTick();
    for (const p of this.peers) {
      if (!p.ready) continue;
      const rows = [...this.peers].filter(other => other !== p).map(other => this.row(other)).filter(Boolean);
      if (rows.length) p.send({t: 'cars', c: rows});
    }
  }

  remove(peer) {
    if (!this.peers.delete(peer)) return;
    if (![...this.peers].some(other => other.player === peer.player)) {
      this.partyInvites.delete(peer.player);
      this.leaveParty(peer.player);
    }
    for (const p of this.peers) if (p.ready) p.send({t: 'gone', id: String(peer.player.number)});
  }
}

class Peer {
  constructor(socket, player, game) {
    this.socket = socket;
    this.player = player;
    this.game = game;
    this.buffer = Buffer.alloc(0);
    this.fragments = [];
    this.fragmentBytes = 0;
    this.ready = false;
    this.state = null;
    this.lastSeen = 0;
    this.closed = false;
    this.messages = 0;
    this.window = Date.now();
  }

  send(message) {
    if (this.closed) return;
    const data = Buffer.from(JSON.stringify(message));
    let header;
    if (data.length < 126) header = Buffer.from([0x81, data.length]);
    else if (data.length < 65536) header = Buffer.from([0x81, 126, data.length >> 8, data.length & 255]);
    else { header = Buffer.alloc(10); header[0] = 0x81; header[1] = 127; header.writeBigUInt64BE(BigInt(data.length), 2); }
    if (this.socket.writable && this.socket.writableLength < 1024 * 1024)
      this.socket.write(Buffer.concat([header, data]));
  }

  receive(bytes) {
    this.buffer = Buffer.concat([this.buffer, bytes]);
    if (this.buffer.length > MAX_FRAME * 2) return this.close();
    while (this.buffer.length >= 2) {
      const first = this.buffer[0], second = this.buffer[1];
      const masked = !!(second & 0x80);
      let length = second & 0x7f, offset = 2;
      if (!masked) return this.close();
      if (length === 126) { if (this.buffer.length < 4) return; length = this.buffer.readUInt16BE(2); offset = 4; }
      else if (length === 127) return this.close();
      if (length > MAX_FRAME || this.buffer.length < offset + 4 + length) return length > MAX_FRAME ? this.close() : undefined;
      const mask = this.buffer.subarray(offset, offset + 4);
      const payload = Buffer.from(this.buffer.subarray(offset + 4, offset + 4 + length));
      this.buffer = this.buffer.subarray(offset + 4 + length);
      for (let i = 0; i < payload.length; i++) payload[i] ^= mask[i & 3];
      const opcode = first & 15;
      if (opcode === 8) return this.close(payload);
      if (opcode === 9) {
        if (payload.length > 125) return this.close();
        this.socket.write(Buffer.from([0x8a, payload.length, ...payload])); continue;
      }
      if (opcode !== 1 && opcode !== 0) continue;
      if (opcode === 1 && this.fragments.length) return this.close();
      if (opcode === 0 && !this.fragments.length) return this.close();
      this.fragments.push(payload);
      this.fragmentBytes += payload.length;
      if (this.fragmentBytes > MAX_FRAME) return this.close();
      if (!(first & 0x80)) continue;
      const text = Buffer.concat(this.fragments).toString('utf8');
      this.fragments = [];
      this.fragmentBytes = 0;
      if (Date.now() - this.window > 1000) { this.window = Date.now(); this.messages = 0; }
      if (++this.messages > 120) return this.close();
      try { this.game.onMessage(this, JSON.parse(text)); } catch (error) { console.error('Local message error:', error.message); }
    }
  }

  close(payload = Buffer.from([3, 232])) {
    if (this.closed) return;
    this.closed = true;
    this.game.remove(this);
    if (this.socket.writable) {
      const reply = payload.length <= 125 ? payload : Buffer.from([3, 232]);
      this.socket.write(Buffer.concat([Buffer.from([0x88, reply.length]), reply]));
      this.socket.end();
    } else this.socket.destroy();
  }
}

// Both localhost and LAN can use one listener. A second process with the same
// save directory would otherwise overwrite newer players when either exits.
const STATE_LOCK = STATE_FILE + '.lock';
function acquireStateLock() {
  fs.mkdirSync(path.dirname(STATE_FILE), {recursive: true});
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const fd = fs.openSync(STATE_LOCK, 'wx', 0o600);
      let written = false;
      try {fs.writeFileSync(fd, String(process.pid)); written = true;}
      finally {
        fs.closeSync(fd);
        if (!written) fs.unlinkSync(STATE_LOCK);
      }
      return;
    } catch (error) {
      if (error.code !== 'EEXIST') throw error;
      const holder = Number(fs.readFileSync(STATE_LOCK, 'utf8').trim());
      if (!Number.isSafeInteger(holder) || holder <= 0)
        throw new Error(`Local player state lock is invalid: ${STATE_LOCK}`);
      let alive = true;
      try {process.kill(holder, 0);}
      catch (problem) {if (problem.code === 'ESRCH') alive = false;}
      if (alive) throw new Error(`Local player state is already in use by PID ${holder}. Use one server for localhost and LAN.`);
      fs.unlinkSync(STATE_LOCK);
    }
  }
  throw new Error(`Could not claim local player state lock: ${STATE_LOCK}`);
}
acquireStateLock();
process.on('exit', () => {
  try {
    if (fs.readFileSync(STATE_LOCK, 'utf8').trim() === String(process.pid))
      fs.unlinkSync(STATE_LOCK);
  } catch (error) {if (error.code !== 'ENOENT') console.error('Could not release local player state lock:', error.message);}
});
const game = new LocalGame();
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => {
  try {game.flushSync();} catch (error) {console.error('Could not save local players:', error.message);}
  process.exit(signal === 'SIGINT' ? 130 : 143);
});
module.exports = game;
