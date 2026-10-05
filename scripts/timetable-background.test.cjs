const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');

test('timetable photo picker copies a gallery image and covers the page without stretching', () => {
  const store = read('feature/timetable/data/TimetableBackgroundStore.ets');
  assert.match(store, /picker\.PhotoViewPicker/);
  assert.match(store, /PhotoViewMIMETypes\.IMAGE_TYPE/);
  assert.match(store, /maxSelectNumber = 1/);
  assert.match(store, /copyFileSync/);
  assert.match(store, /unlinkSync/);
  assert.match(store, /timetable-background\.jpg/);

  const home = read('pages/Home.ets');
  const tab = home.slice(home.indexOf('  tabTimetable()'), home.indexOf('  statusBanner('));
  assert.match(tab, /sys\.symbol\.camera/);
  assert.match(tab, /this\.onTimetableBackgroundTap\(\)/);
  assert.match(home, /text: '更换壁纸'/);
  assert.match(home, /text: '移除壁纸'/);
  assert.match(home, /showActionMenu/);
  assert.match(home, /this\.removeTimetableBackground\(\)/);
  assert.match(home, /TimetableBackgroundStore\.remove/);
  assert.match(tab, /Image\(this\.timetableBgUri\)/);
  assert.match(tab, /objectFit\(ImageFit\.Cover\)/);
  assert.match(tab, /hitTestBehavior\(HitTestMode\.None\)/);
  assert.match(tab, /expandSafeArea\(\[SafeAreaType\.SYSTEM\], \[SafeAreaEdge\.TOP, SafeAreaEdge\.BOTTOM\]\)/);
  assert.match(tab, /backgroundColor\(Color\.Transparent\)/);
  assert.match(tab, /accessibilityText\('选择时间表字体颜色'\)/);
  assert.match(tab, /TimetableTheme\.PALETTE/);
  assert.match(home, /drawTimetableWeek\([\s\S]*!this\.hasTimetableBackground\(\), this\.timetableTextColor\)/);
  assert.match(tab, /timetableDateHeader\(\)/);
  assert.match(tab, /timetableDateHeader\(\)[\s\S]*backgroundColor\(Color\.Transparent\)/);
  assert.match(tab, /Text\(this\.timetableCampusTerm\(\)\)[\s\S]*?\.backgroundColor\(Color\.Transparent\)/);

  const draw = read('feature/timetable/views/TimetableWeekDraw.ets');
  const header = draw.slice(draw.indexOf('function drawWeekHeader'), draw.indexOf('export function drawTimetableWeek('));
  assert.match(header, /if \(fillPage\) \{[\s\S]*fillRect\(x, 4, colW, headerH - 2\)/);
  assert.match(draw, /labelColor: string = ''/);

  const theme = read('common/theme/TimetableTheme.ets');
  const palette = /PALETTE: string\[\] = \[([\s\S]*?)\]/.exec(theme)[1];
  assert.match(palette, /'#14213D'/);
  assert.match(palette, /'#FFFFFF'/);
  assert.match(palette, /'#E53935'/);
  assert.match(palette, /'#FB8C00'/);
  assert.match(palette, /'#F9A825'/);
  assert.match(palette, /'#43A047'/);
  assert.match(palette, /'#00ACC1'/);
  assert.match(palette, /'#1E88E5'/);
  assert.match(palette, /'#8E24AA'/);
  assert.equal((palette.match(/'#[0-9A-Fa-f]{6}'/g) || []).length, 9);

  const colors = read('feature/timetable/data/TimetableSelectionStore.ets');
  assert.match(colors, /timetable_text_color/);
});
