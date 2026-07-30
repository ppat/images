# obsidian

A headless [Obsidian](https://obsidian.md/) image: the stock Electron desktop app running against
a virtual display, with [`obsidian-local-rest-api`](https://github.com/coddingtonbear/obsidian-local-rest-api)
baked in and turned on automatically, so a vault can be read and written over HTTP by something
outside the container while exactly one process (this one) ever touches the vault's files. The
ratified community plugin set — [Tasks](https://github.com/obsidian-tasks-group/obsidian-tasks)
and [Dataview](https://github.com/blacksmithgu/obsidian-dataview), and nothing else — is baked in
alongside it; see "Baked-in community plugins" below.

A VNC server is installed but never started, so an operator can attach to the *same* running
Obsidian instance on demand for the settings that are only reachable through the GUI.

## Why this image is built from scratch

`linuxserver/obsidian` and `sytone/obsidian-remote` both ship a stock Obsidian binary with no
plugins and no vault, on a desktop-streaming base image whose GUI has passwordless `sudo` —
linuxserver's own README says so. This container holds the read-write mount of an authoritative
vault and its GUI is deliberately reachable for configuration and repair, so inheriting a
root-from-the-GUI path is not acceptable. Building on plain `debian:bookworm-slim` also drops
s6-overlay, the start-as-root-then-drop-privileges dance, and a continuously running desktop
stack. The cost is owning the Electron dependency set, which is bounded — it is exactly the
`DT_NEEDED` list of the shipped binary, enumerated in the `Dockerfile`.

Obsidian itself is installed from the per-architecture `.tar.gz` release asset rather than the
AppImage: an AppImage has to be executed (`--appimage-extract`) or FUSE-mounted to unpack, and
executing it would force the `arm64` build under QEMU emulation. The tarball unpacks to the same
tree with neither constraint.

## Auto-trust: why there is a Chrome DevTools Protocol client in here

Obsidian will not load a community plugin until the vault is trusted (Restricted Mode off), and
**that flag is not a file**. It lives in the Electron renderer's `localStorage` under a key
derived from a per-install app id — not in the vault, not in `.obsidian/`, not in
`obsidian.json`. Installing the plugin's files and listing its id in
`.obsidian/community-plugins.json` is necessary but *not sufficient*: the plugin sits there
enabled on paper and never loads, and the REST API never binds.

So the entrypoint starts Obsidian with `--remote-debugging-port=9222 --remote-allow-origins=*`
(Chromium binds that port to `127.0.0.1` only, and it is not `EXPOSE`d), and `auto-trust.py`
attaches over the Chrome DevTools Protocol and calls the same runtime API the GUI's trust toggle
calls — `app.plugins.setEnable(true)`, which turns Restricted Mode off *vault-wide* and is what
lets any plugin already listed in `.obsidian/community-plugins.json` load, Tasks and Dataview
included. `auto-trust.py` additionally calls `enablePluginAndSave` for the Local REST API plugin
specifically and then polls its HTTPS listener, because that plugin is the one thing this design
needs a positive, verified-working guarantee for — it's the only path in from outside the
container. It runs on every start and is idempotent, which also means it self-heals a container
whose `/config` volume was lost or replaced. The technique is the one demonstrated by
[`shanehull/obsidian-remote`](https://github.com/shanehull/obsidian-remote)'s `auto-trust.sh`
(GPL-3.0; referenced for the approach, implemented independently here).

The debugging port stays open for the life of the process. Closing it would mean restarting
Obsidian after trust is established, which would mean a second Obsidian launch and a supervisor
to sequence it — against the one-process design. It is loopback-only inside a single-purpose
container, so the only things that can reach it are the other processes this image starts.

## Baked-in community plugins

The ratified set ([`ppat/images#538`](https://github.com/ppat/images/issues/538)) is **Tasks and
Dataview**, and nothing else:

- **[Tasks](https://github.com/obsidian-tasks-group/obsidian-tasks)** (plugin id
  `obsidian-tasks-plugin`) — inline task tracking: due dates, recurring tasks, done dates,
  filtering.
- **[Dataview](https://github.com/blacksmithgu/obsidian-dataview)** (plugin id `dataview`) — kept
  for one reason: Obsidian's built-in Bases queries cached metadata, not file bodies, so it
  cannot read inline checkbox task lines at all. Dataview covers exactly that gap and is
  removable the day Bases can read task lines natively. It's also, deliberately, a read path this
  image now exposes further than the vault's content model strictly requires: an MCP server
  sitting in front of this container can serve Dataview query-language (DQL) searches, which is a
  welcome capability, not an incidental one — nothing is written to the vault by a query, and the
  "no query engine" requirement in the vault's design is about the vault's *content* staying
  plain and portable, not a ban on a richer read path. The one real residual: Dataview has had no
  commits to `master` since 2025-04-08, so a read path that leans on it leans on a dormant
  plugin — a cost already accepted, since Dataview is retained regardless for inline task queries
  that Bases structurally cannot serve.

**Deliberately excluded** (`ppat/images#538`, `ppat/obsidian-vault#2`): Templater and QuickAdd
(both require Obsidian `>= 1.13.0`, today's beta/insider channel only — this image pins stable
`1.12.7`), Linter and Frontmatter Date Manager (frontmatter normalisation is owned entirely by
the maintenance pass that runs outside the application), a validation plugin such as Propsec (a
second, lossy source of truth competing with the JSON-Schema validator that is the authoritative
gate), and Kanban (publicly seeking maintainers, unmaintained; board views come from Bases
instead). Don't install any of these by hand — that recreates exactly the conflict the ratified
set exists to avoid.

## What the entrypoint does

`docker-entrypoint.sh` runs under `tini` as PID 1 (no s6-overlay, no init supervisor, no `sudo`)
and, as uid 1000:

- **Force-copies every baked-in plugin's code into the vault, on every start, no exceptions.**
  `/vault` and `/config` are external volumes at runtime, so anything baked into those paths
  would be shadowed by the mount; everything baked in lives under `/opt/obsidian-seed` and is
  applied at start. `main.js`/`manifest.json`/`styles.css` are overwritten unconditionally —
  plugin code tracks the image, and copy-if-absent would mean a Renovate version bump never
  reached a vault that had already been started once. A plugin's own state, such as the REST API
  plugin's `data.json` (API key and settings), is never in this list and is never overwritten.
- **Enables plugins differently depending on which one it is.** The Local REST API plugin is
  merged into `.obsidian/community-plugins.json` on *every* start — it's load-bearing, nothing
  outside the container can reach the vault without it, so its enabled state must never be
  allowed to drift. Tasks and Dataview are merged in only the *first* time their plugin directory
  is seeded (i.e. it did not already exist before this start); after that, an operator who
  disables one of them at the GUI has that choice respected on every later restart instead of the
  container silently re-enabling it out from under them. Code and enablement are deliberately
  decoupled for exactly this reason — see `seed_plugin()` in `docker-entrypoint.sh`.
- **Registers the vault** in `${XDG_CONFIG_HOME}/obsidian/obsidian.json` if that file is absent,
  with a vault id derived from the vault path so it is stable if `/config` is lost. This does not
  establish trust; it only makes Obsidian open the vault instead of the vault picker.
- **Pins the REST API key** from `OBSIDIAN_API_KEY` if that variable is set (see below), then
  `chmod 0600`s `data.json` on every start — a Kubernetes `fsGroup` mount re-adds group `rw` to
  every existing file before the container starts, so a one-off `chmod` would not survive.
- **Binds the REST API listeners to all interfaces** (`bindingHost: "0.0.0.0"` in `data.json`,
  merged in the same way as the API key) instead of the plugin's own default of `127.0.0.1`.
  Loopback-only is right for the desktop use case the plugin was built for, but wrong for a
  container whose only purpose is to be reached from outside itself — see "Health" below for why
  this is load-bearing, not just a convenience.
- **Starts `Xvfb`** on `$DISPLAY` and waits for its socket.
- **Starts `auto-trust.py`** in the background (it polls, so starting it before Obsidian is fine).
- **`exec`s Obsidian**, which becomes the container's long-running process.

`umask 0027`: files this container creates are owner read-write, `fsGroup` read-only, nothing for
world. Group-**read** rather than group-write is deliberate — a sidecar sharing the volume (a git
syncer, say) can read and commit, but the single-writer invariant stays structurally enforced.

## Configuration

| variable | default | purpose |
| --- | --- | --- |
| `OBSIDIAN_VAULT_DIR` | `/vault` | vault to open; mount the vault volume here |
| `XDG_CONFIG_HOME` | `/config` | Electron `userData`; holds `obsidian.json` and the `localStorage` LevelDB that records the trust flag |
| `OBSIDIAN_API_KEY` | *(unset)* | pins the REST API key instead of letting the plugin generate a random one; unset means the plugin owns its own key |
| `OBSIDIAN_SCREEN_GEOMETRY` | `1920x1080x24` | `Xvfb` screen geometry |
| `DISPLAY` | `:99` | X display for both Obsidian and an on-demand `x11vnc` |
| `OBSIDIAN_CDP_PORT` | `9222` | loopback DevTools port used by auto-trust |

`/config` should be persisted. Everything still works if it is not — auto-trust re-runs — but
application settings and the trust flag are re-established from scratch on every start.

`/home/obsidian` (Electron cache) and `/tmp` (X11 socket, Chromium shared memory) must be
writable; with a read-only root filesystem, give both an `emptyDir`.

## Health

Port `27124` is the plugin's HTTPS listener, with a self-signed certificate the plugin generates
itself. Its root endpoint answers without authentication, and it only binds once the vault is
open *and* trusted *and* the plugin has loaded — so it is a far better readiness signal than the
process existing:

```yaml
readinessProbe:
  httpGet:
    scheme: HTTPS
    port: 27124
    path: /
```

`httpGet` with `scheme: HTTPS` does not verify the certificate, so the self-signed cert is fine.
The plaintext listener on `27123` is left disabled — the plugin defaults it off and nothing here
needs it.

This only works because the entrypoint forces the plugin's `bindingHost` to `0.0.0.0` (see above):
`kubelet` connects to the pod IP, never to loopback, so a `startupProbe`/`readinessProbe`/
`livenessProbe` against `27124` on a loopback-bound listener fails every attempt — the startup
probe exhausts its budget and liveness then restarts the container in a loop, never reaching
`Running`. The same bind is what lets anything else reach the plugin over the pod network at all,
including MCP server pods proxying this API from a different node. Binding wider than loopback is
not the security boundary for this API and was never meant to be one: that boundary is the
`Service` being `ClusterIP` with no ingress, a `NetworkPolicy` admitting only the intended peers,
and the plugin still requiring its bearer token on every request regardless of which interface the
request arrived on.

## GUI access

The GUI is for the handful of settings that are only reachable through it — property types,
default location for new notes, attachment folder, daily-note format, template folder — and for
repair. It is off by default and attaches to the *already running* Obsidian process; there is no
second entrypoint mode and no second deployment, because two Obsidian processes against one vault
would break the single-writer invariant.

1. Start `x11vnc` against the display Obsidian is already using:

    ```bash
    kubectl exec -it deploy/<deployment> -c obsidian -- \
      x11vnc -display :99 -localhost -rfbport 5900 -nopw -shared -forever
    ```

    `-localhost` binds `127.0.0.1` only. `-nopw` is safe *because of* `-localhost`: the port is
    reachable only from inside the pod's network namespace, which is exactly what
    `kubectl port-forward` connects to. Nothing on the cluster network can reach it.

2. In another terminal, forward the port:

    ```bash
    kubectl port-forward deploy/<deployment> 5900:5900
    ```

3. Point a VNC viewer at `localhost:5900`.

4. When finished, stop `x11vnc` with `Ctrl-C` in the `kubectl exec` terminal. Obsidian keeps
   running; only the viewer goes away.

## Expected startup log noise

Three lines show up on every boot that look like failures and are not — the boot chain completes
past all of them, so treat any of the three, alone, as expected rather than as something to chase:

- `_XSERVTransmkdir: Owner of /tmp/.X11-unix should be set to root` — `Xvfb` wants that directory
  root-owned; this container runs as uid 1000 with `/tmp` as an `emptyDir`. Warning only, the X11
  socket is still created (the entrypoint waits on it and would `die` if it were not).
- `Failed to connect to the bus: ... /run/dbus/system_bus_socket` — Electron/Chromium probing the
  system D-Bus for desktop integration (notifications, power/screensaver inhibition, and the
  Secret Service keyring API). There is no D-Bus daemon in this image and none is needed for a
  headless vault.
- `LaunchProcess: failed to execvp: xdg-settings` — Chromium checking default-browser association,
  which is meaningless for this container.

Related to the D-Bus line: this image installs `libsecret-1-0` (Chromium's Secret Service /
GNOME-keyring backend for its `safeStorage` API), but it is `dlopen()`ed by soname at runtime, not
a link-time dependency — confirmed by inspecting the shipped Electron binary: `readelf -d obsidian`
lists no `libsecret` `NEEDED` entry, while `strings obsidian` contains
`key_storage_libsecret.cc`, `chrome_libsecret_os_crypt_password_v2`, and the literal fallback
message `Could not load libsecret-1.so.0:`. With no D-Bus daemon here, that dlopen always fails and
the keyring backend silently degrades — harmless today, since Obsidian Sync is unused and the REST
API key arrives via `OBSIDIAN_API_KEY`/`data.json` rather than the OS keyring, but it is the first
place a future plugin that wants OS-level credential storage would fail silently.

## Architectures

`linux/amd64` and `linux/arm64`. Both the Obsidian tarball and the plugin's release assets are
fetched and unpacked in a `--platform=$BUILDPLATFORM` builder stage, so the `arm64` image is
assembled without QEMU emulating anything — only `apt-get install` runs under emulation.
