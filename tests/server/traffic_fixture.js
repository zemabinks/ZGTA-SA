// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
// Invented one-way square. No original navigation arrays or game assets.
function square(side=40,height=13,nodeFlags=null){
 const sections=[],header=Buffer.alloc(32);header.writeUInt32LE(0x44524453);header.writeUInt32LE(1,4);
 for(const at of [8,12,16])header.writeUInt32LE(4,at);
 const part=(values,size,write)=>{const p=Buffer.alloc((values.length*size+3)&~3);values.forEach((v,i)=>p[write](v,i*size));sections.push(p);};
 const points=[[0,0,height],[side,0,height],[side,side,height],[0,side,height]],targets=[1,2,3,0];
 part(points.flat().map(v=>Math.round(v*8)),2,'writeInt16LE');part([0,1,2,3,4],4,'writeUInt32LE');
 part(nodeFlags??[0,1,2,3].map(i=>i<<12),4,'writeUInt32LE');part([0,0,0,0],1,'writeUInt8');
 part(targets,4,'writeUInt32LE');part([0,1,2,3],4,'writeUInt32LE');
 part([[side/2,0],[side,side/2],[side/2,side],[0,side/2]].flat().map(v=>Math.round(v*8)),2,'writeInt16LE');
 part(targets,4,'writeUInt32LE');part([100,0,0,100,-100,0,0,-100],1,'writeInt8');part([256,256,256,256],4,'writeUInt32LE');
 return Buffer.concat([header,...sections]);
}
module.exports={square};
