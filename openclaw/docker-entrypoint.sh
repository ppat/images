#!/bin/bash
set -eo pipefail

# All gateway-created state files/dirs land 600/700 so they don't trip OpenClaw's
# fs.credentials_dir.perms_writable / fs.sessions_store.perms_readable audit checks on a
# group-writable fsGroup-mounted PVC. (The state-dir *root* is the kubelet-owned fsGroup mount
# point -- umask can't affect it, so fs.state_dir.perms_group_writable stays config-suppressed.)
umask 077

STATE_DIR="${OPENCLAW_STATE_DIR:-${OPENCLAW_DATA_DIR:-/home/node/.openclaw}}"

# The plugins installed at image build time (see Dockerfile) live under the OpenClaw state dir
# (npm/projects/* + the pinned install records). Deployments commonly mount external storage (a
# PVC, a bind mount) over that dir for gateway state; a freshly-mounted volume starts empty and
# hides everything baked into the image. Restore anything missing from the build-time seed, with
# cp -n so content an operator persisted always wins.
if [[ -d /home/node/.openclaw-seed ]]; then
  if mkdir -p "${STATE_DIR}" 2>/dev/null; then
    cp -an /home/node/.openclaw-seed/. "${STATE_DIR}/" 2>/dev/null \
      || echo "docker-entrypoint: could not seed ${STATE_DIR}, continuing without it" >&2
  else
    echo "docker-entrypoint: ${STATE_DIR} is not writable, continuing without seeding" >&2
  fi
fi

# Seed the gateway config from a read-only source (e.g. a Kubernetes ConfigMap mount) into its
# writable config path, so OpenClaw's CLI can write the file back (channels login, doctor) without
# EBUSY against a read-only mount. Copy only if the target is absent (an in-place edit in a
# writable volume wins), then tighten to 600 per the fs.config.perms_world_readable audit check.
# This folds in the work a separate config-seed init container would otherwise do.
CONFIG_SEED="${OPENCLAW_CONFIG_SEED:-}"
CONFIG_PATH="${OPENCLAW_CONFIG_PATH:-}"
if [[ -n "${CONFIG_SEED}" && -f "${CONFIG_SEED}" && -n "${CONFIG_PATH}" && ! -e "${CONFIG_PATH}" ]]; then
  if mkdir -p "$(dirname "${CONFIG_PATH}")" 2>/dev/null && cp "${CONFIG_SEED}" "${CONFIG_PATH}" 2>/dev/null; then
    chmod 600 "${CONFIG_PATH}" 2>/dev/null || true
  else
    echo "docker-entrypoint: could not seed config ${CONFIG_PATH} from ${CONFIG_SEED}" >&2
  fi
fi

# Exec the upstream gateway command supplied via CMD (kept in CMD, not hardcoded here, so it stays
# explicit/overridable). The base image ENTRYPOINT (tini -s --) remains PID 1 for signal handling.
exec "$@"
