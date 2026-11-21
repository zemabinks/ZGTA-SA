#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Execute the actual drawActors occurrence construction/consumption boundary.

The generated Swift carrier extracts the production override declaration, queue,
appendPed, retained non-ped append statements and loop preamble. Opaque fixture
pose/transform/flight/context values test ownership and preservation, not Metal
rendering. A position adapter counts real String-interpolation calls in the
extracted historical path; this is not a timing test of Swift's SIMD formatter.
No game files, application build, server, network or device is used.
"""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import argparse, hashlib, json, os, subprocess, sys, time
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def block(source, marker, opening='{', closing='}'):
    start = source.index(marker)
    at = source.index(opening, start)
    depth = 0
    quote = False
    escaped = False
    for index in range(at, len(source)):
        c = source[index]
        if quote:
            if escaped:
                escaped = False
            elif c == '\\':
                escaped = True
            elif c == '"':
                quote = False
            continue
        if c == '"':
            quote = True
        elif c == opening:
            depth += 1
        elif c == closing:
            depth -= 1
            if depth == 0:
                return source[start:index+1]
    raise ValueError('Unclosed production block: ' + marker)

def extract(path):
    source = path.read_text()
    override = block(source, '    private struct ActorPoseOverride')
    draw = block(source, '    private func drawActors(')
    begin = draw.index('        var modelInstances:')
    end = draw.index('        if driving,isPassenger,', begin)
    queue = draw[begin:end]
    begin = draw.index('        for (name, position, angle, pitch, clip, elapsed, weapon, vehicleContext')
    end = draw.index('            let mesh =', begin)
    consume = draw[begin:end]
    calls = []
    at = 0
    while True:
        try:
            start = draw.index('modelInstances.append(', at)
        except ValueError:
            break
        call = block(draw[start:], 'modelInstances.append(', '(', ')')
        calls.append(call)
        at = start + len(call)
    has_traffic=any('SIMD3<Float>(traffic.body.position)' in call for call in calls)
    if len(calls) != 6+int(has_traffic):
        raise ValueError('Review new/removed production occurrence producers; expected appendPed, five retained direct sites and the explicit traffic site when present')
    roles = {}
    for name, marker in [('own', 'name,camera,'), ('remote', 'name,player.position,'),
                         ('projectile', 'projectile.model,'), ('parked', 'name,vehicle.position,'),
                         ('carriage', 'name,carriage.position,')]:
        matches = [call for call in calls if marker in call]
        if len(matches) != 1:
            raise ValueError('Ambiguous production producer: ' + name)
        roles[name] = matches[0]
    if has_traffic:
        matches=[call for call in calls if 'SIMD3<Float>(traffic.body.position)'in call]
        if len(matches)!=1:raise ValueError('Ambiguous traffic occurrence producer')
        roles['traffic']=matches[0]
    return dict(override=override, queue=queue, consume=consume, roles=roles,
                sourceSHA256=sha(path), source=str(path),
                drawSHA256=hashlib.sha256(draw.encode()).hexdigest())

PRELUDE = r'''
import Foundation

private enum FormatProbe { static var calls = 0 }
// Instrumentation adapter only: production queue code uses this exact type
// spelling, while payload mathematics and real SIMD performance are out of scope.
private struct SIMD3<Scalar: BinaryFloatingPoint>: Equatable, CustomStringConvertible {
    let x: Scalar, y: Scalar, z: Scalar
    init(_ x: Scalar, _ y: Scalar, _ z: Scalar) { self.x=x; self.y=y; self.z=z }
    init(_ other:Self){self=other}
    var description: String {
        FormatProbe.calls += 1
        return "[\(x),\(y),\(z)]"
    }
}
private enum NativeSkeletalActor { struct Pose: Equatable { let marker: Int } }
private enum NativeFlightAnimation {
    struct Frame: Equatable { let marker: Int }
    struct Canopy: Equatable { let marker: Int }
}
private struct simd_float4x4: Equatable { let marker: Int }
private struct VehicleDrawContext: Equatable { let marker: Int }
private struct TransparentVehicleDraw {}
private struct Observation {
    let name: String, position: SIMD3<Float>, angle: Float, pitch: Float
    let clip: String, elapsed: Double, weapon: Int
    let vehicleContext: VehicleDrawContext?, queued: ActorPoseOverride?
}
private struct CheckFailure: Error { let label: String }
private var checks = 0
private func check(_ value: Bool, _ label: String) throws {
    checks += 1
    if !value { throw CheckFailure(label: label) }
}
'''

INVOCATIONS = r'''
    let point=SIMD3<Float>(10,20,30)
    if frame != 1 {
        appendPed("shared-skin",point,1,2,"own-clip",3.25,4,
            pose:.init(marker:100+frame),transform:.init(marker:200+frame),original:true,
            flight:.init(marker:300+frame),identity:"own",ownFoot:true)
        appendPed("shared-skin",point,5,6,"remote-clip",7.25,8,
            pose:.init(marker:400+frame),identity:"__REMOTE_ID__",ownFoot:false__CANOPY_ARGUMENT__)
        appendPed("shared-skin",point,9,10,"rider-clip",11.25,12,
            pose:.init(marker:500+frame),transform:.init(marker:600+frame),original:true,
            flight:.init(marker:700+frame),identity:"passenger",ownFoot:false__TRAFFIC_OCCUPANT_ARGUMENT__)
        appendPed("fallback-skin",point,13,14,"fallback-clip",15.25,16)
    }
    do {
        let name="shared-car",camera=point,heading:Float=21,vehiclePitch:Float=22
        let context=VehicleDrawContext(marker:800+frame)
        __OWN__
    }
    do {
        struct Player { let position:SIMD3<Float>,heading:Float,pitch:Float }
        let name="shared-car",player=Player(position:point,heading:23,pitch:24)
        let context=VehicleDrawContext(marker:900+frame)
        __REMOTE__
    }
    do {
        struct Projectile { let model:String,position:SIMD3<Float> }
        let projectile=Projectile(model:"projectile",position:point),direction:Float=25,pitch:Float=26
        __PROJECTILE__
    }
    do {
        struct Vehicle { let position:SIMD3<Float>,heading:Float,pitch:Float }
        let name="shared-car",vehicle=Vehicle(position:point,heading:27,pitch:28)
        let context=VehicleDrawContext(marker:1000+frame)
        __PARKED__
    }
    do {
        struct Carriage { let position:SIMD3<Float> }
        let name="shared-car",carriage=Carriage(position:point)
        let context=VehicleDrawContext(marker:1100+frame)
        __CARRIAGE__
    }
    // TRAFFIC_INVOCATION
'''

CHECKS = r'''
@main private enum Gate {
    static func main() {
        let historical=CommandLine.arguments.contains("--historical")
        var result: [String:Any] = ["scope":"Extracted production occurrence boundary with opaque fixtures; no renderer/Metal/device/performance claim"]
        do {
            var observed: [[String:Any]] = []
            for frame in 0..<3 {
                let rows=productionFrame(frame)
                let pedCount=frame == 1 ? 0:4
                try check(rows.count == pedCount+__NONPED_COUNT__,"all explicit non-ped producers and expected pedestrians")
                for (index,row) in rows.enumerated() {
                    try check(row.position == SIMD3<Float>(10,20,30),"position retained")
                    if index < pedCount {
                        try check(row.queued != nil,"ped has its own occurrence payload")
                        let q=row.queued!
                        // CANOPY_CHECKS
                        // TRAFFIC_PROVENANCE_CHECKS
                        switch index {
                        case 0:
                            try check(row.name == "shared-skin" && row.angle == 1 && row.pitch == 2 && row.clip == "own-clip" && row.elapsed == 3.25 && row.weapon == 4,"owned first eight draw values")
                            try check(q.pose?.marker == 100+frame,"own pose")
                            try check(q.transform?.marker == 200+frame,"own transform")
                            try check(q.original,"own original flag")
                            try check(q.flight?.marker == 300+frame,"own flight")
                            try check(q.identity == "own","own identity")
                            try check(q.ownFoot,"own foot flag")
                        case 1:
                            try check(row.name == "shared-skin" && row.angle == 5 && row.pitch == 6 && row.clip == "remote-clip" && row.elapsed == 7.25 && row.weapon == 8,"co-located remote first eight values")
                            try check(q.pose?.marker == 400+frame && q.transform == nil,"remote pose/nil transform")
                            try check(!q.original && q.flight == nil,"remote original/flight defaults")
                            try check(q.identity == "__REMOTE_ID__" && !q.ownFoot,"remote identity/foot flags")
                        case 2:
                            try check(row.name == "shared-skin" && row.angle == 9 && row.pitch == 10 && row.clip == "rider-clip" && row.elapsed == 11.25 && row.weapon == 12,"co-located rider first eight values")
                            try check(q.pose?.marker == 500+frame && q.transform?.marker == 600+frame,"rider pose and transform")
                            try check(q.original && q.flight?.marker == 700+frame,"rider original and flight")
                            try check(q.identity == "passenger" && !q.ownFoot,"rider identity and foot")
                        default:
                            try check(row.name == "fallback-skin" && row.angle == 13 && row.pitch == 14 && row.clip == "fallback-clip" && row.elapsed == 15.25 && row.weapon == 16,"fallback first eight values")
                            try check(q.pose == nil && q.transform == nil && !q.original && q.flight == nil && q.identity == nil && !q.ownFoot,"all nil/default payload fields retained")
                        }
                        try check(row.vehicleContext == nil,"ped cannot acquire vehicle body context")
                    } else {
                        let role=index-pedCount
                        try check(row.queued == nil,"vehicle/projectile has no ped override")
                        try check(row.clip.isEmpty && row.elapsed == 0 && row.weapon == 0,"non-ped non-appearance fields")
                        let expectedAngles:[Float]=[21,23,25,27,0,29],expectedPitches:[Float]=[22,24,26,28,0,30]
                        try check(row.angle == expectedAngles[role] && row.pitch == expectedPitches[role],"actual producer heading/pitch")
                        if role == 2 {try check(row.name == "projectile" && row.vehicleContext == nil,"projectile stays unowned")}
                        else {
                            let expected=[800,900,0,1000,1100,1200][role]+frame
                            try check(row.name == "shared-car" && row.vehicleContext?.marker == expected,"co-located vehicle context preserved")
                        }
                    }
                    observed.append(["frame":frame,"index":index,"name":row.name,"position":[row.position.x,row.position.y,row.position.z],
                        "angle":row.angle,"pitch":row.pitch,"clip":row.clip,"elapsed":row.elapsed,"weapon":row.weapon,
                        "context":row.vehicleContext?.marker as Any? ?? NSNull(),"hasOverride":row.queued != nil,
                        "pose":row.queued?.pose?.marker as Any? ?? NSNull(),"transform":row.queued?.transform?.marker as Any? ?? NSNull(),
                        "original":row.queued?.original as Any? ?? NSNull(),"flight":row.queued?.flight?.marker as Any? ?? NSNull(),
                        "identity":row.queued?.identity as Any? ?? NSNull(),"ownFoot":row.queued?.ownFoot as Any? ?? NSNull()])
                }
            }
            let formattingCalls=FormatProbe.calls
            result["observations"]=observed
            result["formattingCalls"]=formattingCalls
            if historical {try check(formattingCalls > 0,"historical position formatting reproduced")}
            else {try check(formattingCalls == 0,"occurrence boundary never formats positions")}
            result["passed"]=true
        } catch let error as CheckFailure {
            result["passed"]=false;result["error"]=error.label;result["formattingCalls"]=FormatProbe.calls
        } catch {result["passed"]=false;result["error"]=String(describing:error)}
        result["checks"]=checks
        let data=try! JSONSerialization.data(withJSONObject:result,options:[.sortedKeys])
        print(String(data:data,encoding:.utf8)!)
        if result["passed"] as? Bool != true {exit(1)}
    }
}
'''

def carrier(parts):
    invocation = INVOCATIONS
    traffic='traffic'in parts['roles']
    traffic_invocation='''do {
        struct Traffic {struct Body {let position:SIMD3<Float>,heading:Double,pitch:Double};let body:Body}
        let name="shared-car",traffic=Traffic(body:.init(position:point,heading:29,pitch:30))
        let context=VehicleDrawContext(marker:1200+frame)
        __TRAFFIC__
    }'''if traffic else ''
    invocation=invocation.replace('// TRAFFIC_INVOCATION',traffic_invocation)
    canopy = 'var canopySamples:' in parts['override']
    occupant = 'var trafficOccupant:' in parts['override']
    remote_id='c3.0'if occupant else'remote'
    invocation=invocation.replace('__REMOTE_ID__',remote_id).replace('__TRAFFIC_OCCUPANT_ARGUMENT__',
        ',trafficOccupant:(3,UInt64(20+frame),2,9,frame==2)'if occupant else'')
    invocation = invocation.replace('__CANOPY_ARGUMENT__',
        ',canopySamples:[.init(marker:10000+frame),nil,.init(marker:20000+frame)]' if canopy else '')
    canopy_checks = '''if index == 1 {
                            try check(q.canopySamples.count == 3,"remote ordered canopy payload count")
                            try check(q.canopySamples[0]?.marker == 10000+frame && q.canopySamples[1] == nil && q.canopySamples[2]?.marker == 20000+frame,"remote ordered canopy targets/nil retained")
                        } else {try check(q.canopySamples.isEmpty,"co-located actor cannot acquire another canopy sequence")}
                        ''' if canopy else ''
    occupant_checks='''if index == 2 {
                            try check(q.trafficOccupant?.id==3 && q.trafficOccupant?.generation==UInt64(20+frame),"typed traffic lifetime stayed on its own occurrence")
                            try check(q.trafficOccupant?.seat==2 && q.trafficOccupant?.skin==9 && q.trafficOccupant?.dead==(frame==2),"typed traffic seat/skin/death fields retained")
                        }else{try check(q.trafficOccupant==nil,"human lookalike ID or adjacent occurrence acquired traffic provenance")}
                        '''if occupant else''
    for name, text in parts['roles'].items():
        invocation = invocation.replace('__'+name.upper()+'__', text)
    return (PRELUDE + '\n' + parts['override'] + '\nprivate func productionFrame(_ frame:Int) -> [Observation] {\n' +
            parts['queue'] + invocation + '\n    var observations:[Observation]=[]\n' + parts['consume'] +
            '\n            observations.append(.init(name:name,position:position,angle:angle,pitch:pitch,clip:clip,elapsed:elapsed,weapon:weapon,vehicleContext:vehicleContext,queued:queued))\n' +
            '        }\n    return observations\n}\n' + CHECKS.replace('// CANOPY_CHECKS',canopy_checks).replace('// TRAFFIC_PROVENANCE_CHECKS',occupant_checks).replace('__REMOTE_ID__',remote_id).replace('__NONPED_COUNT__',str(6 if traffic else 5)))

def private_output(value):
    output = Path(os.path.abspath(value))
    if not output.is_relative_to(ROOT/'local-only') or output == ROOT/'local-only':
        raise ValueError('Output must be a new directory under this checkout local-only')
    for p in [output, *output.parents]:
        if p.is_symlink():
            raise ValueError('Refusing linked output or ancestor')
        if p == ROOT:
            break
    if output.exists():
        raise ValueError('Choose a new output directory')
    return output

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source',type=Path,default=ROOT/'ios/App/NativeWorldRenderer.swift')
    parser.add_argument('--historical',type=Path)
    parser.add_argument('--output',type=Path,default=ROOT/'local-only/research'/('draw-occurrences-'+str(time.time_ns())))
    parser.add_argument('--prepare-only',action='store_true')
    args = parser.parse_args()
    output = private_output(args.output)
    output.mkdir(parents=True)
    sources = {'current':args.source.resolve()}
    if args.historical:
        sources['historical']=args.historical.resolve()
    parts = {name:extract(path) for name,path in sources.items()}
    report = dict(scope='Extracted production occurrence boundary; asset-free opaque fixtures; no Metal/device or performance benchmark',
                  sources={name:{k:v for k,v in p.items() if k in ['source','sourceSHA256','drawSHA256']}for name,p in parts.items()},
                  output=str(output),passed=False,prepareOnly=args.prepare_only)
    try:
        for name, p in parts.items():
            file=output/(name+'.swift')
            file.write_text(carrier(p))
            report['sources'][name]['carrierSHA256']=sha(file)
        if args.prepare_only:
            report['passed']=True
        else:
            for name in parts:
                executable=output/name
                command=['xcrun','swiftc','-parse-as-library','-whole-module-optimization','-O','-swift-version','5',
                         '-module-cache-path',str(output/'modules'),str(output/(name+'.swift')),'-o',str(executable)]
                built=subprocess.run(command,capture_output=True,timeout=180,cwd=ROOT)
                (output/(name+'-compile.log')).write_bytes(built.stdout+built.stderr)
                built.check_returncode()
                # Historical source must fail today's no-formatting contract,
                # then pass its explicitly labelled diagnostic expectation.
                if name=='historical':
                    negative=subprocess.run([str(executable)],capture_output=True,timeout=20)
                    (output/'historical-current-contract.log').write_bytes(negative.stdout+negative.stderr)
                    rejected=json.loads(negative.stdout)
                    if negative.returncode==0 or rejected.get('error')!='occurrence boundary never formats positions':
                        raise ValueError('Historical negative did not reproduce the actual formatting contract failure')
                    report['historicalCurrentContractRejected']=True
                result=subprocess.run([str(executable)]+(['--historical']if name=='historical'else[]),capture_output=True,timeout=20)
                (output/(name+'-run.log')).write_bytes(result.stdout+result.stderr)
                result.check_returncode()
                report[name]=json.loads(result.stdout)
            if 'historical' in report and report['current']['observations']!=report['historical']['observations']:
                raise ValueError('Current occurrence payloads differ from historical behavior on the authored normal cases')
            report['passed']=True
    except Exception as error:
        report['error']=str(error)
    report['sourceUnchanged']=all(sha(sources[name])==p['sourceSHA256']for name,p in parts.items())
    report['passed']=report['passed']and report['sourceUnchanged']
    (output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:report.get(k)for k in ['passed','prepareOnly','sourceUnchanged','output','error']}))
    return 0 if report['passed']else 1

if __name__=='__main__':
    sys.exit(main())
