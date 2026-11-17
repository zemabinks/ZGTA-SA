#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Pinned C bridge selection for authored raw-store tests; no game resources."""
from pathlib import Path
import hashlib,importlib.util,sys
ROOT=Path(__file__).resolve().parent

def bridge_module(output):
    spec=importlib.util.spec_from_file_location('raw_lease_bridge_builder',ROOT/'build_installer_bridge.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    module.OUT=output
    return module

def pinned_host_archive(candidate=None):
    if candidate:
        path=Path(candidate).resolve(strict=True)
        assert path.name=='libzgtasa_installer.a' and path.parent.name=='host'
        module=bridge_module(path.parent.parent)
        # The builder's read-only verifier pins C/header/vendor hashes, target,
        # config, sanitizer policy and the archive's complete SHA256.
        assert module.valid_archive('host',module.c_hashes()),'Requested host archive is not pinned to the current source/header/config'
        return path
    output=ROOT/'local-only/research/raw-leases-109/installer-bridge'
    module=bridge_module(output)
    if not module.valid_archive('host',module.c_hashes()):
        saved=sys.argv
        try:
            sys.argv=['build_installer_bridge.py','--platform','host']
            result=module.main()
            assert result in (None,0)
        finally:sys.argv=saved
    assert module.valid_archive('host',module.c_hashes())
    return output/'host/libzgtasa_installer.a'
