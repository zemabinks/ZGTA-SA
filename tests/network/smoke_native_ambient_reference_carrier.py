#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Compile the optional NPC policy carrier against independently authored rows.

This protects the optional archived-observation path's interface. The fixture
below is a contract witness, not an archived-browser or retail comparison.
"""
from pathlib import Path
import argparse,hashlib,json,os,re,subprocess,time
ROOT=Path(__file__).resolve().parents[2]

def fixtures():
    def row(**changes):
        result=dict(dispatch='hit',nativeHeading=0.0,wireFrom=1.5707963267948966,
            expectedSide=0,timestampMS=1000.0,speed=0.0,flags=0,
            hitCounter=0,hitWeapon=0,piece=0,burning=False,crouch=False,
            thrown=0.0,fellBefore=False,faceDownBefore=False,
            expectedControllerCalls=[],expectedFellAfter=False,
            expectedFaceDownAfter=False,expectedHitsSeenAfter=0,
            expectedHitUntilAfterMS=None,expectedLostHeadAfter=False)
        result.update(changes);return result
    def death(kind,correction=False):
        result=dict(method='die',kind=kind,arriveLying=False)
        if correction:result['correctExisting']=True
        return result
    def rest():return dict(method='rest',restEnabled=True)
    cases=[
        dict(name='ordinary-hit-baseline-event-repeat-and-wrap',steps=[
            row(hitCounter=1,hitWeapon=22,piece=3,expectedHitsSeenAfter=1),
            row(timestampMS=1100.0,hitsSeenBefore=1,hitCounter=2,hitWeapon=22,piece=3,
                expectedControllerCalls=[dict(method='flinch',kind='flinch')],
                expectedHitsSeenAfter=2,expectedHitUntilAfterMS=2600.0),
            row(timestampMS=1200.0,hitsSeenBefore=2,hitCounter=2,hitWeapon=22,piece=3,
                hitUntilBeforeMS=2600.0,expectedHitsSeenAfter=2,expectedHitUntilAfterMS=2600.0),
            row(timestampMS=1300.0,hitsSeenBefore=31,hitCounter=0,hitWeapon=22,piece=3,
                hitUntilBeforeMS=2600.0,expectedHitUntilAfterMS=2600.0)]),
        dict(name='persistent-head-baseline-zero-and-repeat',steps=[
            row(flags=8,hitWeapon=24,piece=9,expectedLostHeadAfter=True,
                expectedControllerCalls=[dict(method='loseHead')]),
            row(timestampMS=1100.0,hitsSeenBefore=0,flags=8,hitWeapon=24,piece=9,
                expectedLostHeadAfter=True)]),
        dict(name='late-cause-correction-and-getup-orientation',steps=[
            row(dispatch='down',flags=1,expectedControllerCalls=[rest(),death('floorHit')],expectedFellAfter=True),
            row(dispatch='down',timestampMS=1100.0,flags=1,fellBefore=True,hitsSeenBefore=0,
                hitCounter=1,hitWeapon=24,piece=3,expectedControllerCalls=[death('koSkidFront',True)],
                expectedFellAfter=True,expectedFaceDownAfter=True),
            row(dispatch='down',timestampMS=1200.0,fellBefore=True,faceDownBefore=True,
                hitsSeenBefore=1,hitCounter=1,expectedFaceDownAfter=True,expectedControllerCalls=[dict(method='revive'),
                    dict(method='act',kind='getup_front',actCut=True,actOnce=True)])]),
        dict(name='head-visibility-resets-on-revive',steps=[
            row(dispatch='down',flags=9,hitWeapon=24,piece=9,expectedLostHeadAfter=True,
                expectedControllerCalls=[rest(),death('floorHit')],expectedFellAfter=True),
            row(dispatch='down',timestampMS=1100.0,fellBefore=True,hitsSeenBefore=0,
                expectedControllerCalls=[dict(method='revive'),dict(method='act',kind='getup',actCut=True,actOnce=True)]),
            row(timestampMS=1200.0,flags=8,hitsSeenBefore=0,hitWeapon=24,piece=9,
                expectedLostHeadAfter=True,expectedControllerCalls=[dict(method='loseHead')])]),
        dict(name='ordinary-unchanged-torso-death-shape',steps=[
            row(dispatch='down',flags=1,hitCounter=1,hitWeapon=22,piece=3,
                expectedControllerCalls=[rest(),death('koFront')],expectedFellAfter=True)])]
    # The down-policy branch checks the independently specified fall owner;
    # the hit-policy branch checks its independently specified counter owner.
    return dict(referenceKind='authored-contract',cases=cases)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--historical-root',type=Path,help='Compile the frozen old optional carrier; require the known interface failure')
    args=parser.parse_args();os.setpriority(os.PRIO_PROCESS,0,15)
    owner=ROOT/'ios/App/NativeAmbientPedestrianAnimation.swift'
    helper=ROOT/'tests/network/smoke_native_ambient_animation_reference.swift'
    if args.historical_root:
        historical=args.historical_root.resolve();assert historical!=ROOT
        assert (historical/'ios/App'/owner.name).read_bytes()==owner.read_bytes(),'Historical controller must be identical'
        helper=historical/'tests/network'/helper.name
    paths=[Path(__file__).resolve(),owner,helper,ROOT/'ios/App/NativeAmbientPedestrianProtocol.swift',ROOT/'ios/App/NativePedestrianReaction.swift']
    hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in paths}
    out=ROOT/'local-only/research/ambient-reference-carrier'/str(time.time_ns());out.mkdir(parents=True)
    source=re.sub(r'\bNativeFootAnimation\b','NPCFootSpy',owner.read_text()).replace('private var ','var ').replace('private func advance(','func advance(')
    (out/'PolicyCarrier.swift').write_text(source);(out/'authored-rows.json').write_text(json.dumps(fixtures(),indent=2)+'\n')
    report=dict(status='RUNNING',sourceHashes=hashes,historicalRequested=args.historical_root is not None,
        scope='Actual optional carrier interface and independent NPC policy with authored rows and explicit common-controller spy. No archived, full animation, rendering, device or retail comparison.')
    def save():
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        (out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),status=report['status']),indent=2)+'\n')
    save()
    try:
        command=['xcrun','swiftc','-parse-as-library','-Onone','-whole-module-optimization','-j','1','-num-threads','1','-module-cache-path',str(out/'modules'),str(paths[4]),str(paths[3]),str(out/'PolicyCarrier.swift'),str(helper),'-o',str(out/'carrier')]
        with(out/'compile.log').open('x')as log:r=subprocess.run(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,timeout=240)
        report['compileExit']=r.returncode
        if args.historical_root:
            text=(out/'compile.log').read_text();assert r.returncode!=0 and "has no member 'lostHead'"in text and "extra argument 'correctExisting'"in text,'Expected old optional-carrier interface failure was not observed'
            report['status']='EXPECTED_OLD_OPTIONAL_CARRIER_COMPILE_FAILURE'
        else:
            assert r.returncode==0,(out/'compile.log').read_text()[-6500:]
            r=subprocess.run([str(out/'carrier'),str(out/'authored-rows.json')],capture_output=True,text=True,timeout=30)
            (out/'runtime.log').write_text(r.stdout+r.stderr);report.update(exitCode=r.returncode,output=r.stdout+r.stderr)
            assert r.returncode==0,r.stdout+r.stderr
            result=json.loads(r.stdout);assert result['referenceKind']=='authored-contract' and result['cases']==5 and result['steps']==13 and result['checks']>=50
            report.update(status='PASS',checks=result['checks'],cases=result['cases'],steps=result['steps'])
    except BaseException as error:report.update(status='FAIL',error=repr(error));raise
    finally:
        report.update(sourcesHeld=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in hashes.items()),completedAt=time.time());save();print(json.dumps({k:v for k,v in report.items()if k!='sourceHashes'},indent=2))
    assert report['sourcesHeld']
if __name__=='__main__':main()
