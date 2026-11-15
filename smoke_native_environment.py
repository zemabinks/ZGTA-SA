#!/usr/bin/env python3
"""Compare native time/weather interpolation against the actual archived JS.

Requires this Mac's local-only archive and Swift. No game data is copied into
the repository; temporary reference cases and compiled modules are removed.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent

JAVASCRIPT = r'''
const fs=require('node:fs'),vm=require('node:vm');
const sandbox={self:{webpackChunk_N_E:[]}};
vm.runInNewContext(fs.readFileSync(process.argv[2],'utf8'),sandbox);
const modules=Object.assign({},...sandbox.self.webpackChunk_N_E.map(x=>x[1])),cache={};
function load(id){if(cache[id])return cache[id].exports;const m={exports:{}};cache[id]=m;modules[id](m,m.exports,load);return m.exports}
load.d=(t,o)=>Object.entries(o).forEach(([k,v])=>Object.defineProperty(t,k,{get:v}));
const original=load(7508)._$,cases=[];
for(let weather=0;weather<23;weather++)for(const hour of [0,5.5,6.75,12,20.5,23.999])
for(const altitude of [0,120,350,700])cases.push({from:weather,to:weather,blend:1,hour,altitude});
for(let i=0;i<120;i++)cases.push({from:i%23,to:(i*7+2)%23,blend:(i%11)/10,hour:(i*1.713)%24,altitude:(i*29)%800});
for(const c of cases)c.expected=JSON.parse(JSON.stringify(original(c.hour,c.from,c.to,c.blend,c.altitude)));
fs.writeFileSync(process.argv[3],JSON.stringify(cases));
'''

SWIFT = r'''
let environment = try NativeWorldEnvironment(data: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
let cases = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))) as! [[String:Any]]
var largest: Float = 0
for value in cases {
    let sample = environment.sample(weatherFrom: value["from"] as! Int, to: value["to"] as! Int,
        blend: (value["blend"] as! NSNumber).floatValue, hour: (value["hour"] as! NSNumber).floatValue,
        altitude: (value["altitude"] as! NSNumber).floatValue)
    let expected = value["expected"] as! [String:Any]
    for (key, actual) in [("skyTop", sample.skyTop), ("skyBottom", sample.skyBottom), ("water", sample.waterColor)] {
        let values = expected[key] as! [NSNumber]
        for i in values.indices {
            let error = abs(actual[i]-values[i].floatValue); largest = max(largest,error)
            assert(error < 0.0001, "color mismatch \(key), component \(i)")
        }
    }
    assert(abs(sample.farClip-(expected["farClip"] as! NSNumber).floatValue) < 0.003, "far clip mismatch")
    assert(abs(sample.fogStart-(expected["fogStart"] as! NSNumber).floatValue) < 0.003, "fog mismatch")
}
assert(NativeWorldEnvironment.gameHour(epochMilliseconds: 720000) == 12)
assert(NativeWorldEnvironment.gameHour(epochMilliseconds: 1440000) == 0)
assert(NativeWorldEnvironment.nightShare(hour: 6.5) == 0.5)
assert(NativeWorldEnvironment.nightShare(hour: 20.5) == 0.5)
print("PASS: \(cases.count) native sky/water/fog samples match archived JS; maximum color error \(largest)")
'''


def main():
    chunk = next(path for path in (ROOT / 'local-only/site/_next/static/chunks').glob('*.js')
                 if '7508:(e,t,n)' in path.read_text() and '98459:e=>' in path.read_text())
    with tempfile.TemporaryDirectory(prefix='zgta-environment-') as temporary:
        work = Path(temporary)
        js = work / 'reference.js'
        js.write_text(JAVASCRIPT)
        reference = work / 'reference.json'
        subprocess.run(['node', str(js), str(chunk), str(reference)], check=True)
        swift = work / 'verify.swift'
        swift.write_text((ROOT / 'ios/App/ServerAddress.swift').read_text() +
                         (ROOT / 'ios/App/NativeWorldEnvironment.swift').read_text() + SWIFT)
        subprocess.run(['swift', '-module-cache-path', str(work / 'modules'), str(swift),
                        str(ROOT / 'local-only/site/game/native/environment.json'), str(reference)], check=True)


if __name__ == '__main__':
    main()
