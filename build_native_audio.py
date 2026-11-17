#!/usr/bin/env python3
"""Verify/build native radio archives used by the iOS App; no game data."""
import argparse,hashlib,importlib.util,json,os,pathlib,shutil,subprocess,sys,tempfile
sys.dont_write_bytecode=True
ROOT=pathlib.Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('zgta_audio_build',ROOT/'native-audio/build.py')
audio=importlib.util.module_from_spec(spec);spec.loader.exec_module(audio)
MEMBERS={'device':['ios-arm64'],'simulator':['ios-simulator-arm64','ios-simulator-x86_64']}
ARCHES={'device':{'arm64'},'simulator':{'arm64','x86_64'}}
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def regular(p):
 if p.is_symlink()or not p.is_file():raise ValueError('Missing or linked audio artifact: '+str(p))
 for parent in p.parents:
  if parent.is_symlink():raise ValueError('Linked audio artifact parent: '+str(parent))
  if parent==ROOT:break
def target_metadata(cache,name,sources,stamp):
 folder=audio.private_output(cache/name);file=folder/'source-stamp.json';regular(file);value=json.loads(file.read_text())
 if value['sourceHashes']!=sources or value['sourceStamp']!=stamp or value['target']!=audio.TARGETS[name][1] or value['sanitizers'] is not False:raise ValueError('Stale or sanitizer-only native audio target: '+name)
 for artifact,key in [('libzgtasa_native_audio.a','librarySHA256'),('link-probe','linkProbeSHA256')]:
  p=folder/artifact;regular(p)
  if digest(p)!=value[key]:raise ValueError('Native audio target digest mismatch: '+name+'/'+artifact)
 return {'sourceStamp':stamp,'librarySHA256':value['librarySHA256'],'linkProbeSHA256':value['linkProbeSHA256'],'receiptSHA256':digest(file)}
def architectures(library):return set(subprocess.check_output(['xcrun','lipo','-archs',str(library)],text=True).split())
def verify(output,platform,sources,stamp):
 directory=audio.private_output(output/('ios-'+('device'if platform=='device'else'simulator')));library=directory/'libzgtasa_native_audio.a';receipt=directory/'build-report.json';regular(library);regular(receipt);value=json.loads(receipt.read_text())
 expected={name:target_metadata(output/'targets',name,sources,stamp)for name in MEMBERS[platform]}
 if value['schema']!=1 or value['platform']!=platform or value['sourceStamp']!=stamp or value['members']!=expected or value['wrapperSHA256']!=digest(pathlib.Path(__file__)) or value['librarySHA256']!=digest(library) or architectures(library)!=ARCHES[platform]:raise ValueError('Stale or invalid App native audio archive: '+platform)
 return value
def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--platform',action='append',choices=['device','simulator']);parser.add_argument('--check',action='store_true');args=parser.parse_args();platforms=list(dict.fromkeys(args.platform or ['device','simulator']))
 output=audio.private_output(ROOT/'local-only/native-audio');cache=audio.private_output(output/'targets');sources=audio.source_hashes();stamp=hashlib.sha256(json.dumps(sources,sort_keys=True,separators=(',',':')).encode()).hexdigest()
 if args.check:
  for platform in platforms:verify(output,platform,sources,stamp)
  print(json.dumps({'status':'VALID','platforms':platforms,'sourceStamp':stamp,'readOnly':True}));return
 output.mkdir(parents=True,exist_ok=True)
 missing=[]
 for name in dict.fromkeys(n for platform in platforms for n in MEMBERS[platform]):
  try:target_metadata(cache,name,sources,stamp)
  except (OSError,KeyError,ValueError):missing.append(name)
 if missing:
  command=[sys.executable,str(ROOT/'native-audio/build.py'),'--output',str(cache)]
  for name in missing:command+=['--platform',name]
  subprocess.run(command,check=True)
 for platform in platforms:
  try:verify(output,platform,sources,stamp);continue
  except (OSError,KeyError,ValueError):pass
  members={name:target_metadata(cache,name,sources,stamp)for name in MEMBERS[platform]}
  directory=audio.private_output(output/('ios-'+('device'if platform=='device'else'simulator')));directory.mkdir(exist_ok=True)
  with tempfile.TemporaryDirectory(prefix='.app-audio-',dir=output)as temporary:
   stage=pathlib.Path(temporary);library=stage/'libzgtasa_native_audio.a';inputs=[cache/name/'libzgtasa_native_audio.a'for name in MEMBERS[platform]]
   if len(inputs)==1:shutil.copyfile(inputs[0],library)
   else:subprocess.run(['xcrun','lipo','-create',*map(str,inputs),'-output',str(library)],check=True)
   if architectures(library)!=ARCHES[platform]or audio.source_hashes()!=sources:raise ValueError('Native audio architecture or source changed')
   report={'schema':1,'platform':platform,'sourceStamp':stamp,'members':members,'wrapperSHA256':digest(pathlib.Path(__file__)),'librarySHA256':digest(library),'architectures':sorted(ARCHES[platform]),'runtimeExecuted':False}
   receipt=stage/'build-report.json';receipt.write_text(json.dumps(report,indent=2)+'\n')
   for p in [directory/'libzgtasa_native_audio.a',directory/'build-report.json']:
    if p.is_symlink():raise ValueError('Refusing linked App audio output')
   os.replace(library,directory/library.name);os.replace(receipt,directory/receipt.name)
  verify(output,platform,sources,stamp)
 print(json.dumps({'status':'VALID','platforms':platforms,'sourceStamp':stamp,'runtimeExecuted':False}))
if __name__=='__main__':
 try:main()
 except (OSError,KeyError,ValueError,subprocess.SubprocessError)as error:print(str(error),file=sys.stderr);raise SystemExit(1)
