#!/usr/bin/env python3
"""Standard synthesized WAV checks; optional real owner/FFmpeg comparison.

No sound is played. All original/decoded recording bytes remain in local-only.
"""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import argparse,hashlib,json,struct,subprocess,tempfile,wave
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'local-only/research/audio-settings'
COEFFICIENTS=[(256,0),(512,-256),(0,0),(192,64),(240,0),(460,-208),(392,-232)]
def chunk(name,data):return name+struct.pack('<I',len(data))+data+(b'\0' if len(data)%2 else b'')
def adpcm(channels,block,align,predictor=0,fact=None):
 samples=2+(align-7*channels)*2//channels
 fmt=struct.pack('<HHIIHHHHH',2,channels,22050,22050*align//samples,align,4,32,samples,7)+b''.join(struct.pack('<hh',*c)for c in COEFFICIENTS)
 body=b'WAVE'+chunk(b'fmt ',fmt)+(chunk(b'fact',struct.pack('<I',fact))if fact is not None else b'')+chunk(b'data',block)
 return b'RIFF'+struct.pack('<I',len(body))+body
SWIFT=r'''
let rows=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [[String:Any]]
var checks=0,ownerSamples=0
for row in rows {
 let data=try Data(contentsOf:URL(fileURLWithPath:row["input"] as! String)),decoded=NativeMenuSoundData.playableWave(data)
 if row["reject"] as? Bool==true {precondition(decoded==nil,"Invalid WAV accepted: \(row["name"]!)");checks+=1;continue}
 guard let decoded else{fatalError("Valid recording rejected: \(row["name"]!)")}
 let expected=try Data(contentsOf:URL(fileURLWithPath:row["expected"] as! String))
 precondition(Data(decoded.dropFirst(44))==expected,"Decoded PCM differs: \(row["name"]!)")
 checks += expected.count/2
 if row["owner"] as? Bool==true {ownerSamples += expected.count/2}
 let out=URL(fileURLWithPath:CommandLine.arguments[2]).appendingPathComponent((row["name"] as! String)+".pcm.wav")
 try decoded.write(to:out)
}
print("PASS menu recording decode: \(checks) exact PCM/rejection checks; \(ownerSamples) real owner channel samples, no playback")
'''
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--owner-root',type=Path);p.add_argument('--ffmpeg',type=Path);args=p.parse_args()
 OUT.mkdir(parents=True,exist_ok=True);rows=[];real=[]
 with tempfile.TemporaryDirectory(prefix='menu-',dir=OUT)as t:
  work=Path(t)
  def add(name,data,expected=None,owner=False):
   file=work/(name+'.wav');file.write_bytes(data);row={'name':name,'input':str(file),'owner':owner}
   if expected is None:row['reject']=True
   else:
    raw=expected if isinstance(expected,bytes) else struct.pack('<'+'h'*len(expected),*expected)
    target=work/(name+'.expected');target.write_bytes(raw);row['expected']=str(target)
    if args.ffmpeg:
     decoded=subprocess.run([str(args.ffmpeg),'-hide_banner','-loglevel','error','-f','wav','-i',str(file),'-f','s16le','-acodec','pcm_s16le','-'],check=True,capture_output=True).stdout
     if name=='fact-trim':
      # FFmpeg's raw decoder emits the entire synthesized block. Native also
      # honors the RIFF fact frame count; compare the declared frames and
      # independently require that the reference block contains all4samples.
      assert len(decoded)==8 and decoded[:4]==raw,(name,'Fact/container boundary mismatch')
     else:assert decoded==raw,(name,'Independent FFmpeg synthetic sample mismatch')
   rows.append(row)
  mono=bytes([0])+struct.pack('<hhh',16,100,200)+bytes([0x12])
  add('mono',adpcm(1,mono,8),[200,100,116,148])
  stereo=bytes([0,0])+struct.pack('<hhhhhh',16,32,100,-100,200,-200)+bytes([0x12])
  add('stereo',adpcm(2,stereo,15),[200,-200,100,-100,116,-36])
  alternate=bytes([1])+struct.pack('<hhh',16,100,200)+bytes([0x1e])
  add('predictor',adpcm(1,alternate,8),[200,100,16,-100])
  add('fact-trim',adpcm(1,mono,8,fact=2),[200,100])
  invalid=bytearray(adpcm(1,mono,8));invalid[-8]=255;add('invalid-predictor',invalid)
  add('truncated',adpcm(1,mono,8)[:-1]);add('not-wave',b'not a WAV file')
  explosive=bytes([0])+struct.pack('<hhh',32767,32767,32767)+bytes([0x77])*505
  add('overflow-delta',adpcm(1,explosive,512))
  if args.owner_root:
   assert args.ffmpeg,'Real owner proof requires an independent --ffmpeg executable'
   manifest=json.loads((args.owner_root/'selected-pak-resources.json').read_text())
   for r in manifest:
    if not r['entry']['path'].endswith('.m.ubulk') or '/FRONTEND_MENU/' not in r['entry']['path']:continue
    file=args.owner_root/r['decoded_path'];data=file.read_bytes()
    expected=subprocess.run([str(args.ffmpeg),'-hide_banner','-loglevel','error','-f','wav','-i',str(file),'-f','s16le','-acodec','pcm_s16le','-'],check=True,capture_output=True).stdout
    name=Path(r['entry']['path']).name.split('.')[0];add(name,data,expected,True)
    real.append({'name':name,'inputSHA256':hashlib.sha256(data).hexdigest(),'pcmSHA256':hashlib.sha256(expected).hexdigest(),'samples':len(expected)//2})
  else:print('SKIP optional owner recordings; synthesized mono/stereo/coefficient/fact/error checks still run')
  (work/'rows.json').write_text(json.dumps(rows));(work/'main.swift').write_text((ROOT/'ios/App/NativeMenuSoundData.swift').read_text()+SWIFT)
  subprocess.run(['swiftc','-O','-module-cache-path','/private/tmp/zgtasa-core-swift-modules',str(work/'main.swift'),'-o',str(work/'verify')],check=True)
  subprocess.run([str(work/'verify'),str(work/'rows.json'),str(work)],check=True)
  (OUT/'menu-decode-report.json').write_text(json.dumps({'pass':True,'syntheticCases':8,'ownerRecordings':real,'reference':'Independent FFmpeg when supplied; standardized synthesized vectors otherwise','scope':'Decode into memory/files only; no hardware audio output','sourceSHA256':hashlib.sha256((ROOT/'ios/App/NativeMenuSoundData.swift').read_bytes()).hexdigest()},indent=2)+'\n')
if __name__=='__main__':main()
