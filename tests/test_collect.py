import datetime as dt
import sys
import contextlib
import io
import json
import tempfile
from unittest.mock import patch
from pathlib import Path
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from collect import collect, main, atomic
import claude_usage_cli as cli

NOW = 1792227600
STAMP = dt.datetime.fromtimestamp(NOW, dt.timezone.utc).isoformat()
READING = {'status': 'ok', 'observed_at': STAMP, 'windows': [{'window': 'weekly', 'used_percent': 12, 'resets_at': '2026-10-22T00:00:00+00:00'}]}

class RecoveryTests(unittest.TestCase):
    def test_success_and_duplicate_poll(self):
        calls = []
        def read(): calls.append(1); return READING
        first = collect({}, ['codex'], NOW, {'codex': read})
        second = collect(first, ['codex'], NOW+60, {'codex': read})
        self.assertEqual(first, second)
        self.assertEqual(len(calls), 1)

    def test_failure_preserves_source_date_and_recovers(self):
        first = collect({}, ['codex'], NOW, {'codex': lambda: READING})
        def fail(): raise ValueError('secret raw error')
        failed = collect(first, ['codex'], NOW+300, {'codex': fail})
        self.assertEqual(failed['codex']['observed_at'], STAMP)
        self.assertEqual(failed['codex']['failure_reason'], 'unavailable')
        self.assertEqual(failed['codex']['next_attempt_epoch'], NOW+1200)
        recovered = collect(failed, ['codex'], NOW+1200, {'codex': lambda: dict(READING, observed_at='2026-10-17T11:00:00Z')})
        self.assertEqual(recovered['codex']['refresh_status'], 'ok')

    def test_disabled_provider_removed_and_independent_failure(self):
        def fail(): raise ValueError('sign_in_required')
        value = collect({}, ['claude', 'codex'], NOW, {'claude': fail, 'codex': lambda: READING})
        self.assertEqual(value['claude']['refresh_status'], 'failed')
        self.assertEqual(value['codex']['refresh_status'], 'ok')
        self.assertNotIn('claude', collect(value, ['codex'], NOW+1, {}))

    def test_clock_rollback_retries(self):
        prior = {'codex': {'next_attempt_epoch': NOW+100000}}
        result = collect(prior, ['codex'], NOW, {'codex': lambda: READING})
        self.assertEqual(result['codex']['observed_at'], STAMP)

    def test_account_generation_discards_previous_account(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'collection.json'
            atomic(path, {'_generation': 'old-account', 'codex': dict(READING, next_attempt_epoch=9999999999)})
            argv = ['collect', '--state-dir', folder, '--generation', 'new-account', '--providers', 'codex']
            new = dict(READING, windows=[dict(READING['windows'][0], used_percent=77)])
            with patch.object(sys, 'argv', argv), patch('collect.codex_usage_cli.fetch', return_value=new) as fetch, contextlib.redirect_stdout(io.StringIO()) as output:
                main()
            self.assertEqual(fetch.call_count, 1)
            self.assertEqual(json.loads(output.getvalue())['usage']['codex']['windows'][0]['used_percent'], 77)
            self.assertEqual(json.loads(path.read_text())['_generation'], 'new-account')

    def test_optional_claude_model_and_timezone(self):
        now = dt.datetime(2026, 10, 17, 10, tzinfo=dt.timezone.utc)
        text = 'Current session\n12% used\nResets 1pm (Europe/London)\nCurrent week (Example)\n30% used\nResets Oct 20 at 1pm (Europe/London)'
        result = cli.parse_panel(text, now)
        self.assertEqual(len(result['windows']), 2)
        self.assertEqual(result['windows'][1]['label'], 'Weekly · Example')
        with self.assertRaises(cli.UsageUnavailable):
            cli.parse_panel('Current session\n12% used\nResets 1pm', now)

if __name__ == '__main__': unittest.main()
