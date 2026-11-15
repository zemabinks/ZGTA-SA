#!/usr/bin/env python3
"""Compare native water surfaces/index to the actual archived water factory."""
from pathlib import Path
import subprocess,tempfile
ROOT=Path(__file__).resolve().parent
JS=r'''
const fs=require('node:fs'),vm=require('node:vm'),source=fs.readFileSync(process.argv[2],'utf8');
const start=source.indexOf('y=function(e){let t=new Map'),stop=source.indexOf('}(e),d=',start);
const factory=vm.runInNewContext('('+source.slice(start+2,stop+1)+')');
const rows=JSON.parse(fs.readFileSync(process.argv[3],'utf8')).water.map(r=>r.map(Math.fround));
rows.push([100,100,7,100,100,7,100,101,7,100,101,7], [200,200,3,200.00005,200,4,200,200.00005,5].map(Math.fround), [0,0,3,1,0,4,0,1,5]);
const water=factory(rows),cases=[];
function add(x,y,z){x=Math.fround(x);y=Math.fround(y);z=Math.fround(z);cases.push({x,y,z,expected:water.level(x,y,z)})}
for(const p of rows){const points=[];let x=0,y=0;for(let i=0;i<p.length;i+=3){points.push([p[i],p[i+1]]);x+=p[i];y+=p[i+1]};points.push([x/(p.length/3),y/(p.length/3)]);
 for(const point of points)for(const z of [-100,0,13,1000]){add(...point,z);add(point[0]+.01,point[1]-.01,z)}}
for(let i=0;i<5000;i++)add((i*7919)%8000-4000,(i*3571)%8000-4000,i%200-100);
add(.5,.5000004,0);add(100,100.5,0);add(200.000015,200.000015,0);
fs.writeFileSync(process.argv[4],JSON.stringify({rows,cases}));
'''
SWIFT=r'''
let document=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [String:Any]
let rows=(document["rows"] as! [[NSNumber]]).map{$0.map(\.floatValue)},water=NativeWorldWater(rows:rows)
let cases=document["cases"] as! [[String:Any]]
var largest:Float=0
for item in cases {
 let x=(item["x"] as! NSNumber).floatValue,y=(item["y"] as! NSNumber).floatValue,z=(item["z"] as! NSNumber).floatValue
 let actual=water.height(x:x,y:y,z:z)
 if let expected=item["expected"] as? NSNumber {let error=abs(actual!-expected.floatValue);largest=max(largest,error);precondition(error<0.0001,"water mismatch at \(x),\(y),\(z): \(String(describing:actual)) != \(expected)")}
 else {precondition(actual==nil,"unexpected water at \(x),\(y),\(z)")}
}
let began=Date().timeIntervalSinceReferenceDate
var count=0
for y in 0..<133{for x in 0..<133{if water.height(x:Float(x)-1730,y:Float(y)-1840,z:0) != nil{count += 1}}}
print("PASS: \(cases.count) native water levels match actual JS factory, including triangle tolerances/degenerate quads/depth limits; max error \(largest); 17,689 near-net ground queries in \(Date().timeIntervalSinceReferenceDate-began)s (\(count) wet)")
'''

def main():
 chunks=ROOT/'local-only/site/_next/static/chunks'
 source=next(p for p in chunks.glob('*.js') if 'y=function(e){let t=new Map' in p.read_text())
 with tempfile.TemporaryDirectory(prefix='zgta-water-index-') as tmp:
  work=Path(tmp);js=work/'reference.js';js.write_text(JS);reference=work/'reference.json'
  subprocess.run(['node',str(js),str(source),str(ROOT/'local-only/site/game/world/index.json'),str(reference)],check=True)
  swift=work/'main.swift';binary=work/'verify';swift.write_text((ROOT/'ios/App/NativeWorldWater.swift').read_text()+SWIFT)
  subprocess.run(['swiftc','-O','-module-cache-path','/private/tmp/zgta-macos-swift-modules',str(swift),'-o',str(binary)],check=True)
  subprocess.run([str(binary),str(reference)],check=True)
if __name__=='__main__':main()
