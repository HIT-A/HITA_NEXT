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
  const session = home.slice(home.indexOf('  sessionSheet()'));
  assert.match(session, /Column\(\) \{\s*Row\(\) \{\s*HeaderBackButton\(\{/);
  const login = read('feature/eas/webLogin/EasLoginPage.ets');
  assert.match(login, /Row\(\{ space: 8 \}\) \{\s*HeaderBackButton\(\{/);
});

test('timetable detail uses an aligned color circle instead of the old back button and stripe', () => {
  const home = read('pages/Home.ets');
  const header = home.slice(home.indexOf('  courseDetailSheet('), home.indexOf('  courseDetailRow('));
  const row = home.slice(home.indexOf('  courseDetailRow('), home.indexOf('  private static canvasColorCss('));
  assert.match(home, /const COURSE_DETAIL_ICON_SIZE: number = 38;/);
  assert.match(home, /const COURSE_DETAIL_TEXT_GAP: number = 12;/);
  assert.match(header, /Row\(\) \{\s*Circle\(\)/);
  assert.doesNotMatch(header, /HeaderBackButton|\.width\(7\)|\.height\(50\)/);
  for (const section of [header, row]) {
    assert.match(section, /\.width\(COURSE_DETAIL_ICON_SIZE\)/);
    assert.match(section, /\.height\(COURSE_DETAIL_ICON_SIZE\)/);
    assert.match(section, /\.flexShrink\(0\)/);
    assert.match(section, /\.margin\(\{ left: COURSE_DETAIL_TEXT_GAP \}\)/);
    assert.match(section, /\.alignItems\(HorizontalAlign\.Start\)/);
  }
  assert.match(header, /CirclePaintModifier\(Home\.canvasColorCss\(timetableBlockColor\(event\.color\)\)\)/);
  assert.match(header, /event\.type === EasEventType\.EXAM \? '考试详情' : '课程详情'/);
  assert.match(home, /\.bindSheet\(\$\$this\.activeSheetVisible,[\s\S]*?dragBar: true/);
});

test('login uses one app-return button and no overlapping system close control', () => {
  const home = read('pages/Home.ets');
  const source = read('feature/eas/webLogin/EasLoginPage.ets');
  assert.match(home, /\.bindSheet\(\$\$this\.activeSheetVisible,/);
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
  assert.match(login, /onCancel: \(\) => \{\s*this\.closeActiveSheet\(\);/);
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
