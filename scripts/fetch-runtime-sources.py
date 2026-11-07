#!/usr/bin/env python3
"""Fetch checksummed corresponding source archives from recorded Homebrew metadata."""
import hashlib, json, pathlib, subprocess, sys
manifest=json.loads(pathlib.Path(sys.argv[1]).read_text())
root=pathlib.Path(sys.argv[2])
for formula in manifest['formulae']:
    stable=formula['urls']['stable']
    url=stable['url']; checksum=stable['checksum']
    target=root/(formula['name']+'-'+formula['versions']['stable']+'.source')
    if not target.exists():
        subprocess.run(['curl','-fL','--retry','3','-o',str(target)+'.part',url],check=True)
        pathlib.Path(str(target)+'.part').rename(target)
    actual=hashlib.sha256(target.read_bytes()).hexdigest()
    if actual != checksum: raise SystemExit('Source checksum mismatch: '+formula['name'])
