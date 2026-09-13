#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
./scripts/build-sandbox.sh
mkdir -p .build/sandbox-validation
printf sandbox-external-fixture > .build/sandbox-validation/external.txt
app="$PWD/.build/sandbox/ClipNest.app"
codesign -d --entitlements :- "$app" > .build/sandbox-validation/entitlements.plist
for phase in seed verify; do
  "$app/Contents/MacOS/ClipNest" --sandbox-check "$phase" \
    --external-fixture "$PWD/.build/sandbox-validation/external.txt" \
    > ".build/sandbox-validation/$phase.json"
done
python3 - <<'PY'
import json, plistlib
from pathlib import Path
root = Path('.build/sandbox-validation')
assert plistlib.loads((root / 'entitlements.plist').read_bytes())['com.apple.security.app-sandbox'] is True
for phase in ('seed', 'verify'):
    report = json.loads((root / f'{phase}.json').read_text())
    assert report['passed'] and report['externalFileDenied'], report
    assert '/Containers/com.clipnest.sandbox/' in report['directory'], report
print('PASS: sandbox enforced; text/image/container-file round trips survive process restart')
print('NOT TESTED: automatic paste, external file grants, general clipboard monitoring')
PY
