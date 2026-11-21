# hh-scoring freeze — 2026-11-21

Project frozen by owner order (vacancies exhausted, work stopped). Local working copies removed after a
hash-verified copy was stored in Yandex Object Storage (class COLD). Restore at any time from this page.

## Where the copy is

| Item | Value |
|---|---|
| Endpoint | `https://storage.yandexcloud.net` |
| Bucket | `arwox-server-backup` |
| Prefix | `cold/hh-scoring/2026-11-21/` |
| Storage class | `COLD` |
| Credentials | `/root/workspaces/secrets/yandex-s3.env` (variables `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) |

Objects:

| Object | Bytes | sha256 |
|---|---|---|
| `archive.tar.zst` (hh-scoring-dev) | 1572831971 | `30b2d4bd3d7e52a8477b04d065fd28ea560df1d662be8c2f2bac0a0cdd09a3a6` |
| `manifest-dev.sha256.gz` (31732 files) | 1.1 MiB | per-file sha256, relative paths |
| `prod-and-legacy.tar.zst` (hh-scoring-prod + hh-scoring) | 161302012 | `fbd617edf0df2dded4e5f768507706ba6c0368f78b476b237118d21bafa4f78f` |
| `manifest-prod-legacy.sha256.gz` (3849 files) | 175 KiB | per-file sha256, relative paths |

Independent second copy: the same trees are inside the restic repository (`RESTIC_REPOSITORY` from
`/root/workspaces/secrets/restic.env`, tag `server`); snapshot `a6568edd` lists 42 830 files under
`/root/workspaces/projects/hh-scoring-dev`.

Excluded from the archives (regenerable): `.venv`, `.repowise`, `node_modules`, `__pycache__`,
`.pytest_cache`.

## Restore

```bash
set -a; . /root/workspaces/secrets/yandex-s3.env; set +a
export MC_HOST_yc="https://${AWS_ACCESS_KEY_ID}:${AWS_SECRET_ACCESS_KEY}@storage.yandexcloud.net"
P=cold/hh-scoring/2026-11-21

# 1. fetch and verify the archive
mc cp yc/arwox-server-backup/$P/archive.tar.zst /tmp/
sha256sum /tmp/archive.tar.zst   # must equal 30b2d4bd...a3a6

# 2. unpack the working copy
mkdir -p /root/workspaces/projects/hh-scoring-dev
tar --use-compress-program=unzstd -xf /tmp/archive.tar.zst -C /root/workspaces/projects/hh-scoring-dev

# 3. per-file verification
mc cp yc/arwox-server-backup/$P/manifest-dev.sha256.gz /tmp/
gunzip -c /tmp/manifest-dev.sha256.gz > /tmp/manifest.sha256
cd /root/workspaces/projects/hh-scoring-dev && sha256sum -c /tmp/manifest.sha256 --quiet

# 4. rebuild the virtualenv that was not archived
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt

# 5. start the services again (all were stopped, not removed)
pm2 start hh-cabinet hh-cabinet-staging hh-dashboard-fastloop hh-hub-api hh-litestream \
          hh-pipeline hh-screening-monitor hh-pipeline-prod hh-wal-checkpoint
pm2 save

# 6. re-enable the per-minute pulse cron (commented out during the freeze)
crontab -l | sed 's|^# FREEZE-20261121 ||' | crontab -
```

`prod-and-legacy.tar.zst` restores the same way into `/root/workspaces/projects/` (two top-level
directories `hh-scoring-prod` and `hh-scoring`).

## What was changed on the host

- `pm2 stop` for: `hh-cabinet`, `hh-cabinet-staging`, `hh-dashboard-fastloop`, `hh-hub-api`,
  `hh-litestream`, `hh-pipeline`, `hh-screening-monitor`, `hh-pipeline-prod`, `hh-wal-checkpoint`;
  ecosystem entries kept intact, `pm2 save` done.
- crontab line for `hh-scoring-dev/scripts/pulse.sh` commented with the prefix `# FREEZE-20261121 `.
- Local trees deleted only after both checks passed: remote sha256 matched the local archive and a
  restore drill of 31 732 + 3 849 files verified with zero failures.
- `hh-cabinet-bridge`, `hh-import`, `hh-refetch`, `hh-token-refresh` belong to `arwox-biz` and were
  not touched.