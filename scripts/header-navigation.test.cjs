const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const pages = ['NoticesPage', 'ScorePage', 'ExamPage',
  'ImportTimetablePage', 'TimetableManagerPage', 'TimetableDetailPage', 'AddEventPage',
  'AssistantPage', 'NewsPage', 'PortalsPage'];

test('all more pages use the shared navigation button, not text glyphs', () => {
  for (const page of pages) {
    const source = read(`pages/${page}.ets`);
    assert.match(source, /import \{ HeaderBackButton \}/, page);
    assert.match(source, /HeaderBackButton\(\{/, page);
    assert.doesNotMatch(source, /Text\(['"][<‹×]['"]\)/, page);
  }
  const home = read('pages/Home.ets');
  assert.equal((home.match(/HeaderBackButton\(\{/g) || []).length, 1);
  assert.doesNotMatch(home, /sheetCloseButton/);
});

test('the shared button keeps the reference style and accessible click target', () => {
  const source = read('common/components/HeaderBackButton.ets');
  assert.match(source, /ButtonType\.Circle/);
  assert.match(source, /sys\.symbol\.chevron_left/);
  assert.match(source, /\.width\(44\)[\s\S]*\.height\(44\)/);
  assert.match(source, /\.flexShrink\(0\)/);
  assert.match(source, /\.backgroundColor\(\$r\('app\.color\.hita_control'\)\)/);
  const colors = JSON.parse(read('../resources/base/element/color.json')).color;
  assert.equal(colors.find(item => item.name === 'hita_control').value, '#F2F4F7');
  assert.match(source, /\.accessibilityText\(this\.accessibilityLabel\)/);
  assert.match(source, /\.onClick\(\(\) => \{\s*this\.onBack\(\);/);
});

test('page and sheet header back buttons stay on the leading side', () => {
  for (const page of pages) {
    const source = read(`pages/${page}.ets`);
    const header = source.slice(source.indexOf('  build()'));
    assert.match(header, /Row\(\) \{\s*HeaderBackButton\(\{/, page);
  }
  const home = read('pages/Home.ets');
  const sessionHeader = home.slice(home.indexOf('  sessionSheet()'));
  assert.match(sessionHeader, /Column\(\) \{\s*Row\(\) \{\s*HeaderBackButton\(\{/);
  const login = read('feature/eas/webLogin/EasLoginPage.ets');
  assert.match(login, /Row\(\{ space: 8 \}\) \{\s*HeaderBackButton\(\{/);
});

test('timetable detail header aligns its colored circle and title with the information rows', () => {
  const home = read('pages/Home.ets');
  const sheet = home.slice(home.indexOf('  courseDetailSheet('), home.indexOf('  courseDetailRow('));
  const row = home.slice(home.indexOf('  courseDetailRow('), home.indexOf('  sessionSheet()'));
  assert.doesNotMatch(sheet, /HeaderBackButton|\.width\(7\)|\.height\(50\)/);
  assert.match(sheet, /Circle\(\)[\s\S]*?\.width\(38\)\s*\.height\(38\)\s*\.flexShrink\(0\)/);
  assert.match(sheet, /\.fill\(argbToCss\(timetableBlockColor\(event\.color\), 1\)\)/);
  assert.match(sheet, /\.constraintSize\(\{ minHeight: 56 \}\)/);
  assert.match(sheet, /\.width\('100%'\)\s*\.maxLines\(2\)/);
  for (const style of ['.width(38)', '.height(38)', '.flexShrink(0)',
    '.layoutWeight(1)', '.alignItems(HorizontalAlign.Start)', '.margin({ left: 12 })']) {
    assert.ok(sheet.includes(style), `Detail header: ${style}`);
    assert.ok(row.includes(style), `Detail row: ${style}`);
  }
  assert.match(home, /dragBar: true/);
  assert.match(home, /showClose: false/);
  assert.doesNotMatch(home, /shouldDismiss: false/);
});

test('login uses one app-return button and no overlapping system close control', () => {
  const home = read('pages/Home.ets');
  const source = read('feature/eas/webLogin/EasLoginPage.ets');
  assert.match(home, /\.bindSheet\(this\.activeSheetVisible,/);
  assert.match(home, /showClose: false/);
  assert.doesNotMatch(home, /showClose: this\.loginSheetOpen/);
  assert.equal((source.match(/HeaderBackButton\(\{/g) || []).length, 1);
  assert.match(source, /onBack: \(\) => this\.cancelLogin\(\)/);
  assert.match(source, /private cancelLogin\(\): void \{\s*this\.loginController\.stop\(\);\s*this\.onCancel\(\);/);
  assert.match(source, /private navigateWebBack\(\): void \{[\s\S]*?this\.webController\.backward\(\)/);
  assert.match(source, /\.enabled\(this\.canGoBack\)/);
  assert.match(source, /this\.webController\.refresh\(\)/);
});

test('sheet dismissal preserves the active content until onDisappear', () => {
  const home = read('pages/Home.ets');
  const login = home.slice(home.indexOf('  activeSheet()'), home.indexOf('  pillNavigation()'));
  assert.match(login, /onCancel: \(\) => \{\s*this\.activeSheetVisible = false;/);
  assert.doesNotMatch(login, /this\.loginSheetOpen = false/);
  assert.match(home, /onDisappear: \(\) => \{[\s\S]*?this\.loginSheetOpen = false;[\s\S]*?this\.selectedCourse = undefined;/);
});

test('manager selection cancel and course editor cancel keep their behavior', () => {
  const manager = read('pages/TimetableManagerPage.ets');
  assert.match(manager, /HeaderBackButton\(\{[\s\S]*?if \(this\.selectionMode\) \{[\s\S]*?this\.selectedIds = \[\];[\s\S]*?this\.selectionMode = false;[\s\S]*?getRouter\(\)\.back\(\)/);
  const editor = read('pages/AddEventPage.ets');
  assert.match(editor, /HeaderBackButton\(\{\s*onBack: \(\) => this\.onCancel\(\)/);
  assert.match(editor, /HeaderBackButton\(\{\s*onBack: \(\) => this\.getUIContext\(\)\.getRouter\(\)\.back\(\)/);
  const detail = read('pages/TimetableDetailPage.ets');
  assert.match(detail, /HeaderBackButton\(\{\s*onBack: \(\) => this\.closeSheet\(\)/);
});
