// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
// Prepared source-family structure only; native bind pose, image decoding and
// GPU/animation acceptance remain with the native prepared-runtime verifier.
function validateFamily(mesh,atlas,skin){
 const requireValue=(v,why)=>{if(!v)throw Error('Population model '+why);};
 const finite=(bytes,at,count)=>{for(let i=0;i<count;i++)requireValue(Number.isFinite(bytes.readFloatLE(at+4*i)),'nonfinite geometry/rig');};
 requireValue(mesh.length>=16&&mesh.length<=64*1048576,'mesh byte budget');
 const vertices=mesh.readUInt32LE(4),indices=mesh.readUInt32LE(8),layers=mesh.readUInt32LE(12);
 requireValue(mesh.readUInt32LE(0)===0x324c5257&&vertices>0&&vertices<100000&&indices>0&&indices<=3000000&&indices%3===0&&layers>0&&layers<=65535,'mesh header');
 requireValue(mesh.length===16+30*vertices+4*indices+2*(vertices%2)+2*layers,'mesh exact length');
 finite(mesh,16,5*vertices);
 for(let i=0;i<indices;i++)requireValue(mesh.readUInt32LE(16+20*vertices+4*i)<vertices,'mesh triangle index');
 for(let i=0;i<vertices;i++)requireValue(mesh.readUInt16LE(16+24*vertices+4*indices+2*i)<layers,'mesh texture layer');
 requireValue(atlas.length>=33&&atlas.length<=64*1048576&&atlas.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10]))&&atlas.readUInt32BE(8)===13&&atlas.toString('ascii',12,16)==='IHDR','atlas header');
 const width=atlas.readUInt32BE(16),height=atlas.readUInt32BE(20);
 requireValue(width>0&&width<=16384&&height>0&&height<=16384&&width*height<=67108864,'atlas dimensions');
 requireValue(skin.length>=144&&skin.length<=64*1048576,'skeleton byte budget');
 const frames=skin.readUInt32LE(8),bones=skin.readUInt32LE(12);
 requireValue(skin.readUInt32LE(0)===0x314e4b53&&skin.readUInt32LE(4)===vertices&&frames>0&&frames<=512&&bones>0&&bones<=64,'mesh/skeleton header identity');
 requireValue(skin.length===144+72*frames+68*bones+32*vertices,'skeleton exact length');finite(skin,16,32);
 const tags=new Set();let at=144;
 for(let i=0;i<frames;i++,at+=72){const parent=skin.readInt32LE(at),tag=skin.readInt32LE(at+4);
  requireValue(parent>=-1&&parent<i&&tag>=-1&&(tag<0||!tags.has(tag)),'frame hierarchy/tag');if(tag>=0)tags.add(tag);finite(skin,at+8,16);}
 requireValue(tags.has(0)&&tags.has(1),'required actor bone tags');
 for(let i=0;i<bones;i++,at+=68){requireValue(skin.readUInt32LE(at)<frames,'palette frame');finite(skin,at+4,16);}
 for(let i=0;i<vertices;i++,at+=32){finite(skin,at,3);let sum=0;
  for(let j=0;j<4;j++){requireValue(skin[at+12+j]<bones,'skin palette index');const w=skin.readFloatLE(at+16+4*j);requireValue(Number.isFinite(w)&&w>=0,'skin weights');sum+=w;}
  requireValue(Math.abs(sum-1)<.01,'skin weights');}
 return{vertices,indices,layers,frames,bones,atlas:[width,height]};
}
module.exports={validateFamily};
