#!/usr/bin/env node
// Derive local physics configuration with the archived browser's own DFF
// parser, scene assembly, default stance, handling and chassis construction.
// All original assets and output stay in the ignored local-only directory.
const fs = require('node:fs');
const path = require('node:path');
const {createHash} = require('node:crypto');
const {archivedModules} = require('./smoke_vehicle_dynamics');

async function main() {
  const load = archivedModules(), R = load(55077); await R.init();
  const T = load(85339), catalogue = load(72197), modelParser = load(78315).A;
  const geometry = load(88711), stance = load(74921).p, handling = load(87605);
  const solver = load(23895), requested = process.argv.slice(2).map(Number);
  const game = path.join(__dirname,'local-only/site/game'), output = path.join(game,'native/vehicles.physics.json');
  const models = requested.length && fs.existsSync(output) ? JSON.parse(fs.readFileSync(output,'utf8')).models : {};
  const failures = [];
  const vector = value => [value.x,value.y,value.z];
  for (const definition of catalogue.Wd) {
    const id = Number(definition.id); if (requested.length && !requested.includes(id)) continue;
    try {
      const source = fs.readFileSync(path.join(game,definition.model + '.dff'));
      const parsed = modelParser(source), options = catalogue.AX({id}), assets = catalogue.yc(options);
      const root = geometry.yK(parsed,new Map(),{kind:'vehicle',damage:true,blades:true,lowDetail:true,wheels:load(90317).y(id)});
      geometry.u2(root,[],new Map(),{colors:assets.colors,wheelScale:assets.wheelScale});
      const wheels = stance(root,assets.stance), visualBox = new T.NRn().setFromObject(root);
      const size = visualBox.getSize(new T.Pq0()); root.position.y = -visualBox.min.y;
      const body = new T.YJl(); body.add(root); handling.FV(id,body,root,wheels);
      const table = handling.c_(id,size).table, bounds = handling.BO(parsed.collision,size,root.position.y);
      const kind = catalogue.I(definition) ?? 'car';
      const raw = {id,model:definition.model,type:definition.type,kind,origin:root.position.y,
        width:size.x,height:size.y,length:size.z,table,bounds,
        visualBounds:{min:vector(visualBox.min),max:vector(visualBox.max)},
        wheels:wheels.map(w=>({centre:vector(w.centre),radius:w.radius,width:w.width,front:w.front,left:w.left})),
        collision:parsed.collision ? {spheres:parsed.collision.spheres,boxes:parsed.collision.boxes,box:parsed.collision.box} : null,
        dffSHA256:createHash('sha256').update(source).digest('hex')};
      const seatFrame = root.userData.frames.get('ped_frontseat');
      if (seatFrame) {
        const eye = new T.Pq0().setFromMatrixPosition(seatFrame);
        raw.driverEye = [Math.abs(eye.x)<0.15?eye.x:-Math.abs(eye.x),eye.y,eye.z];
      }
      if (kind === 'bike') {
        const frames = root.userData.frames;
        const front = frames.get('wheel_front'), rear = frames.get('wheel_rear');
        if (!front || !rear) throw new Error('Original bike wheel frames unavailable');
        const scales = definition.wheelScale ?? [0.7,0.7];
        raw.hubs = {front:{at:vector(new T.Pq0().setFromMatrixPosition(front)),radius:scales[0]/2},
          rear:{at:vector(new T.Pq0().setFromMatrixPosition(rear)),radius:scales[1]/2}};
        raw.bike = load(78338).y(load(58075).uo[id]); raw.pedalled = catalogue.qc(definition);
      }
      if (kind === 'boat') raw.boat = load(3104).v(load(58075).jm[id]);
      if (kind === 'plane' || kind === 'heli') {
        raw.struts = [];
        const frames = root.userData.frames, scales = definition.wheelScale ?? [0.7,0.7];
        for (const [name,front,left] of [['wheel_lf_dummy',true,true],['wheel_lb_dummy',false,true],['wheel_rf_dummy',true,false],['wheel_rb_dummy',false,false]]) {
          const frame = frames.get(name); if (!frame) continue;
          const point = new T.Pq0().setFromMatrixPosition(frame);
          raw.struts.push({front,left,radius:scales[front?0:1]/2,centre:[point.x,raw.origin+point.z,-point.y]});
        }
        if (raw.struts.length<3) raw.kind = 'car';
        else {
          raw.flying = load(89888).sE(load(58075).SD[id]);
          if (load(58075).jm[id]) raw.boat = load(3104).v(load(58075).jm[id]);
        }
      }
      // Ground chassis are made by the original factory, including sphere
      // clearance changes and its fallback only where original COL is absent.
      if (['car','trailer','bike','plane','heli','boat','train'].includes(raw.kind)) {
        const world = new R.World({x:0,y:-9.81,z:0});
        const built = {...raw,id:String(id),nitro:0,hydraulics:false,
          wheels:raw.wheels.map(w=>({...w,centre:new T.Pq0(...w.centre)}))};
        const environment = {RAPIER:R,world,waterLevel:()=>null};
        let car;
        if (raw.kind === 'train') {
          const rigid = world.createRigidBody(R.RigidBodyDesc.kinematicVelocityBased().setCanSleep(false));
          car = {rigid,solids:solver.vX(environment,built,rigid,327663)};
          raw.carriages = load(91584).Wm[id] ?? [];
        } else car = kind === 'bike' ? (raw.pedalled ? load(40405).u : load(78338).o)(environment,built,id) : solver.Xn(environment,built,id);
        raw.chassis = [];
        for (const collider of car.solids) {
          const common = {centre:vector(collider.translation()),piece:car.solids.pieces.get(collider.handle),
            friction:collider.friction(),restitution:collider.restitution(),
            collisionGroups:collider.collisionGroups(),solverGroups:collider.solverGroups()};
          if (collider.shape.type === R.ShapeType.Ball) raw.chassis.push({...common,kind:'sphere',radius:collider.radius()});
          else if (collider.shape.type === R.ShapeType.Cuboid) raw.chassis.push({...common,kind:'box',halfExtents:vector(collider.halfExtents())});
          else throw new Error('Unexpected original chassis shape ' + collider.shape.type);
        }
        raw.massProperties={mass:car.rigid.mass(),centre:vector(car.rigid.localCom()),
          principalInertia:vector(car.rigid.principalInertia())};
        raw.solverSupported = ['car','trailer','bike','plane','heli','boat'].includes(raw.kind); world.free();
      } else raw.solverSupported = false;
      geometry.xd(root,null); models[id] = raw;
    } catch (error) { failures.push({id,model:definition.model,error:error.message}); }
  }
  const temporary = output + '.tmp';
  const collisionFallbackParts = {};
  for (const name of fs.readdirSync(path.join(game,'world'))) {
    if (!name.endsWith('.col.generated.json')) continue;
    const manifest = JSON.parse(fs.readFileSync(path.join(game,'world',name),'utf8'));
    if (manifest.reconstructed && Array.isArray(manifest.parts))
      collisionFallbackParts[name.slice(0,-'.col.generated.json'.length)] = manifest.parts.map(({indexStart,indexCount})=>({indexStart,indexCount}));
  }
  fs.writeFileSync(temporary,JSON.stringify({version:1,axes:'Rapier Y-up [GTA x,GTA z,-GTA y]',
    source:'Archived modules 78315,88711,74921,90317,87605,23895; default unmodified vehicles',
    materialClasses:Array.from({length:256},(_,id)=>load(77287).Qm(id)),
    materialClassifierSHA256:createHash('sha256').update(load(77287).Qm.toString()).digest('hex'),
    collisionFallbackParts,
    nativePhysics:{bindingVersion:R.version(),coreCommit:'3e12c2679cb1940a876bde93af9cec0cf2f57944',mathFeature:'wasm-scalar-math'},
    models,failures}),{mode:0o600}); fs.renameSync(temporary,output);
  console.log('Prepared',Object.keys(models).length,'original vehicle configurations,',
    Object.values(models).filter(m=>m.solverSupported).length,'enabled native solvers,',failures.length,'failures');
  const rails = load(91873);
  fs.writeFileSync(path.join(game,'native/trains.json.tmp'),JSON.stringify({version:1,...rails}),{mode:0o600});
  fs.renameSync(path.join(game,'native/trains.json.tmp'),path.join(game,'native/trains.json'));
  for (const failure of failures) console.error(failure.id,failure.model,failure.error);
  if (failures.length) process.exitCode=1;
}
main().catch(error=>{console.error(error);process.exitCode=1});
