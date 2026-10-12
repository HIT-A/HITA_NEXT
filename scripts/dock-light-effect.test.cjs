const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const source = fs.readFileSync(path.join(root, 'common/util/DockLightEffect.ets'), 'utf8');
const output = ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;
const mod = { exports: {} };
const envelopeModule = { exports: {} };
new Function('module', 'exports', ts.transpileModule(
  fs.readFileSync(path.join(root, 'common/util/ImmersiveLightEffect.ets'), 'utf8'),
  { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }
).outputText)(envelopeModule, envelopeModule.exports);
new Function('require', 'module', 'exports', output)(() => envelopeModule.exports, mod, mod.exports);
const { sampleDockFlow, DockLightController, DOCK_FLOW_DURATION_MS, sampleDockHoldLight,
  dockWhiteLightColor, DOCK_TAP_LIGHT_ALPHA, DOCK_HOLD_LIGHT_RAMP_MS } = mod.exports;

test('held white light brightens continuously from tap opacity and settles at its original intensity', () => {
  assert.equal(sampleDockHoldLight(0), DOCK_TAP_LIGHT_ALPHA);
  assert.equal(sampleDockHoldLight(-10), DOCK_TAP_LIGHT_ALPHA);
  let previous = DOCK_TAP_LIGHT_ALPHA;
  for (let elapsed = 1; elapsed <= DOCK_HOLD_LIGHT_RAMP_MS; elapsed++) {
    const alpha = sampleDockHoldLight(elapsed);
    assert.ok(alpha >= previous && alpha <= 1);
    assert.ok(alpha - previous < 0.005, 'no sudden brightness jump');
    assert.match(dockWhiteLightColor(alpha), /^#[0-9a-f]{2}FFFFFF$/);
    previous = alpha;
  }
  assert.equal(sampleDockHoldLight(DOCK_HOLD_LIGHT_RAMP_MS), 1);
  assert.equal(sampleDockHoldLight(10000), 1);
  assert.equal(dockWhiteLightColor(0.35), '#59FFFFFF');
  assert.equal(dockWhiteLightColor(1), '#ffFFFFFF');
});

test('light travels from the previous icon to its target in either direction without overshoot', () => {
  for (const [from, to] of [[0, 1], [0, 2], [2, 0], [2, 1], [1, 0], [1, 2]]) {
    const start = (from + 0.5) * 212 / 3;
    const end = (to + 0.5) * 212 / 3;
    assert.equal(sampleDockFlow(from, to, 0, 212).center, start);
    let previous = start;
    for (let elapsed = 0; elapsed <= DOCK_FLOW_DURATION_MS; elapsed += 10) {
      const sample = sampleDockFlow(from, to, elapsed, 212);
      assert.ok(sample.center >= Math.min(start, end) && sample.center <= Math.max(start, end));
      assert.ok((sample.center - previous) * (to - from) >= 0);
      assert.ok((sample.center - sample.tail) * (to - from) >= 0, 'tail follows the travel direction');
      assert.ok(sample.alpha >= 0 && sample.alpha <= DOCK_TAP_LIGHT_ALPHA, 'short-click light stays subdued');
      previous = sample.center;
    }
    assert.ok(Math.abs(sampleDockFlow(from, to, 360, 212).center - end) < 1e-6);
    assert.equal(sampleDockFlow(from, to, DOCK_FLOW_DURATION_MS, 212).alpha, 0);
    assert.equal(sampleDockFlow(from, to, 10000, 212).alpha, 0);
  }
});

test('light starts transparent, rises smoothly, and fades completely', () => {
  assert.equal(sampleDockFlow(0, 2, 0, 212).alpha, 0);
  assert.ok(sampleDockFlow(0, 2, 45, 212).alpha > sampleDockFlow(0, 2, 15, 212).alpha);
  assert.equal(sampleDockFlow(0, 2, 180, 212).alpha, DOCK_TAP_LIGHT_ALPHA);
  assert.ok(sampleDockFlow(0, 2, 450, 212).alpha < sampleDockFlow(0, 2, 180, 212).alpha);
});

test('same-tab clicks do not flash; lifecycle cleanup cannot unregister a newer light player', () => {
  const controller = new DockLightController();
  const actions = [];
  const first = { transfer: (...indices) => actions.push(['first', ...indices]), stop() {} };
  const second = { transfer: (...indices) => actions.push(['second', ...indices]), stop: () => actions.push(['stop']) };
  controller.register(first);
  controller.transfer(1, 1);
  controller.transfer(-1, 2);
  assert.deepEqual(actions, []);
  controller.transfer(0, 2);
  controller.register(second);
  controller.unregister(first);
  controller.transfer(2, 0);
  controller.stop();
  controller.unregister(second);
  controller.transfer(0, 1);
  assert.deepEqual(actions, [['first', 0, 2], ['second', 2, 0], ['stop']]);
});
