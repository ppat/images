#!/bin/bash
set -eo pipefail

DATA_DIR="${OPENCLAW_DATA_DIR:-/home/node/.openclaw}"

# The plugins installed at image build time (see Dockerfile) live under the OpenClaw data dir
# (npm/projects/* + the pinned install records). Deployments commonly mount external storage
# (a PVC, a bind mount) over that data dir for gateway state; a freshly-mounted volume starts
# empty and hides everything baked into the image. Restore anything missing from the build-time
# seed, with cp -n so existing content an operator persisted always wins.
if [[ -d /home/node/.openclaw-seed ]]; then
  if mkdir -p "${DATA_DIR}" 2>/dev/null; then
    cp -an /home/node/.openclaw-seed/. "${DATA_DIR}/" 2>/dev/null \
      || echo "docker-entrypoint: could not seed ${DATA_DIR}, continuing without it" >&2
  else
    echo "docker-entrypoint: ${DATA_DIR} is not writable, continuing without seeding" >&2
  fi
fi

exec node openclaw.mjs gateway "$@"
