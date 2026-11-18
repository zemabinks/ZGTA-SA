#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual metadata/selection ownership with resource, dispatch and audio spies."""
from pathlib import Path
import argparse,hashlib,json,subprocess,tempfile,time
ROOT=Path(__file__).resolve().parent
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--historical-root',type=Path)
args=parser.parse_args()
out=ROOT/'local-only/research/radio-metadata-117'/str(time.time_ns());out.mkdir(parents=True)
def declaration(text,marker,optional=False):
    if optional and marker not in text:return ''
    assert text.count(marker)==1,marker
    start=text.index(marker);brace=text.index('{',start);end=brace+1;depth=1
    while depth:
        depth+=(text[end]=='{')-(text[end]=='}');end+=1
    return text[start:end].replace('private ','')
markers={
 'STATION':'    private struct Station ', 'TRACK':'    private struct Track:',
 'SONG':'    private struct Song:', 'INDEX':'    private struct Index:',
 'STATION_ID':'    var stationID:', 'STATION_NAME':'    var stationName:',
 'CYCLE':'    func cycle(', 'STOP':'    func stop()', 'RESUME':'    func resume()',
 'ENTER':'    func enter(', 'REFRESH':'    private func refreshMetadata(',
 'CONFIGURE':'    private func configureVehicleStation(', 'CANCEL_DIAL':'    private func cancelDial(',
 'LOAD_PROGRAM':'    private func loadProgram(', 'AUDIO_URL':'    private func audioURL(',
}
paths=['ios/App/NativeVehicleRadio.swift','ios/App/NativeRadioProgram.swift','ios/App/NativeRadioSelection.swift',
       'smoke_native_radio_metadata.swift','smoke_native_radio_metadata.py']
frozen={p:(ROOT/p).read_bytes()for p in paths}
def run(source_root,label,historical=False):
    radio=(source_root/'ios/App/NativeVehicleRadio.swift').read_text()
    source=frozen['smoke_native_radio_metadata.swift'].decode()
    for key,marker in sorted(markers.items(),key=lambda item:-len(item[0])):
        value=declaration(radio,marker,optional=historical and key in {'REFRESH','CONFIGURE','CANCEL_DIAL'})
        if key=='CANCEL_DIAL' and not value:value='func cancelDial(){dial?.cancel();dial=nil;dialOwner=nil}'
        # Explicit dispatch adapter can release an already-dequeued work item;
        # it changes no closure, condition or game/source metadata.
        value=value.replace('DispatchWorkItem {','QueuedWork {').replace('DispatchQueue.main.asyncAfter(', 'DialScheduler.enqueue(')
        source=source.replace('// ACTUAL_'+key,value)
    assert '// ACTUAL_' not in source
    work=out/label;work.mkdir();main=work/'main.swift';main.write_text(source)
    files=[]
    for name in ['NativeRadioProgram','NativeRadioSelection']:
        p=work/(name+'.swift');p.write_bytes(frozen['ios/App/'+name+'.swift']);files.append(str(p))
    command=['xcrun','swiftc','-swift-version','5','-whole-module-optimization','-Onone','-num-threads','1',
             '-module-cache-path',str(out/'modules'),*files,str(main),'-o',str(work/'verify')]
    with (work/'compile.log').open('w')as log:result=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=180)
    if result.returncode:print((work/'compile.log').read_text()[-8000:]);result.check_returncode()
    result=subprocess.run([str(work/'verify')],capture_output=True,text=True,timeout=30)
    (work/'runtime.log').write_text(result.stdout+result.stderr)
    if historical:assert result.returncode==23 and 'late index replaces explicit station intent' in result.stderr,'Historical control must compile and fail target ownership assertion'
    else:print(result.stdout,end='');print(result.stderr,end='');result.check_returncode()
    return {'label':label,'sourceSHA256':hashlib.sha256(radio.encode()).hexdigest(),'exitCode':result.returncode,
            'output':result.stdout+result.stderr,'historicalExpectedFailure':historical}
results=[run(ROOT,'current')]
if args.historical_root:results.append(run(args.historical_root.resolve(),'historical',True))
assert all((ROOT/p).read_bytes()==v for p,v in frozen.items())
report={'pass':True,'results':results,'sourceUnchanged':True,'sourceSHA256':{p:hashlib.sha256(v).hexdigest()for p,v in frozen.items()},
 'audioDeviceOrEngineStarted':False,'networkOpened':False,'retailParityVerified':False,
 'scope':'Actual extracted metadata callbacks, vehicle selection, station cycling and dial closures; actual programme parser; explicit resource/audio/queued-dispatch spies'}
(out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('Report:',out/'report.json')
