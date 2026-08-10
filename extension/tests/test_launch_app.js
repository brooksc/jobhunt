const test = require("node:test");
const assert = require("node:assert");
const jobhuntLaunch = require("../launch_app.js");

/** Storage double with the two methods the module uses. */
function fakeStorage(initial = {}) {
  const data = { ...initial };
  return {
    data,
    async get(key) {
      return key in data ? { [key]: data[key] } : {};
    },
    async set(values) {
      Object.assign(data, values);
    },
  };
}

test("auto-launch is off unless explicitly enabled", async () => {
  // Launching an app is not something to do behind someone's back.
  assert.equal(await jobhuntLaunch.isEnabled(fakeStorage()), false);
  assert.equal(await jobhuntLaunch.isEnabled(fakeStorage({ [jobhuntLaunch.ENABLED_KEY]: false })), false);
  // A non-boolean stored value must not read as enabled.
  assert.equal(await jobhuntLaunch.isEnabled(fakeStorage({ [jobhuntLaunch.ENABLED_KEY]: "yes" })), false);
});

test("the toggle round-trips", async () => {
  const storage = fakeStorage();
  await jobhuntLaunch.setEnabled(storage, true);
  assert.equal(await jobhuntLaunch.isEnabled(storage), true);
  await jobhuntLaunch.setEnabled(storage, false);
  assert.equal(await jobhuntLaunch.isEnabled(storage), false);
});

test("an already-running app is not launched again", async () => {
  // Firing the scheme anyway would raise Chrome's confirmation prompt for nothing.
  let opened = 0;
  const result = await jobhuntLaunch.launchAndWait({
    openURL: async () => { opened += 1; },
    isServerReady: async () => true,
    sleep: async () => {},
    now: () => 0,
    lastAttemptAt: 0,
  });
  assert.equal(opened, 0);
  assert.deepEqual(result, { launched: false, ready: true });
});

test("launches and reports ready once the server answers", async () => {
  let opened = null;
  let polls = 0;
  const result = await jobhuntLaunch.launchAndWait({
    openURL: async (url) => { opened = url; },
    isServerReady: async () => {
      polls += 1;
      return polls > 3; // first call is the pre-check, then it comes up
    },
    sleep: async () => {},
    now: () => 0,
    lastAttemptAt: 0,
  });
  assert.equal(opened, jobhuntLaunch.LAUNCH_URL);
  assert.equal(result.ready, true);
  assert.equal(result.launched, true);
});

test("gives up after the timeout without treating it as an error", async () => {
  // The capture is already queued; a failed launch just means it flushes later, as before.
  let clock = 0;
  const result = await jobhuntLaunch.launchAndWait({
    openURL: async () => {},
    isServerReady: async () => false,
    sleep: async (ms) => { clock += ms; },
    now: () => clock,
    lastAttemptAt: null,
  });
  assert.equal(result.launched, true);
  assert.equal(result.ready, false);
  assert.equal(result.reason, "timeout");
});

test("a burst of captures only prompts once", () => {
  // Without the cooldown, capturing three jobs while the app is closed fires three jobhunt:// opens
  // and Chrome shows its external-protocol prompt for each one.
  const start = 1_000_000;
  assert.equal(jobhuntLaunch.canAttempt(start, start + 1000), false);
  assert.equal(jobhuntLaunch.canAttempt(start, start + jobhuntLaunch.RELAUNCH_COOLDOWN_MS), true);
  // Never attempted yet.
  assert.equal(jobhuntLaunch.canAttempt(null, start), true);
  assert.equal(jobhuntLaunch.canAttempt(0, start), true);
});

test("respects the cooldown inside launchAndWait", async () => {
  let opened = 0;
  const result = await jobhuntLaunch.launchAndWait({
    openURL: async () => { opened += 1; },
    isServerReady: async () => false,
    sleep: async () => {},
    now: () => 1000,
    lastAttemptAt: 900,
  });
  assert.equal(opened, 0);
  assert.equal(result.reason, "cooldown");
});

test("a failed open is reported rather than thrown", async () => {
  // Chrome can refuse the protocol handler; the capture stays queued and the user sees no crash.
  const result = await jobhuntLaunch.launchAndWait({
    openURL: async () => { throw new Error("no handler"); },
    isServerReady: async () => false,
    sleep: async () => {},
    now: () => 0,
    lastAttemptAt: null,
  });
  assert.equal(result.launched, false);
  assert.equal(result.ready, false);
  assert.match(result.reason, /no handler/);
});

test("the launch URL carries no capture data", () => {
  // A capture can be several MB; URLs can't. The scheme starts the app and nothing else.
  assert.equal(jobhuntLaunch.LAUNCH_URL, "jobhunt://launch");
  assert.ok(!jobhuntLaunch.LAUNCH_URL.includes("?"));
});
