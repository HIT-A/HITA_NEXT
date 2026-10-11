const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');

test('only Today event cards use the API 26-capable material branch; heading and empty state stay unchanged', () => {
  const home = read('pages/Home.ets');
  const today = home.slice(home.indexOf('  tabToday()'), home.indexOf('  todayHeader()'));
  assert.match(today, /this\.todaySectionHeader\(\);\s*if \(this\.todayItems\.length === 0\) \{\s*this\.emptyToday\(\)/);
  assert.match(today, /ForEach\(this\.todayItems, \(event: EasEventItem\) => \{\s*ListItem\(\) \{\s*if \(CompatibleSheetMaterial\.isEnabled\(\)\) \{\s*ImmersiveEventCard/);
  assert.match(today, /ImmersiveEventCard\(\{ content: \(\) => \{ this\.eventRow\(event, true\); \} \}\)\s*\} else \{\s*this\.eventRow\(event\)/);
  assert.match(today, /\}, \(event: EasEventItem\) => event\.id\)/);
  assert.doesNotMatch(home.slice(home.indexOf('  todaySectionHeader()'), home.indexOf('  emptyToday()')),
    /ImmersiveEventCard|CompatibleMaterialModifier|systemMaterial/);
});

test('card material lives inside the supported title host, matches measured content height and has no shadow', () => {
  const card = read('common/components/ImmersiveEventCard.ets');
  assert.match(card, /@State private contentHeight: number = 0/);
  assert.match(card, /if \(this\.contentHeight > 0\) \{[\s\S]*?Column\(\) \{\s*ImmersiveHeader\(\{ barHeight: this\.contentHeight \}\)/);
  assert.match(card, /Row\(\)\s*\.width\('100%'\)\s*\.height\(this\.contentHeight\)/);
  assert.match(card, /new CompatibleMaterialModifier\(\$r\('app\.color\.hita_surface'\)\)/);
  assert.match(card, /\.onAreaChange\(\(oldArea: Area, area: Area\) => \{ this\.updateHeight\(Number\(area\.height\)\); \}\)/);
  assert.match(card, /\.hitTestBehavior\(HitTestMode\.Transparent\)/);
  assert.match(card, /\.backgroundColor\(this\.contentHeight > 0 \? Color\.Transparent : \$r\('app\.color\.hita_surface'\)\)/);
  assert.doesNotMatch(card, /\.shadow\(/);
  assert.doesNotMatch(card, /\.height\(1[0-9][0-9]\)|\.height\(2[0-9][0-9]\)/);
  const material = read('common/theme/ImmersiveHeaderMaterial.ets');
  assert.match(material, /applyShadow: shadow === undefined \? blueSurface : shadow/);
  assert.match(material, /interactive: true/);
  assert.match(material, /lightEffect: \{ color: Color\.White \}/);
});

test('measured card height ignores invalid values and updates when event content changes', () => {
  const source = read('common/components/ImmersiveEventCard.ets');
  const method = source.slice(source.indexOf('  private updateHeight('), source.indexOf('  build()'));
  const compiled = ts.transpileModule('class Card { contentHeight = 0;\n' + method + '\n}; return Card;', {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const Card = new Function(compiled)();
  const card = new Card();
  for (const invalid of [0, -1, NaN, Infinity, -Infinity]) {
    card.updateHeight(invalid);
    assert.equal(card.contentHeight, 0);
  }
  card.updateHeight(127.2);
  assert.equal(card.contentHeight, 128);
  card.updateHeight(127.8);
  assert.equal(card.contentHeight, 128);
  card.updateHeight(201.1);
  assert.equal(card.contentHeight, 202);
});

test('card text, status colors, time rail and progress remain in the original content layer', () => {
  const home = read('pages/Home.ets');
  const row = home.slice(home.indexOf('  eventRow('), home.indexOf('  emptyTimetableActions()'));
  for (const source of ['EasTimeTools.printTime(event.from)', "Text('已结束')",
    'Home.typeTag(event.type)', 'Home.eventStatus(event, this.nowTick)',
    'event.place.length > 0', 'event.teacher.length > 0',
    'Progress({ value: event.getProgress(this.nowTick) * 100']) {
    assert.ok(row.includes(source), source);
  }
  assert.match(row, /eventRow\(event: EasEventItem, immersive: boolean = false\)/);
  assert.match(row, /\.backgroundColor\(immersive \? Color\.Transparent : COLOR_CARD\)/);
  assert.match(row, /\.hitTestBehavior\(immersive \? HitTestMode\.Transparent : HitTestMode\.Default\)/);
  assert.match(row, /\.margin\(\{ bottom: immersive \? 0 : 2 \}\)/);
  assert.match(row, /event\.containsTimestamp\(this\.nowTick\) \? \$r\('app\.color\.hita_focus'\)/);
});
