const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');

function materialModule(overrides = {}, sdkApiVersion = 26) {
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
    if (name === '@kit.BasicServicesKit') return { deviceInfo: { sdkApiVersion } };
    assert.equal(name, '@kit.ArkUI');
    return { get uiMaterial() {
      assert.ok(sdkApiVersion >= 26, 'API 23 must never access the API 26 material module');
      return uiMaterial;
    } };
  };
  new Function('require', 'module', 'exports', 'Color', output)(
    platform, mod, mod.exports, { Transparent: 'transparent', White: 'white' });
  return mod.exports;
}

const material = overrides => materialModule(overrides).DockBarMaterial;

test('native dock retains fixed dimensions, safe-area margin and default mask', () => {
  const style = material().floatingStyle(36);
  assert.deepEqual(style.barWidth, { smallBarWidth: 212, mediumBarWidth: 212, largeBarWidth: 212 });
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
  assert.match(home, /attributeModifier\(new DockBarModifier\(12 \+ this\.navBarInset,\s*this\.selectedNav === TAB_TIMETABLE && this\.hasTimetableBackground\(\), this\.darkMode\)\)/);
});

test('the dark dock changes only its mask color and keeps wallpaper unobscured', () => {
  const dock = material();
  const light = dock.floatingStyle(36, false, false);
  const dark = dock.floatingStyle(36, false, true);
  assert.equal(dark.maskColor, '#99101214');
  assert.deepEqual({ ...dark, maskColor: light.maskColor }, light);
  assert.equal(dock.floatingStyle(36, true, true).maskColor, 'transparent');
  assert.equal(dock.floatingStyle(36, true, true).maskHeight, 0);
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

test('one Tabs controller owns Today, Timetable and More on both navigation implementations', () => {
  const home = read('pages/Home.ets');
  const shell = home.slice(home.indexOf('  build() {'), home.indexOf('  activeSheet()'));
  assert.match(shell, /Tabs\(\{ barPosition: BarPosition\.End, controller: this\.tabsController \}\)/);
  assert.equal((shell.match(/TabContent\(\)/g) || []).length, 3);
  assert.deepEqual([...shell.matchAll(/\.tabBar\(this\.dockTab\(\$r\('[^']+'\), '([^']+)'\)\)/g)]
    .map(match => match[1]), ['今日', '时间表', '更多']);
  assert.match(home, /const NAV_TAB_COUNT: number = 3/);
  assert.doesNotMatch(home, /AssistantTab|NewsTab|assistantMounted|newsMounted|mountTabsNear/);
  assert.match(shell, /\.barOverlap\(true\)/);
  assert.match(shell, /\.barHeight\(this\.nativeFloatingDock \? 56 : 0\)/);
  assert.match(shell, /\.barBackgroundColor\(Color\.Transparent\)/);
  assert.match(home, /normal\.fontColor\(\[\$r\('sys\.color\.ohos_id_color_text_secondary'\)\]\)/);
  assert.match(home, /selected\.fontColor\(\[\$r\('sys\.color\.ohos_id_color_text_primary'\)\]\)/);
  assert.ok(!fs.existsSync(path.join(root, 'common/theme/DockGlass.ets')));
  assert.doesNotMatch(home, /DockGlass|pillNavigation|navDroplet|tabSwiper/);
});

test('API 23 and 24 neither load new materials nor call barFloatingStyle', () => {
  for (const version of [23, 24]) {
    const { DockBarMaterial, DockBarModifier } = materialModule({}, version);
    assert.equal(DockBarMaterial.supportsFloatingBar(), false);
    const tabs = { get barFloatingStyle() { throw new Error('Unavailable API'); } };
    new DockBarModifier(36, false, false).applyNormalAttribute(tabs);
    assert.equal(DockBarMaterial.floatingStyle(36).systemMaterial, undefined);
  }
  assert.match(read('common/theme/ImmersiveDockModifier.ets'),
    /import lazy \{ uiMaterial \} from '@kit.ArkUI'/);
});

test('API 26 retains the native floating dock and immersive material', () => {
  const { DockBarMaterial, DockBarModifier } = materialModule();
  assert.equal(DockBarMaterial.supportsFloatingBar(), true);
  const calls = [];
  new DockBarModifier(36, true, true).applyNormalAttribute({
    barFloatingStyle: style => calls.push(style)
  });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].barBottomMargin, 36);
  assert.equal(calls[0].maskHeight, 0);
  assert.ok(calls[0].systemMaterial);
});

test('the API 23 dock has equal hit targets, an animated selection and no page-wide background', () => {
  const home = read('pages/Home.ets');
  const dock = home.slice(home.indexOf('  compatibilityDock()'), home.indexOf('  activeSheet()'));
  assert.match(home, /if \(!this\.nativeFloatingDock\) \{\s*this\.compatibilityDock\(\)/);
  assert.match(dock, /\.width\(212\)\s*\.height\(56\)/);
  assert.match(dock, /\.width\(204\)\s*\.height\(48\)/);
  assert.match(dock, /\.width\(68\)\s*\.height\(48\)/);
  assert.match(dock, /translate\(\{ x: this\.selectedNav \* 68 \}\)/);
  assert.match(dock, /animation\(\{ duration: TAB_SWIPE_MS/);
  assert.match(dock, /margin\(\{ bottom: 12 \+ this\.navBarInset \}\)/);
  assert.match(dock, /backgroundColor\(COLOR_CARD\)/);
  assert.match(dock, /this\.tabsController\.changeIndex\(index\)/);
  assert.match(dock, /accessibilitySelected\(this\.selectedNav === index\)/);
  assert.deepEqual([...dock.matchAll(/compatibilityDockItem\(\$r\('[^']+'\), '([^']+)'/g)].map(x => x[1]),
    ['今日', '时间表', '更多']);
});

test('standalone news fills the screen and keeps the final rows above the system gesture bar', () => {
  const news = read('pages/NewsPage.ets');
  const expansions = news.match(/expandSafeArea\(\[SafeAreaType\.SYSTEM\], \[SafeAreaEdge\.BOTTOM\]\)/g) || [];
  assert.ok(expansions.length >= 4);
  assert.equal((news.match(/Column\(\)\.height\(12 \+ this\.navBarInset\)/g) || []).length, 1);
  assert.match(read('pages/PortalsPage.ets'), /Column\(\)\.height\(12 \+ this\.navBarInset\)/);
  assert.doesNotMatch(news, /\.padding\(\{ left: 16, right: 16, bottom: 12 \}\)/);
});
