#!/usr/bin/env python3
"""Compare public pedestrian reaction49368.be across weapons/body parts."""
from pathlib import Path
import subprocess,tempfile
from smoke_native_foot_animation import SWIFT as FOOT_SWIFT
ROOT=Path(__file__).resolve().parent
JS=r'''
const fs=require('node:fs'),path=require('node:path'),load=require(path.join(process.cwd(),'smoke_vehicle_dynamics')).archivedModules(),reaction=load(49368).be,rows=[];
for(let weapon=0;weapon<=54;weapon++)for(let side=0;side<4;side++)for(let piece=3;piece<=9;piece++)for(let bits=0;bits<8;bits++){
 const input={weapon,side,piece,still:!!(bits&1),crouched:!!(bits&2),stun:!!(bits&4),damage:bits%2?25:10,now:1000,until:bits===0?1100:-1000},output=reaction(input);
 rows.push({input,expected:{kind:output.kind??null,until:output.until,stun:output.stun??false}});
}
fs.writeFileSync(process.argv[2],JSON.stringify(rows));
'''
SWIFT=r'''
let rows=try JSONDecoder().decode(ExactFixtureJSON.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))).any as! [[String:Any]]
for (index,row)in rows.enumerated(){let p=row["input"] as! [String:Any],e=row["expected"] as! [String:Any]
 func n(_ key:String)->Double{(p[key] as! NSNumber).doubleValue}
 let actual=NativePedestrianReaction.reaction(.init(weapon:Int(n("weapon")),side:Int(n("side")),piece:Int(n("piece")),still:p["still"] as! Bool,crouched:p["crouched"] as! Bool,damage:n("damage"),now:n("now"),until:n("until"),stun:p["stun"] as! Bool))
 assert(actual.kind==e["kind"] as? String && actual.until==(e["until"] as! NSNumber).doubleValue && actual.stun==e["stun"] as! Bool,"reaction \(index)")
}
print("PASS: \(rows.count) actual 49368.be reactions covering55 weapons,4 directions,7 body parts,crouch/movement/stun and cooldowns")
'''
def main():
 with tempfile.TemporaryDirectory(prefix='zgta-ped-reaction-')as tmp:
  work=Path(tmp);(work/'reference.js').write_text(JS)
  subprocess.run(['node',str(work/'reference.js'),str(work/'reference.json')],cwd=ROOT,check=True)
  (work/'verify.swift').write_text((ROOT/'ios/App/NativePedestrianReaction.swift').read_text()+FOOT_SWIFT[:FOOT_SWIFT.index('let root=')]+SWIFT)
  subprocess.run(['swift','-module-cache-path','/private/tmp/zgta-macos-swift-modules',str(work/'verify.swift'),str(work/'reference.json')],check=True)
if __name__=='__main__':main()
