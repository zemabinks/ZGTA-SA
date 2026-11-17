#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual local radio/leases/PCM with authored math recordings; no audio output.

Existing source-stamped audio/installer archives are read only. This test never
builds C, runs a server, imports owner files, starts an engine or operates UI.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import struct
import subprocess
import sys
import time
sys.dont_write_bytecode=True
from smoke_native_climb_runtime import function
from native_raw_test_support import pinned_host_archive,bridge_module

ROOT=Path(__file__).resolve().parent
NAMES=['NativeResourceManifest','NativeResourceStore','NativeRawResourceLease','NativeRawResourceStore',
       'NativeRadioArchive','NativeRadioProgram','NativeRadioPCMWindow','NativeLocalRadioProvider','ServerAddress','NativeRadioPlayback']
SDK_NAMES=['NativeAppSettings','NativeRadioSelection','NativeVehicleRadio']


def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path);value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value


def fixtures(out):
    math=module('authored_radio_math',ROOT/'native-audio/tests/fixtures.py')
    key=bytes([234,58,196,161,154,168,20,243,72,176,215,35,157,232,255,241])
    names=['AA','CH','ADVERTS','CO'];paths=['AuDiO/CoNfIg/StrmPaks.dat','AUDIO/config/TrakLkup.dat',
         'audio/STREAMS/AA','AUDIO/streams/CH','AuDiO/Streams/ADVERTS','audio/streams/CO']
    for tag in ['A','B']:
        folder=out/tag;folder.mkdir(parents=True)
        packs=[]
        for name in names:
            payload=math.payload('mono' if tag=='B' and name=='CH' else 'stereo')
            start=29+8068
            packs.append(bytes(start)+bytes(b^key[(start+i)&15] for i,b in enumerate(payload))+b'authored outside indexed record')
        table=b''.join(name.encode()+bytes(16-len(name)) for name in names)
        lookup=b''.join(bytes([index,0xcd,0xcd,0xcd])+struct.pack('<II',29,8068+len(math.payload('mono' if tag=='B' and name=='CH' else 'stereo')))for index,name in enumerate(names))
        # Track2 is adverts and track3 is CO; wire IDs never compact.
        values=[table,lookup,*packs]
        for path,data in zip(paths,values):
            target=folder/path;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
    (out/'paths.json').write_text(json.dumps(paths))
    (out/'references.json').write_text(json.dumps({name:value['reference']for name,value in math.FIXTURES.items()}))
    station={'songs':[[1,[1,1],[1,1]]],'idents':None,'talk':{},'noAdverts':[]}
    program={'rate':32000,'samples':[20000,20000,1000,20000],'stations':[station]*12,'adverts':[2,2],
             'vehicleDefaults':{'9001':[1,0],'9002':[0,3]},'stationNames':[{}]*13,'rain':[],'sun':[],'fog':[],
             'stationRegions':{},'talkShowGroups':[[0]],'weather':{'la':[0],'sf':[0],'desert':[0]}}
    (out/'program.json').write_text(json.dumps(program))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--library-root',type=Path,default=ROOT/'local-only/native-audio/targets')
    parser.add_argument('--installer-archive',type=Path,default=ROOT/'local-only/native-installer/host/libzgtasa_installer.a')
    parser.add_argument('--sdk-check',action='store_true')
    args=parser.parse_args()
    out=ROOT/'local-only/research/local-radio-109'/('run-'+str(time.time_ns()));work=out/'source';work.mkdir(parents=True)
    installer=pinned_host_archive(args.installer_archive)
    audio=module('verified_radio_builder',ROOT/'native-audio/build.py')
    expected=audio.source_hashes();stamp=hashlib.sha256(json.dumps(expected,sort_keys=True,separators=(',',':')).encode()).hexdigest()
    host='macos-'+platform.machine()
    def checked_audio(name):
        folder=args.library_root/name;record=json.loads((folder/'source-stamp.json').read_text());archive=folder/'libzgtasa_native_audio.a'
        assert record['sourceHashes']==expected and record['sourceStamp']==stamp and record['target']==audio.TARGETS[name][1] and not record['sanitizers']
        assert archive.is_file()and not archive.is_symlink()and hashlib.sha256(archive.read_bytes()).hexdigest()==record['librarySHA256']
        return archive
    library=checked_audio(host)
    files=[ROOT/'ios/App'/(n+'.swift')for n in NAMES+SDK_NAMES]
    files += [ROOT/'native-installer/swift/NativeISOExtraction.swift',ROOT/'native-installer/swift/NativeRawResourceSelection.swift',
              ROOT/'smoke_native_local_radio.swift',Path(__file__),ROOT/'native-audio/tests/fixtures.py']
    before={str(p.relative_to(ROOT)):p.read_bytes()for p in files}
    for name in NAMES+SDK_NAMES:(work/(name+'.swift')).write_bytes(before['ios/App/'+name+'.swift'])
    wrappers=[]
    for name in ['NativeISOExtraction','NativeRawResourceSelection']:
        file=work/(name+'.swift');file.write_bytes(before['native-installer/swift/'+name+'.swift']);wrappers.append(str(file))
    source=before['smoke_native_local_radio.swift'].decode()
    playback=before['ios/App/NativeRadioPlayback.swift'].decode();vehicle=before['ios/App/NativeVehicleRadio.swift'].decode()
    source=source.replace('// ACTUAL_ADVANCE',function(playback,'    private func advance('))
    source=source.replace('// ACTUAL_FINISH',function(playback,'    private func finish('))
    source=source.replace('// ACTUAL_TUNE',function(vehicle,'    private func tune('))
    source=source.replace('// ACTUAL_ENTER',function(vehicle,'    func enter('))
    source=source.replace('// ACTUAL_FALLBACK',function(vehicle,'    private func tuneFallback('))
    provider=before['ios/App/NativeLocalRadioProvider.swift'].decode()
    source=source.replace('// ACTUAL_RESERVE',function(provider,'    private func reserveRequest('))
    source=source.replace('// ACTUAL_TRACK',function(provider,'    private func track('))
    source=source.replace('// ACTUAL_UNTRACK',function(provider,'    private func untrack('))
    mainfile=work/'main.swift';mainfile.write_text(source)
    fixture=out/'authored';fixture.mkdir();fixtures(fixture)
    base=['xcrun','swiftc','-swift-version','5','-parse-as-library','-whole-module-optimization','-Onone',
          '-I',str(ROOT/'native-audio/include'),'-I',str(ROOT/'native-installer/include'),'-module-cache-path',str(out/'modules')]
    def run(command,label,timeout=1200):
        with (out/(label+'.log')).open('w')as log:
            result=subprocess.run(list(map(str,command)),stdout=log,stderr=subprocess.STDOUT,timeout=timeout)
        if result.returncode:print((out/(label+'.log')).read_text()[-10000:]);result.check_returncode()
    native=[str(work/(n+'.swift'))for n in NAMES]+wrappers
    run(base+native+[str(mainfile),str(library),str(installer),'-lz','-lm','-o',str(out/'verify')],'compile')
    run([out/'verify',fixture,out/'fixture'],'runtime',180)
    report=json.loads((out/'fixture/report.json').read_text())
    sdk=[]
    if args.sdk_check:
        bridge=bridge_module(installer.parent.parent)
        for sdkname,target,audioname,installername in [
            ('iphoneos','arm64-apple-ios16.0','ios-arm64','device'),
            ('iphonesimulator','arm64-apple-ios16.0-simulator','ios-simulator-arm64','simulator'),
            ('iphonesimulator','x86_64-apple-ios16.0-simulator','ios-simulator-x86_64','simulator')]:
            assert bridge.valid_archive(installername,bridge.c_hashes()),'Unverified installer target'
            audioarchive=checked_audio(audioname);installarchive=installer.parent.parent/installername/'libzgtasa_installer.a'
            sdkpath=subprocess.check_output(['xcrun','--sdk',sdkname,'--show-sdk-path'],text=True).strip()
            command=['xcrun','--sdk',sdkname,'swiftc','-swift-version','5','-parse-as-library','-emit-library','-whole-module-optimization','-Onone',
                     '-target',target,'-sdk',sdkpath,'-I',str(ROOT/'native-audio/include'),'-I',str(ROOT/'native-installer/include'),
                     '-module-cache-path',str(out/'sdk-modules'),*native,*[str(work/(n+'.swift'))for n in SDK_NAMES],
                     str(audioarchive),str(installarchive),'-lz','-lm','-o',str(out/(audioname+'.dylib'))]
            run(command,audioname);sdk.append({'target':target,'compileAndLink':'PASS','executed':False})
    assert all((ROOT/path).read_bytes()==data for path,data in before.items()),'Source changed during immutable test'
    assert audio.source_hashes()==expected,'Codec source changed during immutable test'
    report.update(sourceUnchanged=True,sourceHashes={p:hashlib.sha256(v).hexdigest()for p,v in before.items()},
                  codecSourceStamp=stamp,codecArchiveSHA256=hashlib.sha256(library.read_bytes()).hexdigest(),
                  installerArchiveSHA256=hashlib.sha256(installer.read_bytes()).hexdigest(),sdk=sdk,
                  limits=['Actual raw Store/lease/catalogue/C decoder and AVAudioPCMBuffer; independently authored mathematical compressed audio',
                          'Completion/tune ownership uses actual extracted methods with explicit audio-sink/lifecycle spies; no audio device',
                          'No original files, service, engine.start, Simulator, phone, retail runtime or performance claim'])
    (out/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
    print(json.dumps(report,indent=2,sort_keys=True))


if __name__=='__main__':main()
