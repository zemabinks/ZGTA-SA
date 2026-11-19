// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
// All script text, plans and records below are independently authored fixtures.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const {PROFILE,applyPinnedPolicy,create} = require('../../browser_task_policy');
const sha = text => crypto.createHash('sha256').update(text).digest('hex');
const clone = value => JSON.parse(JSON.stringify(value));
let checks = 0;
function equal(actual,expected,message) {checks++;assert.equal(actual,expected,message);}
function refuses(source,plan,pattern) {checks++;assert.throws(()=>applyPinnedPolicy(source,plan),pattern);}

const fixture = `(function(seed){
let phase=seed/*STATE*/,spare=0,owner=null;
function make(kind){if(kind==="missing")return 0;owner={kind,weight:1,ending:false/*FRESH*/};return 1;}
return {
evaluate(rows,dt=0){let table=rows;/*CACHE*/let before=phase;phase=(phase+dt)%1;return before;},
launch(){return make(/*CHOOSE*/);},
land(kind,callback){if(make(kind)){owner.weight=1/*MARK*/,callback&&callback();}},
complete(){if(owner){owner.ending=true;owner.weight=0;}},
retire(dt=0){let before=phase;phase+=dt;let travel=phase-before;if(owner&&owner.ending&&owner.weight<=0){/*RETIRE*/}return travel;},
replace(kind){make(kind);},die(){owner=null;},phase(){return phase;},owner(){return owner;}
};})`;
const unpatched = fixture.replace('/*CHOOSE*/','((phase < 0.5) ? "launch" : "launchR")')
  .replace('/*RETIRE*/','owner=null');
const source = Buffer.from(unpatched);
const slots = {
  'declare-associations-float32':'/*STATE*/',
  'initialize-completion-capability-false':'/*FRESH*/',
  'capture-logical-gait-weights':'/*CACHE*/',
  'mark-ordinary-landing-owner':'/*MARK*/',
  'choose-launch-side-float32':'((phase < 0.5) ? "launch" : "launchR")',
  'complete-ordinary-landing-and-clear-owner':'owner=null',
};
const plan = {schema:1,profile:PROFILE,enabled:true,
  source:{bytes:source.length,sha256:sha(source)},
  factory:{byteStart:0,byteEnd:source.length,sha256:sha(source)},
  bindings:{phase:'phase',associationTable:'table',actionOwner:'owner',landingKind:'kind',
    newAssociationState:'_fixtureWeights',newOwnerCapability:'_fixtureRestart'},
  logicalRows:[{kind:'walk',index:1},{kind:'run',index:0},{kind:'sprint',index:2}],edits:[]};
for (const [payloadKind,marker] of Object.entries(slots)) {
  // Anchor retirement to its actual qualified owner condition. Initialization
  // and death also clear an owner and must remain distinct operations.
  const retirement='if(owner&&owner.ending&&owner.weight<=0){';
  const start = payloadKind.startsWith('complete-') ? unpatched.indexOf(retirement)+retirement.length : unpatched.indexOf(marker);
  assert(start>=0);
  plan.edits.push({payloadKind,originalByteStart:start,originalByteEnd:start+marker.length,
    expectedOriginalSpanSHA256:sha(Buffer.from(marker))});
}
const output = applyPinnedPolicy(source,plan);
const construct = vm.runInNewContext(output.toString());
function engine(phase,weights=[0,0,0]) {
  const e = construct(phase);
  e.evaluate([[{},weights[1]],[{},weights[0]],[{},weights[2]]]);
  return e;
}
function choice(e) {e.launch();return e.owner().kind;}
equal(choice(construct(0.8)),'launch','cold association owner');
equal(choice(engine(0.8)),'launch','evaluated idle owner');
for(const [phase,right] of [[0,false],[0.132,false],[0.133,true],[0.193,true],[0.633,true],[0.6331,false],[0.8,false]])
  equal(choice(engine(phase,[0.7,0,0])),right?'launchR':'launch','Float phase/wrap');
for(const [weights,right] of [[[0.7,0.3,0],false],[[0.7,0.29999,0],true],[[0,0.7,0.3],false],[[0,0.7,0.29999],true]])
  equal(choice(engine(0.193,weights)),right?'launchR':'launch','logical priority/threshold');
const stale = engine(0.193,[0.7,0,0]);stale.evaluate([[null,0.7],[null,0.7],[null,0.7]]);
equal(choice(stale),'launch','missing prepared handles clear all cached slots');
for(const kind of ['land','fallLand','collapse']) {
  const e=engine(0.193,[0.7,0,0]);e.land(kind);e.complete();
  checks++;assert(Math.abs(e.retire(0.07)-0.07)<1e-12,'restart changed integrated root displacement');
  equal(e.phase(),0,'ordinary completed landing resets gait');
  e.retire(0.013);checks++;assert(Math.abs(e.phase()-0.013)<1e-12,'completion reset repeated');
}
for(const kind of ['knock','getUp','missing']) {
  const e=engine(0.193);e.land(kind);e.complete();e.retire();equal(e.phase(),0.193,'unrelated/missing task reset gait');
}
const replaced=engine(0.193);replaced.land('fallLand',()=>replaced.replace('roll'));replaced.complete();replaced.retire();
equal(replaced.phase(),0.193,'callback replacement inherited old capability');
const dead=engine(0.193);dead.land('land');dead.die();dead.retire();equal(dead.phase(),0.193,'death inherited pending completion');
const historical=vm.runInNewContext(unpatched)(0.8);historical.launch();equal(historical.owner().kind,'launchR','historical idle negative');
const oldLand=vm.runInNewContext(unpatched)(0.193);oldLand.land('land');oldLand.complete();oldLand.retire();equal(oldLand.phase(),0.193,'historical landing negative');

let bad=clone(plan);bad.source.sha256='0'.repeat(64);refuses(source,bad,/source identity/);
bad=clone(plan);bad.factory.sha256='0'.repeat(64);refuses(source,bad,/factory identity/);
bad=clone(plan);bad.edits[0].expectedOriginalSpanSHA256='0'.repeat(64);refuses(source,bad,/span identity/);
bad=clone(plan);bad.edits.pop();refuses(source,bad,/complete policy/);
bad=clone(plan);bad.edits[1].payloadKind=bad.edits[0].payloadKind;refuses(source,bad,/complete policy/);
bad=clone(plan);Object.assign(bad.edits[1],{originalByteStart:bad.edits[0].originalByteStart,originalByteEnd:bad.edits[0].originalByteEnd,
  expectedOriginalSpanSHA256:bad.edits[0].expectedOriginalSpanSHA256});refuses(source,bad,/overlapping/);
bad=clone(plan);bad.bindings.phase='globalThis.attack()';refuses(source,bad,/symbol binding/);
bad=clone(plan);bad.bindings.newAssociationState='spare';refuses(source,bad,/collides/);
bad=clone(plan);bad.logicalRows[1].index=bad.logicalRows[0].index;refuses(source,bad,/share a row/);
bad=clone(plan);bad.enabled=false;refuses(source,bad,/plan profile/);
const extended=Buffer.concat([source,Buffer.from('//é')]);bad=clone(plan);bad.source.bytes=extended.length;bad.source.sha256=sha(extended);
refuses(extended,bad,/ASCII/);

const directory=fs.mkdtempSync(path.join(os.tmpdir(),'zgta-browser-policy-'));
try {
  const root=path.join(directory,'site');fs.mkdirSync(root);
  const target=path.join(root,'fixture.js'),config=path.join(directory,'private-plan.json');fs.writeFileSync(target,source);
  const configured=clone(plan);configured.source.path=target;fs.writeFileSync(config,JSON.stringify(configured));
  equal(create({siteRoot:'does-not-exist'}).matches(target),false,'unconfigured feature does not access owner paths');
  const provider=create({siteRoot:root,configuration:config});equal(provider.matches(target),true,'configured route');
  equal(provider.matches(path.join(root,'other.js')),false,'unrelated route');
  equal(provider.read().equals(output),true,'provider uses the verified emitter');
  fs.writeFileSync(target,Buffer.concat([source,Buffer.from(' ')]));checks++;assert.throws(()=>provider.read(),/source identity/);
  equal(provider.matches(target),true,'drift cannot fall through to raw serving');
  fs.unlinkSync(target);fs.symlinkSync(config,target);checks++;assert.throws(()=>provider.read(),/source path changed/);
  fs.unlinkSync(target);fs.writeFileSync(target,source);
  const outside=clone(configured);outside.source.path=config;fs.writeFileSync(config,JSON.stringify(outside));
  checks++;assert.throws(()=>create({siteRoot:root,configuration:config}),/outside site root/);

  // Real archive aliases: one explicitly selected logical route, with its
  // original target and complete source identity pinned independently.
  const bank=path.join(directory,'authored-bank'),otherBank=path.join(directory,'other-bank');
  fs.mkdirSync(bank);fs.mkdirSync(otherBank);fs.mkdirSync(path.join(root,'_next'));
  for(const folder of [bank,otherBank])fs.writeFileSync(path.join(folder,'authored.js'),source);
  const link=path.join(root,'_next/chunks');fs.symlinkSync(bank,link);
  const alias=path.join(link,'authored.js'),aliased=clone(plan);aliased.source.path=alias;
  fs.writeFileSync(config,JSON.stringify(aliased));
  checks++;assert.throws(()=>create({siteRoot:root,configuration:config}),/outside site root/,'legacy mode must remain strict');
  aliased.source.relativePath='_next/chunks/authored.js';fs.writeFileSync(config,JSON.stringify(aliased));
  const archiveProvider=create({siteRoot:root,configuration:config});
  equal(archiveProvider.matches(alias),true,'explicit logical archive route');
  equal(archiveProvider.read().equals(output),true,'nested read-only alias retains pinned transformation');
  equal(archiveProvider.matches(path.join(bank,'other.js')),false,'one alias cannot expose an unrelated file');
  equal(fs.readFileSync(path.join(bank,'authored.js')).equals(source),true,'provider never rewrites archived source');
  for(const relativePath of ['../bank/authored.js','/authored.js','_next//authored.js','_next/./authored.js',
    '_next/../authored.js','C:/authored.js','_next\\authored.js','_next/authored.css','_next/a .js']) {
    const invalid=clone(aliased);invalid.source.relativePath=relativePath;fs.writeFileSync(config,JSON.stringify(invalid));
    checks++;assert.throws(()=>create({siteRoot:root,configuration:config}),/invalid owner script route/);
  }
  const wrong=clone(aliased);wrong.source.path=target;fs.writeFileSync(config,JSON.stringify(wrong));
  checks++;assert.throws(()=>create({siteRoot:root,configuration:config}),/source path changed/,'same bytes at another target do not authorize the route');
  fs.writeFileSync(config,JSON.stringify(aliased));
  fs.unlinkSync(link);fs.symlinkSync(otherBank,link);
  checks++;assert.throws(()=>archiveProvider.read(),/source path changed/,'alias retargeting fails even with identical file bytes');
  fs.unlinkSync(link);fs.symlinkSync(bank,link);
  equal(archiveProvider.read().equals(output),true,'restored pinned target');
  fs.appendFileSync(path.join(bank,'authored.js'),' ');
  checks++;assert.throws(()=>archiveProvider.read(),/source identity/,'aliased source drift cannot fall through');
  equal(archiveProvider.matches(alias),true,'drift retains route ownership');
  fs.writeFileSync(path.join(bank,'authored.js'),source);
  const logicalRoot=path.join(directory,'logical-site');fs.symlinkSync(root,logicalRoot);
  const rootProvider=create({siteRoot:logicalRoot,configuration:config});
  equal(rootProvider.read().equals(output),true,'root and nested aliases may coexist');
  fs.unlinkSync(logicalRoot);fs.symlinkSync(otherBank,logicalRoot);
  checks++;assert.throws(()=>rootProvider.read(),/source path changed/,'root identity remains fixed');
} finally {fs.rmSync(directory,{recursive:true,force:true});}
console.log(`PASS browser task policy: ${checks} authored selection/owner/pin/route checks; original assets stay separate`);
module.exports={source,plan,output};
