#!/usr/bin/env python3
"""Bound smoke tests without running Wine through SIP-protected timeout wrappers."""
import os, subprocess, sys
if os.environ.get('CONVERSIO_RUNTIME_LIBRARIES'):
    os.environ['DYLD_FALLBACK_LIBRARY_PATH']=os.environ['CONVERSIO_RUNTIME_LIBRARIES']
try:
    result=subprocess.run(sys.argv[2:],timeout=float(sys.argv[1]))
    raise SystemExit(result.returncode)
except subprocess.TimeoutExpired:
    print('Smoke test timed out',file=sys.stderr)
    raise SystemExit(124)
