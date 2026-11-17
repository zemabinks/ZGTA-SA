#!/usr/bin/env python3
"""Build the bounded Apple ISO/InstallShield static bridge in this clone's ignored cache."""
from pathlib import Path
import argparse,hashlib,json,platform,subprocess,shutil
ROOT=Path(__file__).resolve().parent
BASE=ROOT/'native-installer'
OUT=ROOT/'local-only/native-installer'
VENDOR=BASE/'vendor/unshield'
CONFIG='''#define HAVE_STDINT_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_STDBOOL_H 1
#define HAVE_UNISTD_H 1
#define HAVE_FNMATCH 1
#define USE_OUR_OWN_MD5 1
#define PACKAGE_STRING "unshield 1.6.2 (pinned3914dff)"
#define VERSION "1.6.2"
#define SIZE_FORMAT "zi"
'''
VARIANTS={'host':('macosx',platform.machine()+'-apple-macos13.0'),'device':('iphoneos','arm64-apple-ios16.0'),'simulator-arm64':('iphonesimulator','arm64-apple-ios16.0-simulator'),'simulator-x86_64':('iphonesimulator','x86_64-apple-ios16.0-simulator')}
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def c_hashes():
 paths=sorted((BASE/'src').rglob('*'))+sorted(VENDOR.rglob('*'))+[BASE/'include/zgtasa_installer.h',BASE/'patches/unsigned-le32.json']
 return {str(p.relative_to(ROOT)):digest(p) for p in paths if p.is_file()}
def safe_output(path):
 current=ROOT
 for component in path.relative_to(ROOT).parts:
  current=current/component
  if current.is_symlink():raise ValueError('Refusing linked installer output: '+str(current))
 path.resolve().relative_to((ROOT/'local-only').resolve())
def valid_archive(name,hashes,sanitized=False):
 folder=OUT/(name+'-sanitized' if sanitized else name)
 try:
  stamp=json.loads((folder/'source-stamp.json').read_text());record=stamp.get('cSourceHashes',stamp.get('sources',{}))
  assert all(record.get(p)==sha for p,sha in hashes.items())
  if 'cSourceHashes' not in stamp:
   assert stamp['sources'].get('build_installer_bridge.py')=='8f589736b9bf9c86b922b79e679474962324afb84f963a453349289d360fc14e'
  if name!='simulator':
   assert stamp['configSHA256']==hashlib.sha256(CONFIG.encode()).hexdigest()
   assert stamp['target']==VARIANTS[name][1]
  else:assert set(stamp['architectures'])=={'arm64','x86_64'}
  assert stamp.get('sanitizers',[])==(['address','undefined'] if sanitized else [])
  assert digest(folder/'libzgtasa_installer.a')==stamp['librarySHA256']
  return True
 except (OSError,ValueError,KeyError,AssertionError):return False

def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--platform',choices=['all','host','device','simulator'],default='all');parser.add_argument('--sanitize',action='store_true');parser.add_argument('--link-probes',action='store_true');parser.add_argument('--check',action='store_true',help='Read-only archive/source check; never extract resources or write build state');parser.add_argument('--force',action='store_true')
 args=parser.parse_args()
 if args.sanitize and args.platform!='host':parser.error('--sanitize requires --platform host')
 provenance=json.loads((VENDOR/'PROVENANCE.json').read_text())
 for name,expected in provenance['files'].items():assert digest(VENDOR/name)==expected,'Pinned vendor changed: '+name
 hashes=c_hashes();requested=['host','device','simulator'] if args.platform=='all' else [args.platform]
 valid={name:valid_archive(name,hashes,args.sanitize) for name in requested}
 if args.check:
  if not all(valid.values()):print('Installer archives missing or stale:',','.join(n for n in requested if not valid[n]));return 1
  print('PASS installer source/archive check (read-only; raw resources are untouched)');return 0
 safe_output(OUT);OUT.mkdir(parents=True,exist_ok=True)
 for path in OUT.rglob('*'):
  if path.is_symlink():raise ValueError('Refusing installer rebuild through linked cache/output: '+str(path))
 names=[]
 for name in requested:
  if valid[name] and not args.force:print('REUSED',name,OUT/name/'libzgtasa_installer.a')
  else:names.extend(['simulator-arm64','simulator-x86_64'] if name=='simulator' else [name])
 for name in names:safe_output(OUT/(name+'-sanitized' if args.sanitize else name))
 if names:
  staged=OUT/'staged-unshield';safe_output(staged);staged.mkdir(parents=True,exist_ok=True)
  for name in provenance['files']:
   destination=staged/name;safe_output(destination);destination.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(VENDOR/name,destination)
  patch=json.loads((BASE/'patches/unsigned-le32.json').read_text());header=staged/patch['path'];text=header.read_text();assert text.count(patch['before'])==1
  header.write_text(text.replace(patch['before'],patch['after']))
  stagedHashes={name:digest(staged/name) for name in provenance['files']}
  sources=sorted((staged/'lib').glob('*.c'))+[BASE/'src/zgtasa_installer.c']
  cfg=OUT/'config';safe_output(cfg);(cfg/'lib').mkdir(parents=True,exist_ok=True);(cfg/'lib/unshield_config.h').write_text(CONFIG);(cfg/'libunshield_export.h').write_text('#define UNSHIELD_API\n')
  for name in names:
   sdk,target=VARIANTS[name];folder=OUT/(name+'-sanitized' if args.sanitize else name);folder.mkdir(parents=True,exist_ok=True);(folder/'source-stamp.json').unlink(missing_ok=True)
   sdkpath=subprocess.check_output(['xcrun','--sdk',sdk,'--show-sdk-path'],text=True).strip();objects=[];logs=[]
   for source in sources:
    output=folder/(source.stem+'.o');safe_output(output);command=['xcrun','--sdk',sdk,'clang','-target',target,'-isysroot',sdkpath,'-std=c11','-O2','-fno-common','-I'+str(BASE/'include'),'-I'+str(staged/'lib'),'-I'+str(BASE/'src'),'-I'+str(cfg),'-DLIBUNSHIELD_STATIC_DEFINE','-c',str(source),'-o',str(output)]
    command+=['-Wall','-Wextra'] if source.name=='zgtasa_installer.c' else ['-w']
    if args.sanitize:command+=['-fsanitize=address,undefined','-fno-sanitize-recover=all','-fno-omit-frame-pointer','-g']
    run=subprocess.run(command,capture_output=True,text=True);logs.append(run.stdout+run.stderr)
    if run.returncode:(folder/'compile.log').write_text(''.join(logs));print(''.join(logs));run.check_returncode()
    objects.append(output)
   (folder/'compile.log').write_text(''.join(logs));library=folder/'libzgtasa_installer.a';safe_output(library)
   subprocess.run(['xcrun','--sdk',sdk,'libtool','-static','-o',str(library),*map(str,objects)],check=True,capture_output=True,text=True)
   stamp={'platform':name,'target':target,'sdk':sdkpath,'cSourceHashes':hashes,'configSHA256':hashlib.sha256(CONFIG.encode()).hexdigest(),'librarySHA256':digest(library),'linkDependencies':['libz.tbd','Apple CommonCrypto (system)'],'vendorCommit':provenance['commit'],'stagedVendorHashes':stagedHashes,'sanitizers':['address','undefined'] if args.sanitize else []}
   (folder/'source-stamp.json').write_text(json.dumps(stamp,indent=2)+'\n');print('BUILT',name,library)
  if 'simulator-arm64' in names:
   folder=OUT/'simulator';safe_output(folder);folder.mkdir(exist_ok=True);library=folder/'libzgtasa_installer.a';safe_output(library)
   subprocess.run(['xcrun','lipo','-create',str(OUT/'simulator-arm64/libzgtasa_installer.a'),str(OUT/'simulator-x86_64/libzgtasa_installer.a'),'-output',str(library)],check=True)
   (folder/'source-stamp.json').write_text(json.dumps({'platform':'simulator-universal','architectures':['arm64','x86_64'],'cSourceHashes':hashes,'librarySHA256':digest(library),'vendorCommit':provenance['commit']},indent=2)+'\n');print('BUILT simulator universal',library)
 if args.link_probes:
  if args.sanitize:parser.error('Use ordinary platform archives for Swift link probes')
  reports=[];variants=[]
  for name in requested:variants.extend(['simulator-arm64','simulator-x86_64'] if name=='simulator' else [name])
  for name in variants:
   sdk,target=VARIANTS[name];sdkpath=subprocess.check_output(['xcrun','--sdk',sdk,'--show-sdk-path'],text=True).strip();folder=OUT/name;safe_output(folder);folder.mkdir(exist_ok=True)
   archive=OUT/('simulator' if name.startswith('simulator-') else name)/'libzgtasa_installer.a'
   executable=folder/'swift-link-probe';safe_output(executable)
   swift=[BASE/'swift/NativeRawResourceSelection.swift',BASE/'swift/NativeISOExtraction.swift',BASE/'tests/link.swift']
   command=['xcrun','--sdk',sdk,'swiftc','-parse-as-library','-sdk',sdkpath,'-target',target,'-I',str(BASE/'include'),'-module-cache-path',str(OUT/'swift-modules'),*map(str,swift),str(archive),'-lz','-o',str(executable)]
   run=subprocess.run(command,capture_output=True,text=True);(folder/'swift-link.log').write_text(run.stdout+run.stderr)
   if run.returncode:print(run.stdout+run.stderr);run.check_returncode()
   reports.append({'platform':name,'target':target,'status':'PASS','executableSHA256':digest(executable)});print('LINKED Swift+C',name)
  (OUT/'swift-link-probes.json').write_text(json.dumps({'scope':'Apple SDK Swift/C static linking only; never installed/run on iOS','cSourceHashes':hashes,'results':reports},indent=2)+'\n')
 return 0
if __name__=='__main__':raise SystemExit(main())
