"""Generate a small, bounded stream of GET requests for the monitoring lab."""
import argparse
import time
import urllib.error
import urllib.request

p = argparse.ArgumentParser()
p.add_argument("--url", default="http://127.0.0.1:8000")
p.add_argument("--seconds", type=int, default=180)
p.add_argument("--interval", type=float, default=.25)
a = p.parse_args()
if not 1 <= a.seconds <= 600 or not .1 <= a.interval <= 10:
    p.error("seconds must be 1..600 and interval .1..10")
deadline = time.monotonic() + a.seconds
ok = failed = 0
while time.monotonic() < deadline:
    try:
        with urllib.request.urlopen(a.url.rstrip('/') + '/api/tickets?limit=5', timeout=5) as response:
            response.read()
        ok += 1
    except (urllib.error.URLError, TimeoutError):
        failed += 1
    time.sleep(a.interval)
print(f"Completed: successful={ok}, failed={failed}")
