#!/usr/bin/env python3
"""Turn Obsidian's Restricted Mode off from outside the GUI, then wait for the REST API.

Why this exists, because it will look bizarre otherwise
------------------------------------------------------
Obsidian will not load a community plugin until the vault is "trusted" (Restricted Mode off).
That flag is NOT a file: it lives in the Electron renderer's localStorage, under a key derived
from a per-install app id. It is not in the vault, not in `.obsidian/`, and not in
`obsidian.json`. So copying the plugin's `main.js`/`manifest.json` into
`.obsidian/plugins/<id>/` and listing the id in `.obsidian/community-plugins.json` -- which the
entrypoint does, and which is necessary -- is not sufficient. Without the step below the plugin
sits on disk, enabled on paper, and never loads; the REST API never binds; nothing works.

The only known headless way to flip it is to talk to the running renderer. Obsidian is Electron,
so the entrypoint starts it with `--remote-debugging-port=9222 --remote-allow-origins=*`
(Chromium binds that port to 127.0.0.1 only), and this script attaches over the Chrome DevTools
Protocol and calls the exact same runtime API the GUI's own trust toggle calls:
`app.plugins.setEnable(true)`. The technique is the one demonstrated by
shanehull/obsidian-remote's `auto-trust.sh` (GPL-3.0 -- referenced for the approach, implemented
independently here).

This is idempotent by construction: `setEnable(true)` on an already-trusted vault is a no-op, and
the plugin is only enabled if it isn't already. It therefore runs unconditionally on every start,
which also means it self-heals a vault whose `/config` volume was lost or replaced.
"""

import json
import os
import ssl
import sys
import time
import urllib.error
import urllib.request

import websocket

CDP_URL = os.environ.get("OBSIDIAN_CDP_URL", "http://127.0.0.1:9222")
REST_API_URL = os.environ.get("OBSIDIAN_REST_API_URL", "https://127.0.0.1:27124/")
PLUGIN_ID = os.environ.get("OBSIDIAN_PLUGIN_ID", "obsidian-local-rest-api")

CDP_WAIT_SECONDS = int(os.environ.get("OBSIDIAN_CDP_WAIT_SECONDS", "120"))
APP_WAIT_SECONDS = int(os.environ.get("OBSIDIAN_APP_WAIT_SECONDS", "120"))
REST_API_WAIT_SECONDS = int(os.environ.get("OBSIDIAN_REST_API_WAIT_SECONDS", "120"))

# Enable community plugins (== turn Restricted Mode off), then make sure our specific plugin is
# on. `enablePluginAndSave` also rewrites .obsidian/community-plugins.json, so the two sources of
# truth stay consistent even if an operator edited one of them by hand. The modal close at the
# end dismisses Obsidian's "this vault contains community plugins" dialog if it appeared, so an
# operator opening the GUI later doesn't land on a stale dialog. It clicks the *close* control,
# never a confirm button -- blind-clicking modal buttons in someone's vault is not acceptable.
ENABLE_EXPRESSION = """
(async () => {
    const id = %s;
    await app.plugins.setEnable(true);
    if (!app.plugins.enabledPlugins.has(id)) {
        await app.plugins.enablePluginAndSave(id);
    }
    document.querySelectorAll('.modal-close-button').forEach((b) => b.click());
    return JSON.stringify({
        enabled: Array.from(app.plugins.enabledPlugins),
        loaded: Object.keys(app.plugins.plugins),
    });
})()
""" % json.dumps(PLUGIN_ID)


def log(message):
    print("auto-trust: %s" % message, flush=True)


def fail(message):
    print("auto-trust: %s" % message, file=sys.stderr, flush=True)
    sys.exit(1)


def http_get_json(url, timeout=5):
    with urllib.request.urlopen(url, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8"))


def wait_for_renderer_target():
    """Return the WebSocket debugger URL of Obsidian's renderer page."""
    deadline = time.monotonic() + CDP_WAIT_SECONDS
    last_error = "no page target"
    while time.monotonic() < deadline:
        try:
            targets = http_get_json("%s/json/list" % CDP_URL)
            # Obsidian's renderer is served from app://obsidian.md/index.html. Match on that
            # rather than taking the first page, so a devtools/about:blank target can't win.
            for target in targets:
                if target.get("type") == "page" and "obsidian.md" in target.get("url", ""):
                    return target["webSocketDebuggerUrl"]
        except (urllib.error.URLError, OSError, ValueError) as error:
            last_error = repr(error)
        time.sleep(2)
    fail("timed out after %ss waiting for the Obsidian renderer on CDP (%s)" % (CDP_WAIT_SECONDS, last_error))


class CdpSession:
    def __init__(self, ws_url):
        # suppress_origin: Chromium rejects a DevTools WebSocket carrying a non-null Origin
        # unless --remote-allow-origins matches it. The entrypoint passes `*`, but not sending an
        # Origin at all keeps this working even if that flag is ever tightened.
        self._ws = websocket.create_connection(ws_url, timeout=30, suppress_origin=True)
        self._seq = 0

    def evaluate(self, expression):
        self._seq += 1
        request_id = self._seq
        self._ws.send(json.dumps({
            "id": request_id,
            "method": "Runtime.evaluate",
            "params": {"expression": expression, "awaitPromise": True, "returnByValue": True},
        }))
        # Responses are interleaved with unsolicited protocol events; keep reading until ours.
        while True:
            message = json.loads(self._ws.recv())
            if message.get("id") == request_id:
                return message

    def close(self):
        try:
            self._ws.close()
        except OSError:
            pass


def evaluated_value(message):
    if "error" in message:
        raise RuntimeError("CDP error: %s" % message["error"])
    result = message.get("result", {})
    if "exceptionDetails" in result:
        raise RuntimeError("evaluation threw: %s" % result["exceptionDetails"])
    return result.get("result", {}).get("value")


def wait_for_app(session):
    deadline = time.monotonic() + APP_WAIT_SECONDS
    while time.monotonic() < deadline:
        # `app` only exists once the vault (not the vault picker) is open, which is the point at
        # which app.plugins is real. Poll rather than sleeping a fixed amount: vault open time
        # scales with vault size and with how contended the node is.
        ready = evaluated_value(session.evaluate("typeof app !== 'undefined' && !!app.plugins && !!app.vault"))
        if ready is True:
            return
        time.sleep(2)
    fail("timed out after %ss waiting for the Obsidian app object (is the vault open?)" % APP_WAIT_SECONDS)


def wait_for_rest_api():
    """The REST API answering is the only real proof this worked end to end."""
    # The plugin generates its own self-signed certificate, so verification is meaningless here
    # and the connection never leaves the loopback interface.
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE

    deadline = time.monotonic() + REST_API_WAIT_SECONDS
    last_error = "never answered"
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(REST_API_URL, timeout=5, context=context) as response:
                log("REST API is up (%s -> HTTP %s)" % (REST_API_URL, response.status))
                return
        except urllib.error.HTTPError as error:
            # Any HTTP status means the listener is bound and serving, which is what we're after.
            log("REST API is up (%s -> HTTP %s)" % (REST_API_URL, error.code))
            return
        except (urllib.error.URLError, OSError) as error:
            last_error = repr(error)
        time.sleep(2)
    fail("timed out after %ss waiting for the REST API on %s (%s)" % (REST_API_WAIT_SECONDS, REST_API_URL, last_error))


def main():
    log("waiting for the Obsidian renderer on %s" % CDP_URL)
    ws_url = wait_for_renderer_target()

    session = CdpSession(ws_url)
    try:
        wait_for_app(session)
        log("enabling community plugins and %s" % PLUGIN_ID)
        state = evaluated_value(session.evaluate(ENABLE_EXPRESSION))
        log("plugin state: %s" % state)
    except RuntimeError as error:
        fail(str(error))
    finally:
        session.close()

    wait_for_rest_api()
    log("done")


if __name__ == "__main__":
    main()
