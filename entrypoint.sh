#!/bin/sh
# dsh rejects wildcard binds. In a Compose bridge network the container has a
# concrete interface address; DSM's reverse proxy can forward to the published port.
set -eu
host="${DSH_BIND_HOST:-$(hostname -i 2>/dev/null | awk '{print $1}')}"
if [ -z "$host" ]; then
  echo "dshd: cannot determine a concrete bind address; set DSH_BIND_HOST" >&2
  exit 1
fi
echo "dshd: binding http://$host:3080"

# When DSM terminates TLS, the browser-facing authority differs from the bind
# address. Both flags are needed: --public-url makes the printed token URL usable,
# --trusted-host lets dsh's Host/Origin fence accept the reverse-proxy authority.
if [ -n "${DSH_PUBLIC_URL:-}" ] && [ -n "${DSH_TRUSTED_HOST:-}" ]; then
  echo "dshd: public URL $DSH_PUBLIC_URL (trusted host $DSH_TRUSTED_HOST)"
  exec dsh web --host "$host" --port 3080 --no-open \
    --public-url "$DSH_PUBLIC_URL" --trusted-host "$DSH_TRUSTED_HOST"
fi
exec dsh web --host "$host" --port 3080 --no-open
