#!/usr/bin/env python3
"""Generate fresh synthetic reports and three years of history; no Hub access."""
import datetime
import json
import pathlib
import sys

out = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/token-monitor-resize")
out.mkdir(parents=True, exist_ok=True)
root = pathlib.Path(__file__).resolve().parents[1]
stats = json.loads((root / "Tests/MonitorCoreTests/Fixtures/stats.json").read_text())
now = datetime.datetime.now(datetime.timezone.utc)
stamp = now.isoformat().replace("+00:00", "Z")
stats["updatedAt"] = stamp
for device in stats["devices"]:
    device.update(receivedAt=stamp, updatedAt=stamp, stale=False)
    device.pop("periodWindows", None)
(out / "stats.json").write_text(json.dumps(stats))
today = datetime.date.today()
rows = [{"date": str(today - datetime.timedelta(days=i)), "tokens": (i % 17) * 7000,
         "perClient": {"codex": {"tokens": (i % 17) * 7000}}} for i in range(1095)]
(out / "history.json").write_text(json.dumps({"daily": rows, "monthly": []}))
print(f"Synthetic resize fixtures: {out}")
