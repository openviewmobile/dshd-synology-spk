#!/bin/sh
# Runs inside the dshd container. Captures dsh's one-time token URL to the
# package var directory so the unprivileged DSM package user can read it.
set -eu
mkdir -p /run/dshd
chown -R dsh:dsh /home/dsh /workspace 2>/dev/null || true
rm -f /run/dshd/token-url.txt
host=$(hostname -i | awk '{print $1}')
dsh web --host "$host" --port 3080 --no-open \
  --public-url "$DSH_PUBLIC_URL" --trusted-host "$DSH_TRUSTED_HOST" 2>&1 |
while IFS= read -r line; do
  printf '%s\n' "$line"
  case "$line" in
    *'?token='*)
      printf '%s\n' "$line" |
        grep -o 'http[^ ]*?token=[^ ]*' | head -n 1 > /run/dshd/token-url.txt
      ;;
  esac
done
