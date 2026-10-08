const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');

test('API 23-25 render without loading the API 26 material module or calling its tab API', () => {
  for (const api of [23, 24, 25, 26, 27]) {
    const calls = [];
    const source = read('common/theme/CompatibleDockModifier.ets');
    assert.match(source, /import lazy \{ DockBarMaterial \}/);
    const output = ts.transpileModule(source.replace('import lazy ', 'import '), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
    }).outputText;
    const material = {};
    Object.defineProperty(material, 'DockBarMaterial', { get() {
      assert.ok(api >= 26, 'old devices must never evaluate the new material module');
      return { floatingStyle: (...args) => { calls.push(['material', ...args]); return 'native-style'; } };
    } });
    const mod = { exports: {} };
    new Function('require', 'module', 'exports', output)(name => {
      if (name === '@kit.BasicServicesKit') return { deviceInfo: { apiAvailable: () => api >= 26 } };
      assert.equal(name, './ImmersiveDockModifier');
      return material;
    }, mod, mod.exports);
    const instance = { barHeight: value => calls.push(['height', value]) };
    if (api >= 26) instance.barFloatingStyle = value => calls.push(['native', value]);
    new mod.exports.CompatibleDockModifier(36, true, true).applyNormalAttribute(instance);
    assert.deepEqual(calls, api >= 26 ? [['material', 36, true, true], ['native', 'native-style']] : []);
  }
});

test('both products accept API 23 and retain the existing API 26 target and compiler', () => {
  const profile = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../build-profile.json5'), 'utf8').trimStart());
  assert.equal(profile.app.products.length, 2);
  for (const product of profile.app.products) {
    assert.equal(product.compatibleSdkVersion, '6.1.0(23)');
    assert.equal(product.targetSdkVersion, '26.0.0');
    assert.equal(product.compileSdkVersion, '26.0.0');
  }
});

test('older dock keeps three actions, reactive selection, safe-area spacing and automatic foreground inversion', () => {
  const dock = read('common/components/FrostedDock.ets');
  assert.deepEqual([...dock.matchAll(/this\.item\([^\n]+, '([^']+)', (\d)\)/g)]
    .map(m => [m[1], Number(m[2])]), [['今日', 0], ['时间表', 1], ['更多', 2]]);
  assert.equal((dock.match(/\.blendMode\(BlendMode\.DIFFERENCE, BlendApplyType\.OFFSCREEN\)/g) || []).length, 2,
    'both symbol and label invert the backdrop through their painted alpha');
  assert.doesNotMatch(dock, /\.invert\(|\.shadow\(|\.opacity\(/);
  assert.match(dock, /\.backgroundEffect\(\{/);
  assert.match(dock, /\.margin\(\{ bottom: 12 \+ this\.bottomInset \}\)/);
  assert.match(dock, /\.onClick\(\(\) => this\.onSelect\(index\)\)/);
  assert.match(dock, /\.accessibilitySelected\(this\.selectedIndex === index\)/);
  const home = read('pages/Home.ets');
  assert.match(home, /if \(!deviceInfo\.apiAvailable\('26\.0\.0'\)\) \{\s*FrostedDock/);
  assert.match(home, /onSelect: \(index: number\) => \{\s*this\.tabsController\.changeIndex\(index\)/);
  assert.match(home, /\.barHeight\(deviceInfo\.apiAvailable\('26\.0\.0'\) \? 56 : 0\)/);
  assert.match(home, /if \(deviceInfo\.apiAvailable\('26\.0\.0'\)\) \{\s*this\.homeTabs\(\);/);
  assert.match(home, /Stack\(\{ alignContent: Alignment\.Bottom \}\) \{\s*this\.homeTabs\(\);\s*this\.compatibleDock\(\);/);
  assert.doesNotMatch(home, /\.overlay\(this\.compatibleDock/);
});
