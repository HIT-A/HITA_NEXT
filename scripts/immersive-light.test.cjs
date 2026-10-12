const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = relative => fs.readFileSync(path.join(root, relative), 'utf8');
const compile = source => ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;
const envelopeModule = { exports: {} };
new Function('module', 'exports', compile(read('common/util/ImmersiveLightEffect.ets')))(
  envelopeModule, envelopeModule.exports);
const { ImmersiveLightEnvelope: Envelope, IMMERSIVE_TAP_ALPHA: tap,
  IMMERSIVE_TAP_RISE_MS: rise, IMMERSIVE_RELEASE_MS: fade,
  IMMERSIVE_HOLD_DELAY_MS: hold, IMMERSIVE_HOLD_RAMP_MS: ramp } = envelopeModule.exports;

test('quick taps complete a smooth subdued rise, then a slower fall, even when released immediately', () => {
  for (const duration of [0, 16, 60, 120, 179]) {
    const light = new Envelope();
    light.press(1000);
    light.release(1000 + duration);
    let previous = 0;
    for (let t = 0; t <= rise + fade; t++) {
      const alpha = light.sample(1000 + t);
      assert.ok(alpha >= 0 && alpha <= tap);
      assert.ok(Math.abs(alpha - previous) < 0.003, 'tap brightness cannot jump');
      if (t <= rise) assert.ok(alpha >= previous, 'finish brightening after a quick release');
      else assert.ok(alpha <= previous, 'fade without a second flash');
      previous = alpha;
    }
    assert.equal(light.sample(1000), 0);
    assert.equal(light.sample(1000 + rise), tap);
    assert.equal(light.sample(1000 + rise + fade), 0);
    assert.equal(light.needsFrame(1000 + rise + fade), false);
  }
});

test('holds rise continuously through the tap peak to full brightness and release without a step', () => {
  const light = new Envelope();
  light.press(0);
  let previous = 0;
  for (let t = 0; t <= hold + ramp; t++) {
    const alpha = light.sample(t);
    assert.ok(alpha >= previous && alpha <= 1);
    assert.ok(alpha - previous < 0.0031);
    previous = alpha;
  }
  assert.equal(light.sample(hold), tap);
  assert.equal(light.sample(hold + ramp), 1);
  assert.equal(light.sample(5000), 1);
  light.release(5000);
  assert.equal(light.sample(5000), 1);
  assert.ok(light.sample(5000 + fade / 2) > 0 && light.sample(5000 + fade / 2) < 1);
  assert.equal(light.sample(5000 + fade), 0);
});

test('cancellation fades from the sampled intensity and retouching cannot jump or restart a stale ramp', () => {
  for (const releasedAt of [30, 179, 240, 500, 900]) {
    const light = new Envelope();
    light.press(0);
    const atRelease = light.sample(releasedAt);
    light.release(releasedAt, true);
    assert.equal(light.sample(releasedAt), atRelease);
    assert.ok(light.sample(releasedAt + 60) < atRelease);
    const beforeRetouch = light.sample(releasedAt + 60);
    light.press(releasedAt + 60);
    assert.equal(light.sample(releasedAt + 60), beforeRetouch);
    light.release(releasedAt + 90, true);
    assert.equal(light.sample(releasedAt + 90 + fade), 0);
    light.reset();
    assert.equal(light.sample(10000), 0);
    assert.equal(light.needsFrame(10000), false);
  }
});

function feedbackHarness() {
  let now = 1000;
  let nextTimer = 0;
  const timers = new Map();
  const advance = elapsed => {
    const end = now + elapsed;
    while (true) {
      const next = [...timers].filter(([, value]) => value.due <= end)
        .sort((a, b) => a[1].due - b[1].due)[0];
      if (!next) break;
      now = next[1].due;
      timers.delete(next[0]);
      next[1].callback();
    }
    now = end;
  };
  const gradients = [];
  const paints = [];
  const clips = [];
  const drawing = {
    Brush: class { setAntiAlias() {} setShaderEffect(shader) { this.shader = shader; } },
    ShaderEffect: { createRadialGradient(...args) { gradients.push(args); return args; } },
    RoundRect: class { constructor(rect, x, y) { Object.assign(this, { rect, x, y }); } },
    ClipOp: { INTERSECT: 'intersect' }, TileMode: { CLAMP: 'clamp' }
  };
  const TouchType = { Down: 0, Up: 1, Move: 2, Cancel: 3 };
  const mod = { exports: {} };
  new Function('require', 'module', 'exports', 'DrawModifier', 'TouchType', 'Date',
    'setTimeout', 'clearTimeout', compile(read('common/theme/ImmersiveLightFeedback.ets')))(
    name => {
      if (name === '@kit.ArkUI') return { uiMaterial: { isImmersiveMaterialSupported: () => true } };
      if (name === '@kit.ArkGraphics2D') return { drawing };
      if (name === '@kit.BasicServicesKit') return { Available: () => value => value };
      return envelopeModule.exports;
    }, mod, mod.exports, class { invalidate() {} }, TouchType, { now: () => now },
    (callback, delay) => { timers.set(++nextTimer, { callback, due: now + delay }); return nextTimer; },
    id => timers.delete(id));
  const node = () => ({
    drawModifier(draw) { this.draw = draw; },
    onTouch(callback) { this.touch = callback; },
    onDetach(callback) { this.detach = callback; },
    onVisibleAreaChange(_ratios, callback) { this.visible = callback; },
    onClick() { assert.fail('light must not replace the action'); }
  });
  const render = instance => {
    instance.draw.drawForeground({
      size: { width: 100, height: 44 }, sizeInPixel: { width: 300, height: 132 },
      canvas: { save() {}, restore() {}, clipRoundRect: clip => clips.push(clip),
        attachBrush: brush => paints.push(brush), drawRect() {}, detachBrush() {} }
    });
  };
  let sequence = 0;
  const event = (type, points = [{ id: 1, x: 30, y: 20 }]) => ({
    type, timestamp: ++sequence, touches: type === TouchType.Up || type === TouchType.Cancel ? [] : points,
    stopPropagation() { assert.fail('light must not block bubbling'); }
  });
  return { Feedback: mod.exports.ImmersiveLightFeedback, node, event, render, TouchType,
    advance, timers, paints, clips, gradients };
}

test('the drawing layer is white, density-correct, clipped, reusable across rerenders and finite after release', () => {
  const h = feedbackHarness();
  const instance = h.node();
  h.Feedback.apply(instance, 12);
  const original = instance.draw;
  instance.touch(h.event(h.TouchType.Down));
  h.advance(80);
  h.Feedback.apply(instance, 12);
  assert.equal(instance.draw, original, 'selection rerenders must not replace the active light');
  instance.touch(h.event(h.TouchType.Up));
  h.advance(100);
  h.render(instance);
  const gradient = h.gradients.at(-1);
  assert.deepEqual(gradient[0], { x: 90, y: 60 });
  assert.equal(gradient[1], 135);
  assert.ok(gradient[2].every(color => (color & 0xFFFFFF) === 0xFFFFFF));
  assert.ok((gradient[2][0] >>> 24) <= Math.round(tap * 255));
  assert.equal(h.clips.at(-1).x, 36);
  h.advance(500);
  const paints = h.paints.length;
  h.render(instance);
  assert.equal(h.paints.length, paints);
  assert.equal(h.timers.size, 0);
});

test('panel bubbling cannot double the control glow; cancellation, hiding and removal stop held feedback', () => {
  const h = feedbackHarness();
  const button = h.node(), panel = h.node();
  h.Feedback.apply(button);
  h.Feedback.apply(panel, 24, true);
  const down = h.event(h.TouchType.Down);
  button.touch(down);
  panel.touch(down);
  h.advance(600);
  h.render(panel);
  assert.equal(h.paints.length, 0);
  h.render(button);
  assert.equal(h.gradients.at(-1)[2][0] >>> 24, 255);
  button.touch(h.event(h.TouchType.Cancel));
  h.advance(fade + 20);
  assert.equal(h.timers.size, 0);
  for (const hide of ['detach', 'visible']) {
    button.touch(h.event(h.TouchType.Down));
    h.advance(220);
    if (hide === 'detach') button.detach();
    else button.visible(false);
    h.advance(1000);
    const count = h.paints.length;
    h.render(button);
    assert.equal(h.paints.length, count);
    assert.equal(h.timers.size, 0);
  }
});

test('new light binding evaluates native drawing only on API 26, including hardware fallbacks', () => {
  for (const api of [23, 24, 25, 26, 27, 28]) {
    const native = {};
    let calls = 0;
    Object.defineProperty(native, 'ImmersiveLightFeedback', { get() {
      assert.equal(api, 26);
      return { apply() { calls++; } };
    } });
    const mod = { exports: {} };
    new Function('require', 'module', 'exports',
      compile(read('common/theme/CompatibleLightModifier.ets').replace('import lazy ', 'import ')))(
      name => name === '@kit.BasicServicesKit' ? { deviceInfo: {
        apiAvailable: version => api >= Number(version.split('.')[0])
      } } : native, mod, mod.exports);
    const Modifier = mod.exports.CompatibleLightModifier;
    new Modifier(22, false).applyNormalAttribute({});
    assert.equal(calls, 0);
    new Modifier().applyNormalAttribute({});
    assert.equal(calls, api === 26 ? 1 : 0);
  }
});
