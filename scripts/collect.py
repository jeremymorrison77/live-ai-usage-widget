#!/usr/bin/env python3
"""Usage-only collection. No credentials, conversations, browser data or raw errors saved."""
import argparse
import datetime as dt
import fcntl
import json
import os
from pathlib import Path
import tempfile
import time
import claude_usage_cli
import codex_usage_cli

REASONS = {'sign_in_required', 'interactive_setup_required', 'rate_limited',
           'cli_update_required', 'usage_read_timed_out', 'usage_panel_incomplete', 'reset_format_changed',
           'reset_out_of_range', 'invalid_usage', 'terminal_bounds', 'output_too_large',
           'probe_directory_unavailable', 'cli_unavailable'}


def read_state(path):
    try:
        if path.stat().st_size > 262144:
            return {}
        result = json.loads(path.read_text())
        return result if isinstance(result, dict) else {}
    except (OSError, ValueError):
        return {}


def atomic(path, value):
    fd, temporary = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as handle:
            json.dump(value, handle, allow_nan=False)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def claude():
    raw = claude_usage_cli.fetch()
    def name(label):
        return {'5-hour limit': '5-hour', 'Weekly · all models': 'weekly all'}.get(label,
                    label.replace('Weekly · ', 'weekly '))
    return {'status': 'ok', 'observed_at': raw['observedAt'],
            'windows': [{'window': name(w['label']), 'used_percent': w['percentUsed'],
                         'resets_at': w['resetsAt']} for w in raw['windows']]}


def collect(previous, enabled, now=None, readers=None):
    now = time.time() if now is None else now
    readers = readers or {'claude': claude, 'codex': codex_usage_cli.fetch}
    result = {}
    stamp = dt.datetime.fromtimestamp(now, dt.timezone.utc).isoformat()
    for provider in enabled:
        old = previous.get(provider, {})
        if not isinstance(old, dict):
            old = {}
        due = old.get('next_attempt_epoch', 0)
        # Clock rollback cannot suspend collection indefinitely.
        if isinstance(due, (int, float)) and now < due <= now + 900:
            result[provider] = old
            continue
        value = dict(old)
        value['last_attempt_at'] = stamp
        try:
            reading = readers[provider]()
            value.update(reading)
            value.update(refresh_status='ok', last_success_at=reading['observed_at'],
                         failure_reason=None, next_attempt_epoch=now + 300)
        except Exception as error:
            reason = str(error)
            value.update(refresh_status='failed', last_failure_at=stamp,
                         failure_reason=reason if reason in REASONS else 'unavailable',
                         next_attempt_epoch=now + 900)
            # A failure retains the last source date and never creates a reading.
            value.setdefault('status', 'unavailable')
            value.setdefault('windows', [])
        result[provider] = value
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--state-dir', required=True, type=Path)
    parser.add_argument('--generation', default='initial')
    parser.add_argument('--providers', nargs='*', choices=['claude', 'codex'], default=[])
    args = parser.parse_args()
    os.umask(0o077)
    args.state_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    claude_usage_cli.PROBE = args.state_dir / 'probe'
    with (args.state_dir / 'collection.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise SystemExit(75)
        path = args.state_dir / 'collection.json'
        previous = read_state(path)
        if previous.pop('_generation', None) != args.generation:
            previous = {}
        value = collect(previous, args.providers)
        atomic(path, dict(value, _generation=args.generation))
        print(json.dumps({'usage': value}, allow_nan=False))


if __name__ == '__main__':
    main()
