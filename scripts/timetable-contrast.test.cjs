const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const cache = new Map();
let nativeImage, nativeFiles, prefs;
function load(name) {
  const file = path.resolve(root, name);
  if (cache.has(file)) return cache.get(file).exports;
  const output = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const mod = { exports: {} }; cache.set(file, mod);
  const req = key => {
    if (key === '@kit.ImageKit') return { get image() { return nativeImage; } };
    if (key === '@kit.CoreFileKit') return { get fileIo() { return nativeFiles; } };
    if (key === '@kit.ArkData') return { preferences: { getPreferences: async () => prefs } };
    if (key === '@kit.PerformanceAnalysisKit') return { hilog: { warn() {} } };
    return load(path.resolve(path.dirname(file), key + '.ets'));
  };
  new Function('require', 'module', 'exports', output)(req, mod, mod.exports);
  return mod.exports;
}
const { TimetableBackdropPixels: Pixels, TimetableBackdropColors: Colors } = load('common/theme/TimetableBackdrop.ets');
const { TimetableTheme: Theme } = load('common/theme/TimetableTheme.ets');
const { TimetableWallpaperSampler: Sampler } = load('feature/timetable/data/TimetableWallpaperSampler.ets');
const { TimetableSelectionStore: Selection } = load('feature/timetable/data/TimetableSelectionStore.ets');

function bitmap(w, h, color, premultiplied = false, padding = 0) {
  const stride = w * 4 + padding;
  const pixels = new Uint8Array(stride * h);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    pixels.set(color(x, y), y * stride + x * 4);
  }
  return new Pixels(w, h, stride, pixels, premultiplied);
}
const colors = (pixels, dark = false, mask = 0, w = 360, h = 800, today = 3) =>
  pixels.colors(dark, mask, w, h, 200, 64, today);

test('wallpaper brightness overrides the app theme independently for the header, dates and time axis', () => {
  const split = bitmap(36, 80, (x, y) => y < 14 || y >= 20 && x < 5 ? [0, 0, 0, 255] : [255, 255, 255, 255]);
  for (const dark of [true, false]) {
    const c = colors(split, dark);
    assert.equal(c.titleText, '#FFFFFF');
    assert.equal(c.dateText, '#333333');
    assert.equal(c.timeText, '#FFFFFF');
    assert.equal(c.line, 'rgba(51,51,51,0.14)');
  }
});

test('black mask changes the rendered contrast, while wallpaper lines stay subtle on dark images', () => {
  const white = bitmap(36, 80, () => [255, 255, 255, 255]);
  const black = bitmap(36, 80, () => [0, 0, 0, 255]);
  assert.equal(colors(white).timeText, '#333333');
  const dimmed = colors(white, false, 70);
  assert.equal(dimmed.titleText, '#FFFFFF');
  assert.equal(dimmed.dateText, '#FFFFFF');
  assert.equal(dimmed.timeText, '#FFFFFF');
  assert.equal(dimmed.line, 'rgba(255,255,255,0.16)');
  assert.equal(dimmed.minorLine, 'rgba(255,255,255,0.07)');
  assert.deepEqual(dimmed, colors(black));
});

test('today column samples its own background and shares the exact same mask in native header and canvas', () => {
  // The rest of this wallpaper is bright; only today's column is dark.
  const columns = bitmap(360, 800, (x, y) =>
    x >= 137 && x < 182 ? [0, 0, 0, 255] : [255, 255, 255, 255]);
  const current = colors(columns, false, 0, 360, 800, 3);
  const other = colors(columns, false, 0, 360, 800, 7);
  assert.equal(current.todayHeader >>> 24, 46);
  assert.equal(other.todayHeader >>> 24, 23);
  const argb = current.todayHeader;
  assert.equal(current.todayMask, `rgba(${argb >>> 16 & 255},${argb >>> 8 & 255},${argb & 255},${(argb >>> 24) / 255})`);
});

test('ImageFit.Cover crop ignores bright hidden sides of a landscape wallpaper', () => {
  const wide = bitmap(96, 48, x => x >= 36 && x < 60 ? [0, 0, 0, 255] : [255, 255, 255, 255]);
  assert.equal(colors(wide).titleText, '#FFFFFF');
  assert.equal(colors(wide, false, 0, 800, 400).titleText, '#333333');
});

test('transparent images use the underlying page and honor pixel stride and premultiplied alpha', () => {
  const transparent = bitmap(8, 16, () => [0, 0, 0, 0], true, 12);
  assert.equal(colors(transparent).titleText, '#333333');
  assert.equal(colors(transparent, true).titleText, '#FFFFFF');
  const straight = bitmap(8, 16, () => [200, 100, 40, 128]);
  const premultiplied = bitmap(8, 16, () => [100, 50, 20, 128], true, 12);
  assert.deepEqual(colors(straight), colors(premultiplied));
  assert.deepEqual(colors(new Pixels(0, 0, 0, new Uint8Array(), true)), new Colors(false));
});

test('manual text colors remain exact, including the former default color', () => {
  assert.equal(Theme.resolveText('auto', false, true, '#FFFFFF'), '#FFFFFF');
  assert.equal(Theme.resolveText('auto', true, true, '#333333'), '#333333');
  for (const color of Theme.PALETTE) {
    assert.equal(Theme.resolveText(color, true, true, '#FFFFFF'), color);
  }
});

test('status time and gesture indicator sample their own wallpaper areas instead of using title text', () => {
  const image = bitmap(36, 80, (x, y) =>
    y < 3 || y >= 77 ? [0, 0, 0, 255] : [255, 255, 255, 255]);
  const c = colors(image);
  assert.equal(c.titleText, '#333333');
  assert.equal(c.statusText, '#FFFFFF');
  assert.equal(c.navigationText, '#FFFFFF');
  const home = fs.readFileSync(path.join(root, 'pages/Home.ets'), 'utf8');
  const method = home.slice(home.indexOf('  private updateTimetableSystemBars()'),
    home.indexOf('  private async loadTimetableWallpaperColors('));
  const code = ts.transpileModule(`class Page {${method}}`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const calls = [];
  const page = new Function('AppearanceStore', 'TAB_TIMETABLE', code + '; return new Page();')({
    getInstance: () => ({ setPageBarColors: (...args) => calls.push(args) })
  }, 1);
  Object.assign(page, { pageVisible: true, currentTab: 1, timetableBackdrop: c,
    activeSheetVisible: false, hasTimetableBackground: () => true });
  page.updateTimetableSystemBars(); assert.deepEqual(calls.at(-1), ['#FFFFFF', '#FFFFFF']);
  page.activeSheetVisible = true;
  page.updateTimetableSystemBars(); assert.deepEqual(calls.at(-1), ['#FFFFFF', '']);
  page.currentTab = 2;
  page.updateTimetableSystemBars(); assert.deepEqual(calls.at(-1), ['', '']);
  page.currentTab = 1; page.pageVisible = false;
  page.updateTimetableSystemBars(); assert.deepEqual(calls.at(-1), ['', '']);
  for (const state of ['currentTab', 'pageVisible', 'activeSheetVisible', 'timetableBackdrop']) {
    assert.match(home, new RegExp(`@Watch\\('updateTimetableSystemBars'\\)[^\\n]*\\b${state}:`));
  }
});

test('legacy default migrates to automatic, explicit choices and returning to automatic survive restart', async () => {
  const data = new Map([['timetable_text_color', '#14213D'], ['active_timetable_id', 'original']]);
  prefs = { get: async (key, fallback) => data.has(key) ? data.get(key) : fallback,
    put: async (key, value) => data.set(key, value), flush: async () => {} };
  const store = new Selection(); await store.init({});
  assert.equal(await store.loadTextColor('auto'), 'auto');
  data.set('timetable_text_color', '#E53935');
  assert.equal(await store.loadTextColor('auto'), '#E53935');
  await store.saveTextColor('#14213D');
  const reopened = new Selection(); await reopened.init({});
  assert.equal(await reopened.loadTextColor('auto'), '#14213D');
  await reopened.saveTextColor('auto');
  assert.equal(await store.loadTextColor('auto'), 'auto');
  prefs.flush = async () => { throw new Error('disk'); };
  await assert.rejects(store.saveTextColor('#FFFFFF'), /save failed/);
  assert.equal(await store.loadTextColor('auto'), 'auto');
  assert.equal(data.get('active_timetable_id'), 'original');
});

test('sampling decodes at most 96 pixels per edge and releases all native resources on success or failure', async () => {
  for (const failAt of ['', 'info', 'decode', 'read', 'release']) {
    const released = []; let options;
    const fail = name => { if (failAt === name) throw new Error(name); };
    const pixelMap = {
      getImageInfo: async () => ({ size: { width: 48, height: 96 }, alphaType: 2 }),
      getPixelBytesNumber: () => 48 * 96 * 4,
      getBytesNumberPerRow: () => 48 * 4,
      readPixelsToBuffer: async () => fail('read'),
      release: async () => { released.push('pixels'); fail('release'); }
    };
    nativeImage = { PixelMapFormat: { RGBA_8888: 3 }, DecodingDynamicRange: { SDR: 1 },
      AlphaType: { PREMUL: 2 }, createImageSource: () => ({
        getImageInfo: async () => { fail('info'); return { size: { width: 2400, height: 4800 } }; },
        createPixelMap: async opt => { options = opt; fail('decode'); return pixelMap; },
        release: async () => { released.push('source'); }
      }) };
    nativeFiles = { OpenMode: { READ_ONLY: 0 }, openSync: () => ({ fd: 1 }),
      closeSync: () => released.push('file') };
    const result = await Sampler.read('/wallpaper.jpg');
    assert.ok(released.includes('file') && released.includes('source'));
    if (!['info', 'decode'].includes(failAt)) assert.ok(released.includes('pixels'));
    if (options) assert.deepEqual(options.desiredSize, { width: 48, height: 96 });
    assert.equal(!!result, failAt === '' || failAt === 'release');
  }
  assert.equal(await Sampler.read(''), undefined);
});

test('a late decode cannot replace a newer wallpaper or restore one that was removed', async () => {
  const home = fs.readFileSync(path.join(root, 'pages/Home.ets'), 'utf8');
  const start = home.indexOf('  private async loadTimetableWallpaperColors(');
  const end = home.indexOf('\n  private async selectAppearance', start);
  const method = home.slice(start, end);
  const code = ts.transpileModule(`class Page {${method}}`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const pending = new Map();
  const Page = new Function('TimetableWallpaperSampler', code + '; return Page;')({
    read: path => new Promise(resolve => pending.set(path, resolve))
  });
  const page = new Page();
  Object.assign(page, { timetableWallpaperGeneration: 0, drawTimetableNow() {} });
  const first = page.loadTimetableWallpaperColors('first');
  const second = page.loadTimetableWallpaperColors('second');
  pending.get('second')('new pixels'); await second;
  pending.get('first')('old pixels'); await first;
  assert.equal(page.timetableWallpaperPixels, 'new pixels');
  const third = page.loadTimetableWallpaperColors('third');
  page.timetableWallpaperGeneration++;
  page.timetableWallpaperPixels = undefined;
  pending.get('third')('deleted pixels'); await third;
  assert.equal(page.timetableWallpaperPixels, undefined);
});
