const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const strings = file => Object.fromEntries(JSON.parse(read(file)).string.map(item => [item.name, item.value]));

test('app and launcher display Hi HITA without changing package identity or version', () => {
  const { app } = JSON.parse(read('AppScope/app.json5'));
  const { module } = JSON.parse(read('entry/src/main/module.json5'));
  const appStrings = strings('AppScope/resources/base/element/string.json');
  const entryStrings = strings('entry/src/main/resources/base/element/string.json');
  assert.equal(appStrings[app.label.replace('$string:', '')], 'Hi HITA');
  const launcher = module.abilities.find(ability => ability.name === module.mainElement);
  assert.equal(entryStrings[launcher.label.replace('$string:', '')], 'Hi HITA');
  assert.equal(app.bundleName, 'cn.berry.hitanext');
  assert.equal(app.versionName, '0.1.1');
  assert.equal(app.versionCode, 1001000);
});

test('all packaged app, launcher and splash icons use the same PNG', () => {
  const icons = [
    'AppScope/resources/base/media/app_icon.png',
    'entry/src/main/resources/base/media/app_icon.png',
    'entry/src/main/resources/base/media/ic_launcher.png',
    'entry/src/main/resources/base/media/startIcon.png'
  ].map(file => fs.readFileSync(path.join(root, file)));
  assert.equal(icons[0].subarray(0, 8).toString('hex'), '89504e470d0a1a0a');
  assert.equal(icons[0].readUInt32BE(16), icons[0].readUInt32BE(20));
  for (const icon of icons.slice(1)) assert.deepEqual(icon, icons[0]);
});

test('README uses the new name, folder and organization clone destination', () => {
  const readme = read('README.md');
  assert.match(readme, /^# Hi HITA\r?$/m);
  assert.match(readme, /git clone https:\/\/github\.com\/HIT-A\/HITA_NEXT\.git HiHITA/);
  assert.match(readme, /^HiHITA\/\r?$/m);
  assert.doesNotMatch(readme, /^HitaNEXT\/\r?$/m);
});

test('install script resolves the project folder from its own location', () => {
  const script = read('install_and_run.bat');
  assert.match(script, /cd \/d "%~dp0"/);
  assert.doesNotMatch(script, /c:\\heyiwei\\hitanext/i);
  assert.match(script, /Hi HITA/);
});
