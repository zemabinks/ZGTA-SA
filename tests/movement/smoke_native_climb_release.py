#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual climb-to-foot release through real CLP, fixed motor and Rapier.

Authored admitted ledges isolate task release from ground contacts. The
optional earlier checkout must reproduce nine actual motor differences.
Original game resources and raw reports remain local.
"""
from pathlib import Path
import argparse,hashlib,json,os,platform,runpy,subprocess,textwrap,time
BASE=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--negative-root',type=Path)
args=parser.parse_args();os.setpriority(os.PRIO_PROCESS,0,15)
out=BASE/'local-only/research/climb-release-207';out.mkdir(parents=True,exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
reports=[]
for label,root in ([('historical',args.negative_root.resolve())]if args.negative_root else [])+[('current',BASE)]:
    # Reuse our exact-source assembly boundary, including all actual Renderer
    # methods, rather than maintaining another approximate motion adapter.
    driver=(BASE/'tests/movement/smoke_native_climb_carrier.py').read_text()
    start=driver.index(' helper=runpy.run_path(');end=driver.index(' work=out/(label+',start)
    builder=textwrap.dedent(driver[start:end])
    needle="(BASE/'tests/movement/smoke_native_climb_carrier.swift')"
    assert builder.count(needle)==1
    builder=builder.replace(needle,"(BASE/'tests/movement/smoke_native_climb_release.swift')")
    exec(compile(builder,str(out/'selected-assembly.py'),'exec'))
    assert source.count('    var health=100')==1 and source.count('            expectedHeld=motion.heldFeet')==1
    source=source.replace('    var health=100','    var observedVerticalOverride:Double?\n    var observedTravel=SIMD3<Float>.zero\n    var health=100').replace('            expectedHeld=motion.heldFeet','            observedVerticalOverride=motion.verticalOverride\n            observedTravel=motion.displacement\n            expectedHeld=motion.heldFeet')
    work=out/(label+'-'+str(time.time_ns()));work.mkdir();(work/'main.swift').write_text(source)
    physics=['SwiftRapierWorld','NativeCharacterMotor','NativeRapierCharacterQueries','NativeCharacterController','NativeClimbController','NativeRapierClimbQueries']
    files=[root/'ios/App'/f'{n}.swift'for n in physics+names]+[root/'ios/App/NativeWorldRenderer.swift',root/'ios/App/NativeSkeletalActor.swift',root/'tests/movement/smoke_native_climb_runtime.swift',BASE/'tests/movement/smoke_native_climb_release.swift',BASE/'tests/movement/smoke_native_climb_carrier.py',Path(__file__).resolve()]
    frozen={str(p):sha(p)for p in files}
    report=dict(label=label,status='RUNNING',startedAt=time.time(),sourceHashes=frozen,carrierSHA256=hashlib.sha256(source.encode()).hexdigest())
    def save():(work/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    save()
    try:
        command=['xcrun','swiftc','-parse-as-library','-whole-module-optimization','-Onone','-num-threads','1','-module-cache-path',str(out/'modules'),'-I',str(BASE/'native-physics/include'),*[str(root/'ios/App'/f'{n}.swift')for n in physics],str(work/'main.swift'),*(['-D','CLIMB_RELEASE_CURRENT']if label=='current'else[]),'-L',str(BASE/f'local-only/native-physics/macos-{platform.machine()}'),'-lzgtasa_native_physics','-framework','Security','-framework','CoreFoundation','-o',str(work/'verify')]
        r=subprocess.run(command,capture_output=True,text=True,timeout=600);(work/'compile.log').write_text(r.stdout+r.stderr);report['compileExit']=r.returncode;save();assert r.returncode==0,'Compilation is not an accepted gameplay difference'
        command=[str(work/'verify'),str(BASE),str(work/'actual-cases.json')]+(['legacy']if label=='historical'else[])
        r=subprocess.run(command,capture_output=True,text=True,timeout=120);(work/'runtime.log').write_text(r.stdout+r.stderr);report['runtimeExit']=r.returncode;save();assert r.returncode==(42 if label=='historical'else 0)
        result=json.loads((work/'actual-cases.json').read_text())
        assert result['differences']==(9 if label=='historical'else 0)
        assert len(result['cases'])==(9 if label=='historical'else 85)
        report.update(status='EXPECTED_OLD_DIFFERENCES'if label=='historical'else'PASS',cases=len(result['cases']),checks=result['checks'],differences=result['differences'])
    except BaseException as error:report.update(status='FAIL',error=repr(error));raise
    finally:
        report.update(sourceHeld=all(sha(Path(n))==h for n,h in frozen.items()),completedAt=time.time());save()
    assert report['sourceHeld'];reports.append(dict(report,path=str(work)))
(out/'report.json').write_text(json.dumps(dict(status='PASS',results=reports,actualNice=os.getpriority(os.PRIO_PROCESS,0),scope='Actual Renderer/CLP/task/fixed motor/native Rapier. Authored admission and removal of test floor/finished stand surface isolate exit velocity. No original caller-order, retail, rendered or hardware claim.'),indent=2)+'\n')
print('PASS actual climb release:',[(r['label'],r['cases'],r['differences'])for r in reports],flush=True)
