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

    section('Jobs and time trial');
    if (state.job) {
      if (state.job.mode === 'route') {
        const taxi = state.job.id === 'taxi';
        panel.append(element('p', `${state.job.stage === 'pickup' ? (taxi ? 'Collect the passenger' : 'Collect the package') : (taxi ? 'Drop off the passenger' : 'Deliver the package')} at ${state.job.target.name} (${state.job.target.x}, ${state.job.target.y}). ${state.job.remaining ?? '?'} m away. Get within ${state.job.radius} m.${taxi ? ' You must be driving.' : ''}`, 'zgta-muted'));
        if (state.job.stage === 'pickup')
          row(taxi ? 'Pick up passenger' : 'Pick up package', 'job.pickup', {}, 'Collect', !state.connected || state.job.remaining > state.job.radius);
        else row(taxi ? 'Drop off passenger' : 'Deliver package', 'job.complete', {}, taxi ? 'Drop off' : 'Deliver', !state.connected || state.job.remaining > state.job.radius);
      } else {
        panel.append(element('p', `${state.job.name}: travel ${state.job.remaining} m more (${state.job.progress}/${state.job.goal} m).`, 'zgta-muted'));
        row('Route completed?', 'job.complete', {}, 'Complete', !state.connected || state.job.remaining > 0);
      }
      row('End this task', 'job.cancel', {}, 'Cancel');
    } else {
      for (const job of state.catalog.jobs)
        row(`${job.name} · earn $${job.pay}${job.id === 'taxi' ? ' · needs a car' : ''}`,
          'job.start', {job: job.id}, 'Start', !state.connected || (job.id === 'taxi' && !state.cars.length));
    }
    section('Garage');
    if (state.cars.length === 0) panel.append(element('p', 'No cars owned yet.', 'zgta-muted'));
    state.cars.forEach((car, slot) => row(`${car.name} · owned`, 'car.spawn', {slot}, 'Spawn', !state.connected));
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
    const route = state?.job?.mode === 'route' ? state.job : null;
    objective.hidden = !route || visible;
    if (!route) return;
    let direction = '';
    if (state.position) {
      const dx = route.target.x - state.position.x;
      const dy = route.target.y - state.position.y;
      const compass = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
      direction = ` ${compass[Math.round(Math.atan2(dx, dy) / (Math.PI / 4) + 8) % 8]}`;
    }
    const taxi = route.id === 'taxi';
    objective.textContent = `${route.name}: ${route.stage === 'pickup' ? (taxi ? 'collect passenger' : 'collect package') : (taxi ? 'drop off passenger' : 'deliver package')}\n${route.target.name} · ${route.remaining ?? '?'} m${direction}\nPress F6 for details`;
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
  setInterval(() => {if (visible || state?.job?.mode === 'route') refresh();}, 3000);
})();
