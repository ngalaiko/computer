import json
import os
from pathlib import Path
import subprocess
import sys


services, oneshots = map(Path, sys.argv[1:])
credentials = {
    "RESTIC_REPOSITORY": "b2:dummy:backup",
    "RESTIC_PASSWORD": "dummy backup password",
    "B2_ACCOUNT_ID": "dummy account",
    "B2_ACCOUNT_KEY": "dummy key",
    "RESTIC_CACHE_DIR": "/tmp/dummy cache",
}
environment = os.environ | credentials | {"TEST_NON_SECRET": "safe value"}
safe = {"TEST_NON_SECRET": "safe value"}


def run(script):
    result = subprocess.run(
        ["bash", str(script)], env=environment, text=True, capture_output=True
    )
    assert result.returncode == 0, result.stderr
    return result.stdout


assert json.loads(run(services / "probe/run")) == safe
log = Path(os.environ["TMPDIR"]) / "service-logs/probe/current"
log.parent.mkdir(parents=True)
run(services / "probe/finish")
assert json.loads(log.read_text()) == safe

assert json.loads(run(services / "backup-cron/run")) == credentials | safe

for name, expected in (("probe-once", safe), ("backup-restore", credentials | safe)):
    script = next(oneshots.glob(f"*-{name}"))
    run(script)
    log = Path(os.environ["TMPDIR"]) / "service-logs" / name / "current"
    assert json.loads(log.read_text()) == expected, name

print("Service credential isolation passed")
