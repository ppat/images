// Copies the install records of the image's baked-in plugins from the build-time seed database into
// the state database, so a state dir first populated by an older image ends up with the same records
// a fresh state dir gets from this image. Invoked by docker-entrypoint.sh as
//   node sync-baked-plugin-records.mjs <seed openclaw.sqlite> <state openclaw.sqlite>
// and prints one line per record it wrote; no output means nothing changed.
//
// OpenClaw keeps plugin install records in its state database (config_machine_state row
// `plugins.installedIndex`, JSON at .index.installRecords.<pluginId>), not in files the entrypoint's
// `cp -n` seeding can restore. A plugin newly baked into the image therefore lands on an existing
// state dir with its package but no record, and `openclaw plugins registry --refresh` refuses to
// persist it ("record+install changed; persisted missing"). OpenClaw has no CLI that adopts an
// already-unpacked npm package as an npm install: `plugins install --link` records a path source
// instead, and `plugins install npm:...` downloads again. The row is marked "DO NOT EDIT" because it
// also carries derived registry data; this writes only install records, which are inputs, and the
// entrypoint runs `openclaw plugins registry --refresh` afterwards to rebuild everything derived.
//
// A record is written when the state database has none for that plugin, or when it points at the
// same image-owned package directory but names a different version or integrity -- the entrypoint
// has just replaced that directory with the seed's copy, so the seed's record is the true one.
// Records for any other install path (an operator's own install of the same plugin id) are left
// alone. Anything unexpected in either database's shape makes this a no-op rather than a guess.
import { DatabaseSync } from "node:sqlite";

const KEY = "plugins.installedIndex";
const [seedPath, statePath] = process.argv.slice(2);

function readIndex(db) {
  const row = db.prepare("SELECT value_json FROM config_machine_state WHERE state_key = ?").get(KEY);
  if (!row) return undefined;
  const value = JSON.parse(row.value_json);
  const records = value?.index?.installRecords;
  if (typeof value?.revision !== "number" || !records || typeof records !== "object") {
    throw new Error(`unexpected ${KEY} shape`);
  }
  return value;
}

const seedDb = new DatabaseSync(seedPath, { readOnly: true });
const seed = readIndex(seedDb);
seedDb.close();
if (!seed) process.exit(0);

const db = new DatabaseSync(statePath);
db.exec("PRAGMA busy_timeout = 10000");
db.exec("BEGIN IMMEDIATE");
try {
  const state = readIndex(db);
  if (!state) throw new Error(`no ${KEY} row in ${statePath}`);
  const records = state.index.installRecords;
  const synced = [];
  for (const [id, want] of Object.entries(seed.index.installRecords)) {
    const have = records[id];
    if (have) {
      if (have.installPath !== want.installPath) continue;
      if (have.version === want.version && have.integrity === want.integrity) continue;
    }
    records[id] = want;
    synced.push(`${id} ${have?.version ?? "unrecorded"} -> ${want.version}`);
  }
  if (synced.length > 0) {
    state.revision = Math.max(Date.now(), state.revision + 1);
    db.prepare("UPDATE config_machine_state SET value_json = ?, updated_at_ms = ? WHERE state_key = ?")
      .run(JSON.stringify(state), state.revision, KEY);
  }
  db.exec("COMMIT");
  for (const line of synced) console.log(line);
} catch (error) {
  db.exec("ROLLBACK");
  throw error;
}
