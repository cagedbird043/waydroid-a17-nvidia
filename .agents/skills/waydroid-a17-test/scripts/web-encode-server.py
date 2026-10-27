#!/usr/bin/env python3
"""Per-case WebCodecs/WebRTC evidence collector (guest Chrome only)."""
import argparse
import http.server
import json
import pathlib
import subprocess
import threading
import time
import uuid

p = argparse.ArgumentParser()
p.add_argument('--out', required=True)
p.add_argument('--timeout', type=int, default=150)
a = p.parse_args()
here = pathlib.Path(__file__).resolve().parent
out = pathlib.Path(a.out); out.mkdir(parents=True, exist_ok=True)
run = uuid.uuid4().hex
expected = [('wc-' + str(i), 'webcodecs') for i in range(4)] + [('rtc-' + str(i), 'webrtc') for i in range(3)]
components = ['avc', 'hevc', 'av1']
results = []
active = None
finished = threading.Event()

def guest(cmd):
    return subprocess.run([str(here / 'guest.sh'), cmd], capture_output=True, text=True, timeout=15)

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kw):
        super().__init__(*args, directory=str(here / 'web'), **kw)
    def do_POST(self):
        global active
        try:
            data = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
            ident = data['id']
            assert data['run'] == run
            if self.path == '/case/start':
                assert active is None and ident == expected[len(results)][0]
                r = guest('logcat -c')
                assert r.returncode == 0, r.stderr
                active = ident
                (out / (ident + '.start.json')).write_text(json.dumps({'id': ident, 'host_time_ns': time.time_ns()}))
            elif self.path == '/case/result':
                assert ident == active
                r = guest('logcat -d -v threadtime')
                (out / (ident + '.logcat')).write_text(r.stdout + r.stderr)
                value = data['result']
                if expected[len(results)][1] == 'webcodecs':
                    ok = value.get('out') == 60 and value.get('keys', 0) > 0 and value.get('errs') == [] and not value.get('error')
                else:
                    component = 'c2.nvprolapse.' + components[int(ident[-1])] + '.encoder:'
                    ok = value.get('encoded', 0) > 0 and value.get('width', 0) >= 960 and value.get('height', 0) >= 540 and component in r.stdout and not value.get('error')
                data.update(passed=bool(ok and r.returncode == 0), end_host_time_ns=time.time_ns(), logcat_exit=r.returncode)
                (out / (ident + '.json')).write_text(json.dumps(data, indent=2))
                results.append(data); active = None
                if len(results) == len(expected): finished.set()
            else: raise ValueError('unknown endpoint')
            self.send_response(200); self.end_headers(); self.wfile.write(b'{}')
        except Exception as error:
            self.send_response(400); self.end_headers(); self.wfile.write(str(error).encode())

server = http.server.ThreadingHTTPServer(('192.168.240.1', 8765), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
status = 1
try:
    r = guest('setsid toybox nc -s 127.0.0.1 -p 8765 -L toybox nc 192.168.240.1 8765 </dev/null >/dev/null 2>&1 &')
    assert r.returncode == 0, r.stderr
    r = subprocess.run(['waydroid', 'app', 'intent', 'android.intent.action.VIEW', 'http://localhost:8765/?run=' + run], capture_output=True, text=True, timeout=20)
    (out / 'launch.log').write_text(r.stdout + r.stderr)
    if r.returncode == 0 and finished.wait(a.timeout):
        status = 0 if len(results) == 7 and all(r['passed'] for r in results) else 1
finally:
    server.shutdown(); server.server_close()
    guest("pkill -f 'nc -s 127.0.0.1 -p 8765' || true")
    (out / 'results.json').write_text(json.dumps({'run': run, 'exit': status, 'results': results}, indent=2))
print(json.dumps({'exit': status, 'cases': len(results), 'passed': sum(r['passed'] for r in results), 'evidence': str(out)}))
raise SystemExit(status)
