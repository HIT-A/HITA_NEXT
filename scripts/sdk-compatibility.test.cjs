const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const json5 = require('json5');

const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');

test('all shipping products allow HarmonyOS 6.1 while retaining the current compiler and target', () => {
  const profile = json5.parse(read('build-profile.json5'));
  assert.deepEqual(profile.app.products.map(p => p.name).sort(), ['default', 'store']);
  for (const product of profile.app.products) {
    assert.equal(product.compatibleSdkVersion, '6.1.0(23)', product.name);
    assert.equal(product.compileSdkVersion, '26.0.0', product.name);
    assert.equal(product.targetSdkVersion, '26.0.0', product.name);
    assert.equal(product.runtimeOS, 'HarmonyOS', product.name);
  }
});

test('compatibility revision preserves bundle and visible version, with a higher internal build number', () => {
  const { app } = json5.parse(read('AppScope/app.json5'));
  assert.equal(app.bundleName, 'cn.berry.hitanext');
  assert.equal(app.versionName, '0.2.0');
  assert.equal(app.versionCode, 2000001);
});

test('release packaging verifies the minimum API of both pack.info and embedded HAPs', () => {
  const script = read('scripts/build-agc-store-app.ps1');
  assert.match(script, /compatibleSdkVersion -ne '6\.1\.0\(23\)'/);
  assert.match(script, /\$Module\.apiVersion\.compatible -ne 23/);
  assert.match(script, /\$Manifest\.app\.minAPIVersion -ne 60100023/);
  assert.match(script, /\$Manifest\.app\.debug -ne \$false/);
  assert.match(script, /\$Manifest\.app\.buildMode -ne 'release'/);
  assert.match(script, /verify-app -inFile \$VerifyFiles\[\$i\]/);
  assert.ok(script.indexOf('$Manifest.app.minAPIVersion') < script.indexOf('Copy-Item -LiteralPath $Package'));
});

test('README distinguishes minimum system from build SDK and does not claim device validation', () => {
  const readme = read('README.md');
  assert.match(readme, /最低运行系统：HarmonyOS 6\.1\.0/);
  assert.match(readme, /最低兼容 SDK：6\.1\.0\(23\)/);
  assert.match(readme, /不替代 HarmonyOS 6\.1 实机/);
  assert.match(readme, /2000001/);
});
