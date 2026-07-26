#!/bin/bash
set -eo pipefail

# Files this process creates land 600/700 (dirs) so they don't trip OpenClaw's fs-perms audit
# checks. umask alone isn't enough on a Kubernetes fsGroup-mounted PVC: the kubelet re-applies
# group rw to every EXISTING file on the volume at each mount (before this container starts), so
# state persisted from a prior boot comes back group-writable -- the chmod re-tighten step below
# fixes that on every start. The state-dir ROOT stays group-writable regardless (it's the
# kubelet-owned fsGroup mount point, chmod EPERM for uid 1000) and remains audit-suppressed
# (fs.state_dir.perms_group_writable).
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

# Re-tighten the uid-1000-owned sensitive state trees AFTER the kubelet's fsGroup mount (which
# ran before this container started and re-added group rw to everything on the PVC, defeating
# umask on files persisted from a prior boot). This is what makes the fixes stick across restarts
# -- a manual chmod would be undone by the next mount. Covers, per OpenClaw's security audit:
#   fs.credentials_dir.perms_writable   -> <state>/credentials             (dir 700)
#   fs.auth_profiles.perms_writable     -> <state>/agents/*/agent/*.sqlite* (files 600)
#   fs.sessions_store.perms_readable    -> <state>/agents/*/sessions/*.json (files 600)
# `go-rwx` recursively strips group/other on these trees; uid 1000 owns them so it keeps access
# via owner bits, and it doesn't touch the (kubelet-owned, un-chmod-able) state-dir root. The
# large npm/plugin trees are left alone -- they aren't audited and don't need tightening.
for tree in "${STATE_DIR}/credentials" "${STATE_DIR}/agents"; do
  if [[ -d "${tree}" ]]; then
    chmod -R go-rwx "${tree}" 2>/dev/null || true
  fi
done

# Exec the upstream gateway command supplied via CMD (kept in CMD, not hardcoded here, so it stays
# explicit/overridable). The base image ENTRYPOINT (tini -s --) remains PID 1 for signal handling.
exec "$@"
