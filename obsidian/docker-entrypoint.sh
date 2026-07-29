#!/bin/bash
set -eo pipefail

# Files this process creates land 0640/0750: owner (uid 1000, the only writer) read-write, the
# pod's fsGroup read-only, nothing for world. Group-read rather than group-write is deliberate
# and load-bearing -- the design's cardinal invariant is that exactly one process ever writes the
# vault's files, so a sidecar sharing the volume can read/commit but cannot author. umask alone
# isn't enough on a Kubernetes fsGroup-mounted PVC: the kubelet re-applies group rw to every
# EXISTING file at each mount, before this container starts, so anything persisted from a prior
# boot comes back group-writable. That's harmless for notes but not for the plugin's data.json,
# which holds the REST API key -- the explicit chmod further down re-tightens it every start.
umask 0027

VAULT_DIR="${OBSIDIAN_VAULT_DIR:-/vault}"
CONFIG_DIR="${XDG_CONFIG_HOME:-/config}"
PLUGIN_ID="${OBSIDIAN_PLUGIN_ID:-obsidian-local-rest-api}"
GEOMETRY="${OBSIDIAN_SCREEN_GEOMETRY:-1920x1080x24}"
CDP_PORT="${OBSIDIAN_CDP_PORT:-9222}"

SEED_PLUGIN_DIR="/opt/obsidian-seed/plugins/${PLUGIN_ID}"
VAULT_PLUGIN_DIR="${VAULT_DIR}/.obsidian/plugins/${PLUGIN_ID}"
ELECTRON_CONFIG_DIR="${CONFIG_DIR}/obsidian"

log() {
  echo "docker-entrypoint: $*"
}

die() {
  echo "docker-entrypoint: $*" >&2
  exit 1
}

# ----------------------------------------------------------------------------------------------
# Vault and plugin seeding
#
# At runtime both ${VAULT_DIR} and ${CONFIG_DIR} are external volumes mounted over whatever the
# image put there, so nothing plugin-related can simply be baked into its final location -- the
# mount would shadow it. Everything baked in lives under /opt/obsidian-seed and is applied here.
# ----------------------------------------------------------------------------------------------
mkdir -p "${VAULT_PLUGIN_DIR}" "${ELECTRON_CONFIG_DIR}" \
  || die "cannot write to ${VAULT_DIR} / ${CONFIG_DIR}; both must be writable by uid $(id -u)"

# Plugin code tracks the IMAGE, not the volume, so this overwrites unconditionally. This is a
# deliberate departure from the copy-if-absent seeding the openclaw image uses: main.js/
# manifest.json/styles.css are build artifacts pinned by a Renovate-tracked version in the
# Dockerfile, and copy-if-absent would mean a plugin version bump never actually reached any
# vault that had already been started once. The plugin's own state -- data.json, which holds the
# generated API key and settings -- is NOT in this list and is never overwritten.
install -m 0640 \
  "${SEED_PLUGIN_DIR}/main.js" \
  "${SEED_PLUGIN_DIR}/manifest.json" \
  "${SEED_PLUGIN_DIR}/styles.css" \
  "${VAULT_PLUGIN_DIR}/" \
  || die "failed to install the ${PLUGIN_ID} plugin into ${VAULT_PLUGIN_DIR}"
log "installed ${PLUGIN_ID} $(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' \
  "${VAULT_PLUGIN_DIR}/manifest.json") into ${VAULT_PLUGIN_DIR}"

# Obsidian reads the set of enabled community plugins from this file. Merge rather than write:
# an operator may have enabled other plugins through the GUI and we must not drop them.
python3 - "${VAULT_DIR}/.obsidian/community-plugins.json" "${PLUGIN_ID}" <<'PY'
import json
import os
import sys

path, plugin_id = sys.argv[1], sys.argv[2]
try:
    with open(path) as handle:
        plugins = json.load(handle)
    if not isinstance(plugins, list):
        plugins = []
except (OSError, ValueError):
    plugins = []

if plugin_id not in plugins:
    plugins.append(plugin_id)
    with open(path, "w") as handle:
        json.dump(plugins, handle, indent=2)
    print("docker-entrypoint: added %s to %s" % (plugin_id, os.path.basename(path)))
PY

# obsidian.json is Electron-side (not vault-side) state listing the vaults Obsidian knows about.
# Written only when absent, so anything an operator does in the GUI afterwards wins. The vault id
# is derived from the path rather than random so it stays stable if ${CONFIG_DIR} is ever lost.
# Note this file does NOT establish trust -- the Restricted Mode flag lives in the renderer's
# localStorage and is dealt with by auto-trust.py. This only makes Obsidian open the vault.
OBSIDIAN_JSON="${ELECTRON_CONFIG_DIR}/obsidian.json"
if [[ ! -e "${OBSIDIAN_JSON}" ]]; then
  VAULT_ID="$(printf '%s' "${VAULT_DIR}" | md5sum | cut -c1-16)"
  printf '{"vaults":{"%s":{"path":"%s","ts":%s,"open":true}}}\n' \
    "${VAULT_ID}" "${VAULT_DIR}" "$(date +%s%3N)" > "${OBSIDIAN_JSON}"
  log "registered ${VAULT_DIR} as vault ${VAULT_ID} in ${OBSIDIAN_JSON}"
fi

# The plugin generates a random API key the first time it's enabled, which leaves the key
# discoverable only by exec-ing into a running container -- awkward to wire a client up to
# declaratively. Setting OBSIDIAN_API_KEY (e.g. from a Kubernetes Secret) pins it instead. Opt-in:
# unset, the plugin keeps generating and owning its own key. Merged into any existing data.json so
# settings an operator changed in the GUI survive.
DATA_JSON="${VAULT_PLUGIN_DIR}/data.json"
if [[ -n "${OBSIDIAN_API_KEY}" ]]; then
  python3 - "${DATA_JSON}" <<'PY'
import json
import os
import sys

path = sys.argv[1]
try:
    with open(path) as handle:
        settings = json.load(handle)
    if not isinstance(settings, dict):
        settings = {}
except (OSError, ValueError):
    settings = {}

if settings.get("apiKey") != os.environ["OBSIDIAN_API_KEY"]:
    settings["apiKey"] = os.environ["OBSIDIAN_API_KEY"]
    with open(path, "w") as handle:
        json.dump(settings, handle, indent=2)
    print("docker-entrypoint: set the REST API key from OBSIDIAN_API_KEY")
PY
fi

# Re-tighten after the kubelet's fsGroup mount re-added group rw to it (see the umask comment).
# A one-off manual chmod would be undone by the next mount; doing it on every start is what makes
# it stick.
if [[ -e "${DATA_JSON}" ]]; then
  chmod 0600 "${DATA_JSON}" || log "could not chmod ${DATA_JSON}"
fi

# ----------------------------------------------------------------------------------------------
# Virtual display
#
# Obsidian is an Electron app; it has no headless mode and will not start without an X display.
# Xvfb provides one that nothing is attached to. x11vnc is installed in the image but is NOT
# started here -- an operator attaches it to this same display on demand (see README).
# ----------------------------------------------------------------------------------------------
Xvfb "${DISPLAY}" -screen 0 "${GEOMETRY}" -nolisten tcp &
log "started Xvfb on ${DISPLAY} (${GEOMETRY})"

X_SOCKET="/tmp/.X11-unix/X${DISPLAY#:}"
for _ in $(seq 1 30); do
  [[ -S "${X_SOCKET}" ]] && break
  sleep 1
done
[[ -S "${X_SOCKET}" ]] || die "Xvfb did not create ${X_SOCKET}; is /tmp writable?"

# Runs concurrently with Obsidian because it has to: it drives the running renderer over CDP and
# there is nothing to attach to until Obsidian is up. It polls, so starting it first is safe.
# tini (PID 1) reaps it once Obsidian is exec'd below and this shell is replaced.
/usr/local/bin/auto-trust.py &

# --no-sandbox: Chromium's setuid sandbox needs either a setuid helper binary or user namespaces,
#   neither of which is available to an unprivileged uid in a locked-down pod.
# --disable-dev-shm-usage: containers get a 64MB /dev/shm by default and Chromium crashes when it
#   runs out; this makes it use /tmp instead.
# --disable-gpu: there is no GPU and no DRM device here; without this Electron spends startup
#   probing for one and falling back anyway.
# --remote-debugging-port / --remote-allow-origins: the auto-trust mechanism. See auto-trust.py
#   for why turning Restricted Mode off requires driving the renderer. Chromium binds this port
#   to 127.0.0.1 only and it is not EXPOSEd, so it is reachable only from inside this container.
# The vault path is passed as an argument as well as being registered in obsidian.json above --
# either alone is usually enough, together they make "the vault is open" not depend on which.
exec /opt/obsidian/obsidian \
  --no-sandbox \
  --disable-dev-shm-usage \
  --disable-gpu \
  --remote-debugging-port="${CDP_PORT}" \
  --remote-allow-origins='*' \
  "${VAULT_DIR}"
