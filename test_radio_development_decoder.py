#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Authored native-radio WAV exporter and development-helper regression.

Uses existing mathematical Vorbis fixtures. No original audio, Python audio
packages, listening devices, server listeners or SDK builds are needed.
"""
from pathlib import Path
import argparse, hashlib, importlib.util, json, math, os, shutil, struct, subprocess, sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / 'native-audio/tests'))
import fixtures
spec = importlib.util.spec_from_file_location('radio_build', ROOT / 'native-audio/build.py')
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)
KEY = bytes([234,58,196,161,154,168,20,243,72,176,215,35,157,232,255,241])
HEADER = 8068

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--decoder', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = build.private_output(args.output)
    if output.exists():
        parser.error('Choose a new output directory')
    decoder = build.private_output(args.decoder)
    build.check_regular(decoder)
    provenance = json.loads((decoder.parent / 'build-report.json').read_text())
    if build.sha(decoder) != provenance['executableSHA256'] or build.sha(ROOT / 'native-audio/tools/radio_wav.c') != provenance['toolSHA256']:
        raise ValueError('Exporter does not match its build report/current source')
    output.mkdir(parents=True)
    report = dict(passed=False, checks=[], output=str(output), scope='Authored mathematical fixtures; no original recordings, network listener, speaker or iOS runtime')
    def check(value, label):
        report['checks'].append(dict(label=label, passed=bool(value)))
        if not value:
            raise AssertionError(label)
    def run(file, offset, size, destination, accepted=True):
        result = subprocess.run([str(decoder), str(file), str(offset), str(size), str(destination)], capture_output=True, timeout=30)
        check((result.returncode == 0) == accepted, 'CLI-status-' + destination.name)
        return result
    def pack(name, payload, offset=29):
        start = offset + HEADER
        file = output / (name + '.bin')
        file.write_bytes(bytes(start) + bytes(b ^ KEY[(start+i)&15] for i,b in enumerate(payload)) + b'outside-record-never-read')
        return file, offset, HEADER + len(payload)
    try:
        valid = {}
        for name in ('stereo', 'mono'):
            item = pack(name, fixtures.payload(name), 29 if name == 'stereo' else 43)
            destination = output / (name + '.wav')
            result = run(*item, destination)
            metadata = json.loads(result.stdout)
            check(metadata['frames'] == 16000 and metadata['rate'] == 32000 and metadata['channels'] == 2 and metadata['sourceStamp'] == provenance['sourceStamp'], 'decoded-format-' + name)
            data = destination.read_bytes()
            check(len(data) == 56 + 16000 * 8 and data[:4] == b'RIFF' and data[8:16] == b'WAVEfmt ' and data[48:52] == b'data', 'WAV-container-' + name)
            check(struct.unpack_from('<I', data, 4)[0] == len(data)-8 and struct.unpack_from('<HHIIHH', data, 20) == (3,2,32000,256000,8,32) and struct.unpack_from('<I', data, 44)[0] == 16000, 'WAV-header-' + name)
            samples = struct.unpack('<' + 'f' * (16000 * 2), data[56:])
            check(all(map(math.isfinite, samples)), 'finite-PCM-' + name)
            for index, expected in fixtures.FIXTURES[name]['reference'].items():
                wanted = expected if len(expected) == 2 else expected * 2
                check(max(abs(samples[int(index)*2+j] - wanted[j]) for j in range(2)) < 5e-6, 'independent-fixture-PCM-' + name + '-' + str(index))
            check(destination.stat().st_mode & 0o777 == 0o600, 'private-output-' + name)
            before = hashlib.sha256(data).hexdigest()
            run(*item, destination, accepted=False)
            check(hashlib.sha256(destination.read_bytes()).hexdigest() == before, 'preserve-existing-output-' + name)
            valid[name] = item
        linked_target = output / 'unrelated.txt'; linked_target.write_text('keep')
        linked = output / 'linked.wav'; linked.symlink_to(linked_target)
        run(*valid['stereo'], linked, accepted=False)
        check(linked_target.read_text() == 'keep' and linked.is_symlink(), 'refuse-linked-output')
        payload = bytearray(fixtures.payload('stereo')); payload[100] ^= 1
        for name, data in [('bad-crc', bytes(payload)), ('truncated', fixtures.payload('stereo')[:-1])]:
            destination = output / (name + '.wav')
            run(*pack(name, data), destination, accepted=False)
            check(not destination.exists(), 'no-invalid-output-' + name)
        run(valid['stereo'][0], '-1', valid['stereo'][2], output / 'negative.wav', accepted=False)
        check(not (output / 'negative.wav').exists(), 'reject-negative-range')
        owner = output / 'authored-owner'
        (owner / 'audio/config').mkdir(parents=True)
        (owner / 'audio/streams').mkdir()
        shutil.copyfile(valid['stereo'][0], owner / 'audio/streams/CH')
        (owner / 'audio/config/StrmPaks.dat').write_bytes(b'CH' + bytes(14))
        (owner / 'audio/config/TrakLkup.dat').write_bytes(struct.pack('<B3xII', 0, valid['stereo'][1], valid['stereo'][2]))
        javascript = r'''
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),{Writable}=require('node:stream');
const [root,owner,output,decoder]=process.argv.slice(1),{create,register}=require(path.join(root,'native_radio_server'));
(async()=>{const config=path.join(output,'adapter-owner.json');register(owner,{configuration:config});
const cache=path.join(output,'adapter-cache'),radio=create({configuration:config,cache,decoder,python:'/no-python-dependency'});
const track=radio.tracks()[0];const [a,b]=await Promise.all([radio.converted(track),radio.converted(track)]);assert.equal(a,b);
const chunks=[];let status,headers;const res=new Writable({write(b,e,done){chunks.push(b);done();}});res.writeHead=(s,h)=>{status=s;headers=h;};
const finish=new Promise(resolve=>res.on('finish',resolve));await radio.handle({method:'GET',headers:{range:'bytes=36-55'}},res,'/game/radio/native/track/0.wav');await finish;
assert.equal(status,206);assert.equal(Buffer.concat(chunks).length,20);assert.equal(headers['content-range'],'bytes 36-55/128056');
assert(!fs.readdirSync(cache).some(n=>/\.(ogg|partial)$/.test(n)));
process.env.ZGTA_RADIO_DECODER=decoder;const environment=create({configuration:config,cache:path.join(output,'environment-cache'),python:'/no-python-dependency'});
assert(fs.readFileSync(await environment.converted(track)).equals(fs.readFileSync(a)));
console.log(JSON.stringify({wav:a,deduplicated:true,range:true,environment:true}));
})().catch(e=>{console.error(e);process.exitCode=1;});
'''
        result = subprocess.run(['node', '-e', javascript, str(ROOT), str(owner), str(output), str(decoder)], capture_output=True, timeout=30)
        (output / 'adapter.log').write_bytes(result.stdout + result.stderr)
        check(result.returncode == 0, 'actual-development-adapter-native-conversion')
        adapter = json.loads(result.stdout)
        check(Path(adapter['wav']).read_bytes() == (output / 'stereo.wav').read_bytes(), 'adapter-WAV-matches-direct-export')
        check(adapter['environment'], 'native-decoder-environment-selection')
        report['decoderProvenance'] = provenance
        report['passed'] = True
    except Exception as error:
        report['error'] = str(error)
    (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(dict(passed=report['passed'], checks=len(report['checks']), output=str(output), error=report.get('error'))))
    return 0 if report['passed'] else 1

if __name__ == '__main__':
    sys.exit(main())
