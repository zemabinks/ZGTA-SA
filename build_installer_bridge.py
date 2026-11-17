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
def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--platform',choices=['all','host','device','simulator'],default='all');parser.add_argument('--sanitize',action='store_true',help='Host-only ASan/UBSan archive in an independent cache');parser.add_argument('--link-probes',action='store_true',help='Cross-link actual Swift wrapper against each selected Apple SDK/archive');args=parser.parse_args()
 if args.sanitize and args.platform!='host':parser.error('--sanitize requires --platform host')
 provenance=json.loads((VENDOR/'PROVENANCE.json').read_text())
 for name,expected in provenance['files'].items():
  assert hashlib.sha256((VENDOR/name).read_bytes()).hexdigest()==expected,'Pinned vendor changed: '+name
 staged=OUT/'staged-unshield';staged.mkdir(parents=True,exist_ok=True)
 for name in provenance['files']:
  destination=staged/name;destination.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(VENDOR/name,destination)
 patch=json.loads((BASE/'patches/unsigned-le32.json').read_text());header=staged/patch['path'];text=header.read_text()
 assert text.count(patch['before'])==1,'Pinned unsigned reader patch changed'
 header.write_text(text.replace(patch['before'],patch['after']))
 stagedHashes={name:hashlib.sha256((staged/name).read_bytes()).hexdigest() for name in provenance['files']}
 sources=sorted((staged/'lib').glob('*.c'))+[BASE/'src/zgtasa_installer.c']
 tracked=sorted(p for p in BASE.rglob('*') if p.is_file())+[Path(__file__)]
 hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in tracked}
 cfg=OUT/'config';(cfg/'lib').mkdir(parents=True,exist_ok=True);(cfg/'lib/unshield_config.h').write_text(CONFIG);(cfg/'libunshield_export.h').write_text('#define UNSHIELD_API\n')
 names=list(VARIANTS) if args.platform=='all' else ['simulator-arm64','simulator-x86_64'] if args.platform=='simulator' else [args.platform]
 for name in names:
  sdk,target=VARIANTS[name];folder=OUT/(name+'-sanitized' if args.sanitize else name);folder.mkdir(parents=True,exist_ok=True)
  (folder/'source-stamp.json').unlink(missing_ok=True)
  sdkpath=subprocess.check_output(['xcrun','--sdk',sdk,'--show-sdk-path'],text=True).strip();objects=[];logs=[]
  for source in sources:
   output=folder/(source.stem+'.o');command=['xcrun','--sdk',sdk,'clang','-target',target,'-isysroot',sdkpath,'-std=c11','-O2','-fno-common','-I'+str(BASE/'include'),'-I'+str(staged/'lib'),'-I'+str(BASE/'src'),'-I'+str(cfg),'-DLIBUNSHIELD_STATIC_DEFINE','-c',str(source),'-o',str(output)]
   command+=['-Wall','-Wextra'] if source.name=='zgtasa_installer.c' else ['-w']
   if args.sanitize:command+=['-fsanitize=address,undefined','-fno-sanitize-recover=all','-fno-omit-frame-pointer','-g']
   run=subprocess.run(command,capture_output=True,text=True);logs.append(run.stdout+run.stderr)
   if run.returncode:(folder/'compile.log').write_text(''.join(logs));print(''.join(logs));run.check_returncode()
   objects.append(output)
  (folder/'compile.log').write_text(''.join(logs))
  library=folder/'libzgtasa_installer.a';subprocess.run(['xcrun','--sdk',sdk,'libtool','-static','-o',str(library),*map(str,objects)],check=True,capture_output=True,text=True)
  stamp={'platform':name,'target':target,'sdk':sdkpath,'sources':hashes,'configSHA256':hashlib.sha256(CONFIG.encode()).hexdigest(),'librarySHA256':hashlib.sha256(library.read_bytes()).hexdigest(),'linkDependencies':['libz.tbd','Apple CommonCrypto (system)'],'vendorCommit':provenance['commit'],'stagedVendorHashes':stagedHashes,'sanitizers':['address','undefined'] if args.sanitize else []}
  (folder/'source-stamp.json').write_text(json.dumps(stamp,indent=2)+'\n');print('BUILT',name,library)
 if 'simulator-arm64' in names:
  folder=OUT/'simulator';folder.mkdir(exist_ok=True)
  library=folder/'libzgtasa_installer.a';subprocess.run(['xcrun','lipo','-create',str(OUT/'simulator-arm64/libzgtasa_installer.a'),str(OUT/'simulator-x86_64/libzgtasa_installer.a'),'-output',str(library)],check=True)
  (folder/'source-stamp.json').write_text(json.dumps({'platform':'simulator-universal','architectures':['arm64','x86_64'],'sources':hashes,'librarySHA256':hashlib.sha256(library.read_bytes()).hexdigest(),'vendorCommit':provenance['commit']},indent=2)+'\n');print('BUILT simulator universal',library)
 if args.link_probes:
  if args.sanitize:parser.error('Use ordinary platform archives for Swift link probes')
  reports=[]
  for name in names:
   sdk,target=VARIANTS[name];sdkpath=subprocess.check_output(['xcrun','--sdk',sdk,'--show-sdk-path'],text=True).strip()
   folder=OUT/name;executable=folder/'swift-link-probe'
   swift=[BASE/'swift/NativeRawResourceSelection.swift',BASE/'swift/NativeISOExtraction.swift',BASE/'tests/link.swift']
   command=['xcrun','--sdk',sdk,'swiftc','-parse-as-library','-sdk',sdkpath,'-target',target,'-I',str(BASE/'include'),'-module-cache-path',str(OUT/'swift-modules'),*map(str,swift),str(folder/'libzgtasa_installer.a'),'-lz','-o',str(executable)]
   run=subprocess.run(command,capture_output=True,text=True);(folder/'swift-link.log').write_text(run.stdout+run.stderr)
   if run.returncode:print(run.stdout+run.stderr);run.check_returncode()
   reports.append({'platform':name,'target':target,'status':'PASS','executableSHA256':hashlib.sha256(executable.read_bytes()).hexdigest()});print('LINKED Swift+C',name)
  (OUT/'swift-link-probes.json').write_text(json.dumps({'scope':'Actual Apple SDK Swift/C static linking only; binaries never installed or run on iOS','sources':hashes,'results':reports},indent=2)+'\n')
if __name__=='__main__':main()
