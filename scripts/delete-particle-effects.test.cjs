const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
function clock() {
  let time = 0;
  let next = 0;
  const timers = new Map();
  return {
    setTimeout(callback, delay) {
      const id = ++next;
      timers.set(id, { callback, due: time + delay });
      return id;
    },
    clearTimeout(id) { timers.delete(id); },
    advance(ms) {
      const target = time + ms;
      while (true) {
        const nextTimer = [...timers].filter(([, timer]) => timer.due <= target)
          .sort((a, b) => a[1].due - b[1].due)[0];
        if (!nextTimer) break;
        time = nextTimer[1].due;
        timers.delete(nextTimer[0]);
        nextTimer[1].callback();
      }
      time = target;
    },
    size: () => timers.size
  };
}

function compile(source, dependencies, timer, globals = {}) {
  const mod = { exports: {} };
  const js = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  new Function('require', 'module', 'exports', 'setTimeout', 'clearTimeout', 'Curve', ...Object.keys(globals), js)(
    name => dependencies[name], mod, mod.exports,
    timer.setTimeout, timer.clearTimeout, { EaseOut: 'ease-out', EaseInOut: 'ease' }, ...Object.values(globals));
  return mod.exports;
}

function setup() {
  const timer = clock();
  const { DeleteEffectController } = compile(read('common/util/DeleteEffectController.ets'), {}, timer);
  return { timer, Controller: DeleteEffectController, controller: new DeleteEffectController() };
}

test('dissolve workload stays bounded for small, tall and wide cards', () => {
  const library = compile(read('common/util/DeleteDissolve.ets'), {}, clock());
  for (const [width, height] of [[340, 130], [156, 260], [360, 3500], [1, 10000], [10000, 1]]) {
    const [columns, rows] = library.deleteDissolveGrid(width, height);
    assert.ok(columns >= 1 && rows >= 1);
    assert.ok(columns * rows <= library.DELETE_DISSOLVE_MAX_GRAINS);
  }
});

test('dissolve preserves source color differences and transparency and finishes without lingering grains', () => {
  const library = compile(read('common/util/DeleteDissolve.ets'), {}, clock());
  const pixels = new Uint8ClampedArray([255, 20, 20, 255, 20, 40, 255, 255, 255, 255, 255, 0]);
  const mesh = library.createDeleteDissolve(90, 30, pixels, 3, 1);
  assert.equal(mesh.grains[0].color, 'rgb(255,20,20)');
  assert.equal(mesh.grains[1].color, 'rgb(20,40,255)');
  for (const grain of mesh.grains) {
    assert.equal(library.deleteGrainFrame(grain, 0).alpha, 0);
    assert.equal(library.deleteGrainFrame(grain, library.DELETE_DISSOLVE_DURATION).alpha, 0);
    assert.ok(grain.birth + library.DELETE_SOURCE_FADE_DURATION < library.DELETE_SOURCE_END,
      'the source image must be erased before its layer disappears');
    assert.ok(grain.birth + grain.lifetime <= library.DELETE_DISSOLVE_DURATION,
      'the slower tail must finish before the card is removed');
  }
  assert.equal(library.deleteGrainFrame(mesh.grains[2], 300).alpha, 0);
  const grain = mesh.grains[0];
  const a = library.deleteGrainFrame(grain, grain.birth + 80);
  const b = library.deleteGrainFrame(grain, grain.birth + 250);
  const c = library.deleteGrainFrame(grain, grain.birth + 450);
  assert.ok(a.alpha > 0 && b.alpha > 0 && c.alpha > 0);
  const cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
  assert.ok(Math.abs(cross) > 1, 'dust should follow a curved flow rather than a straight spray');
});

test('particles keep sampled light, dark and custom card colors without tinting or brightening', () => {
  const library = compile(read('common/util/DeleteDissolve.ets'), {}, clock());
  const samples = [[255, 255, 255, 255], [244, 247, 252, 255], [28, 31, 35, 255],
    [0, 0, 0, 255], [128, 128, 128, 255], [52, 101, 65, 255], [138, 46, 66, 255],
    [46, 134, 232, 128], [129, 199, 132, 64], [200, 50, 20, 0]];
  const mesh = library.createDeleteDissolve(samples.length * 10, 10,
    new Uint8ClampedArray(samples.flat()), samples.length, 1);
  mesh.grains.forEach((grain, index) => {
    const [r, g, b, a] = samples[index];
    assert.equal(grain.color, `rgb(${r},${g},${b})`);
    assert.equal(grain.argb, (0xff000000 | r << 16 | g << 8 | b) >>> 0);
    assert.equal(grain.alpha, a / 255);
  });
});

test('the canvas contains the complete visible trail instead of clipping its edges', () => {
  const library = compile(read('common/util/DeleteDissolve.ets'), {}, clock());
  const [columns, rows] = library.deleteDissolveGrid(156, 260);
  const mesh = library.createDeleteDissolve(156, 260,
    new Uint8ClampedArray(columns * rows * 4).fill(255), columns, rows);
  const padding = library.DELETE_DISSOLVE_PADDING;
  for (let time = 0; time < library.DELETE_DISSOLVE_DURATION; time += 32) {
    for (const grain of mesh.grains) {
      const frame = library.deleteGrainFrame(grain, time);
      if (frame.alpha < 0.03) continue;
      assert.ok(frame.x - frame.radius * library.DELETE_GLOW_SCALE >= -padding);
      assert.ok(frame.x + frame.radius * library.DELETE_GLOW_SCALE <= mesh.width + padding);
      assert.ok(frame.y - frame.radius * library.DELETE_GLOW_SCALE >= -padding);
      assert.ok(frame.y + frame.radius * library.DELETE_GLOW_SCALE <= mesh.height + padding);
    }
  }
});

function rendererSetup() {
  const library = compile(read('common/util/DeleteDissolve.ets'), {}, clock());
  class Pen {
    setColor(value) { this.color = value; }
    setAlpha(value) { this.alpha = value; }
    setStrokeWidth(value) { this.width = value; }
    setAntiAlias() {}
    setCapStyle(value) { this.cap = value; }
    setBlendMode(value) { this.blend = value; }
  }
  const { DeleteDissolveRenderer } = compile(read('common/util/DeleteDissolveRenderer.ets'), {
    './DeleteDissolve': library,
    '@kit.ArkGraphics2D': {
      drawing: {
        Pen, Brush: Pen, CapStyle: { ROUND_CAP: 2, SQUARE_CAP: 1 },
        BlendMode: { DST_OUT: 8 }, PointMode: { POINTS: 0 }
      }
    }
  }, clock());
  const [columns, rows] = library.deleteDissolveGrid(340, 130);
  const pixels = new Uint8ClampedArray(columns * rows * 4).fill(255);
  for (let index = 0; index < pixels.length; index += 4) {
    const color = index < pixels.length / 3 ? [37, 99, 235] : [240, 240, 240];
    pixels.set(color, index);
  }
  const mesh = library.createDeleteDissolve(340, 130, pixels, columns, rows);
  const renderer = new DeleteDissolveRenderer(mesh, {});
  return { library, renderer, mesh, Renderer: DeleteDissolveRenderer };
}

test('native batches and their glow use source colors and ignore transparent corner colors', () => {
  const { library, Renderer } = rendererSetup();
  const transparent = [[255, 0, 0, 0], [0, 255, 0, 0], [0, 0, 255, 0],
    [255, 255, 0, 0], [255, 0, 255, 0], [0, 255, 255, 0], [100, 50, 0, 0],
    [30, 80, 140, 0], [120, 20, 180, 0]];
  for (const source of [[255, 255, 255], [128, 128, 128], [28, 31, 35], [52, 101, 65], [138, 46, 66]]) {
    const samples = [...transparent, ...Array.from({ length: 60 }, () => [...source, 255])];
    const mesh = library.createDeleteDissolve(340, 130, new Uint8ClampedArray(samples.flat()), samples.length, 1);
    const renderer = new Renderer(mesh, {});
    const canvas = recordingCanvas();
    renderer.draw(canvas, 550, 3.25);
    const batches = canvas.batches.filter(batch => batch.pen.cap === 2);
    assert.ok(batches.length > 0);
    assert.ok(batches.some(batch => batch.pen.width > 2.7), 'also exercise the colored glow');
    const expected = (0xff000000 | source[0] << 16 | source[1] << 8 | source[2]) >>> 0;
    assert.ok(batches.every(batch => batch.pen.color === expected),
      'neutral or colored surfaces must not acquire another hue from transparent pixels');
  }
});

function recordingCanvas() {
  return {
    commands: 0, depth: 0, pen: undefined, brush: undefined, batches: [], images: 0,
    clear(color) { assert.equal(color, 0); this.commands++; },
    save() { this.depth++; this.commands++; },
    restore() { this.depth--; this.commands++; },
    scale() { this.commands++; },
    attachPen(pen) { this.pen = pen; this.commands++; },
    detachPen() { this.pen = undefined; this.commands++; },
    attachBrush(brush) { this.brush = brush; this.commands++; },
    detachBrush() { this.brush = undefined; this.commands++; },
    drawImageRect() { assert.ok(this.brush); this.images++; this.commands++; },
    drawPoints(points) {
      assert.ok(points.length > 0, 'the native API rejects empty point arrays');
      assert.ok(this.pen);
      this.batches.push({ pen: this.pen, points: [...points] });
      this.commands++;
    }
  };
}

test('native renderer batches the original dust trajectories with far fewer drawing calls', () => {
  const { library, renderer, mesh } = rendererSetup();
  let firstPoints;
  for (const time of [350, 780]) {
    const canvas = recordingCanvas();
    renderer.draw(canvas, time, 2);
    assert.equal(canvas.depth, 0);
    assert.equal(canvas.pen, undefined);
    assert.equal(canvas.brush, undefined);
    assert.equal(canvas.images, time < library.DELETE_SOURCE_END ? 1 : 0);
    let oldCommands = 0;
    const oldCanvas = new Proxy({}, {
      get: () => () => { oldCommands++; },
      set: () => { oldCommands++; return true; }
    });
    library.drawDeleteDissolve(oldCanvas, {}, mesh, time);
    assert.ok(canvas.commands < oldCommands / 5,
      `batching must reduce drawing calls: ${canvas.commands} versus ${oldCommands}`);
    const dust = [...new Set(canvas.batches.filter(batch => batch.pen.cap === 2)
      .flatMap(batch => batch.points))];
    const expected = mesh.grains.map(grain => library.deleteGrainFrame(grain, time))
      .filter(frame => frame.alpha >= 0.02);
    assert.equal(dust.length, expected.length);
    const positions = new Set(dust.map(point => `${point.x}:${point.y}`));
    for (const frame of expected) {
      const padding = library.DELETE_DISSOLVE_PADDING;
      assert.ok(positions.has(`${padding + frame.x}:${padding + frame.y}`));
    }
    if (!firstPoints) firstPoints = new Set(dust);
    else assert.ok(dust.filter(point => firstPoints.has(point)).length > dust.length * 0.7,
      'most live grains must reuse coordinate objects from the earlier frame');
  }
  const final = recordingCanvas();
  renderer.draw(final, library.DELETE_DISSOLVE_DURATION, 2);
  assert.equal(final.commands, 1);
  assert.equal(final.batches.length, 0);
});

test('native renderer restores its drawing state even if a mask submission fails', () => {
  const { renderer } = rendererSetup();
  const canvas = recordingCanvas();
  canvas.drawPoints = () => { throw Error('drawing failed'); };
  assert.throws(() => renderer.draw(canvas, 230, 2), /drawing failed/);
  assert.equal(canvas.depth, 0);
  assert.equal(canvas.pen, undefined);
  assert.equal(canvas.brush, undefined);
});

test('slower dissolve stretches the card erosion and particle tail instead of adding an empty delay', () => {
  const { library, renderer } = rendererSetup();
  const eroding = recordingCanvas();
  renderer.draw(eroding, 400, 2);
  assert.equal(eroding.images, 1, 'the card must still be dissolving after the former 380ms cutoff');
  const tail = recordingCanvas();
  renderer.draw(tail, 1000, 2);
  assert.equal(tail.images, 0);
  assert.ok(tail.batches.some(batch => batch.pen.cap === 2 && batch.pen.alpha > 16),
    'visible dust must continue moving after the former 940ms total duration');
  const end = recordingCanvas();
  renderer.draw(end, library.DELETE_DISSOLVE_DURATION, 2);
  assert.equal(end.batches.length, 0);
});

test('card patches and finer grains share a smooth opacity handoff with no size pop or early clipping', () => {
  const { library, mesh, renderer } = rendererSetup();
  const grain = mesh.grains[Math.floor(mesh.grains.length / 2)];
  const fade = library.DELETE_SOURCE_FADE_DURATION;
  assert.equal(library.deleteSourceDissolve(grain, grain.birth), 0);
  assert.equal(library.deleteSourceDissolve(grain, grain.birth + fade), 1);
  assert.ok(Math.abs(library.deleteSourceDissolve(grain, grain.birth + fade / 2) - 0.5) < 1e-10);
  assert.ok(library.deleteSourceDissolve(grain, grain.birth + 1) < 0.001);
  const radii = mesh.grains.map(item => library.deleteGrainFrame(item, item.birth + fade).radius);
  const averageRadius = radii.reduce((sum, value) => sum + value, 0) / radii.length;
  assert.ok(averageRadius >= 0.95 && averageRadius <= 1.1,
    'keep a readable medium grain without returning to large fragments or sub-pixel dust');
  assert.ok(Math.max(...radii) > Math.min(...radii) * 1.8, 'retain varied fragment sizes');
  for (const item of mesh.grains) {
    assert.ok(item.birth + fade < library.DELETE_SOURCE_END);
    assert.ok(item.birth + item.lifetime <= library.DELETE_DISSOLVE_DURATION);
  }
  const canvas = recordingCanvas();
  renderer.draw(canvas, 500, 2);
  const cores = canvas.batches.filter(batch => batch.pen.cap === 2 && batch.pen.alpha > 32);
  assert.ok(cores.every(batch => batch.pen.width <= 2.7), 'bright particle cores must remain small');
  const total = cores.reduce((sum, batch) => sum + batch.points.length, 0);
  const small = cores.filter(batch => batch.pen.width <= 2)
    .reduce((sum, batch) => sum + batch.points.length, 0);
  assert.ok(small / total > 0.75, 'most particles should be fine or medium sized');
  assert.ok(cores.some(batch => batch.pen.width >= 2 && batch.pen.alpha > 128),
    'retain enough visible particles to avoid an imperceptible dust effect');
  const glows = canvas.batches.filter(batch => batch.pen.cap === 2 && batch.pen.width > 2.7);
  assert.ok(glows.length > 0);
  assert.ok(glows.every(batch => batch.pen.width <= 4.86 && batch.pen.alpha <= 18),
    'a broad, bright halo must not enlarge the apparent grain size');
});

test('unmounted cards, inactive pages and duplicate IDs never hang or replay a deletion', async () => {
  const { controller, timer } = setup();
  await controller.play(['missing']);
  let plays = 0;
  let end;
  let stops = 0;
  const player = { start(finish) { plays++; end = finish; }, stop() { stops++; } };
  controller.register('a', player);
  controller.pause();
  await controller.play(['a']);
  assert.equal(plays, 0);
  controller.resume();
  const pending = controller.play(['a', 'a']);
  assert.equal(plays, 1);
  end();
  end();
  await pending;
  assert.equal(stops, 1);
  assert.equal(timer.size(), 0);
});

test('batch deletion caps simultaneous effects at three and ignores invisible players', async () => {
  const { controller, timer } = setup();
  const ends = [];
  controller.register('offscreen', { start: finish => finish(), stop() {} });
  for (const id of ['a', 'b', 'c', 'd', 'e']) {
    controller.register(id, { start: finish => ends.push(finish), stop() {} });
  }
  const pending = controller.play(['offscreen', 'a', 'b', 'c', 'd', 'e']);
  assert.equal(ends.length, 3);
  assert.equal(timer.size(), 3);
  ends.forEach(finish => finish());
  await pending;
  assert.equal(timer.size(), 0);
});

test('renderer failure, missing callbacks and page exit always settle visual completion', async () => {
  const { controller, timer } = setup();
  controller.register('throws', {
    start() { throw Error('renderer unavailable'); },
    stop() { throw Error('already disposed'); }
  });
  await controller.play(['throws']);
  let stops = 0;
  controller.register('silent', { start() {}, stop() { stops++; } });
  const timed = controller.play(['silent']);
  timer.advance(1600);
  await timed;
  assert.equal(stops, 1);
  const hidden = controller.play(['silent']);
  controller.pause();
  await hidden;
  assert.equal(stops, 2);
  assert.equal(timer.size(), 0);
});

test('slow preparation does not consume playback time and repeated ready callbacks cannot extend the watchdog', async () => {
  const { controller, timer } = setup();
  let ready;
  let finish;
  let stops = 0;
  controller.register('slow', {
    start(done, onReady) { finish = done; ready = onReady; },
    stop() { stops++; }
  });
  const pending = controller.play(['slow']);
  timer.advance(1200);
  ready();
  timer.advance(1400);
  assert.equal(stops, 0, 'the old 1600ms deadline must not interrupt the animation');
  finish();
  await pending;
  const hung = controller.play(['slow']);
  ready();
  timer.advance(2999);
  ready();
  timer.advance(1);
  await hung;
  assert.equal(stops, 2);
  ready();
  assert.equal(timer.size(), 0);
});

test('animation clock skips duplicate frames and preserves the tail after a long frame stall', () => {
  const { DeleteAnimationClock } = compile(read('common/util/DeleteAnimationClock.ets'), {}, clock());
  const regular = new DeleteAnimationClock();
  const fast = new DeleteAnimationClock();
  for (let index = 0; index <= 60; index++) {
    const time = index * 1000000000 / 60;
    const elapsed = regular.advance(time);
    if (index > 0) assert.equal(fast.advance(time - 1000000000 / 120), -1);
    assert.ok(Math.abs(fast.advance(time) - elapsed) < 0.001);
  }
  const stalled = new DeleteAnimationClock();
  assert.equal(stalled.advance(0), 0);
  assert.equal(stalled.advance(16000000), 16);
  assert.equal(stalled.advance(16000000), -1);
  assert.equal(stalled.advance(15000000), -1);
  assert.equal(stalled.advance(816000000), 66);
  assert.equal(stalled.advance(832000000), 82);
});

test('unmount and replacement cannot cancel another card with the same identity', async () => {
  const { controller, timer } = setup();
  let oldStops = 0;
  let newStops = 0;
  const old = { start() {}, stop() { oldStops++; } };
  const next = { start() {}, stop() { newStops++; } };
  controller.register('a', old);
  const first = controller.play(['a']);
  controller.register('a', next);
  await first;
  const second = controller.play(['a']);
  controller.unregister('a', old);
  assert.equal(oldStops, 1);
  assert.equal(newStops, 0);
  controller.unregister('a', next);
  await second;
  assert.equal(newStops, 1);
  assert.equal(timer.size(), 0);
});

function cardSetup(capture, drawFailure = false) {
  const env = setup();
  const calls = { release: 0, start: 0, stop: 0, off: 0, invalidates: 0, frames: [] };
  const snapshot = { release: async () => { calls.release++; } };
  const sync = {
    setExpectedFrameRateRange() {},
    on(_event, callback) { calls.frame = callback; },
    start() { calls.start++; },
    stop() { calls.stop++; },
    off() { calls.off++; }
  };
  class Canvas {
    constructor(width = 1, height = 1) { this.width = width; this.height = height; }
    drawImage() {}
    getImageData() {
      return { data: new Uint8ClampedArray(this.width * this.height * 4).fill(255) };
    }
  }
  const dissolve = compile(read('common/util/DeleteDissolve.ets'), {}, env.timer);
  let source = read('common/components/DeleteParticleCard.ets').replace(/\r\n/g, '\n');
  source = source.slice(0, source.indexOf('\n  @Builder\n')) + '\n}';
  source = source.replace(/^@Component\r?\n/gm, '')
    .replace(/@(State|Prop|BuilderParam)\s+/g, '')
    .replace('export struct DeleteParticleCard', 'export class DeleteParticleCard');
  const { DeleteParticleCard } = compile(source, {
    '../util/DeleteEffectController': { DeleteEffectController: env.Controller },
    '../util/DeleteDissolve': dissolve,
    '../util/DeleteAnimationClock': compile(read('common/util/DeleteAnimationClock.ets'), {}, env.timer),
    '../util/DeleteDissolveRenderer': { DeleteDissolveRenderer: class {
      draw(_canvas, time, density) {
        if (drawFailure) throw Error('native drawing unavailable');
        assert.equal(density, 2);
        calls.frames.push(time);
      }
    } },
    '@kit.ArkGraphics2D': { displaySync: { create: () => sync } },
    '@kit.ArkUI': { LengthMetricsUnit: { PX: 1 } },
    '@kit.PerformanceAnalysisKit': { hilog: { info() {}, warn() {} } }
  }, env.timer, {
    DrawingRenderingContext: class {
      canvas = {};
      invalidate() { calls.invalidates++; }
    },
    OffscreenCanvasRenderingContext2D: Canvas,
    RenderingContextSettings: class {}
  });
  const card = new DeleteParticleCard();
  card.effectId = 'card';
  card.controller = env.controller;
  card.getUIContext = () => ({
    vp2px: value => value * 2,
    getComponentSnapshot: () => ({ get: capture || (async () => snapshot) })
  });
  card.aboutToAppear();
  return { ...env, card, calls, snapshot };
}

const flush = () => new Promise(resolve => setImmediate(resolve));

test('the card stays visible until its snapshot is ready, then follows display frames and releases resources', async () => {
  const { controller, card, timer, calls } = cardSetup();
  card.visible = true;
  card.cardWidth = 320;
  card.cardHeight = 100;
  const pending = controller.play(['card']);
  assert.equal(card.playing, false);
  assert.equal(card.contentOpacity, 1);
  await flush();
  assert.equal(card.playing, true);
  assert.equal(calls.release, 0, 'native drawing retains the PixelMap until playback ends');
  card.animate();
  card.animate();
  assert.equal(calls.start, 1, 'a repeated Canvas.onReady must not start another frame stream');
  assert.equal(card.contentOpacity, 0);
  for (let index = 0; index <= 59; index++) calls.frame({ timestamp: index * 16000000 });
  assert.equal(card.playing, true, 'the effect must remain alive past its previous end time');
  for (let index = 60; index <= 88; index++) calls.frame({ timestamp: index * 16000000 });
  await pending;
  assert.equal(calls.frames.at(-1), 1408);
  assert.equal(calls.frames.length, 90);
  assert.equal(calls.invalidates, 90);
  assert.equal(card.playing, false);
  assert.equal(card.finish, undefined);
  assert.equal(calls.release, 1);
  assert.equal(calls.stop, 1);
  assert.equal(calls.off, 1);
  assert.equal(timer.size(), 0);
});

test('offscreen or unmeasured cards skip effects; unmount clears an active burst', async () => {
  const { controller, card, timer, calls } = cardSetup();
  await controller.play(['card']);
  assert.equal(card.playing, false);
  card.visible = true;
  await controller.play(['card']);
  assert.equal(card.playing, false);
  card.cardWidth = 150;
  card.cardHeight = 260;
  const pending = controller.play(['card']);
  await flush();
  card.animate();
  card.aboutToDisappear();
  await pending;
  assert.equal(timer.size(), 0);
  assert.equal(card.playing, false);
  assert.equal(calls.release, 1);
  assert.equal(calls.off, 1);
  calls.frame({ timestamp: 1200000000 });
  card.aboutToDisappear();
  assert.equal(calls.release, 1);
  assert.equal(calls.frames.length, 1, 'queued callbacks after unmount cannot draw');
});

test('a stalled frame keeps the effect alive instead of jumping to the end', async () => {
  const { controller, card, calls } = cardSetup();
  card.visible = true;
  card.cardWidth = 320;
  card.cardHeight = 100;
  const pending = controller.play(['card']);
  await flush();
  card.animate();
  calls.frame({ timestamp: 0 });
  calls.frame({ timestamp: 500000000 });
  calls.frame({ timestamp: 1200000000 });
  assert.equal(card.playing, true);
  assert.equal(calls.frames.at(-1), 100);
  for (let index = 1; index <= 82; index++) {
    calls.frame({ timestamp: 1200000000 + index * 16000000 });
  }
  await pending;
  assert.equal(calls.release, 1);
});

test('native drawing failure releases the snapshot and resolves deletion', async () => {
  const { controller, card, calls, timer } = cardSetup(undefined, true);
  card.visible = true;
  card.cardWidth = 320;
  card.cardHeight = 100;
  const pending = controller.play(['card']);
  await flush();
  card.animate();
  await pending;
  assert.equal(calls.release, 1);
  assert.equal(card.playing, false);
  assert.equal(timer.size(), 0);
});

test('leaving during snapshot capture releases a late snapshot without starting an animation', async () => {
  let resolve;
  const { controller, card, calls, timer } = cardSetup(() => new Promise(done => { resolve = done; }));
  card.visible = true;
  card.cardWidth = 300;
  card.cardHeight = 120;
  const pending = controller.play(['card']);
  controller.pause();
  await pending;
  let releases = 0;
  resolve({ release: async () => { releases++; } });
  await flush();
  assert.equal(releases, 1);
  assert.equal(card.playing, false);
  assert.equal(calls.start, 0);
  assert.equal(timer.size(), 0);
});

test('snapshot failure falls back immediately without hiding the card or rejecting deletion', async () => {
  const { controller, card, timer } = cardSetup(async () => { throw Error('snapshot unsupported'); });
  card.visible = true;
  card.cardWidth = 300;
  card.cardHeight = 120;
  await controller.play(['card']);
  assert.equal(card.contentOpacity, 1);
  assert.equal(card.playing, false);
  assert.equal(timer.size(), 0);
});

test('material cards use their supplied full-color source and hide the live card only when particles are ready', async () => {
  const { controller, card, calls, snapshot } = cardSetup(() => {
    assert.fail('material snapshots must not rely on a screenshot with a missing background');
  });
  let captureDensity, hidden = 0;
  card.captureSource = async density => { captureDensity = density; return snapshot; };
  card.onSourceHidden = () => { hidden++; };
  card.visible = true;
  card.cardWidth = 43;
  card.cardHeight = 88;
  const pending = controller.play(['card']);
  await flush();
  assert.equal(captureDensity, 2);
  assert.equal(hidden, 0);
  assert.equal(card.playing, true);
  card.animate();
  assert.equal(hidden, 1);
  for (let i = 0; i <= 88; i++) calls.frame({ timestamp: i * 16000000 });
  await pending;
  assert.equal(calls.release, 1);
  assert.equal(hidden, 1);
});

test('timetable management animates only after successful deletion and keeps other tables', async () => {
  for (const fail of [false, true]) {
    const timer = clock();
    const calls = [];
    const source = read('pages/TimetableManagerPage.ets');
    const method = source.slice(source.indexOf('  private async performDelete('),
      source.indexOf('\n  @Builder')).replace('private async', 'async');
    const body = `const RdbHelper = require('db');
      const TimetableSelectionStore = require('selection');
      const hilog = {info() {}, error() {}}, DOMAIN = 0, TAG = '';
      export class Host { ${method} }`;
    const { Host } = compile(body, {
      db: { getInstance: () => ({
        deleteTimetablesCascade: async ids => {
          calls.push(['delete', ids]);
          if (fail) throw Error('write failed');
        }
      }) },
      selection: { getInstance: () => ({ clearIf: async id => calls.push(['selection', id]) }) }
    }, timer);
    const host = new Host();
    host.timetables = [{ id: 'a' }, { id: 'b' }, { id: 'c' }];
    host.selectedIds = ['a', 'c'];
    host.selectionMode = true;
    host.deleting = false;
    host.deleteEffects = { play: async ids => {
      assert.deepEqual(calls, [['delete', ['a', 'c']]]);
      calls.push(['particles', ids]);
    } };
    host.load = async () => {};
    host.getUIContext = () => ({
      animateTo: (_opts, change) => change(),
      getPromptAction: () => ({ showToast: options => calls.push(['toast', options.message]) })
    });
    await host.performDelete(['a', 'c']);
    assert.deepEqual(host.timetables.map(t => t.id), fail ? ['a', 'b', 'c'] : ['b']);
    assert.equal(calls.some(call => call[0] === 'particles'), !fail);
    assert.equal(host.deleting, false);
  }
});
