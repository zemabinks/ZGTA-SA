#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
// Test only the actual result classifier with authored child processes; no game
// archive, accounts, native executable, server or external network is used.
'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const {spawn}=require('node:child_process');
const source=fs.readFileSync(path.join(require('node:path').resolve(__dirname, '../..'),'tests/network/test_native_skin_network.js'),'utf8');
const marker='function completedNativeChild(',start=source.indexOf(marker);assert(start>=0);
let opening=source.indexOf('{',start),at=opening+1,depth=1;
while(depth&&at<source.length){depth+=(source[at]==='{')-(source[at]==='}');at++;}
assert.equal(depth,0);const classify=vm.runInNewContext('('+source.slice(start,at)+')');
const stdout='PASS actual skin WebSockets: 313 checks; 32 bidirectional foot/driver cases; authored classifier fixture\n';
const report={status:'PASS',nativeEntryGrants:8,browserEntryGrants:8};let checks=0;
function check(value,label){assert(value,label);checks++;}
function child(script){return new Promise((resolve,reject)=>{const process=spawn(global.process.execPath,['-e',script],{stdio:['ignore','pipe','pipe']});let output='';process.stdout.on('data',data=>output+=data);process.once('error',reject);process.once('close',(code,signal)=>resolve({code,signal,stdout:output}));});}
(async()=>{
 const killed=await child('process.kill(process.pid,"SIGTERM")');
 check(killed.code===null&&killed.signal==='SIGTERM','Actual callback must expose signal/null');
 check(!classify(killed.code,killed.signal,stdout,report),'Signal/null must fail despite fabricated PASS output');
 const failed=await child('process.exit(7)');
 check(failed.code===7&&failed.signal===null,'Actual child nonzero status');
 check(!classify(failed.code,failed.signal,stdout,report),'Nonzero must fail despite PASS output');
 const empty=await child('');check(empty.code===0&&empty.signal===null,'Actual empty child exit0');
 check(!classify(empty.code,empty.signal,empty.stdout,report),'Exit0 without completion marker must fail');
 const done=await child('process.stdout.write('+JSON.stringify(stdout)+')');
 check(classify(done.code,done.signal,done.stdout,report),'Completed exit0 and PASS report must pass');
 check(!classify(done.code,done.signal,done.stdout,{...report,status:'FAIL'}),'FAIL report must fail');
 check(!classify(done.code,done.signal,done.stdout,{...report,nativeEntryGrants:0}),'Missing genuine native entry must fail');
 check(!classify(done.code,done.signal,done.stdout,{...report,browserEntryGrants:0}),'Missing genuine browser entry must fail');
 check(!classify(undefined,null,stdout,report),'Missing child status must fail');
 console.log(JSON.stringify({status:'PASS',checks,scope:'Actual child exit callback and extracted actual classifier only; no gameplay/network acceptance'}));
})().catch(error=>{console.error(error.stack);process.exitCode=1;});
