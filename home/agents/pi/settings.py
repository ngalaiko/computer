import json
import os
from pathlib import Path
import sys
import tempfile

target, defaults = map(Path, sys.argv[1:])
settings = json.loads(target.read_text()) if target.exists() else {}
settings.update(json.loads(defaults.read_text()))
target.parent.mkdir(parents=True, exist_ok=True)
with tempfile.NamedTemporaryFile(mode="w", dir=target.parent, delete=False) as handle:
    json.dump(settings, handle, indent=2)
    handle.write("\n")
os.replace(handle.name, target)
