// Small local gameplay panel for the independent server. No copied game assets.
(() => {
  if (document.getElementById('zgta-local-open')) return;
  const css = document.createElement('style');
  css.textContent = `
    #zgta-local-open{position:fixed;right:16px;bottom:18px;z-index:1000;border:1px solid #86a9ff;border-radius:10px;background:#14264f;color:white;padding:10px 14px;font:700 14px system-ui;cursor:pointer;box-shadow:0 4px 18px #0009}
    #zgta-local-shade{position:fixed;inset:0;z-index:1001;display:none;align-items:center;justify-content:center;background:#000b;font:14px system-ui;color:#f5f7ff}
    #zgta-local-shade[data-open="true"]{display:flex}
    #zgta-local-panel{width:min(440px,calc(100vw - 26px));max-height:min(80vh,720px);overflow:auto;border:1px solid #5b719c;border-radius:14px;background:#111b2e;box-shadow:0 15px 60px #000c;padding:18px}
    #zgta-local-panel h2{font-size:22px;margin:0 0 6px}#zgta-local-panel h3{font-size:16px;margin:18px 0 8px;border-top:1px solid #3b4b69;padding-top:13px}
    #zgta-local-panel p{line-height:1.45;margin:6px 0}#zgta-local-panel .zgta-muted{color:#afbdd6;font-size:12px}
    #zgta-local-panel .zgta-row{display:flex;gap:10px;justify-content:space-between;align-items:center;padding:9px 0;border-bottom:1px solid #29364d}
    #zgta-local-panel .zgta-row span{min-width:0}#zgta-local-panel button{border:1px solid #7797dd;border-radius:8px;background:#254785;color:white;padding:7px 10px;font:600 13px system-ui;cursor:pointer;white-space:nowrap}
    #zgta-local-panel button:disabled{opacity:.45;cursor:default}#zgta-local-panel .zgta-close{float:right;background:#263247}
    #zgta-local-panel select{min-width:0;flex:1;border:1px solid #647795;border-radius:8px;background:#172943;color:white;padding:8px;font:13px system-ui}
    #zgta-local-panel input[type=number]{width:95px;border:1px solid #647795;border-radius:8px;background:#172943;color:white;padding:8px;font:13px system-ui}
    #zgta-local-panel input[type=text]{min-width:0;flex:1;border:1px solid #647795;border-radius:8px;background:#172943;color:white;padding:8px;font:13px system-ui}
    #zgta-local-panel a{color:#b7d4ff;text-decoration:underline;text-underline-offset:3px}
    #zgta-route-map{position:relative;width:min(100%,320px);aspect-ratio:1;margin:9px auto 4px;border:2px solid #7895cc;border-radius:9px;overflow:hidden;background:#25344a url('/tools/map/radar.webp') center/100% 100% no-repeat}
    #zgta-route-map svg{position:absolute;inset:0;width:100%;height:100%;pointer-events:none}
    #zgta-route-map .zgta-map-pin{position:absolute;z-index:1;width:13px;height:13px;border:2px solid white;border-radius:50%;box-shadow:0 0 0 3px #0009,0 0 9px #000;transform:translate(-50%,-50%)}
    #zgta-route-map .zgta-map-you{background:#3f9dff}#zgta-route-map .zgta-map-target{background:#ffcf43}
    #zgta-local-result{min-height:22px;color:#b9dcff;font-weight:600}#zgta-local-result[data-error="true"]{color:#ffb0a8}
    #zgta-local-objective{position:fixed;right:16px;top:72px;z-index:1000;max-width:min(330px,calc(100vw - 32px));border:1px solid #86a9ff;border-radius:10px;background:#14264ff0;color:white;padding:10px 14px;font:600 13px/1.45 system-ui;text-align:left;cursor:pointer;box-shadow:0 4px 18px #0009}
    #zgta-local-objective[hidden]{display:none}
    #zgta-waypoint{position:fixed;left:50%;top:14px;transform:translateX(-50%);z-index:1000;display:flex;align-items:center;gap:9px;max-width:min(360px,calc(100vw - 150px));padding:7px 12px;border:1px solid #f9d868;border-radius:12px;background:#15213eea;color:#fff;font:700 13px/1.25 system-ui;box-shadow:0 4px 18px #0009;cursor:pointer}
    #zgta-waypoint[hidden]{display:none}#zgta-waypoint-arrow{font-size:24px;color:#ffdf71;line-height:1}
    #zgta-waypoint-label{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
    @media(max-width:600px){#zgta-waypoint{top:8px;max-width:calc(100vw - 90px);font-size:11px}}
  `;
  document.head.append(css);
  const openButton = document.createElement('button');
  openButton.id = 'zgta-local-open';
  openButton.type = 'button';
  openButton.textContent = 'ZGTA:SA · Local gameplay (F6)';
  const objective = document.createElement('button');
  objective.id = 'zgta-local-objective';
  objective.type = 'button';
  objective.hidden = true;
  const waypoint = document.createElement('button');
  waypoint.id = 'zgta-waypoint';
  waypoint.type = 'button';
  waypoint.hidden = true;
  const waypointArrow = document.createElement('span');
  waypointArrow.id = 'zgta-waypoint-arrow';
  const waypointLabel = document.createElement('span');
  waypointLabel.id = 'zgta-waypoint-label';
  waypoint.append(waypointArrow, waypointLabel);
  const shade = document.createElement('div');
  shade.id = 'zgta-local-shade';
  shade.dataset.open = 'false';
  const panel = document.createElement('section');
  panel.id = 'zgta-local-panel';
  panel.setAttribute('role', 'dialog');
  panel.setAttribute('aria-label', 'ZGTA:SA local gameplay');
  shade.append(panel);
  document.body.append(openButton, objective, waypoint, shade);
  new MutationObserver(() => {
    if (!openButton.isConnected || !objective.isConnected || !waypoint.isConnected ||
        !shade.isConnected)
      document.body.append(openButton, objective, waypoint, shade);
  }).observe(document.documentElement, {childList: true, subtree: true});
  let visible = false;
  let state = null;
  let result = '';
  let error = false;
  let busy = false;
  let selectedCarModel = '';
  let selectedAircraftModel = '';
  let selectedPilotModel = '593';
  let selectedHomeId = '';
  const transferAmounts = new Map();
  let partyDraft = '';
  const automaticAttempts = new Map();

  function element(tag, text, className) {
    const item = document.createElement(tag);
    if (text !== undefined) item.textContent = text;
    if (className) item.className = className;
    return item;
  }
  function section(title) {
    panel.append(element('h3', title));
  }
  function row(label, action, payload, buttonText, disabled = false) {
    const line = element('div', undefined, 'zgta-row');
    line.append(element('span', label));
    const button = element('button', buttonText);
    button.type = 'button';
    button.disabled = disabled || busy;
    button.addEventListener('click', () => perform(action, payload));
    line.append(button);
    panel.append(line);
  }
  function catalogPicker(items, value, onChange, action, payload, disabled, label) {
    if (!items.length) return;
    const line = element('div', undefined, 'zgta-row');
    const select = element('select');
    select.setAttribute('aria-label', label || (action === 'car.buy' ? 'Vehicle catalog' : 'Property catalog'));
    for (const item of items) {
      const unavailable = label === 'Aircraft catalog' && state.hangar?.within &&
        !item.airports?.includes(state.hangar.id) ||
        label === 'Ground dealership catalog' && state.dealer?.within &&
        !item.dealers?.includes(state.dealer.id);
      const option = element('option', `${item.name} · $${item.price.toLocaleString()}` +
        (unavailable ? ' · not sold here' : ''));
      option.value = String(action === 'car.buy' ? item.model : item.id);
      select.append(option);
    }
    if (items.some(item => String(action === 'car.buy' ? item.model : item.id) === String(value)))
      select.value = String(value);
    onChange(select.value);
    select.addEventListener('change', () => {
      onChange(select.value);
      button.disabled = busy || disabled(items.find(item =>
        String(action === 'car.buy' ? item.model : item.id) === select.value));
    });
    const chosen = items.find(item => String(action === 'car.buy' ? item.model : item.id) === select.value);
    const button = element('button', 'Buy selected');
    button.type = 'button';
    button.disabled = busy || disabled(chosen);
    button.addEventListener('click', () => perform(action, payload(select.value)));
    line.append(select, button);
    panel.append(line);
  }
  function renderRouteMap() {
    const race = state.race?.stage === 'running' && state.race.joined && state.race.target;
    const turf = state.turfs?.find(item => item.capturingYou);
    const tracked = state.exploration?.tracked;
    const target = race || state.job?.target || turf || tracked;
    if (!target || !Number.isFinite(target.x) || !Number.isFinite(target.y)) return;
    section('Route map');
    const map = element('div');
    map.id = 'zgta-route-map';
    const toPercent = (x, y) => ({left: Math.max(0, Math.min(100, (x + 3000) / 60)),
      top: Math.max(0, Math.min(100, (3000 - y) / 60))});
    const destination = toPercent(target.x, target.y);
    map.setAttribute('role', 'img');
    map.setAttribute('aria-label', `Route map to ${target.name}`);
    if (state.position) {
      const you = toPercent(state.position.x, state.position.y);
      const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
      svg.setAttribute('viewBox', '0 0 100 100');
      svg.setAttribute('preserveAspectRatio', 'none');
      const line = document.createElementNS('http://www.w3.org/2000/svg', 'line');
      for (const [name, value] of Object.entries({x1: you.left, y1: you.top,
        x2: destination.left, y2: destination.top, stroke: '#ffe178', 'stroke-width': 0.7,
        'stroke-dasharray': '1.5 1'})) line.setAttribute(name, String(value));
      svg.append(line);
      map.append(svg);
      const marker = element('span', undefined, 'zgta-map-pin zgta-map-you');
      marker.style.left = `${you.left}%`;
      marker.style.top = `${you.top}%`;
      map.append(marker);
    }
    const marker = element('span', undefined, 'zgta-map-pin zgta-map-target');
    marker.style.left = `${destination.left}%`;
    marker.style.top = `${destination.top}%`;
    map.append(marker);
    panel.append(map, element('p', `Blue: you · gold: ${target.name}`, 'zgta-muted'));
  }
  function render() {
    if (!visible) return;
    const scrollTop = panel.scrollTop;
    panel.replaceChildren();
    const close = element('button', 'Close', 'zgta-close');
    close.type = 'button';
    close.addEventListener('click', () => toggle(false));
    panel.append(close, element('h2', 'ZGTA:SA local gameplay'));
    if (!state) {
      panel.append(element('p', 'Loading your local account…'));
      return;
    }
    panel.append(element('p', `${state.name} · $${state.cash.toLocaleString()} · ${state.xp} XP`));
    panel.append(element('p', state.connected ? 'Connected to the local world' :
      'Enter the game world to start jobs or spawn a car.', 'zgta-muted'));
    const status = element('p', result);
    status.id = 'zgta-local-result';
    status.dataset.error = String(error);
    panel.append(status);

    section('Account');
    panel.append(element('p', state.discord?.linked ?
      `Discord linked: ${state.discord.name}. Your guest progress remains available.` :
      'Guest play is ready. Discord is optional.', 'zgta-muted'));
    const community = element('a', 'ZGTA:SA community Discord (optional)');
    community.href = 'https://discord.gg/Cg39cguVUa';
    community.target = '_blank';
    community.rel = 'noopener noreferrer';
    panel.append(community);
    panel.append(element('p', `Health ${state.health}/100 · Armour ${state.armour}/100 · Wanted ${state.wanted}/6 · ${state.kills} kills · ${state.deaths} deaths`, 'zgta-muted'));
    if (state.discord?.available && !state.discord.linked) {
      const link = element('button', `Link Discord · one-time $${state.discord.bonus} bonus`);
      link.type = 'button';
      link.addEventListener('click', () => { window.location.href = '/api/local/discord/start'; });
      panel.append(link);
    }

    renderRouteMap();
    section('Jobs and missions');
    if (state.job) {
      if (state.job.mode === 'route') {
        const taxi = state.job.id === 'taxi';
        const medic = state.job.id === 'medic';
        const thief = state.job.id === 'carthief';
        const trucker = state.job.id === 'trucker';
        const task = state.job.stage === 'pickup' ?
          (trucker ? 'Load cargo into the marked Mule' : thief ? 'Take the marked car' : taxi ? 'Collect the passenger' : medic ? 'Collect the patient' : 'Collect the package') :
          (trucker ? 'Deliver cargo in the marked Mule' : thief ? 'Deliver the marked car' : taxi ? 'Drop off the passenger' : medic ? 'Return the patient' : 'Deliver the package');
        panel.append(element('p', `${task} at ${state.job.target.name} (${state.job.target.x}, ${state.job.target.y}). ${state.job.remaining ?? '?'} m away. Get within ${state.job.radius} m.${taxi || medic || thief || trucker ? ' You must be driving.' : ''}${thief || trucker ? ` ${state.job.secondsLeft} s left.` : ''}`, 'zgta-muted'));
        if (trucker) panel.append(element('p', state.job.convoyBonusAwarded ?
          `Your $${state.job.convoyBonus} group convoy bonus was paid.` :
          `A group mate delivering to the same stop in their own Mule within 80 m earns both drivers a $${state.job.convoyBonus} convoy bonus.`, 'zgta-muted'));
        if (state.job.stage === 'pickup')
          row(trucker ? 'Load freight' : thief ? 'Take getaway car' : taxi ? 'Pick up passenger' : medic ? 'Pick up patient' : 'Pick up package',
            'job.pickup', {}, trucker ? 'Load' : thief ? 'Take' : 'Collect', !state.connected || state.job.remaining > state.job.radius ||
              ((thief || trucker) && state.job.secondsLeft <= 0));
        else row(trucker ? 'Deliver freight' : thief ? 'Deliver getaway car' : taxi ? 'Drop off passenger' : medic ? 'Return patient' : 'Deliver package',
          'job.complete', {}, taxi ? 'Drop off' : medic ? 'Return' : 'Deliver',
          !state.connected || state.job.remaining > state.job.radius ||
            ((thief || trucker) && state.job.secondsLeft <= 0));
      } else if (state.job.mode === 'flight') {
        if (state.job.stage === 'takeoff')
          panel.append(element('p', `Board the marked ${state.job.plane} at ${state.job.from} and climb ${state.job.takeoffAltitude} m above the airport. Current height: ${state.job.altitude ?? '?'} m. Destination: ${state.job.target.name}. ${state.job.secondsLeft} s left.`, 'zgta-muted'));
        else panel.append(element('p', `Land at ${state.job.target.name} (${state.job.target.x}, ${state.job.target.y}). ${state.job.remaining ?? '?'} m away. Stop within ${state.job.radius} m and hold still for two seconds. ${state.job.secondsLeft} s left.`, 'zgta-muted'));
        panel.append(element('p', `Bonuses: +$${state.pilot.smoothBonus} for a clean aircraft with reported condition, +$${state.pilot.earlyBonus} with at least two minutes left, +$${state.pilot.fifthBonus} every fifth completed flight in a row.`, 'zgta-muted'));
        row('Complete pilot flight', 'job.complete', {}, 'Finish',
          !state.connected || state.job.stage !== 'landing' ||
          !state.job.landingReady || state.job.secondsLeft <= 0);
      } else if (state.job.mode === 'fire') {
        const fire = state.job;
        const instruction = fire.stage === 'respond' ?
          'Drive the marked fire truck to the incident.' : fire.stage === 'extinguish' ?
            `Suppress fire ${fire.index + 1}/${fire.total} using the marked truck within 23 m or on foot within 8 m.` :
            'Leave the truck and rescue the person on foot within 10 m.';
        panel.append(element('p', `${instruction} ${fire.target.name} (${fire.target.x}, ${fire.target.y}) · ${fire.remaining ?? '?'} m away · ${fire.secondsLeft} s left.`, 'zgta-muted'));
        if (fire.stage === 'respond')
          row('Arrive at fire call', 'job.respond', {}, 'Arrive',
            !state.connected || fire.remaining > 25 || fire.secondsLeft <= 0);
        else if (fire.stage === 'extinguish')
          row(`Suppress fire ${fire.index + 1}`, 'job.extinguish', {}, 'Extinguish',
            !state.connected || fire.remaining > 23 || fire.secondsLeft <= 0);
        else row('Rescue trapped person', 'job.complete', {}, 'Rescue',
          !state.onFoot || fire.remaining > 10 || fire.secondsLeft <= 0);
      } else if (state.job.mode === 'heist') {
        const heist = state.job;
        if (heist.stage === 'plan') {
          panel.append(element('p', `Enter ${heist.target.name} on foot (${heist.target.x}, ${heist.target.y}) to take the bag. ${heist.remaining ?? '?'} m away · ${heist.secondsLeft} s left. The marked Sultan is your getaway car.`, 'zgta-muted'));
          row('Take the heist bag', 'heist.rob', {}, 'Rob',
            !state.onFoot || heist.remaining > heist.radius || heist.secondsLeft <= 0);
        } else {
          panel.append(element('p', `Lose the police, then drive the marked Sultan to ${heist.target.name} (${heist.target.x}, ${heist.target.y}). ${heist.remaining ?? '?'} m away · wanted ${heist.wanted}/6 · ${heist.secondsLeft} s left.`, 'zgta-muted'));
          if (heist.crewCount)
            panel.append(element('p', `${heist.crewCount} group member${heist.crewCount === 1 ? '' : 's'} joined at the robbery. Each nearby member at the drop-off can earn $${heist.crewBonus}.`, 'zgta-muted'));
          row('Deliver heist bag', 'job.complete', {}, 'Deliver',
            !state.connected || heist.remaining > heist.radius ||
            heist.wanted > 0 || heist.secondsLeft <= 0);
        }
      } else if (state.job.mode === 'service') {
        panel.append(element('p', `Repair the stranded vehicle at ${state.job.target.name} (${state.job.target.x}, ${state.job.target.y}). ${state.job.remaining ?? '?'} m away. Stand on foot within ${state.job.radius} m and hold position. Moving away resets the current stage.`, 'zgta-muted'));
        panel.append(element('p', `${state.job.repairPart} · stage ${Math.min(state.job.repairStep + 1, state.job.repairTotal)}/${state.job.repairTotal} · ${state.job.repairProgress}%`, 'zgta-muted'));
      } else if (state.job.mode === 'checkpoints') {
        const pizza = state.job.id === 'pizza';
        panel.append(element('p', `${pizza ? 'Pizza delivery' : 'Checkpoint'} ${state.job.index}/${state.job.total}: ${state.job.target.name} (${state.job.target.x}, ${state.job.target.y}). ${state.job.remaining ?? '?'} m away. ${state.job.secondsLeft} s left. Drive ${state.job.id === 'patrol' ? 'the marked police car ' : pizza ? 'the marked Pizzaboy scooter ' : ''}within ${state.job.radius} m.`, 'zgta-muted'));
        row(pizza ? (state.job.index === state.job.total ? 'Deliver final pizza' : 'Deliver pizza') :
          state.job.index === state.job.total ?
            (state.job.id === 'patrol' ? 'Finish patrol' : 'Finish time trial') : 'Pass checkpoint',
          state.job.index === state.job.total ? 'job.complete' : 'job.checkpoint', {},
          pizza ? 'Deliver' : state.job.index === state.job.total ? 'Finish' : 'Pass',
          !state.connected || state.job.remaining > state.job.radius || state.job.secondsLeft <= 0);
      } else {
        panel.append(element('p', `${state.job.name}: travel ${state.job.remaining} m more (${state.job.progress}/${state.job.goal} m).`, 'zgta-muted'));
        row('Route completed?', 'job.complete', {}, 'Complete', !state.connected || state.job.remaining > 0);
      }
      row('End this task', 'job.cancel', {}, 'Cancel');
    } else {
      for (const job of state.catalog.jobs)
        row(`${job.name} · earn $${job.pay}${['taxi', 'trial'].includes(job.id) ? ' · needs a car' : ''}${job.id === 'carthief' ? ' · five-minute mission' : ''}${job.id === 'patrol' ? ' · police duty · loaner car' : ''}${job.id === 'pizza' ? ' · six-minute route · loaner scooter' : ''}${job.id === 'trucker' ? ' · seven-minute route · loaner Mule' : ''}${job.id === 'pilot' ? ' · ten-minute flight · loaner Dodo' : ''}${job.id === 'fire' ? ' · eight-minute call · loaner fire truck' : ''}${job.id === 'heist' ? ` · ten-minute route · loaner Sultan${state.heistCooldown ? ` · ${state.heistCooldown} s cooldown` : ''}` : ''}`,
          'job.start', {job: job.id}, 'Start', !state.connected ||
            (['taxi', 'trial'].includes(job.id) && !state.cars.length) ||
            (job.id === 'carthief' && (state.passive || state.policeDuty)) ||
            (job.id === 'heist' && (state.passive || state.policeDuty ||
              state.wanted > 0 || state.heistCooldown > 0)) ||
            (job.id === 'patrol' && !state.policeDuty) ||
            (state.race?.joined && ['lobby', 'running'].includes(state.race.stage)));
    }
    section('Pilot record');
    panel.append(element('p', `Level ${state.pilot.level} · ${state.pilot.flights} flights completed · ${state.pilot.streak} in a row · ${5 - state.pilot.streak % 5} until the next fifth-flight bonus. Every three completed flights unlocks a level; cancelling breaks the streak.`, 'zgta-muted'));
    if (!state.job && state.pilot.aircraft?.length) {
      const line = element('div', undefined, 'zgta-row');
      const select = element('select');
      select.setAttribute('aria-label', 'Pilot aircraft');
      for (const plane of state.pilot.aircraft) {
        const option = element('option', `${plane.name} · level ${plane.level}${plane.premium ? ` · +$${plane.premium}` : ''}`);
        option.value = String(plane.model);
        option.disabled = !plane.unlocked;
        select.append(option);
      }
      if (state.pilot.aircraft.some(item => item.unlocked && String(item.model) === selectedPilotModel))
        select.value = selectedPilotModel;
      else select.value = '593';
      selectedPilotModel = select.value;
      select.addEventListener('change', () => {selectedPilotModel = select.value;});
      const fly = element('button', 'Fly selected');
      fly.type = 'button';
      fly.disabled = busy || !state.connected ||
        (state.race?.joined && ['lobby', 'running'].includes(state.race.stage));
      fly.addEventListener('click', () => perform('job.start',
        {job: 'pilot', model: Number(select.value)}));
      line.append(select, fly);
      panel.append(line);
    }
    section('Multiplayer race');
    const race = state.race;
    if (!race || race.stage === 'finished') {
      if (race?.results.length)
        panel.append(element('p', `Last race: ${race.results.map(item =>
          `#${item.place} ${item.name} · ${item.seconds}s · $${item.pay}`).join(' | ')}`, 'zgta-muted'));
      row('Open a three-checkpoint race with loaner cars · first $600, second $400',
        'race.create', {}, 'Create', !state.connected || !!state.job);
    } else {
      panel.append(element('p', `${race.host}'s ${race.stage} race · ${race.players.map(item =>
        `${item.name} (${item.status})`).join(', ')}`, 'zgta-muted'));
      if (race.stage === 'lobby') {
        panel.append(element('p', `Starting line: ${race.start.x}, ${race.start.y} · ${race.startDistance ?? '?'} m away. Join within 25 m.`, 'zgta-muted'));
        if (!race.joined) row('Join the race', 'race.join', {}, 'Join',
          !state.connected || !!state.job || race.startDistance > 25);
        else {
          if (race.isHost) row('Start with two or more players near the line',
            'race.start', {}, 'Start', race.players.length < 2 || race.startDistance > 25);
          row(race.isHost ? 'Cancel this lobby' : 'Leave this lobby',
            'race.leave', {}, race.isHost ? 'Cancel' : 'Leave');
        }
      } else if (race.joined && race.target) {
        panel.append(element('p', `Checkpoint ${race.index}/${race.total}: ${race.target.name} (${race.target.x}, ${race.target.y}). ${race.remaining ?? '?'} m away. ${race.secondsLeft} s left. Drive within ${race.radius} m.`, 'zgta-muted'));
        const final = race.index === race.total;
        row(final ? 'Finish race' : 'Pass checkpoint',
          final ? 'race.finish' : 'race.checkpoint', {}, final ? 'Finish' : 'Pass',
          !state.connected || race.remaining > race.radius || race.secondsLeft <= 0);
        row('Withdraw from race', 'race.leave', {}, 'Leave');
      } else if (race.joined)
        panel.append(element('p', 'Your race is complete. Waiting for the remaining drivers.', 'zgta-muted'));
    }
    if (state.raceLeaders?.length) {
      panel.append(element('p', 'Saved race standings · ranked by wins, then finishes', 'zgta-muted'));
      for (const entry of state.raceLeaders)
        panel.append(element('p', `#${entry.place} ${entry.name} · ${entry.wins} wins · ${entry.finishes} finishes`, 'zgta-muted'));
    }
    section('Safety and police');
    row(`Passive mode ${state.passive ? 'on' : 'off'}${state.passiveWait ?
      ` · ${state.passiveWait} s cooldown` : ''}`, 'safety.passive', {},
      state.passive ? 'Turn off' : 'Turn on', !state.connected ||
        (!state.passive && (state.wanted > 0 || state.policeDuty || state.passiveWait > 0 ||
          ['carthief', 'heist'].includes(state.job?.id))));
    row(`Police duty ${state.policeDuty ? 'on' : 'off'} · ${state.arrests} arrests`,
      'police.duty', {}, state.policeDuty ? 'End duty' : 'Start duty',
      !state.connected || (!state.policeDuty && (state.wanted > 0 || state.passive ||
        ['carthief', 'heist'].includes(state.job?.id))));
    if (state.policeDuty) {
      if (!state.nearbyWanted.length)
        panel.append(element('p', 'No wanted players within 30 m. Arrests require both players on foot within 4 m.', 'zgta-muted'));
      for (const suspect of state.nearbyWanted)
        row(`${suspect.name} · wanted ${suspect.wanted} · ${suspect.distance} m`,
          'police.arrest', {number: suspect.number}, 'Arrest',
          !state.onFoot || suspect.distance > 4);
    }
    section('Crews and territories');
    panel.append(element('p', state.gang ?
      `Your crew: ${state.gangs.find(item => item.id === state.gang)?.name || state.gang} · ${state.turfCaptures} captures` :
      'Join a crew to contest territory. Guest accounts can join.', 'zgta-muted'));
    for (const gang of state.gangs)
      row(gang.name, 'gang.join', {gang: gang.id},
        state.gang === gang.id ? 'Joined' : 'Join',
        state.gang === gang.id || state.gangSwitchWait > 0);
    if (state.gangSwitchWait)
      panel.append(element('p', `Crew change available in ${state.gangSwitchWait} s.`, 'zgta-muted'));
    const myCapture = state.turfs.find(turf => turf.capturingYou);
    for (const turf of state.turfs) {
      const owner = state.gangs.find(item => item.id === turf.owner)?.name || 'Unclaimed';
      const capturing = turf.capturing ?
        ` · ${state.gangs.find(item => item.id === turf.capturing)?.name || turf.capturing} capturing ${turf.progress}%${turf.contested ? ' (contested)' : ''}` : '';
      const label = `${turf.name} · ${owner}${capturing} · ${turf.distance ?? '?'} m`;
      if (turf.capturingYou)
        row(label, 'turf.leave', {}, 'Cancel');
      else row(label, 'turf.start', {turf: turf.id}, 'Capture',
        !state.gang || !state.onFoot || state.passive || !!state.job ||
        turf.owner === state.gang || !!turf.capturing || !!myCapture ||
        turf.distance === null || turf.distance > 20);
    }
    section('Exploration trail');
    panel.append(element('p', `${state.exploration.found}/${state.exploration.total} locations found · $${state.exploration.reward} and 20 XP each · $${state.exploration.finishReward} completion bonus`, 'zgta-muted'));
    for (const place of state.exploration.items) {
      const label = `${place.name} · ${place.city.toUpperCase()} · ${place.found ? 'found' : `${place.distance ?? '?'} m away`}`;
      if (place.found) row(label, 'explore.track', {}, 'Found', true);
      else if (state.connected && state.onFoot && place.distance !== null && place.distance <= 12)
        row(label, 'explore.claim', {id: place.id}, 'Discover');
      else if (state.exploration.tracked?.id === place.id)
        row(label, 'explore.track', {id: null}, 'Untrack');
      else row(label, 'explore.track', {id: place.id}, 'Track');
    }
    section('Private group');
    if (state.party.invite) {
      panel.append(element('p', `${state.party.invite.from} invited you to a group · ${state.party.invite.secondsLeft} s left.`, 'zgta-muted'));
      row('Join this group', 'party.accept', {}, 'Accept');
      row('Ignore this invitation', 'party.decline', {}, 'Decline');
    }
    const group = state.party.group;
    if (!group) row('Create a group for up to four players', 'party.create', {}, 'Create');
    else {
      panel.append(element('p', `${group.leader}'s group · ${group.members.length}/4 players · session only`, 'zgta-muted'));
      for (const member of group.members)
        if (group.isLeader && member.number !== state.party.you)
          row(member.name, 'party.kick', {number: member.number}, 'Remove');
        else panel.append(element('p', `${member.name}${member.number === group.leaderNumber ? ' · leader' : ''}`, 'zgta-muted'));
      const line = element('div', undefined, 'zgta-row');
      const draft = element('input');
      draft.type = 'text'; draft.maxLength = 160; draft.value = partyDraft;
      draft.placeholder = 'Message your group';
      draft.setAttribute('aria-label', 'Private group message');
      draft.addEventListener('input', () => {partyDraft = draft.value;});
      draft.addEventListener('keydown', event => {
        if (event.key === 'Enter') perform('party.chat', {text: draft.value});
      });
      const send = element('button', 'Send');
      send.type = 'button'; send.disabled = busy;
      send.addEventListener('click', () => perform('party.chat', {text: draft.value}));
      line.append(draft, send); panel.append(line);
      row('Leave this group', 'party.leave', {}, 'Leave');
    }
    if (!group || group.isLeader) for (const candidate of state.party.candidates)
      row(`Invite ${candidate.name}`, 'party.invite', {number: candidate.number}, 'Invite',
        !!group && group.members.length >= 4);
    section('Players and cash');
    if (!state.nearbyPlayers.length)
      panel.append(element('p', 'No other players within 15 m. Cash transfers require 8 m.', 'zgta-muted'));
    for (const other of state.nearbyPlayers) {
      const line = element('div', undefined, 'zgta-row');
      line.append(element('span', `${other.name} · ${other.distance} m`));
      const input = element('input');
      input.type = 'number'; input.min = '1'; input.max = '1000000';
      input.step = '1'; input.value = transferAmounts.get(other.number) || '50';
      input.setAttribute('aria-label', `Cash for ${other.name}`);
      input.addEventListener('input', () => transferAmounts.set(other.number, input.value));
      const send = element('button', 'Give cash');
      send.type = 'button';
      send.disabled = busy || other.distance > 8 || state.cash < 1;
      send.addEventListener('click', () => perform('money.transfer',
        {number: other.number, amount: Number(input.value)}));
      line.append(input, send);
      panel.append(line);
    }
    panel.append(element('p', `Local leaderboard · top ${state.leaderboard.length} by XP`, 'zgta-muted'));
    for (const entry of state.leaderboard)
      panel.append(element('p', `#${entry.place} ${entry.name} · ${entry.xp} XP · ${entry.jobsDone} jobs · ${entry.racesWon} race wins · ${entry.turfCaptures} captures`, 'zgta-muted'));
    section('Garage');
    if (state.homeParking) panel.append(element('p',
      `${state.homeParking.name} parking · ${state.homeParking.distance} m away · ${state.homeParking.occupied}/${state.homeParking.capacity} spaces used. Park and retrieve cars at its exterior.`,
      'zgta-muted'));
    if (state.cars.length === 0) panel.append(element('p', 'No cars owned yet.', 'zgta-muted'));
    state.cars.forEach((car, slot) => {
      const garage = state.garage?.[slot];
      const aircraft = car.type === 'plane' || car.type === 'helicopter';
      const condition = garage ? ` · ${Math.round(garage.health / 10)}% condition${garage.paint ? ' · custom paint' : ''}` : '';
      row(`${car.name} · ${garage?.active ? 'out' : garage?.parkedHomeName ?
        `parked at ${garage.parkedHomeName}` : 'stored'}${condition}`,
        'car.spawn', {slot}, garage?.parkedHomeName ? 'Retrieve' : garage?.active ? 'Recall' : 'Spawn',
        !state.connected || (aircraft && !state.hangar?.within) ||
          (garage?.parkedHome && (!state.homeParking?.within ||
            state.homeParking.id !== garage.parkedHome)));
      if (garage?.active) {
        const nearOnFoot = state.connected && state.onFoot &&
          garage.distance !== null && garage.distance <= 18;
        row(`${car.name} · ${garage.distance ?? '?'} m away`,
          'car.store', {slot}, 'Store', !nearOnFoot);
        if (!aircraft && state.homeParking?.within)
          row(`${car.name} · park at ${state.homeParking.name}`,
            'car.parkhome', {slot}, 'Park', !nearOnFoot ||
              state.homeParking.occupied >= state.homeParking.capacity);
        if (garage.repairCost)
          row(`${car.name} · repair for $${garage.repairCost}`,
            'car.repair', {slot}, 'Repair', !nearOnFoot || state.cash < garage.repairCost);
        row(`${car.name} · fresh paint for $${garage.resprayCost}`,
          'car.respray', {slot}, 'Respray', !nearOnFoot || state.cash < garage.resprayCost);
      }
    });
    for (const car of state.catalog.cars.filter(item => item.source === 'starter'))
      row(`${car.name} · $${car.price}`, 'car.buy', {model: car.model}, 'Buy', state.cash < car.price);
    const originalCars = state.catalog.cars.filter(item => item.source === 'archived' &&
      item.type !== 'plane' && item.type !== 'helicopter');
    if (originalCars.length) {
      if (state.dealer) panel.append(element('p',
        `${state.dealer.name} · ${state.dealer.distance} m away. Buy its listed vehicles within 100 m.`,
        'zgta-muted'));
      else panel.append(element('p', 'Enter the world to find the nearest dealership.', 'zgta-muted'));
      panel.append(element('p', `${originalCars.length} more vehicles from the archived client catalog`, 'zgta-muted'));
      catalogPicker(originalCars, selectedCarModel, value => {selectedCarModel = value;},
        'car.buy', value => ({model: Number(value)}),
        car => !car || !state.dealer?.within || !car.dealers?.includes(state.dealer.id) ||
          state.cash < car.price || state.cars.length >= 12, 'Ground dealership catalog');
    }
    const aircraft = state.catalog.cars.filter(item =>
      item.type === 'plane' || item.type === 'helicopter');
    if (aircraft.length) {
      section('Hangars and aircraft');
      if (state.hangar) panel.append(element('p',
        `${state.hangar.name} · ${state.hangar.distance} m away. Buy and spawn aircraft within 100 m of a hangar.`,
        'zgta-muted'));
      else panel.append(element('p', 'Enter the world to find the nearest hangar.', 'zgta-muted'));
      panel.append(element('p', `${aircraft.length} aircraft from the archived client catalog`, 'zgta-muted'));
      catalogPicker(aircraft, selectedAircraftModel, value => {selectedAircraftModel = value;},
        'car.buy', value => ({model: Number(value)}),
        car => !car || !state.hangar?.within || !car.airports?.includes(state.hangar.id) ||
          state.cash < car.price ||
          state.cars.length >= 12, 'Aircraft catalog');
    }
    section('Workshop supplies');
    panel.append(element('p',
      `Buy at a ground dealership on foot. Use supplies beside an owned active vehicle, or give one to a player within 8 m.`,
      'zgta-muted'));
    for (const item of state.catalog.supplies) {
      const count = state.supplies[item.id] || 0;
      row(`${item.name} · ${count}/${item.capacity} · $${item.price}`,
        'supply.buy', {item: item.id}, 'Buy',
        !state.dealer?.within || !state.onFoot || state.cash < item.price ||
        count >= item.capacity);
      if (!count) continue;
      state.cars.forEach((car, slot) => {
        const garage = state.garage?.[slot];
        if (!garage?.active) return;
        row(`${item.name} on ${car.name} · ${garage.distance ?? '?'} m away`,
          'supply.use', {item: item.id, slot}, 'Use',
          !state.onFoot || garage.distance === null || garage.distance > 18 ||
          (item.id === 'repair_kit' && !garage.repairCost));
      });
      for (const other of state.nearbyPlayers.filter(entry => entry.distance <= 8))
        row(`Give ${item.name.toLowerCase()} to ${other.name}`,
          'supply.give', {item: item.id, number: other.number}, 'Give',
          !state.onFoot || !other.onFoot);
    }
    section('Homes');
    for (const home of state.catalog.homes.filter(item => item.source === 'starter')) {
      const owned = state.homes.some(item => item.id === home.id);
      row(`${home.name} · ${owned ? 'owned' : '$' + home.price}`,
        'home.buy', {home: home.id}, owned ? 'Owned' : 'Buy', owned || state.cash < home.price);
    }
    const originalHomes = state.catalog.homes.filter(item => item.source === 'archived');
    if (originalHomes.length) {
      panel.append(element('p', `${originalHomes.length} properties from the archived client catalog. Exterior visits only; interiors are not available yet.`, 'zgta-muted'));
      catalogPicker(originalHomes, selectedHomeId, value => {selectedHomeId = value;},
        'home.buy', value => ({home: value}),
        home => !home || state.homes.some(item => item.id === home.id) || state.cash < home.price);
      for (const home of state.homes.filter(item => item.source === 'archived'))
        row(`${home.name} · owned`, 'home.visit', {home: home.id}, 'Visit', !state.connected);
    }
    panel.append(element('p', 'Your cash, cars, homes, and active job are saved on this Mac. Press F6 to open this panel again.', 'zgta-muted'));
    panel.scrollTop = scrollTop;
  }
  function renderWaypoint() {
    const race = state?.race?.stage === 'running' && state.race.joined && state.race.target;
    const turf = state?.turfs?.find(item => item.capturingYou);
    const target = race || state?.job?.target || turf || state?.exploration?.tracked;
    if (!state?.connected || !state.position || !target ||
        !Number.isFinite(target.x) || !Number.isFinite(target.y) || visible) {
      waypoint.hidden = true;
      return;
    }
    const dx = target.x - state.position.x;
    const dy = target.y - state.position.y;
    const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    const arrows = ['↑', '↗', '→', '↘', '↓', '↙', '←', '↖'];
    const bearing = Math.round(Math.atan2(dx, dy) / (Math.PI / 4) + 8) % 8;
    const distance = Math.ceil(Math.hypot(dx, dy));
    waypointArrow.textContent = distance <= (state.race?.radius || state.job?.radius || 12) ?
      '◎' : arrows[bearing];
    waypointLabel.textContent = `${target.name} · ${distance} m ${directions[bearing]}`;
    waypoint.title = `Open the route to ${target.name}`;
    waypoint.hidden = false;
  }
  function maybeAutoCheckpoint() {
    if (!state?.connected || !state.driving || busy || visible) return;
    const race = state.race?.stage === 'running' && state.race.joined && state.race.target ?
      state.race : null;
    const job = !race && state.job?.mode === 'checkpoints' ? state.job : null;
    const route = race || job;
    if (!route || route.secondsLeft <= 0 || route.remaining === null ||
        route.remaining > route.radius) return;
    if (job && ['patrol', 'pizza'].includes(job.id) &&
        state.drivingVehicle !== job.vehicleId) return;
    const action = race ? (race.index === race.total ? 'race.finish' : 'race.checkpoint') :
      (job.index === job.total ? 'job.complete' : 'job.checkpoint');
    const key = `${race ? 'race' : job.id}:${route.started}:${route.index}:${action}`;
    const now = Date.now();
    if (now - (automaticAttempts.get(key) || 0) < 5000) return;
    automaticAttempts.set(key, now);
    if (automaticAttempts.size > 100) {
      for (const [past, when] of automaticAttempts)
        if (now - when > 60000) automaticAttempts.delete(past);
    }
    perform(action, {});
  }
  function renderObjective() {
    renderWaypoint();
    const race = state?.race?.stage === 'running' && state.race.joined &&
      state.race.target ? state.race : null;
    const job = state?.job?.mode ? state.job : null;
    const turf = state?.turfs?.find(item => item.capturingYou);
    const found = state?.exploration?.tracked;
    const explore = found ? {target: {x: found.x, y: found.y, name: found.name},
      remaining: found.distance} : null;
    const active = race || job || turf || explore;
    objective.hidden = !active || visible;
    if (!active) return;
    let direction = '';
    const directionTarget = race?.target || job?.target || (!turf && explore?.target);
    if (state.position && directionTarget) {
      const dx = directionTarget.x - state.position.x;
      const dy = directionTarget.y - state.position.y;
      const compass = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
      direction = ` ${compass[Math.round(Math.atan2(dx, dy) / (Math.PI / 4) + 8) % 8]}`;
    }
    if (race) {
      objective.textContent = `Multiplayer race: checkpoint ${race.index}/${race.total} · ${race.secondsLeft} s left\n${race.target.name} · ${race.remaining ?? '?'} m${direction}\nPress F6 for details`;
      objective.style.whiteSpace = 'pre-line';
      return;
    }
    if (turf && !job) {
      objective.textContent = `Territory capture: ${turf.name} · ${turf.progress}%${turf.contested ? ' · contested' : ''}\nStay on foot within 20 m · ${turf.distance ?? '?'} m away\nPress F6 for details`;
      objective.style.whiteSpace = 'pre-line';
      return;
    }
    if (explore && !job) {
      objective.textContent = `Explore: ${explore.target.name}\n${explore.remaining ?? '?'} m${direction} · stand within 12 m\nPress F6 to claim`;
      objective.style.whiteSpace = 'pre-line';
      return;
    }
    if (job.mode === 'flight') {
      objective.textContent = job.stage === 'takeoff' ?
        `${job.plane} flight: take off from ${job.from} · ${job.secondsLeft} s left\nClimb to ${job.takeoffAltitude} m · now ${job.altitude ?? '?'} m\nPress F6 for details` :
        `${job.plane} flight: land at ${job.target.name} · ${job.secondsLeft} s left\n${job.remaining ?? '?'} m${direction} · stop on apron for 2 s\nPress F6 for details`;
      objective.style.whiteSpace = 'pre-line';
      return;
    }
    if (job.mode === 'fire') {
      const step = job.stage === 'respond' ? 'drive the marked truck' :
        job.stage === 'extinguish' ? `suppress fire ${job.index + 1}/${job.total}` :
          'rescue on foot';
      objective.textContent = `Fire response: ${step} · ${job.secondsLeft} s left\n${job.target.name} · ${job.remaining ?? '?'} m${direction}\nPress F6 for details`;
      objective.style.whiteSpace = 'pre-line';
      return;
    }
    if (job.mode === 'heist') {
      const task = job.stage === 'plan' ? 'take the bag on foot' :
        `lose the police (${job.wanted} stars), then deliver in the Sultan`;
      objective.textContent = `Getaway heist: ${task} · ${job.secondsLeft} s left\n${job.target.name} · ${job.remaining ?? '?'} m${direction}\nPress F6 for details`;
      objective.style.whiteSpace = 'pre-line';
      return;
    }
    if (job.mode === 'service') {
      objective.textContent = `Mechanic: ${job.repairPart} ${job.repairProgress}% · ${Math.min(job.repairStep + 1, job.repairTotal)}/${job.repairTotal}\n${job.target.name} · ${job.remaining ?? '?'} m${direction}\nStand beside the car on foot`;
      objective.style.whiteSpace = 'pre-line';
      return;
    }
    const task = job.mode === 'service' ? 'repair vehicle' :
      job.mode === 'checkpoints' ?
        `${job.id === 'pizza' ? 'pizza delivery' : 'checkpoint'} ${job.index}/${job.total} · ${job.secondsLeft} s left` :
      job.stage === 'pickup' ? (job.id === 'trucker' ? `load cargo · ${job.secondsLeft} s left` : job.id === 'carthief' ? `take getaway car · ${job.secondsLeft} s left` : job.id === 'taxi' ? 'collect passenger' :
        job.id === 'medic' ? 'collect patient' : 'collect package') :
        (job.id === 'trucker' ? `deliver cargo · ${job.secondsLeft} s left` : job.id === 'carthief' ? `deliver getaway car · ${job.secondsLeft} s left` : job.id === 'taxi' ? 'drop off passenger' : job.id === 'medic' ?
          'return patient' : 'deliver package');
    objective.textContent = `${job.name}: ${task}\n${job.target.name} · ${job.remaining ?? '?'} m${direction}\nPress F6 for details`;
    objective.style.whiteSpace = 'pre-line';
  }
  async function refresh() {
    if (busy) return;
    try {
      const response = await fetch('/api/local/state', {credentials: 'same-origin'});
      if (!response.ok) throw new Error(`Could not load local state (${response.status}).`);
      const next = await response.json();
      if (JSON.stringify(next) !== JSON.stringify(state)) {
        state = next;
        render();
        renderObjective();
      }
      maybeAutoCheckpoint();
    } catch (failure) { result = failure.message; error = true; render(); }
  }
  async function perform(action, payload) {
    if (busy) return;
    busy = true;
    try {
      const response = await fetch('/api/local/action', {method: 'POST', credentials: 'same-origin',
        headers: {'Content-Type': 'application/json'}, body: JSON.stringify({action, ...payload})});
      const body = await response.json();
      if (!response.ok) throw new Error(body.error || `Action failed (${response.status}).`);
      state = body.state;
      result = body.message;
      error = false;
      if (action === 'party.chat') partyDraft = '';
    } catch (failure) { result = failure.message; error = true; }
    busy = false;
    render();
    renderObjective();
  }
  function toggle(next) {
    visible = next;
    shade.dataset.open = String(next);
    renderObjective();
    if (next) {
      document.exitPointerLock?.();
      result = '';
      render();
      refresh();
    } else openButton.focus();
  }
  openButton.addEventListener('click', () => toggle(true));
  objective.addEventListener('click', () => toggle(true));
  waypoint.addEventListener('click', () => toggle(true));
  shade.addEventListener('click', event => {if (event.target === shade) toggle(false);});
  panel.addEventListener('keydown', event => event.stopPropagation());
  window.addEventListener('keydown', event => {
    if (event.key === 'F6') {event.preventDefault(); event.stopImmediatePropagation(); toggle(!visible);}
    else if (visible && event.key === 'Escape') {event.preventDefault(); event.stopImmediatePropagation(); toggle(false);}
  }, true);
  refresh();
  setInterval(() => {if (visible || state?.job?.mode || state?.race?.joined ||
    state?.turfs?.some(item => item.capturingYou) || state?.exploration?.tracked) refresh();}, 3000);
})();
