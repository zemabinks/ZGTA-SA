#!/usr/bin/env python3
"""Actual archived command/vehicle callbacks against independently written Swift."""
from pathlib import Path
import hashlib,json,subprocess,tempfile
ROOT=Path(__file__).resolve().parent
def main():
    out=ROOT/'local-only/research/original-world-commands';out.mkdir(parents=True,exist_ok=True)
    paths=['ios/App/NativeOriginalWorldCommands.swift','smoke_native_original_commands.swift','smoke_native_original_commands.js','smoke_native_original_commands.py']
    before={name:(ROOT/name).read_bytes()for name in paths}
    subprocess.run(['node',str(ROOT/'smoke_native_original_commands.js'),str(out/'goldens.json')],check=True)
    with tempfile.TemporaryDirectory(prefix='snapshot-',dir=out)as temporary:
        work=Path(temporary);(work/'main.swift').write_bytes(before['smoke_native_original_commands.swift']);(work/'commands.swift').write_bytes(before['ios/App/NativeOriginalWorldCommands.swift'])
        result=subprocess.run(['xcrun','swiftc','-O','-module-cache-path',str(out/'modules'),str(work/'commands.swift'),str(work/'main.swift'),'-o',str(work/'verify')],capture_output=True,text=True)
        (out/'compile.log').write_text(result.stdout+result.stderr)
        if result.returncode:print(result.stdout+result.stderr);result.check_returncode()
        result=subprocess.run([str(work/'verify'),str(out/'goldens.json')],capture_output=True,text=True)
        unchanged=all((ROOT/name).read_bytes()==data for name,data in before.items())
        goldens=json.loads((out/'goldens.json').read_text())
        report={'status':'PASS'if result.returncode==0 and unchanged else'FAIL','sourceUnchanged':unchanged,
            'sourceHashes':{name:hashlib.sha256(data).hexdigest()for name,data in before.items()},
            'archivedSourceHashes':{name:goldens[name]for name in('sourceSHA256','vehicleSHA256','expressionSHA256')},
            'vehicleCases':len(goldens['cases']),'commandCases':len(goldens['commandCases']),'teleportCallbackCases':len(goldens['teleportCases']),
            'output':result.stdout+result.stderr,
            'limits':['Actual archived network normalization/vehicle immunity/hurt callbacks with controlled wheel and occupied-state spies',
                'No renderer integration, actual wheel geometry, full staff inventory application, retail runtime or authenticated original-site gameplay claim',
                'Untrusted numeric fields reject booleans/strings and bound arm work; malformed vhit weapon coercions are deliberately not original parity']}
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(result.stdout+result.stderr,end='');result.check_returncode();assert unchanged
if __name__=='__main__':main()
