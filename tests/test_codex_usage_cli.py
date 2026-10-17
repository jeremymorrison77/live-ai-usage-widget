import datetime as dt
import json
import os
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1] / 'scripts'))
import codex_usage_cli as cli

NOW = dt.datetime(2026, 10, 16, 17, 0, tzinfo=dt.timezone.utc)
WINDOW = {'usedPercent': 25.5, 'windowDurationMins': 10080, 'resetsAt': 1792650147}


class CodexUsageTests(unittest.TestCase):
    def test_exact_codex_bucket_and_minimal_fields(self):
        result = cli.parse_limits({'rateLimitsByLimitId': {
            'codex': {'limitId': 'codex', 'primary': WINDOW, 'credits': {'balance': 'secret'}},
            'other': {'primary': dict(WINDOW, usedPercent=99)}},
            'rateLimits': {'primary': dict(WINDOW, usedPercent=88)},
            'email': 'private@example.invalid'}, NOW)
        self.assertEqual(result['windows'][0]['used_percent'], 25.5)
        self.assertEqual(result['windows'][0]['window'], 'weekly')
        self.assertEqual(result['observed_at'], NOW.isoformat())
        self.assertNotIn('private', json.dumps(result))
        self.assertNotIn('credits', json.dumps(result))

    def test_legacy_single_bucket_and_optional_windows(self):
        result = cli.parse_limits({'rateLimits': {'primary': WINDOW, 'secondary': None}}, NOW)
        self.assertEqual(len(result['windows']), 1)
        self.assertFalse(result['stale'])

    def test_does_not_substitute_another_bucket(self):
        for result in ({'rateLimitsByLimitId': {'other': {'primary': WINDOW}}, 'rateLimits': {'primary': WINDOW}},
                       {'rateLimits': {'limitId': 'other', 'primary': WINDOW}},
                       {'rateLimits': {'primary': None}}):
            with self.assertRaises(cli.UsageUnavailable):
                cli.parse_limits(result, NOW)

    def test_invalid_values_fail_closed(self):
        for field, value in [('usedPercent', True), ('usedPercent', float('nan')),
                             ('usedPercent', 101), ('windowDurationMins', 0),
                             ('resetsAt', 1e100), ('resetsAt', None)]:
            with self.subTest(field=field, value=value), self.assertRaises(cli.UsageUnavailable):
                cli.parse_limits({'rateLimits': {'primary': dict(WINDOW, **{field: value})}}, NOW)

    def fake_server(self, folder, body):
        script = Path(folder) / 'fake-codex'
        script.write_text('#!' + sys.executable + '\nimport sys,json,time\n' + body)
        script.chmod(0o700)
        return str(script)

    def test_protocol_only_initializes_and_reads_usage(self):
        with tempfile.TemporaryDirectory() as folder:
            capture = str(Path(folder) / 'methods.json')
            body = """
methods=[]
for line in sys.stdin:
 m=json.loads(line); methods.append(m['method'])
 if m['method']=='initialize': print(json.dumps({'id':0,'result':{}}),flush=True)
 elif m['method']=='account/rateLimits/read':
  with open(CAPTURE,'w') as f: json.dump(methods,f)
  print(json.dumps({'id':1,'result':{'rateLimits':{'primary':WINDOW}}}),flush=True)
""".replace('CAPTURE', repr(capture)).replace('WINDOW', repr(WINDOW))
            result = cli.fetch(timeout=3, binary=self.fake_server(folder, body))
            self.assertEqual(result['status'], 'ok')
            self.assertEqual(json.loads(Path(capture).read_text()),
                             ['initialize', 'initialized', 'account/rateLimits/read'])

    def test_timeout_and_output_limit(self):
        with tempfile.TemporaryDirectory() as folder:
            start = time.monotonic()
            with self.assertRaisesRegex(cli.UsageUnavailable, 'usage_read_timed_out'):
                cli.fetch(timeout=0.15, binary=self.fake_server(folder, 'time.sleep(20)\n'))
            self.assertLess(time.monotonic() - start, 3)
            with self.assertRaisesRegex(cli.UsageUnavailable, 'output_too_large'):
                cli.fetch(timeout=3, binary=self.fake_server(folder, "sys.stdout.write('x'*300000);sys.stdout.flush();time.sleep(5)\n"))

    def test_error_messages_are_sanitized(self):
        self.assertEqual(cli.error_reason({'message': '401 unauthorized SECRET'}), 'sign_in_required')
        self.assertEqual(cli.error_reason({'message': '429 too many requests SECRET'}), 'rate_limited')
        self.assertEqual(cli.error_reason({'message': 'SECRET'}), 'unavailable')
        with tempfile.TemporaryDirectory() as folder:
            body = "sys.stdin.readline(); print(json.dumps({'id':0,'error':{'message':'401 unauthorized SECRET'}}),flush=True);time.sleep(5)\n"
            with self.assertRaisesRegex(cli.UsageUnavailable, '^sign_in_required$'):
                cli.fetch(timeout=3, binary=self.fake_server(folder, body))

    def test_timeout_cleans_child_after_parent_exits(self):
        with tempfile.TemporaryDirectory() as folder:
            pidfile = Path(folder) / 'child.pid'
            body = "import subprocess,os\np=subprocess.Popen([sys.executable,'-c','import time; time.sleep(20)'])\nopen(PIDFILE,'w').write(str(p.pid))\nos._exit(0)\n".replace('PIDFILE', repr(str(pidfile)))
            try:
                with self.assertRaisesRegex(cli.UsageUnavailable, 'usage_read_timed_out'):
                    cli.fetch(timeout=0.3, binary=self.fake_server(folder, body))
                pid = int(pidfile.read_text())
                for _ in range(50):
                    try:
                        os.kill(pid, 0)
                    except ProcessLookupError:
                        break
                    time.sleep(0.02)
                else:
                    self.fail('Child retained after helper timeout')
            finally:
                if pidfile.exists():
                    try:
                        os.kill(int(pidfile.read_text()), 9)
                    except ProcessLookupError:
                        pass


if __name__ == '__main__':
    unittest.main()
