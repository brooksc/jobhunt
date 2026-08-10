const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");

const dir = path.join(__dirname, "..");
const chrome = JSON.parse(fs.readFileSync(path.join(dir, "manifest.json"), "utf8"));
const firefox = JSON.parse(fs.readFileSync(path.join(dir, "manifest.firefox.json"), "utf8"));

/** The Firefox port (TASK-619): one shared codebase, two manifests that must not drift. */

test("versions match across browsers", () => {
  // Two browsers on different versions makes every future bug report ambiguous.
  assert.equal(firefox.version, chrome.version);
});

test("permissions are identical", () => {
  // Least privilege, and the same privilege: a Firefox build quietly asking for more than the
  // Chrome one is how a review gets rejected and how a user gets surprised.
  assert.deepEqual(firefox.permissions, chrome.permissions);
  assert.deepEqual(firefox.host_permissions, chrome.host_permissions);
});

test("Firefox uses an event page, not a service worker", () => {
  // Firefox MV3 has no background.service_worker; using one silently produces a dead background.
  assert.ok(!("service_worker" in firefox.background));
  assert.deepEqual(firefox.background.scripts, ["service_worker.js"]);
});

test("Firefox declares a stable add-on identity", () => {
  const gecko = firefox.browser_specific_settings && firefox.browser_specific_settings.gecko;
  assert.ok(gecko, "browser_specific_settings.gecko is required for AMO");
  assert.match(gecko.id, /@/);
  assert.ok(gecko.strict_min_version);
});

test("Chrome's key is not carried into the Firefox manifest", () => {
  // `key` pins the unpacked *Chrome* id and means nothing to Firefox; leaving it in is noise in a
  // published artifact.
  assert.ok(!("key" in firefox));
  assert.ok("key" in chrome, "the Chrome manifest still pins the dev id");
});

test("both manifests ship the same icons and commands", () => {
  assert.deepEqual(firefox.icons, chrome.icons);
  assert.deepEqual(firefox.commands, chrome.commands);
});
