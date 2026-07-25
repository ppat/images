#!/bin/bash
set -eo pipefail

DATA_DIR="${OPENCLAW_DATA_DIR:-/home/node/.openclaw}"

# openclaw plugins install (run at image build time, see Dockerfile) drops packages under
# $OPENCLAW_DATA_DIR/extensions. Operators commonly mount external storage (a PVC, a bind
# mount) at that same path for gateway state, which starts out empty and hides whatever was
# baked into the image there. Reseed from the build-time copy whenever it's missing, without
# clobbering anything an operator installed themselves at runtime.
if [[ -d /home/node/.openclaw-extensions.baked ]]; then
  if mkdir -p "${DATA_DIR}/extensions" 2>/dev/null; then
    cp -an /home/node/.openclaw-extensions.baked/. "${DATA_DIR}/extensions/" 2>/dev/null \
      || echo "docker-entrypoint: could not seed ${DATA_DIR}/extensions, continuing without it" >&2
  else
    echo "docker-entrypoint: ${DATA_DIR}/extensions is not writable, continuing without seeding" >&2
  fi
fi

exec node openclaw.mjs gateway "$@"
