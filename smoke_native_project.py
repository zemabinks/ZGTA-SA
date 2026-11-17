#!/usr/bin/env python3
"""Source-only project selection/generation checks in disposable workspaces.

Runs the actual wrapper selection block on Linux/macOS. When XcodeGen is
available, generates both specs with real App sources and synthetic owner data.
Never regenerates the checkout project, compiles native code or reads game data.
"""
from pathlib import Path
import hashlib,json,os,re,shutil,subprocess,tempfile

ROOT=Path(__file__).resolve().parent
SOURCE_SUFFIXES={'.swift','.m','.mm','.c','.cc','.cpp','.metal','.s','.S'}

def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def app_hashes(folder):return {str(p.relative_to(folder)):digest(p) for p in sorted(folder.rglob('*')) if p.is_file()}
def selection(block,folder):
    env=os.environ.copy();env['project_dir']=str(folder)
    result=subprocess.run(['/bin/sh','-c',block+'\nprintf "%s\\n" "$project_spec"'],env=env,text=True,capture_output=True,check=True)
    return result.stdout.strip()
def phase_names(project,phase):
    section=re.search(r'/\* Begin PBX'+phase+r'BuildPhase section \*/(.*?)/\* End PBX'+phase+r'BuildPhase section \*/',project,re.S)
    assert section,('Missing build phase',phase)
    return re.findall(r'/\* ([^\n]*?) in '+phase+r' \*/',section.group(1))

def main():
    output=ROOT/'local-only/native-physics/tests/project-generation';output.mkdir(parents=True,exist_ok=True)
    wrapper=(ROOT/'build_native.sh').read_text()
    begin='# OWNER_MENU_SPEC_BEGIN';end='# OWNER_MENU_SPEC_END'
    assert wrapper.count(begin)==1 and wrapper.count(end)==1,'Wrapper selection boundary missing'
    block=wrapper.split(begin,1)[1].split(end,1)[0]
    assert 'xcodegen generate --spec "$project_spec"' in wrapper,'Build must use the selected spec'
    base=(ROOT/'ios/project.yml').read_text();owner=(ROOT/'ios/project-owner-menu.yml').read_text()
    assert 'OwnerMenu' not in base,'Base spec must contain no owner reference'
    assert re.search(r'^include:\s*\n\s+- project\.yml\s*\n',owner),'Owner spec must include the same-directory base'
    assert owner.count('../local-only/menu-bundle/OwnerMenu')==1 and 'optional:' not in owner,'Owner source must be required'
    assert 'type: folder' in owner and 'buildPhase: resources' in owner
    original_app=app_hashes(ROOT/'ios/App')
    assert original_app,'Actual App sources missing'
    bridge_root=ROOT/'native-installer/swift'
    original_bridge=app_hashes(bridge_root)
    assert original_bridge,'Native installer Swift bridge missing'
    source_names=sorted([Path(name).name for name in original_app if Path(name).suffix in SOURCE_SUFFIXES]+[Path(name).name for name in original_bridge if Path(name).suffix in SOURCE_SUFFIXES])
    assert source_names and len(set(source_names))==len(source_names),'Source names must be unambiguous for this generator check'
    protected=[ROOT/'build_native.sh',ROOT/'ios/project.yml',ROOT/'ios/project-owner-menu.yml']
    before={str(p.relative_to(ROOT)):digest(p) for p in protected}
    live_project=ROOT/'ios/ZGTASA.xcodeproj/project.pbxproj'
    live_before=live_project.read_bytes() if live_project.exists() else None
    generator=shutil.which('xcodegen');cases=[];owner_bytes=None
    with tempfile.TemporaryDirectory(prefix='selection-',dir=output) as temporary:
        parent=Path(temporary)
        for name,mode in [('missing','missing'),('folder-without-manifest','folder'),('owner','manifest'),('manifest-directory','directory')]:
            work=parent/name;ios=work/'ios';ios.mkdir(parents=True)
            shutil.copyfile(ROOT/'ios/project.yml',ios/'project.yml')
            shutil.copyfile(ROOT/'ios/project-owner-menu.yml',ios/'project-owner-menu.yml')
            folder=work/'local-only/menu-bundle/OwnerMenu'
            if mode!='missing':folder.mkdir(parents=True)
            if mode=='manifest':
                (folder/'manifest.json').write_text('{"synthetic":true}\n')
                (folder/'synthetic-owner-marker.txt').write_text('No game resources are used.\n')
            if mode=='directory':(folder/'manifest.json').mkdir()
            expected='project-owner-menu.yml' if mode=='manifest' else 'project.yml'
            chosen=selection(block,work);assert chosen==expected,(name,chosen,expected)
            row={'case':name,'selected':chosen,'selectionPass':True,'generation':'unavailable'}
            if generator:
                shutil.copytree(ROOT/'ios/App',ios/'App')
                shutil.copytree(bridge_root,work/'native-installer/swift')
                result=subprocess.run([generator,'generate','--spec',chosen,'--cache-path',str(work/'generator-cache')],cwd=ios,text=True,capture_output=True)
                assert result.returncode==0,(name,result.stdout,result.stderr)
                project=(ios/'ZGTASA.xcodeproj/project.pbxproj').read_text()
                assert sorted(phase_names(project,'Sources'))==source_names,(name,'App compilation membership changed')
                resources=phase_names(project,'Resources')
                assert resources.count('Assets.xcassets')==1,(name,'Base resources lost')
                if mode=='manifest':
                    assert resources.count('OwnerMenu')==1,'Exactly one owner resource phase entry required'
                    assert 'path = "../local-only/menu-bundle/OwnerMenu";' in project,'Owner folder path must stay local-only and relative to ios'
                    owner_bytes=(ios/'ZGTASA.xcodeproj/project.pbxproj').read_bytes()
                else:assert 'OwnerMenu' not in project,(name,'Ghost owner resource reference')
                assert app_hashes(ios/'App')==original_app,(name,'Generation changed App bytes or copied owner assets into App')
                if mode=='missing':
                    required=subprocess.run([generator,'generate','--spec','project-owner-menu.yml','--cache-path',str(work/'owner-validation-cache')],cwd=ios,text=True,capture_output=True)
                    assert required.returncode!=0,'Owner spec unexpectedly allowed an absent required folder'
                    row['missingOwnerValidation']='rejected'
                row.update(generation='pass',compiledSourceFiles=len(source_names),resourcePhase=resources)
            cases.append(row)
    assert app_hashes(ROOT/'ios/App')==original_app,'Checkout App source bytes changed'
    assert app_hashes(bridge_root)==original_bridge,'Installer Swift bridge changed during generation'
    assert {str(p.relative_to(ROOT)):digest(p) for p in protected}==before,'Spec/wrapper bytes changed during the test'
    assert (live_project.read_bytes() if live_project.exists() else None)==live_before,'Checkout Xcode project was regenerated'
    report={'pass':True,'selectionCases':cases,'xcodegen':generator,'sourceFiles':len(source_names),'appFileHashes':original_app,'installerSwiftHashes':original_bridge,
            'checkoutProjectUnchanged':True,'ownerGenerationMatchesExistingProject':None if owner_bytes is None or live_before is None else owner_bytes==live_before,
            'scope':'Disposable project generation only; no build, original assets or live project mutation'}
    (output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print('PASS native project selection: four actual-wrapper cases; checkout App/spec/project bytes unchanged')
    if generator:print(f'PASS real XcodeGen matrix: four generated projects, {len(source_names)} unchanged App compile entries, no ghost resources; required owner absence rejected')
    else:print('SKIP real XcodeGen generation: executable unavailable; portable selection and spec-safety checks passed')
if __name__=='__main__':main()
