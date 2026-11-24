#!/usr/bin/env python3
"""
PM2 Extended Metrics Parser
Reads PM2 JSON and outputs Prometheus metrics
Aligned with pm2-api.js getStatus() and getHealthScore() logic
"""

import json
import os
import sys
import time


# Path to pm2-status-reasons.json (same as pm2-api.js)
STATUS_REASONS_PATH = os.path.join(
    '/root/workspaces/tools/acc1-scripts', 'data', 'pm2-status-reasons.json'
)

_status_reasons_cache = None
_status_reasons_cache_time = 0
STATUS_REASONS_TTL = 5  # seconds


def get_status_reasons():
    global _status_reasons_cache, _status_reasons_cache_time
    now = time.time()
    if _status_reasons_cache is not None and (now - _status_reasons_cache_time) < STATUS_REASONS_TTL:
        return _status_reasons_cache
    try:
        if os.path.exists(STATUS_REASONS_PATH):
            with open(STATUS_REASONS_PATH, 'r') as f:
                _status_reasons_cache = json.load(f)
            _status_reasons_cache_time = now
            return _status_reasons_cache
    except Exception:
        pass
    _status_reasons_cache = {}
    _status_reasons_cache_time = now
    return _status_reasons_cache


def is_ignored_process(proc_name):
    """Check if process has ignoreHealth: true in pm2-status-reasons.json"""
    reasons = get_status_reasons()
    entry = reasons.get(proc_name)
    return isinstance(entry, dict) and entry.get('ignoreHealth') is True


def get_status(proc):
    """Status classification matching pm2-api.js getStatus() lines 117-124"""
    env = proc['pm2_env']
    status = env.get('status', 'unknown')
    cron_restart = env.get('cron_restart', None)
    name = proc['name']

    if status == 'online':
        return 'online'
    if status == 'stopped' and cron_restart:
        return 'scheduled'
    if status == 'stopped' and is_ignored_process(name):
        return 'paused'
    if status == 'errored':
        return 'errored'
    return 'stopped'


def get_health_score(proc):
    """Health score calculation matching pm2-api.js getHealthScore() lines 127-172"""
    env = proc['pm2_env']
    monit = proc['monit']
    name = proc['name']
    cpu = monit.get('cpu', 0)
    memory_bytes = monit.get('memory', 0)
    mem_mb = round(memory_bytes / 1024 / 1024)
    status = env.get('status', 'unknown')
    cron_restart = env.get('cron_restart', None)
    restarts = env.get('restart_time', 0)

    # Errored = critical
    if status == 'errored':
        return max(5, 15 - (10 if cpu > 80 else 0))

    # Paused: neutral score, excluded from average
    if is_ignored_process(name) and status in ('stopped', 'errored'):
        return 50

    # Stopped cron: check exit code
    if status == 'stopped' and cron_restart:
        exit_code = env.get('exit_code', None)
        if exit_code == 0 or exit_code is None:
            return 90
        return 40

    # Stopped daemon: critical if should be running
    if status == 'stopped' and not cron_restart:
        if env.get('autorestart', False):
            return 10
        return 30

    # Online processes: start from 100
    score = 100
    pm_uptime = env.get('pm_uptime', 0)
    uptime_sec = (time.time() * 1000 - pm_uptime) / 1000 if pm_uptime else 0

    # Stability: penalize only very recent starts
    if uptime_sec < 60:
        score -= 15
    elif uptime_sec < 300:
        score -= 8
    elif uptime_sec < 3600:
        score -= 3

    # CPU usage
    if cpu > 90:
        score -= 15
    elif cpu > 70:
        score -= 8
    elif cpu > 50:
        score -= 3

    # Memory usage
    if mem_mb > 500:
        score -= 10
    elif mem_mb > 200:
        score -= 3

    # Restart penalty
    if restarts > 20:
        score -= 15
    elif restarts > 10:
        score -= 10
    elif restarts > 5:
        score -= 5

    return max(0, min(100, score))


def main():
    if len(sys.argv) < 2:
        print("# ERROR: No JSON file provided", file=sys.stderr)
        sys.exit(1)

    try:
        with open(sys.argv[1], 'r') as f:
            data = json.load(f)
    except (json.JSONDecodeError, FileNotFoundError) as e:
        print(f"# ERROR: Failed to parse pm2 jlist output: {e}", file=sys.stderr)
        sys.exit(1)

    metrics = []

    # Deduplicate by name: prefer 'online' process when multiple entries exist
    seen = {}
    for process in data:
        pname = process['name']
        if pname not in seen:
            seen[pname] = process
        else:
            existing_status = seen[pname]['pm2_env'].get('status', '')
            current_status = process['pm2_env'].get('status', '')
            if current_status == 'online' and existing_status != 'online':
                seen[pname] = process
    data = list(seen.values())

    for process in data:
        name = process['name']
        env = process['pm2_env']

        # Get derived values
        cron_restart = env.get('cron_restart', None)
        restart_time = env.get('restart_time', 0)
        final_status = get_status(process)
        health = get_health_score(process)

        # Escape label values for Prometheus
        name_escaped = name.replace('\\', '\\\\').replace('"', '\\"')
        status_escaped = final_status.replace('\\', '\\\\').replace('"', '\\"')

        # pm2_status_info
        metrics.append(f'pm2_status_info{{name="{name_escaped}",status="{status_escaped}"}} 1')

        # pm2_health_score
        metrics.append(f'pm2_health_score{{name="{name_escaped}"}} {health}')

        # restart count metric
        metrics.append(f'pm2_restart_count{{name="{name_escaped}"}} {restart_time}')

        # pm2_is_scheduled
        is_scheduled = 1 if cron_restart else 0
        metrics.append(f'pm2_is_scheduled{{name="{name_escaped}"}} {is_scheduled}')

        # pm2_cron_schedule (only for cron processes)
        if cron_restart:
            cron_escaped = cron_restart.replace('\\', '\\\\').replace('"', '\\"')
            metrics.append(f'pm2_cron_schedule{{name="{name_escaped}",schedule="{cron_escaped}"}} 1')

    # Group metrics by type for proper Prometheus format (HELP/TYPE before values)
    grouped = {}
    for m in metrics:
        key = m.split('{')[0]
        grouped.setdefault(key, []).append(m)

    headers = {
        'pm2_status_info': ('PM2 process status (online, stopped, errored, scheduled, paused)', 'gauge'),
        'pm2_health_score': ('PM2 process health score (0-100)', 'gauge'),
        'pm2_restart_count': ('PM2 process total restart count', 'counter'),
        'pm2_is_scheduled': ('Whether PM2 process is scheduled (has cron_restart)', 'gauge'),
        'pm2_cron_schedule': ('PM2 cron schedule for scheduled processes', 'gauge'),
    }

    for key in ['pm2_status_info', 'pm2_health_score', 'pm2_restart_count', 'pm2_is_scheduled', 'pm2_cron_schedule']:
        if key in grouped:
            desc, mtype = headers[key]
            print(f'# HELP {key} {desc}')
            print(f'# TYPE {key} {mtype}')
            for line in grouped[key]:
                print(line)


if __name__ == '__main__':
    main()
