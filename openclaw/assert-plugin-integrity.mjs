// Build-time gate: every registry-sourced plugin install must carry an integrity hash.
// Invoked as `node assert-plugin-integrity.mjs <json>` from the Dockerfile -- no shebang, so it
// does not need the executable bit (see the check-shebang-scripts-are-executable pre-commit hook).
//
// `openclaw status --deep` reports missing hashes as the warn-level finding
// `plugins.installs_missing_integrity`, and there is no command that backfills integrity onto an
// existing record -- the only documented remedy is reinstalling. The gateway runs with a
// read-only rootfs, no registry egress and OPENCLAW_OFFLINE=1, so reinstalling is impossible
// there. Build time is the only place this is fixable, so a miss fails the build rather than
// shipping an image whose supply-chain evidence is silently incomplete.
//
// Deliberately self-diagnosing: `openclaw plugins inspect --all --json` has no schema contract we
// control, so rather than assume a shape this walks the whole document for records that look like
// registry installs. Finding NO such records is treated as a failure too -- a shape change that
// silently matched nothing would otherwise turn this gate into a no-op that always passes.
import { readFileSync } from "node:fs";

const REGISTRY_SOURCES = new Set(["npm", "clawhub", "npm-pack", "marketplace"]);

const inputPath = process.argv[2];
if (!inputPath) {
  console.error("usage: assert-plugin-integrity.mjs <plugins-inspect-json>");
  process.exit(2);
}

let doc;
try {
  doc = JSON.parse(readFileSync(inputPath, "utf8"));
} catch (error) {
  console.error(`ERROR: could not parse plugin inspect JSON: ${error.message}`);
  process.exit(2);
}

// Any object carrying a registry `source` is treated as an install record, wherever it sits in
// the document (top level, nested under `install`, inside a `plugins`/`items` array, ...).
const records = [];
const seen = new Set();
const walk = (node, idHint) => {
  if (!node || typeof node !== "object" || seen.has(node)) {
    return;
  }
  seen.add(node);
  if (Array.isArray(node)) {
    for (const entry of node) {
      walk(entry, idHint);
    }
    return;
  }
  const id = node.id ?? node.pluginId ?? node.name ?? idHint;
  if (typeof node.source === "string" && REGISTRY_SOURCES.has(node.source)) {
    records.push({ id: id ?? "<unknown>", source: node.source, integrity: node.integrity });
  }
  for (const value of Object.values(node)) {
    walk(value, id);
  }
};
walk(doc, undefined);

if (records.length === 0) {
  console.error(
    "ERROR: found no registry-sourced plugin install records in `openclaw plugins inspect --all --json`.",
  );
  console.error(
    "The output shape likely changed, which would make this check silently vacuous. Inspect it and update this script.",
  );
  console.error(`Top-level keys: ${Object.keys(doc ?? {}).join(", ") || "(none)"}`);
  process.exit(1);
}

const missing = records.filter(
  (record) => !(typeof record.integrity === "string" && record.integrity.trim() !== ""),
);

if (missing.length > 0) {
  console.error("ERROR: plugin installs were recorded without an integrity hash:");
  for (const record of missing) {
    console.error(`  - ${record.id} (source: ${record.source})`);
  }
  console.error(
    "\nThese surface as `plugins.installs_missing_integrity` in `openclaw status --deep`,",
  );
  console.error(
    "and cannot be repaired at runtime (read-only rootfs, no registry egress, OPENCLAW_OFFLINE=1).",
  );
  console.error("Check the install source prefix in the Dockerfile (clawhub: vs npm:).");
  process.exit(1);
}

console.log(`OK: ${records.length} plugin install record(s), all carrying an integrity hash:`);
for (const record of records) {
  console.log(`  - ${record.id} (${record.source})`);
}
