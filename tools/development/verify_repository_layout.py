#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Check source layout, package references, documentation and audit coverage."""
from pathlib import Path
import argparse, ast, contextlib, importlib.util, io, re, tempfile, urllib.parse

ROOT=Path(__file__).resolve().parents[2]

def verify(root):
    failures=[];checks=0
    def check(condition,message):
        nonlocal checks
        checks+=1
        if not condition:failures.append(message)
    entries=[p for p in root.iterdir()if p.is_file()and p.name!='.git']
    check(len(entries)<=80,'Repository root has accumulated more than80 files')
    for p in entries:
        check(not p.name.startswith(('CORE_','smoke_','test_','check_')), 'Technical/test file at root: '+p.name)
        check(not p.name.startswith('prepare_')or p.name=='prepare_native_runtime.sh','Preparation implementation at root: '+p.name)
    for name in ['host.py','build_native.sh','README.md','docs/START-HERE.md','docs/GAME-FILES.md','docs/MULTIPLAYER.md',
                 'docs/TROUBLESHOOTING.md','docs/DEVELOPMENT.md','docs/PROJECT-STATUS.md',
                 'docs/development/CORE_GAMEPLAY_PARITY.md','docs/development/CORE_GAMEPLAY_JOURNAL.md',
                 'docs/development/CORE_RETAIL_REFERENCE.md','tests/core/smoke_core_136.py','tests/core/smoke_core_140.py','tests/core/smoke_core_142.py','tests/core/smoke_core_143.py','tests/core/smoke_core_144.py','tests/core/smoke_core_145.py','tests/core/smoke_core_146.py','tests/core/smoke_core_148.py','tests/core/smoke_core_149.py','tests/core/smoke_core_150.py','tests/core/smoke_core_151.py','tests/core/smoke_core_152.py','tests/core/smoke_core_154.py']:
        check((root/name).is_file(),'Missing stable entrypoint or guide: '+name)
    for directory in ['tests','tools']:
        for p in (root/directory).rglob('*.py'):
            if '__pycache__'in p.parts:continue
            try:tree=ast.parse(p.read_text(),filename=str(p))
            except SyntaxError as error:check(False,str(error));continue
            for node in ast.walk(tree):
                modules=[node.module]if isinstance(node,ast.ImportFrom)and node.level==0 else[a.name for a in node.names]if isinstance(node,ast.Import)else[]
                for module in modules:
                    if not module:continue
                    if module.startswith(('tests.','tools.')):
                        target=root/module.replace('.','/')
                        check(target.with_suffix('.py').is_file()or(target/'__init__.py').is_file(),str(p.relative_to(root))+': unresolved package '+module)
                    check(not module.startswith(('smoke_','test_','prepare_')),'Unqualified relocated import: '+module)
    documents=[*root.glob('*.md'),*list((root/'docs').rglob('*.md'))]
    private_links=0
    for p in documents:
        text=re.sub(r'(?ms)^```.*?^```[^\n]*','',p.read_text())
        for match in re.finditer(r'\[[^\]\n]+\]\(([^)\n]+)\)',text):
            target=match[1]
            if re.match(r'^[A-Za-z][A-Za-z0-9+.-]*:',target)or target.startswith(('#','/')):continue
            if 'local-only/'in target:
                private_links+=1;continue
            target=target[1:target.index('>')]if target.startswith('<')and'>'in target else target.split(' "',1)[0]
            path=urllib.parse.unquote(urllib.parse.urlsplit(target).path)
            if not path:continue
            check((p.parent/path).exists(),str(p.relative_to(root))+': broken local link '+target)
    guard_path=root/'tests/hosting/check_public_source.py'
    spec=importlib.util.spec_from_file_location('zgta_source_layout_guard',guard_path)
    guard=importlib.util.module_from_spec(spec);spec.loader.exec_module(guard)
    for directory in ['tests','tools','docs']:
        with tempfile.TemporaryDirectory(prefix='zgta-layout-guard-')as temporary:
            base=Path(temporary);p=base/directory/'fixture/bad.py';p.parent.mkdir(parents=True)
            p.write_text("token = '"+'ghp_'+'a'*40+"'\n")
            with contextlib.redirect_stdout(io.StringIO()),contextlib.redirect_stderr(io.StringIO()):code=guard.audit(base,directory=True)
            check(code==1,'Source-safety directory audit missed '+directory)
            p.unlink();(p.parent/'original.iso').write_bytes(b'authored non-game carrier')
            with contextlib.redirect_stdout(io.StringIO()),contextlib.redirect_stderr(io.StringIO()):code=guard.audit(base,directory=True)
            check(code==1,'Source-safety audit admitted a nonsource file in '+directory)
    print(('FAIL'if failures else'PASS')+f' repository layout: {checks} checks, {len(entries)} root files, {len(documents)} documents, {private_links} explicit private evidence references')
    for failure in failures:print('FAIL '+failure)
    return 1 if failures else 0

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository',type=Path,default=ROOT)
    raise SystemExit(verify(parser.parse_args().repository.resolve()))
