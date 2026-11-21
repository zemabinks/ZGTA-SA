#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Compact traffic occupant selection with independently authored fixtures."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,time

ROOT=Path(__file__).resolve().parents[2]
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--previous-policy',type=Path)
    parser.add_argument('--reference',type=Path)
    parser.add_argument('--owner-catalog',type=Path)
    args=parser.parse_args()
    if bool(args.reference)!=bool(args.owner_catalog):parser.error('Reference and owner catalog must be supplied together')
    os.setpriority(os.PRIO_PROCESS,0,15)
    out=ROOT/'local-only/research/traffic-occupants-166'/str(time.time_ns());out.mkdir(parents=True)
    files=[ROOT/'ios/App/NativeTrafficOccupants.swift',Path(__file__).with_suffix('.swift')]
    reference_fixture=Path(__file__).with_suffix('.reference.swift')
    inputs=[*files,Path(__file__).resolve()]+([args.previous_policy]if args.previous_policy else[])+([args.reference,args.owner_catalog,reference_fixture]if args.reference else[])
    document=None
    if args.reference:
        document=json.loads(args.reference.read_text());catalog=json.loads(args.owner_catalog.read_text())
        assert document['schemaVersion']==1 and catalog['sourceSHA256']==document['source']['sha256']
        parent=document['parent']
        for path,digest in [(Path(document['source']['path']),document['source']['sha256']),
                            (Path(parent['observationsPath']),parent['observationsSHA256']),
                            (Path(parent['evidencePath']),parent['evidenceSHA256'])]:
            assert hashlib.sha256(path.read_bytes()).hexdigest()==digest,'Reference parent identity changed'
            inputs.append(path)
    frozen={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in inputs}
    report=dict(status='RUNNING',sourceHashes=frozen,scope=__doc__)
    def save():
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
        (out.parent/'latest.json').write_text(json.dumps(dict(path=str(out),status=report['status']),indent=2)+'\n')
    save()
    try:
        report['results']=[]
        variants=([('previous',args.previous_policy,files[1],[])]if args.previous_policy else[])+[('candidate',files[0],files[1],[])]
        if args.reference:
            report['referenceEvidence']=document['evidenceID']
            variants.append(('reference',files[0],reference_fixture,[str(args.owner_catalog.resolve()),str(args.reference.resolve()),str(out/'reference-policy.json')]))
        for label,source,fixture,arguments in variants:
            command=['xcrun','swiftc','-parse-as-library','-j','1','-whole-module-optimization','-num-threads','1','-Onone',
                     '-module-cache-path',str(out/'modules'),str(source),str(fixture),'-o',str(out/label)]
            with(out/(label+'-compile.log')).open('x')as log:r=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=180)
            assert r.returncode==0,(out/(label+'-compile.log')).read_text()[-5000:]
            r=subprocess.run([str(out/label),*arguments],capture_output=True,text=True,timeout=30);output=r.stdout+r.stderr
            (out/(label+'-runtime.log')).write_text(output);report['results'].append(dict(label=label,compileExit=0,exitCode=r.returncode,output=output));save()
            if label=='previous':assert r.returncode!=0 and 'Nullable crew metadata rejected'in output,output
            else:assert r.returncode==0,output
            print(output,end='')
        report['status']='PASS'
    except BaseException as error:report.update(status='FAIL',error=repr(error));raise
    finally:
        report['sourcesHeld']=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in frozen.items());save()
    assert report['sourcesHeld']
if __name__=='__main__':main()
