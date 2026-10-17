#!/usr/bin/env python3
"""Read Claude's own /usage panel. Never reads or copies credential files."""
import datetime as dt
import fcntl
import json
import os
from pathlib import Path
import pty
import re
import select
import shutil
import tempfile
import signal
import struct
import subprocess
import termios
import time
from zoneinfo import ZoneInfo

PROBE = Path(tempfile.gettempdir()) / ('usage-widget-probe-' + str(os.getuid()))
BINARY = shutil.which('claude') or str(Path.home() / '.local/bin/claude')


class UsageUnavailable(Exception):
    pass


def plain(text):
    # Render cursor moves and erased lines, so cached values replaced by a fresh
    # response cannot survive as the first percentage in a flattened transcript.
    text = re.sub(r'\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)', '', text)
    rows = [[]]
    x = y = 0
    for token in re.findall(r'\x1b\[[0-?]*[ -/]*[@-~]|\x1b[()][A-Z0-9]|\x1b.|[^\x1b]', text):
        if token.startswith('\x1b['):
            match = re.fullmatch(r'\x1b\[([0-9;]*)([ABCDEFGHJKf])', token)
            if not match:
                continue
            nums = [int(n or 0) for n in match[1].split(';')]
            n, op = nums[0], match[2]
            if op == 'A': y = max(0, y - (n or 1))
            elif op == 'B': y += n or 1
            elif op == 'C': x += n or 1
            elif op == 'D': x = max(0, x - (n or 1))
            elif op == 'E': y += n or 1; x = 0
            elif op == 'F': y = max(0, y - (n or 1)); x = 0
            elif op == 'G': x = max(0, (n or 1) - 1)
            elif op in ('H', 'f'): y = max(0, (n or 1) - 1); x = max(0, (nums[1] if len(nums)>1 else 1) - 1)
            elif op == 'J' and n == 2: rows = [[]]; x = y = 0
            elif op == 'K' and y < len(rows):
                if n == 2: rows[y] = []
                elif n == 0: rows[y] = rows[y][:x]
                elif n == 1: rows[y][:x+1] = [' '] * min(x+1, len(rows[y]))
            continue
        if token.startswith('\x1b'): continue
        if token == '\r': x = 0; continue
        if token == '\n': y += 1; x = 0; continue
        if token == '\b': x = max(0, x-1); continue
        if ord(token) < 32: continue
        if y > 1000 or x > 1000: raise UsageUnavailable('terminal_bounds')
        while len(rows) <= y: rows.append([])
        while len(rows[y]) <= x: rows[y].append(' ')
        rows[y][x] = token
        x += 1
    return '\n'.join(''.join(row).rstrip() for row in rows).rstrip()


def reset_time(text, now, session=False):
    match = re.search(r'Resets?\s+([^\n]+)', text, re.I)
    if not match:
        return None
    value = match.group(1).strip()
    zone_match = re.search(r'\(([^()]+)\)', value)
    if not zone_match:
        raise UsageUnavailable('reset_format_changed')
    zone = ZoneInfo(zone_match.group(1))
    local = now.astimezone(zone)
    value = re.sub(r'\s*\([^()]+\)', '', value).strip().lower()
    clock = re.search(r'(\d{1,2})(?::(\d{2}))?\s*(am|pm)', value)
    if not clock:
        raise UsageUnavailable('reset_format_changed')
    hour = int(clock[1]) % 12 + (12 if clock[3] == 'pm' else 0)
    minute = int(clock[2] or 0)
    result = local.replace(hour=hour, minute=minute, second=0, microsecond=0)
    prefix = re.sub(r'\s+at$', '', value[:clock.start()].strip(' ,·'))
    if prefix:
        parsed = None
        for fmt in ('%b %d', '%B %d', '%b %d, %Y', '%m/%d'):
            try:
                parsed = dt.datetime.strptime(prefix if '%Y' in fmt else prefix + ' ' + str(local.year), fmt if '%Y' in fmt else fmt + ' %Y')
                break
            except ValueError:
                pass
        if parsed:
            result = result.replace(year=parsed.year, month=parsed.month, day=parsed.day)
            if result < local - dt.timedelta(days=1):
                result = result.replace(year=local.year + 1)
        elif prefix in ('today', 'tomorrow'):
            result += dt.timedelta(days=prefix == 'tomorrow')
        else:
            weekdays = {'mon': 0, 'tue': 1, 'wed': 2, 'thu': 3, 'fri': 4, 'sat': 5, 'sun': 6}
            if prefix[:3] not in weekdays:
                raise UsageUnavailable('reset_format_changed')
            result += dt.timedelta(days=(weekdays[prefix[:3]] - local.weekday()) % 7)
            if result <= local:
                result += dt.timedelta(days=7)
    elif result <= local:
        result += dt.timedelta(days=1)
    if not 0 < (result - local).total_seconds() <= (6 * 3600 if session else 8 * 86400):
        raise UsageUnavailable('reset_out_of_range')
    return result.astimezone(dt.timezone.utc).isoformat()


def parse_panel(text, now=None):
    now = now or dt.datetime.now(dt.timezone.utc)
    text = plain(text)
    headings = list(re.finditer(r'Current\s+(session|week(?:\s*\([^\n)]*\))?)[^\n]*', text, re.I))
    found = {}
    for index, heading in enumerate(headings):
        title = heading.group(0).lower()
        end = headings[index + 1].start() if index + 1 < len(headings) else len(text)
        block = text[heading.end():end]
        label = '5-hour limit' if 'session' in title else 'Weekly · Fable' if 'fable' in title else 'Weekly · all models' if 'all models' in title or title.strip() == 'current week' else 'Weekly · ' + re.sub(r'^current\s+week\s*\(|\)\s*$', '', heading.group(0), flags=re.I)
        if not label:
            continue
        pct = re.search(r'(?<![\d.])(\d{1,3}(?:\.\d+)?)\s*%\s*(used|left|remaining)', block, re.I)
        if not pct:
            continue
        used = float(pct[1]) if pct[2].lower() == 'used' else 100 - float(pct[1])
        if not 0 <= used <= 100:
            raise UsageUnavailable('invalid_usage')
        reset = reset_time(block, now, label == '5-hour limit')
        if reset is None:
            continue
        found[label] = {'label': label, 'percentUsed': used, 'resetsAt': reset}
    labels = tuple(found)[:8]
    if not found:
        raise UsageUnavailable('usage_panel_incomplete')
    return {'status': 'ok', 'windows': [found[x] for x in labels if x in found],
            'observedAt': now.isoformat(), 'savedEpoch': now.timestamp(), 'source': 'claude_cli_usage'}


def prepare_probe(path=PROBE):
    # This disposable directory may be absent after cleanup or a fresh install.
    # Never follow a replacement symlink into another working directory.
    if path.is_symlink():
        raise UsageUnavailable('probe_directory_unavailable')
    try:
        path.mkdir(mode=0o700, parents=True, exist_ok=True)
    except OSError:
        raise UsageUnavailable('probe_directory_unavailable') from None
    if not path.is_dir() or path.is_symlink():
        raise UsageUnavailable('probe_directory_unavailable')


def probe_environment():
    env = dict(os.environ, TERM='xterm-256color')
    # Never inherit another agent's nesting marker. Claude owns its normal login.
    env.pop('CLAUDECODE', None)
    return env


def auth_ready(timeout=5):
    """Read only Claude's official sign-in boolean; discard all identity fields."""
    try:
        prepare_probe(PROBE)
        result = subprocess.run([BINARY, 'auth', 'status', '--json'], cwd=PROBE,
                                env=probe_environment(), capture_output=True,
                                text=True, timeout=timeout)
        if result.returncode != 0 or len(result.stdout) > 65536:
            return False
        value = json.loads(result.stdout)
        return isinstance(value, dict) and value.get('loggedIn') is True
    except (UsageUnavailable, OSError, ValueError, subprocess.SubprocessError):
        return False


def fetch(timeout=35):
    prepare_probe(PROBE)
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 200, 160, 0, 0))
    env = probe_environment()
    args = [BINARY, '--safe-mode', '--no-chrome', '--setting-sources', '', '--tools', '', '--strict-mcp-config', '--permission-mode', 'dontAsk',
            '--settings', '{"disableAllHooks":true,"remoteControlAtStartup":false}', '--ax-screen-reader']
    process = None
    buffer = b''
    sent = False
    dismissed_auto_mode = False
    last_output = time.monotonic()
    started = time.monotonic()
    try:
        process = subprocess.Popen(args, cwd=PROBE, env=env, stdin=slave, stdout=slave,
                                   stderr=slave, start_new_session=True, close_fds=True)
        os.close(slave)
        slave = -1
        while time.monotonic() - started < timeout:
            ready, _, _ = select.select([master], [], [], 0.2)
            if ready:
                try:
                    chunk = os.read(master, 65536)
                except OSError:
                    break
                if not chunk:
                    break
                last_output = time.monotonic()
                buffer += chunk
                if b'\x1b[6n' in chunk:
                    os.write(master, b'\x1b[1;1R')
                if len(buffer) > 262144:
                    raise UsageUnavailable('output_too_large')
            text = plain(buffer.decode('utf-8', 'replace'))
            if re.search(r'unknown option|unrecognized option', text, re.I):
                raise UsageUnavailable('cli_update_required')
            if re.search(r'Not logged in|Login expired|run /login', text, re.I):
                raise UsageUnavailable('sign_in_required')
            if (not sent and not dismissed_auto_mode
                    and 'Permission Required: Make auto mode your default permission mode?' in text
                    and 'Escape to cancel:' in text):
                os.write(master, b'\x1b')
                buffer = b''
                dismissed_auto_mode = True
                continue
            if re.search(r'Enter y/n:|Select login method|Permission Required', text, re.I):
                raise UsageUnavailable('interactive_setup_required')
            if not sent and time.monotonic() - started >= 2 and re.search(r'\$\s*$', text):
                os.write(master, b'/usage\r')
                buffer = b''
                sent = True
            elif sent:
                if re.search(r'429|rate.limit', text, re.I):
                    raise UsageUnavailable('rate_limited')
                try:
                    if 'Refreshing…' in text or time.monotonic() - last_output < 0.75:
                        continue
                    return parse_panel(text)
                except UsageUnavailable:
                    pass
            if process.poll() is not None:
                break
        raise UsageUnavailable('usage_read_timed_out')
    finally:
        if process and process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=2)
        os.close(master)
        if slave >= 0:
            os.close(slave)
