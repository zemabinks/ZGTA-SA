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
    #zgta-local-result{min-height:22px;color:#b9dcff;font-weight:600}#zgta-local-result[data-error="true"]{color:#ffb0a8}
    #zgta-local-objective{position:fixed;right:16px;top:72px;z-index:1000;max-width:min(330px,calc(100vw - 32px));border:1px solid #86a9ff;border-radius:10px;background:#14264ff0;color:white;padding:10px 14px;font:600 13px/1.45 system-ui;text-align:left;cursor:pointer;box-shadow:0 4px 18px #0009}
    #zgta-local-objective[hidden]{display:none}
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
  const shade = document.createElement('div');
  shade.id = 'zgta-local-shade';
  shade.dataset.open = 'false';
  const panel = document.createElement('section');
  panel.id = 'zgta-local-panel';
  panel.setAttribute('role', 'dialog');
  panel.setAttribute('aria-label', 'ZGTA:SA local gameplay');
  shade.append(panel);
  document.body.append(openButton, objective, shade);
  new MutationObserver(() => {
    if (!openButton.isConnected || !objective.isConnected || !shade.isConnected)
      document.body.append(openButton, objective, shade);
  }).observe(document.documentElement, {childList: true, subtree: true});
  let visible = false;
  let state = null;
  let result = '';
  let error = false;
  let busy = false;
  let selectedCarModel = '';
  let selectedHomeId = '';
  const transferAmounts = new Map();

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
  function catalogPicker(items, value, onChange, action, payload, disabled) {
    if (!items.length) return;
    const line = element('div', undefined, 'zgta-row');
    const select = element('select');
    select.setAttribute('aria-label', action === 'car.buy' ? 'Vehicle catalog' : 'Property catalog');
    for (const item of items) {
      const option = element('option', `${item.name} · $${item.price.toLocaleString()}`);
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
    panel.append(element('p', `Health ${state.health}/100 · Armour ${state.armour}/100 · Wanted ${state.wanted}/6 · ${state.kills} kills · ${state.deaths} deaths`, 'zgta-muted'));
    if (state.discord?.available && !state.discord.linked) {
      const link = element('button', `Link Discord · one-time $${state.discord.bonus} bonus`);
      link.type = 'button';
      link.addEventListener('click', () => { window.location.href = '/api/local/discord/start'; });
      panel.append(link);
    }

    section('Jobs and time trial');
    if (state.job) {
      if (state.job.mode === 'route') {
        const taxi = state.job.id === 'taxi';
        const medic = state.job.id === 'medic';
        const thief = state.job.id === 'carthief';
        const task = state.job.stage === 'pickup' ?
          (thief ? 'Take the marked car' : taxi ? 'Collect the passenger' : medic ? 'Collect the patient' : 'Collect the package') :
          (thief ? 'Deliver the marked car' : taxi ? 'Drop off the passenger' : medic ? 'Return the patient' : 'Deliver the package');
        panel.append(element('p', `${task} at ${state.job.target.name} (${state.job.target.x}, ${state.job.target.y}). ${state.job.remaining ?? '?'} m away. Get within ${state.job.radius} m.${taxi || medic || thief ? ' You must be driving.' : ''}${thief ? ` ${state.job.secondsLeft} s left.` : ''}`, 'zgta-muted'));
        if (state.job.stage === 'pickup')
          row(thief ? 'Take getaway car' : taxi ? 'Pick up passenger' : medic ? 'Pick up patient' : 'Pick up package',
            'job.pickup', {}, thief ? 'Take' : 'Collect', !state.connected || state.job.remaining > state.job.radius ||
              (thief && state.job.secondsLeft <= 0));
        else row(thief ? 'Deliver getaway car' : taxi ? 'Drop off passenger' : medic ? 'Return patient' : 'Deliver package',
          'job.complete', {}, taxi ? 'Drop off' : medic ? 'Return' : 'Deliver',
          !state.connected || state.job.remaining > state.job.radius ||
            (thief && state.job.secondsLeft <= 0));
      } else if (state.job.mode === 'service') {
        panel.append(element('p', `Repair the stranded vehicle at ${state.job.target.name} (${state.job.target.x}, ${state.job.target.y}). ${state.job.remaining ?? '?'} m away. Get within ${state.job.radius} m and stand on foot.`, 'zgta-muted'));
        row('Repair stranded vehicle', 'job.complete', {}, 'Repair',
          !state.connected || state.job.remaining > state.job.radius);
      } else if (state.job.mode === 'checkpoints') {
        panel.append(element('p', `Checkpoint ${state.job.index}/${state.job.total}: ${state.job.target.name} (${state.job.target.x}, ${state.job.target.y}). ${state.job.remaining ?? '?'} m away. ${state.job.secondsLeft} s left. Drive within ${state.job.radius} m.`, 'zgta-muted'));
        row(state.job.index === state.job.total ? 'Finish time trial' : 'Pass checkpoint',
          state.job.index === state.job.total ? 'job.complete' : 'job.checkpoint', {},
          state.job.index === state.job.total ? 'Finish' : 'Pass',
          !state.connected || state.job.remaining > state.job.radius || state.job.secondsLeft <= 0);
      } else {
        panel.append(element('p', `${state.job.name}: travel ${state.job.remaining} m more (${state.job.progress}/${state.job.goal} m).`, 'zgta-muted'));
        row('Route completed?', 'job.complete', {}, 'Complete', !state.connected || state.job.remaining > 0);
      }
      row('End this task', 'job.cancel', {}, 'Cancel');
    } else {
      for (const job of state.catalog.jobs)
        row(`${job.name} · earn $${job.pay}${['taxi', 'trial'].includes(job.id) ? ' · needs a car' : ''}${job.id === 'carthief' ? ' · five-minute mission' : ''}`,
          'job.start', {job: job.id}, 'Start', !state.connected ||
            (['taxi', 'trial'].includes(job.id) && !state.cars.length) ||
            (job.id === 'carthief' && (state.passive || state.policeDuty)) ||
            (state.race?.joined && ['lobby', 'running'].includes(state.race.stage)));
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
    section('Safety and police');
    row(`Passive mode ${state.passive ? 'on' : 'off'}${state.passiveWait ?
      ` · ${state.passiveWait} s cooldown` : ''}`, 'safety.passive', {},
      state.passive ? 'Turn off' : 'Turn on', !state.connected ||
        (!state.passive && (state.wanted > 0 || state.policeDuty || state.passiveWait > 0)));
    row(`Police duty ${state.policeDuty ? 'on' : 'off'} · ${state.arrests} arrests`,
      'police.duty', {}, state.policeDuty ? 'End duty' : 'Start duty',
      !state.connected || (!state.policeDuty && (state.wanted > 0 || state.passive)));
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
    if (state.cars.length === 0) panel.append(element('p', 'No cars owned yet.', 'zgta-muted'));
    state.cars.forEach((car, slot) => {
      const garage = state.garage?.[slot];
      const condition = garage ? ` · ${Math.round(garage.health / 10)}% condition` : '';
      row(`${car.name} · ${garage?.active ? 'out' : 'stored'}${condition}`,
        'car.spawn', {slot}, garage?.active ? 'Recall' : 'Spawn', !state.connected);
      if (garage?.active) {
        const nearOnFoot = state.connected && state.onFoot &&
          garage.distance !== null && garage.distance <= 18;
        row(`${car.name} · ${garage.distance ?? '?'} m away`,
          'car.store', {slot}, 'Store', !nearOnFoot);
        if (garage.repairCost)
          row(`${car.name} · repair for $${garage.repairCost}`,
            'car.repair', {slot}, 'Repair', !nearOnFoot || state.cash < garage.repairCost);
      }
    });
    for (const car of state.catalog.cars.filter(item => item.source === 'starter'))
      row(`${car.name} · $${car.price}`, 'car.buy', {model: car.model}, 'Buy', state.cash < car.price);
    const originalCars = state.catalog.cars.filter(item => item.source === 'archived');
    if (originalCars.length) {
      panel.append(element('p', `${originalCars.length} more vehicles from the archived client catalog`, 'zgta-muted'));
      catalogPicker(originalCars, selectedCarModel, value => {selectedCarModel = value;},
        'car.buy', value => ({model: Number(value)}),
        car => !car || state.cash < car.price || state.cars.length >= 12);
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
  function renderObjective() {
    const race = state?.race?.stage === 'running' && state.race.joined &&
      state.race.target ? state.race : null;
    const job = state?.job?.mode ? state.job : null;
    const turf = state?.turfs?.find(item => item.capturingYou);
    const active = race || job || turf;
    objective.hidden = !active || visible;
    if (!active) return;
    let direction = '';
    if (state.position && (race || job)) {
      const dx = active.target.x - state.position.x;
      const dy = active.target.y - state.position.y;
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
    const task = job.mode === 'service' ? 'repair vehicle' :
      job.mode === 'checkpoints' ? `checkpoint ${job.index}/${job.total} · ${job.secondsLeft} s left` :
      job.stage === 'pickup' ? (job.id === 'carthief' ? `take getaway car · ${job.secondsLeft} s left` : job.id === 'taxi' ? 'collect passenger' :
        job.id === 'medic' ? 'collect patient' : 'collect package') :
        (job.id === 'carthief' ? `deliver getaway car · ${job.secondsLeft} s left` : job.id === 'taxi' ? 'drop off passenger' : job.id === 'medic' ?
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
  shade.addEventListener('click', event => {if (event.target === shade) toggle(false);});
  panel.addEventListener('keydown', event => event.stopPropagation());
  window.addEventListener('keydown', event => {
    if (event.key === 'F6') {event.preventDefault(); event.stopImmediatePropagation(); toggle(!visible);}
    else if (visible && event.key === 'Escape') {event.preventDefault(); event.stopImmediatePropagation(); toggle(false);}
  }, true);
  refresh();
  setInterval(() => {if (visible || state?.job?.mode || state?.race?.joined ||
    state?.turfs?.some(item => item.capturingYou)) refresh();}, 3000);
})();
