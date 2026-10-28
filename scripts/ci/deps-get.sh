#!/usr/bin/env sh
# mix deps.get with retries. repo.hex.pm fetches time out intermittently from
# the CI node (`:timeout` on a few packages, then "Unknown package ... in
# lockfile"; defdo_cms pipelines 428-429, 2026-10-26). Fewer parallel fetches,
# a longer timeout and three attempts get past it. Same loop as defdo_cms,
# defdo_my_mvno and defdo_memory_hub.
# Hex stays on the latest release (2.6.x): its known failure, unpacking under a
# hard 120 s await, hit defdo_cms's Longhorn RWX NFS workspace, not this repo;
# 0.6.0 published fine with 2.6.0. The retry loop covers registry timeouts.
set -u
export HEX_HTTP_CONCURRENCY=4 HEX_HTTP_TIMEOUT=120
attempt=1
while :; do
  mix deps.get --check-locked "$@" && exit 0
  [ "$attempt" -ge 3 ] && exit 1
  echo "deps.get failed (attempt $attempt), retrying"
  attempt=$((attempt + 1))
  sleep 15
done
