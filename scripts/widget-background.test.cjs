const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
function load(file) {
  const mod = { exports: {} };
  const code = ts.transpileModule(read(file), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  new Function('require', 'module', 'exports', code)(() => ({}), mod, mod.exports);
  return mod.exports;
}
const { WidgetBackgroundModel: M } = load('feature/widget/WidgetBackgroundModel.ets');
const near = (a, b) => assert.ok(Math.abs(a - b) < 1e-6, `${a} != ${b}`);

test('placement keeps the image ratio: cover fills the card, contain shows the whole image', () => {
  const cover = M.place(M.coverFrame(), 400, 200, 100, 100);
  near(cover.width / cover.height, 2);
  near(cover.height, 100);
  near(cover.left, -50);
  const contain = M.place(M.containFrame(400, 200, 100, 100), 400, 200, 100, 100);
  near(contain.width, 100);
  near(contain.height, 50);
  near(contain.top, 25);
  near(M.minScale(400, 200, 100, 100), 0.5);
});

test('pan follows the finger and stops at the card edge; zoom keeps the pinch point fixed', () => {
  const start = M.coverFrame();
  near(M.place(M.pan(start, 20, 0, 400, 200, 100, 100), 400, 200, 100, 100).left, -30);
  near(M.pan(start, 500, 0, 400, 200, 100, 100).x, 0);
  const zoomed = M.zoom(start, 2, 50, 50, 50, 50, 400, 200, 100, 100);
  near(zoomed.scale, 2);
  const placed = M.place(zoomed, 400, 200, 100, 100);
  near((50 - placed.left) / placed.width, 0.5);
  near((50 - placed.top) / placed.height, 0.5);
  assert.equal(M.withScale(start, 99, 400, 200, 100, 100).scale, 4);
});

test('the same frame gives the same framing in the preview and the baked output', () => {
  const frame = M.frame(1.6, 0.2, 0.7);
  const small = M.place(frame, 3000, 2000, 150, 150);
  const large = M.place(frame, 3000, 2000, 600, 600);
  near(small.left / 150, large.left / 600);
  near(small.width / 150, large.width / 600);
  const region = M.bakeRegion(M.containFrame(400, 200, 600, 600), 400, 200, 600, 600);
  assert.deepEqual([region.destX, region.destY, region.destW, region.destH], [0, 150, 600, 300]);
  assert.deepEqual([region.srcX, region.srcY, region.srcW, region.srcH], [0, 0, 400, 200]);
});

test('orientation, veil and stored state are parsed defensively', () => {
  assert.equal(M.orientationCode('6'), 6);
  assert.equal(M.orientationCode('Right-top'), 6);
  assert.equal(M.orientationCode('Left-bottom'), 8);
  assert.equal(M.orientationCode('?'), 1);
  assert.equal(M.veilChannel(0, 30), 77);
  assert.equal(M.veilChannel(200, 0), 200);
  assert.equal(M.parseState('{"revision":1,"source":"../x","sourceWidth":1,"sourceHeight":1}'), undefined);
  const state = M.parseState('{"revision":5,"source":"source-5.jpg","sourceWidth":10,"sourceHeight":20,' +
    '"veil":500,"compact":{"scale":9,"x":2,"y":-1}}');
  assert.equal(state.veil, 80);
  assert.deepEqual([state.compact.scale, state.compact.x, state.compact.y], [4, 1, 0]);
  assert.equal(state.wide.scale, 1);
});

test('card uses the documented background attributes; More expands into two single-option rows', () => {
  const card = read('widget/pages/NextClassCard.ets');
  assert.match(card, /\.backgroundImage\(this\.backgroundSource\(\)\)/);
  assert.match(card, /\.backgroundImageSize\(ImageSize\.Cover\)/);
  assert.match(card, /'memory:\/\/' \+ name/);
  // backgroundImageResizable is not available in ArkTS widgets and would stretch the image.
  assert.doesNotMatch(card, /backgroundImageResizable|onAreaChange/);
  const service = read('feature/widget/NextClassWidgetService.ets');
  assert.match(service, /payload\.formImages = images/);
  assert.match(service, /finally \{\s*NextClassWidgetService\.close\(opened\)/);
  const home = read('pages/Home.ets');
  const menu = home.slice(home.indexOf('  desktopWidgetSettings() {'), home.indexOf('  appearanceSettings() {'));
  assert.match(menu, /this\.widgetMenuExpanded = !this\.widgetMenuExpanded/);
  assert.ok(menu.indexOf("'设置桌面服务卡片'") < menu.indexOf("'自定义背景'"));
  assert.match(menu, /pushUrl\(\{ url: 'pages\/WidgetBackgroundPage' \}\)/);
  assert.match(menu, /this\.openDesktopWidgetManager\(\)/);
  assert.doesNotMatch(read('pages/WidgetBackgroundPage.ets'), /bindSheet/);
});
