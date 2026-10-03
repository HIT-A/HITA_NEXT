const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
function load(file) {
  const mod = { exports: {} };
  const output = ts.transpileModule(read(file), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  new Function('require', 'module', 'exports', output)(() => assert.fail('no imports expected'), mod, mod.exports);
  return mod.exports;
}
const { DockGlass } = load('common/theme/DockGlass.ets');

test('dock highlights are 60% stronger and clamp at full opacity', () => {
  assert.equal(DockGlass.LIGHT_GAIN, 1.6);
  assert.equal(DockGlass.glow(0.5), 'rgba(255,255,255,0.800)');
  assert.equal(DockGlass.glow(0.34), 'rgba(255,255,255,0.544)');
  assert.equal(DockGlass.glow(0.95), 'rgba(255,255,255,1.000)');
  assert.equal(DockGlass.glow(0), 'rgba(255,255,255,0.000)');
  assert.equal(DockGlass.caustic(0.24), 'rgba(120,196,255,0.384)');
});

test('tab light sources only shine while pressed', () => {
  const modifier = read('common/theme/ImmersiveDockModifier.ets');
  const source = modifier.slice(modifier.indexOf('class DockLightSourceModifier'),
    modifier.indexOf('class DockRimLightModifier'));
  assert.match(source, /applyNormalAttribute[^}]*build\(true, false\)/);
  assert.match(source, /applyPressedAttribute[^}]*build\(true, true\)/);
  assert.match(modifier, /lit \? hdsEffect\.PointLightSourceType\.BRIGHT : hdsEffect\.PointLightSourceType\.NONE/);
});

test('dock glass stays clear and its labels stay crisp', () => {
  const modifier = read('common/theme/ImmersiveDockModifier.ets');
  const tint = Number(/backgroundColor\('rgba\(255,255,255,([\d.]+)\)'\)/.exec(modifier)[1]);
  assert.ok(Math.abs(tint - 0.30) < 0.001, `material tint ${tint} should be 0.30`);
  const home = read('pages/Home.ets');
  const item = home.slice(home.indexOf('  navItem('), home.indexOf('  tabToday()'));
  assert.match(home, /const COLOR_NAV_IDLE: string = '#070B14'/);
  assert.match(home, /const COLOR_NAV_ACTIVE_TEXT: string = '#08367A'/);
  assert.doesNotMatch(item, /COLOR_TEXT_SECONDARY|COLOR_TEXT_HINT|COLOR_TEXT_PRIMARY/);
  assert.equal((item.match(/\.fontWeight\(FontWeight\.Medium\)/g) || []).length, 2);
  assert.match(item, /this\.onNavTap\(index\)/);
  assert.match(home, /this\.tabSwiper\.changeIndex\(index, true\)/);
});

test('dock taps slide the droplet with the page instead of snapping', () => {
  const home = read('pages/Home.ets');
  const tap = home.slice(home.indexOf('  private onNavTap'), home.indexOf('  private followTabSwipe'));
  assert.match(tap, /changeIndex\(index, true\)/);
  assert.match(tap, /this\.navPos = index/);
  assert.match(tap, /duration: TAB_SWIPE_MS/);
  assert.match(tap, /this\.navLifted = true/);
  assert.doesNotMatch(tap, /tabPageOpacity = 0/);
});

test('every dock highlight goes through the shared gain', () => {
  const home = read('pages/Home.ets');
  const dock = home.slice(home.indexOf('  pillNavigation()'), home.indexOf('  navDroplet()'));
  assert.doesNotMatch(dock, /rgba\(255,255,255,/);
  assert.match(dock, /width: DockGlass\.RIM_WIDTH/);
  const droplet = home.slice(home.indexOf('  navDroplet()'), home.indexOf('  navItem('));
  assert.match(droplet, /colors: \[\[DockGlass\.glow\(0\.55\), 0\]/);
  assert.match(droplet, /top: DockGlass\.glow\(0\.92\),\s*left: DockGlass\.glow\(0\.6\)/);
  const rimAt = dock.indexOf('attributeModifier(this.dockRimLight)');
  const tabsAt = dock.lastIndexOf('this.navItem(');
  assert.ok(rimAt >= 0 && tabsAt > rimAt, 'nav items must sit above the glass rim so taps reach them');
  assert.match(dock, /hitTestBehavior\(HitTestMode\.Transparent\)/);
  const modifier = read('common/theme/ImmersiveDockModifier.ets');
  assert.match(modifier, /backdropBlur\(14\)/);
  assert.equal((modifier.match(/backdropBlur\(/g) || []).length, 1);
  assert.doesNotMatch(modifier, /backgroundBlurStyle/);
  assert.doesNotMatch(modifier, /systemMaterial/);
  assert.doesNotMatch(modifier, /ImmersiveStyle/);
  assert.match(dock, /backgroundColor\(DockGlass\.FROST\)/);
  assert.match(dock, /\.clip\(true\)/);
  assert.doesNotMatch(dock, /\.outline\(/);
  assert.equal(DockGlass.FROST, 'rgba(255,255,255,0.30)');
});

test('news fills the screen under the dock instead of leaving a bottom inset', () => {
  const home = read('pages/Home.ets');
  assert.match(home, /NewsTab\(\);[\s\S]*?\.tabPage\(0, COLOR_SURFACE\)/);
  const news = read('feature/news/NewsTab.ets');
  const expansions = news.match(/expandSafeArea\(\[SafeAreaType\.SYSTEM\], \[SafeAreaEdge\.BOTTOM\]\)/g) || [];
  assert.ok(expansions.length >= 4, 'news lists must extend into the bottom safe area');
  assert.doesNotMatch(news, /\.padding\(\{ left: 16, right: 16, bottom: 12 \}\)/);
});
