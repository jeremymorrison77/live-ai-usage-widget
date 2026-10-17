#!/usr/bin/env python3
"""Bounded read of official Codex account limits; never starts a thread or turn.

Codex manages its existing login. This adapter never opens credential files or
exports account identity, credits, conversation data, or raw errors.
"""
import datetime as dt
import json
import math
import os
from pathlib import Path
import select
import shutil
import signal
import subprocess
import time

def window_name(minutes):
    return {300: "5-hour", 10080: "weekly"}.get(minutes, f"{int(minutes)}-minute")

MAX_OUTPUT = 262144
DESKTOP_BINARY = Path('/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex')


class UsageUnavailable(Exception):
    pass


def find_binary():
    for candidate in (DESKTOP_BINARY, Path('/Applications/Codex.app/Contents/Resources/codex'),
                      Path('/opt/homebrew/bin/codex'), Path('/usr/local/bin/codex')):
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    value = shutil.which('codex')
    if value:
        return value
    raise UsageUnavailable('cli_unavailable')


def parse_limits(result, now=None):
    now = now or dt.datetime.now(dt.timezone.utc)
    if not isinstance(result, dict):
        raise UsageUnavailable('usage_panel_incomplete')
    buckets = result.get('rateLimitsByLimitId')
    if isinstance(buckets, dict) and buckets:
        limits = buckets.get('codex')
    else:
        limits = result.get('rateLimits')
    if not isinstance(limits, dict) or limits.get('limitId') not in (None, 'codex'):
        raise UsageUnavailable('usage_panel_incomplete')
    windows = []
    for key in ('primary', 'secondary'):
        item = limits.get(key)
        if item is None:
            continue
        if not isinstance(item, dict):
            raise UsageUnavailable('invalid_usage')
        used, minutes, reset = (item.get(field) for field in ('usedPercent', 'windowDurationMins', 'resetsAt'))
        if any(isinstance(x, bool) or not isinstance(x, (int, float)) or not math.isfinite(x)
               for x in (used, minutes, reset)):
            raise UsageUnavailable('invalid_usage')
        if not 0 <= used <= 100 or not 0 < minutes <= 525600 or reset <= 0:
            raise UsageUnavailable('invalid_usage')
        try:
            reset_date = dt.datetime.fromtimestamp(reset, dt.timezone.utc)
        except (ValueError, OSError, OverflowError):
            raise UsageUnavailable('invalid_usage') from None
        windows.append({'window': window_name(minutes), 'minutes': minutes,
                        'used_percent': float(used), 'resets_at': reset_date.isoformat()})
    if not windows:
        raise UsageUnavailable('usage_panel_incomplete')
    return {'status': 'ok', 'observed_at': now.isoformat(), 'windows': windows, 'stale': False}


def error_reason(error):
    message = str(error.get('message', '')).lower() if isinstance(error, dict) else ''
    if any(term in message for term in ('429', 'rate limit', 'too many requests')):
        return 'rate_limited'
    if any(term in message for term in ('401', 'unauthorized', 'not logged', 'sign in', 'authentication')):
        return 'sign_in_required'
    return 'unavailable'


def fetch(timeout=15, binary=None):
    """One short-lived stdio connection. No socket listener, model request or auth export."""
    process = None
    started = time.monotonic()
    pending = b''
    received = 0
    initialized = False
    def send(value):
        process.stdin.write((json.dumps(value) + '\n').encode())
        process.stdin.flush()
    try:
        process = subprocess.Popen([binary or find_binary(), 'app-server', '--listen', 'stdio://'],
            cwd='/private/tmp', stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, start_new_session=True, bufsize=0)
        send({'id': 0, 'method': 'initialize', 'params': {'clientInfo': {
            'name': 'usage_widget', 'title': 'Live Usage Widget', 'version': '1.0'}}})
        while time.monotonic() - started < timeout:
            if not select.select([process.stdout], [], [], min(0.2, max(0, timeout - (time.monotonic() - started))))[0]:
                continue
            chunk = os.read(process.stdout.fileno(), 65536)
            if not chunk:
                raise UsageUnavailable('unavailable')
            received += len(chunk)
            if received > MAX_OUTPUT:
                raise UsageUnavailable('output_too_large')
            pending += chunk
            while b'\n' in pending:
                line, pending = pending.split(b'\n', 1)
                try:
                    message = json.loads(line)
                except (ValueError, UnicodeDecodeError):
                    raise UsageUnavailable('usage_panel_incomplete') from None
                if not isinstance(message, dict):
                    continue
                if message.get('id') == 0 and not initialized:
                    if 'error' in message or not isinstance(message.get('result'), dict):
                        raise UsageUnavailable(error_reason(message.get('error')))
                    initialized = True
                    send({'method': 'initialized', 'params': {}})
                    send({'id': 1, 'method': 'account/rateLimits/read'})
                elif message.get('id') == 1 and initialized:
                    if 'error' in message:
                        raise UsageUnavailable(error_reason(message['error']))
                    return parse_limits(message.get('result'))
        raise UsageUnavailable('usage_read_timed_out')
    except (OSError, subprocess.SubprocessError):
        raise UsageUnavailable('unavailable') from None
    finally:
        if process:
            # A child can retain stdout after the group leader exits. Clean the
            # helper's entire private group even when the parent already ended.
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except (ProcessLookupError, PermissionError):
                pass
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                pass
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass
            process.wait(timeout=2)
            for stream in (process.stdin, process.stdout):
                if stream:
                    stream.close()
