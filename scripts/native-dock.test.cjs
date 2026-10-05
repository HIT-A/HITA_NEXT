const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');

function material(overrides = {}) {
  const uiMaterial = {
    MaterialLevel: { EXQUISITE: 'exquisite', GENTLE: 'gentle' },
    ImmersiveStyle: { ULTRA_THIN: 'ultra-thin', THIN: 'thin' },
    isImmersiveMaterialSupported: () => true,
    getGlobalMaterialLevel: () => 'exquisite',
    ImmersiveMaterial: class { constructor(options) { Object.assign(this, options); } },
    ...overrides
  };
  const mod = { exports: {} };
  const output = ts.transpileModule(read('common/theme/ImmersiveDockModifier.ets'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const platform = name => {
    assert.equal(name, '@kit.ArkUI');
    return { uiMaterial };
  };
  new Function('require', 'module', 'exports', 'Color', output)(
    platform, mod, mod.exports, { Transparent: 'transparent', White: 'white' });
  return mod.exports.DockBarMaterial;
}

test('native dock retains fixed dimensions, safe-area margin and default mask', () => {
  const style = material().floatingStyle(36);
  assert.deepEqual(style.barWidth, { smallBarWidth: 328, mediumBarWidth: 328, largeBarWidth: 328 });
  assert.equal(style.barBottomMargin, 36);
  assert.equal(style.maskColor, '#66F1F3F5');
  assert.equal(style.maskHeight, 92);
  assert.deepEqual({ ...style.systemMaterial }, {
    style: 'ultra-thin', applyShadow: true, colorInvert: true,
    interactive: false, lightEffect: { color: 'white' }
  });
});

test('timetable wallpaper hides only the background mask, not the dock material', () => {
  const style = material().floatingStyle(12, true);
  assert.equal(style.maskColor, 'transparent');
  assert.equal(style.maskHeight, 0);
  assert.ok(style.systemMaterial);
  const home = read('pages/Home.ets');
  assert.match(home, /barFloatingStyle\(DockBarMaterial\.floatingStyle\(12 \+ this\.navBarInset,\s*this\.selectedNav === TAB_TIMETABLE && this\.hasTimetableBackground\(\)\)\)/);
});

test('dock material follows device quality and falls back when quality lookup fails', () => {
  for (const level of ['gentle', 'unknown']) {
    assert.equal(material({ getGlobalMaterialLevel: () => level }).floatingStyle(12).systemMaterial.style, 'thin');
  }
  const style = material({ getGlobalMaterialLevel: () => { throw new Error('unavailable'); } }).floatingStyle(12);
  assert.equal(style.systemMaterial.style, 'thin');
});

test('unsupported materials never prevent rendering the fallback dock', () => {
  for (const overrides of [
    { isImmersiveMaterialSupported: () => false },
    { isImmersiveMaterialSupported: () => { throw new Error('unavailable'); } },
    { ImmersiveMaterial: class { constructor() { throw new Error('unavailable'); } } }
  ]) {
    const style = material(overrides).floatingStyle(24);
    assert.equal(style.systemMaterial, undefined);
    assert.equal(style.barBottomMargin, 24);
    assert.equal(style.maskHeight, 92);
  }
});

test('one native tab bar owns all five tabs, without an unused custom glass layer', () => {
  const home = read('pages/Home.ets');
  const shell = home.slice(home.indexOf('  build() {'), home.indexOf('  activeSheet()'));
  assert.match(shell, /Tabs\(\{ barPosition: BarPosition\.End, controller: this\.tabsController \}\)/);
  assert.equal((shell.match(/TabContent\(\)/g) || []).length, 5);
  assert.match(shell, /\.barOverlap\(true\)/);
  assert.match(shell, /\.barHeight\(56\)/);
  assert.match(shell, /\.barBackgroundColor\(Color\.Transparent\)/);
  assert.match(home, /normal\.fontColor\(\[\$r\('sys\.color\.ohos_id_color_text_secondary'\)\]\)/);
  assert.match(home, /selected\.fontColor\(\[\$r\('sys\.color\.ohos_id_color_text_primary'\)\]\)/);
  assert.ok(!fs.existsSync(path.join(root, 'common/theme/DockGlass.ets')));
  assert.doesNotMatch(home, /DockGlass|pillNavigation|navDroplet|tabSwiper/);
});

test('news fills the screen under the dock instead of leaving a bottom inset', () => {
  const home = read('pages/Home.ets');
  assert.match(home, /NewsTab\(\);[\s\S]*?\.tabPage\(0, COLOR_SURFACE\)/);
  const news = read('feature/news/NewsTab.ets');
  const expansions = news.match(/expandSafeArea\(\[SafeAreaType\.SYSTEM\], \[SafeAreaEdge\.BOTTOM\]\)/g) || [];
  assert.ok(expansions.length >= 4);
  assert.doesNotMatch(news, /\.padding\(\{ left: 16, right: 16, bottom: 12 \}\)/);
});
