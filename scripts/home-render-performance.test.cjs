const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const home = fs.readFileSync(path.resolve(__dirname, '../entry/src/main/ets/pages/Home.ets'), 'utf8');
const slice = (start, end) => {
  const from = home.indexOf(start);
  const to = home.indexOf(end, from);
  assert.ok(from >= 0 && to > from, start);
  return home.slice(from, to);
};

function harness() {
  const queued = [];
  const intervals = [];
  const code = `
    class Home {
      currentTab = 0;
      selectedNav = 0;
      pageVisible = true;
      tabTransitionRunning = false;
      sheetRequestGeneration = 0;
      timetableMarqueeCallback;
      timetableMarqueeGeneration = 0;
      timetableMarqueeElapsedMs = 500;
      timetableMarqueeLastFrameMs = -1;
      timetablePlaceLabels = [{}];
      timetableAreaW = 380;
      timetableCanvasHeight = 800;
      timetablePlaceCanvas = {};
      clockTimer = -1;
      classReminderEnabled = false;
      dayKey = 'today';
      nowTick = 0;
      paints = 0;
      highlights = 0;
      refreshes = 0;
      getUIContext() { return context; }
      drawTimetableNow() { this.paints++; }
      updateTodayHighlights() { this.highlights++; }
      refreshSummaries() { this.refreshes++; }
      ${slice('  private closeActiveSheet()', '  private requestCalendarExport()')}
      ${slice('  private startClock()', '  async refreshSummaries()')}
      ${slice('  private selectTab(', '  private dockPageInset()')}
    }`;
  const output = ts.transpileModule(code, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const context = {
    postFrameCallback: callback => queued.push(callback),
    postDelayedFrameCallback: callback => queued.push(callback)
  };
  const clock = { day: 'today', printDate() { return this.day; } };
  const page = new Function('context', 'TimetableMarqueeCallback', 'drawTimetablePlaces', 'TAB_TIMETABLE',
    'setInterval', 'EasTimeTools', output + '; return new Home();')(
    context, class { constructor(callback) { this.run = callback; } },
    () => 1200, 1, callback => { intervals.push(callback); return 1; }, clock);
  return { page, queued, intervals, clock };
}

test('returning to the cached timetable resumes labels without repainting the full grid', () => {
  const { page, queued } = harness();
  page.selectTab(1);
  assert.equal(page.paints, 0);
  assert.equal(queued.length, 1);
  assert.equal(page.timetableMarqueeElapsedMs, 500);
  page.selectTab(2);
  queued.shift().run(1000);
  assert.equal(queued.length, 0, 'stale label callbacks cannot keep running on More');
  page.selectTab(1);
  assert.equal(queued.length, 1);
  assert.equal(page.paints, 0);
});

test('tab transitions pause labels and resume once even when change precedes animation end', () => {
  const { page, queued } = harness();
  page.tabTransitionRunning = true;
  page.selectTab(1);
  page.startTimetableMarquee();
  assert.equal(queued.length, 0);
  page.finishTabAnimation(1);
  assert.equal(queued.length, 1);
  page.selectTab(1);
  page.finishTabAnimation(1);
  assert.equal(queued.length, 1);
  assert.equal(page.selectedNav, 1);
  assert.equal(page.paints, 0);
});

test('a cancelled swipe resumes the current timetable and restores the selected indicator', () => {
  const { page, queued } = harness();
  page.selectTab(1);
  page.tabTransitionRunning = true;
  page.stopTimetableMarquee();
  page.selectedNav = 2;
  queued.shift().run(1000);
  assert.equal(queued.length, 0);
  page.finishTabAnimation(1);
  assert.equal(page.selectedNav, 1);
  assert.equal(queued.length, 1);
  assert.equal(page.paints, 0);
});

test('animation end before change also resumes only one label callback', () => {
  const { page, queued } = harness();
  page.tabTransitionRunning = true;
  page.finishTabAnimation(1);
  page.selectTab(1);
  assert.equal(page.currentTab, 1);
  assert.equal(queued.length, 1);
  page.finishTabAnimation(2);
  queued.shift().run(2000);
  assert.equal(queued.length, 0);
  assert.equal(page.currentTab, 2);
  assert.equal(page.selectedNav, 2);
});

test('finishing on another page or hiding the page never starts background label frames', () => {
  for (const hidden of [false, true]) {
    const { page, queued } = harness();
    page.pageVisible = !hidden;
    page.tabTransitionRunning = true;
    page.finishTabAnimation(hidden ? 1 : 2);
    assert.equal(queued.length, 0);
  }
});

test('the clock updates Today without repainting a static grid and still refreshes at midnight', () => {
  const { page, intervals, clock } = harness();
  page.startClock();
  page.startClock();
  assert.equal(intervals.length, 1);
  for (let i = 0; i < 4; i++) intervals[0]();
  assert.equal(page.highlights, 4);
  assert.equal(page.paints, 0);
  assert.equal(page.refreshes, 0);
  clock.day = 'tomorrow';
  intervals[0]();
  assert.equal(page.refreshes, 1);
  intervals[0]();
  assert.equal(page.refreshes, 1);
});

test('data, appearance, wallpaper, week and geometry changes still repaint the timetable', () => {
  assert.match(slice('  async refreshSummaries()', '  private classReminderSubtitle'),
    /this\.drawTimetableNow\(\)/);
  assert.match(slice('  private onAppearanceChanged()', '  private timetableInk'),
    /this\.drawTimetableNow\(\)/);
  assert.match(slice('  private shiftTimetableWeek(', '  private timetableDragLimit'),
    /this\.drawTimetableNow\(\)/);
  assert.match(slice('  private onTimetableArea(', '  private hasTimetableBackground'),
    /this\.drawTimetableNow\(\)/);
  const tab = slice('  tabTimetable()', '  statusBanner(');
  assert.match(tab, /if \(width !== this\.timetableAreaW \|\| height !== this\.timetableAreaH\)/);
  assert.match(tab, /height !== this\.timetableChromeH[\s\S]*this\.onTimetableArea/);
  assert.match(home, /onAnimationStart[\s\S]*?this\.tabTransitionRunning = true;[\s\S]*?this\.stopTimetableMarquee\(\)/);
  assert.match(home, /onAnimationEnd[\s\S]*?this\.finishTabAnimation\(index\)/);
});
