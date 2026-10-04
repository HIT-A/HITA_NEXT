const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const cache = new Map();
function load(file) {
  const absolute = path.resolve(root, file);
  if (cache.has(absolute)) return cache.get(absolute).exports;
  const mod = { exports: {} };
  cache.set(absolute, mod);
  const output = ts.transpileModule(fs.readFileSync(absolute, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const requireLocal = name => {
    assert.ok(name.startsWith('.'), name);
    return load(path.resolve(path.dirname(absolute), name + '.ets'));
  };
  new Function('require', 'module', 'exports', output)(requireLocal, mod, mod.exports);
  return mod.exports;
}
const { drawTimetableFade } = load('feature/timetable/views/TimetableWeekDraw.ets');
const { HeaderFade } = load('common/theme/HeaderFade.ets');
const { EasTimetable } = load('common/model/timetable/TimetableModels.ets');

function gradientCanvas() {
  const ctx = { fills: [], fillStyle: undefined };
  ctx.clearRect = () => {};
  ctx.createLinearGradient = (x0, y0, x1, y1) => {
    const gradient = { axis: [x0, y0, x1, y1], stops: [] };
    gradient.addColorStop = (offset, color) => gradient.stops.push([offset, color]);
    return gradient;
  };
  ctx.fillRect = (x, y, w, h) => ctx.fills.push({ rect: [x, y, w, h], style: ctx.fillStyle });
  return ctx;
}

test('header fade opacity ramps in over the first 24vp of scrolling', () => {
  assert.equal(HeaderFade.opacity(-30), 0);
  assert.equal(HeaderFade.opacity(0), 0);
  assert.equal(HeaderFade.opacity(12), 0.5);
  assert.equal(HeaderFade.opacity(240), 1);
});

test('timetable fade is opaque at the top, clear at the bottom, and keeps the today column tint', () => {
  const w = 380;
  const h = HeaderFade.HEIGHT;
  const ctx = gradientCanvas();
  drawTimetableFade(ctx, w, h, true);
  assert.equal(ctx.fills.length, 2);

  const [base, today] = ctx.fills;
  assert.deepEqual(base.rect, [0, 0, w, h]);
  assert.deepEqual(base.style.axis, [0, 0, 0, h]);
  assert.deepEqual(base.style.stops[0], [0, 'rgba(251,252,254,1.000)']);
  assert.deepEqual(base.style.stops.at(-1), [1, 'rgba(251,252,254,0.000)']);

  const gridLeft = Math.max(48, w * 0.11);
  const colW = (w - gridLeft) / 7;
  const dow = EasTimetable.dowOfMs(Date.now());
  assert.deepEqual(today.rect, [gridLeft + (dow - 1) * colW, 0, colW, h]);
  assert.deepEqual(today.style.stops[0], [0, 'rgba(46,134,232,0.060)']);
  assert.deepEqual(today.style.stops.at(-1), [1, 'rgba(46,134,232,0.000)']);

  const other = gradientCanvas();
  drawTimetableFade(other, w, h, false);
  assert.equal(other.fills.length, 1);
});

test('tabs swipe between neighbours except over a timetable grid, whose swipes page weeks', () => {
  const home = read('pages/Home.ets');
  const shell = home.slice(home.indexOf('  build() {'), home.indexOf('  activeSheet()'));
  assert.match(shell, /Swiper\(this\.tabSwiper\)/);
  assert.match(shell, /\.loop\(false\)/);
  assert.match(shell, /\.disableSwipe\(this\.tabSwipeLocked\(\)\)/);
  // The empty timetable state has no week paging, so it keeps switching tabs.
  assert.match(home, /private tabSwipeLocked\(\): boolean \{\s*return this\.currentTab === TAB_TIMETABLE && this\.currentTimetable !== undefined;/);
  assert.match(shell, /\.onGestureSwipe\(/);
  assert.match(shell, /\.onChange\(\(index: number\) => \{\s*this\.selectTab\(index\);\s*this\.pinNav\(index\);/);
  assert.match(shell, /\.translate\(\{ x: this\.tabSwipeOffset \}\)/);
  assert.match(shell, /\.duration\(TAB_SWIPE_MS\)/);
  assert.match(home, /private navHighlight\(\): number \{\s*return Math\.max\(0, Math\.min\(NAV_TAB_COUNT - 1, Math\.round\(this\.navPos\)\)\);/);
  assert.match(home, /this\.navPos = Math\.max\(0, Math\.min\(NAV_TAB_COUNT - 1, index - pageOffsetX \/ this\.tabPageWidth\)\);/);
  assert.doesNotMatch(home.slice(home.indexOf('  private followTabSwipe'), home.indexOf('  private pinNav')), /animateTo/);
  assert.match(home, /PanGesture\(\{ direction: PanDirection\.Horizontal/);
  assert.match(home, /handleChromeTabPanEnd/);
  assert.match(home, /this\.tabSwiper\.changeIndex\(target, false\)/);
});

test('week paging commits on a shorter drag or a quick flick', () => {
  const home = read('pages/Home.ets');
  const ratio = Number(/const TIMETABLE_SWIPE_RATIO: number = ([\d.]+);/.exec(home)[1]);
  assert.ok(ratio > 0 && ratio < 0.15, String(ratio));
  const panEnd = home.slice(home.indexOf('  private handleTimetablePanEnd'), home.indexOf('  private gotoCurrentTimetableWeek'));
  assert.match(panEnd, /event\.velocityX/);
  assert.match(panEnd, /width \* TIMETABLE_SWIPE_RATIO/);
});

test('news, notices and the timetable fade content scrolling under their headers', () => {
  for (const file of ['feature/news/NewsTab.ets', 'pages/NoticesPage.ets']) {
    const source = read(file);
    assert.match(source, /HeaderFadeMask\(\{ maskOpacity: this\.fadeOpacity/, file);
    assert.match(source, /\.onDidScroll\(\(\) => \{\s*this\.fadeOpacity = HeaderFade\.opacity\(/, file);
  }
  const home = read('pages/Home.ets');
  const tab = home.slice(home.indexOf('  tabTimetable()'), home.indexOf('  statusBanner('));
  assert.match(tab, /HeaderFadeMask\(\{[\s\S]*headerHeight: this\.timetableChromeH/);
  assert.match(tab, /Blank\(\)\.height\(this\.timetableChromeH\)/);
  assert.match(tab, /this\.timetableDateHeader\(\)/);
});

test('notices and the function centre share the transparent header that content scrolls under', () => {
  const home = read('pages/Home.ets');
  const more = home.slice(home.indexOf('  tabMine()'), home.indexOf('  userCard()'));
  assert.match(more, /HeaderFadeMask\(\{[\s\S]*?headerHeight: MORE_HEADER_HEIGHT/);
  assert.match(more, /Text\('功能中心'\)[\s\S]*?\.hitTestBehavior\(HitTestMode\.Transparent\)/);

  const tab = home.slice(home.indexOf('  tabTimetable()'), home.indexOf('  statusBanner('));
  assert.match(tab, /HeaderFadeMask\(\{[\s\S]*headerHeight: this\.timetableChromeH/);
  assert.match(tab, /Blank\(\)\.height\(this\.timetableChromeH\)/);
  assert.match(tab, /this\.timetableDateHeader\(\)/);

  const notices = read('pages/NoticesPage.ets');
  const page = notices.slice(notices.indexOf('  build()'));
  assert.match(page, /HeaderFadeMask\(\{[^}]*headerHeight: HEADER_HEIGHT/);
  assert.match(page, /Row\(\) \{\s*HeaderBackButton\(\{[\s\S]*?\.height\(HEADER_HEIGHT\)[\s\S]*?\.hitTestBehavior\(HitTestMode\.Transparent\)/);
  assert.doesNotMatch(page, /\.border\(\{ width: \{ bottom: 1 \}/);
  // The first list row reserves the header height so notices start below it, then scroll beneath.
  assert.match(page, /List\(\{[^)]*\}\) \{\s*\/\/[^\n]*\n\s*ListItem\(\) \{\s*Column\(\)\s*\.width\('100%'\)\s*\.height\(HEADER_HEIGHT\)/);

  assert.equal(HeaderFade.HEADER_ALPHAS[0], 1);
  assert.equal(HeaderFade.HEADER_ALPHAS.at(-1), 0);
});

test('function-centre secondary pages use the same transparent header', () => {
  const pages = ['NoticesPage', 'ScorePage', 'ExamPage',
    'ImportTimetablePage', 'TimetableManagerPage', 'TimetableDetailPage'];
  for (const page of pages) {
    const source = read(`pages/${page}.ets`);
    const build = source.slice(source.indexOf('  build()'));
    assert.match(build, /HeaderFadeMask\(\{[\s\S]*?headerHeight: HEADER_HEIGHT/, page);
    assert.match(build, /Row\(\) \{\s*HeaderBackButton\(\{[\s\S]*?\.height\(HEADER_HEIGHT\)[\s\S]*?\.hitTestBehavior\(HitTestMode\.Transparent\)/, page);
    assert.doesNotMatch(build, /\.border\(\{ width: \{ bottom: 1 \}/, page);
  }
});
