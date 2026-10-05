const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
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
const { placeMarqueeFrame, PLACE_MARQUEE_PAUSE_MS, PLACE_MARQUEE_SPEED } =
  load('feature/timetable/views/PlaceMarquee.ets');
const { drawTimetableWeek, drawTimetablePlaces, TimetablePlaceLabel, timetableEventSpan,
  timetableBlockColor, argbToCss, TimetableDrawStyle } =
  load('feature/timetable/views/TimetableWeekDraw.ets');
const { EasEventItem, EasTimetable } = load('common/model/timetable/TimetableModels.ets');
const close = (actual, expected) => assert.ok(Math.abs(actual - expected) < 0.0001, `${actual} != ${expected}`);

test('fitting classrooms stay still and do not request animation frames', () => {
  for (const [text, width] of [[20, 30], [30, 30], [10, 0]]) {
    const frame = placeMarqueeFrame(9999, text, width);
    assert.equal(frame.offset, 0);
    assert.equal(frame.nextFrameDelayMs, -1);
  }
});

test('overflowing text pauses at its readable beginning, then moves at a time-based speed', () => {
  assert.equal(PLACE_MARQUEE_PAUSE_MS, 1200);
  assert.equal(PLACE_MARQUEE_SPEED, 30);
  assert.equal(placeMarqueeFrame(0, 90, 30).nextFrameDelayMs, 1200);
  assert.equal(placeMarqueeFrame(1199, 90, 30).offset, 0);
  assert.equal(placeMarqueeFrame(1200, 90, 30).nextFrameDelayMs, 0);
  close(placeMarqueeFrame(1950, 90, 30).offset, 22.5);
});

test('a complete loop wraps continuously and pauses for 1.2 seconds again', () => {
  const distance = 90 + 30 / 3;
  const cycle = 1200 + distance / 30 * 1000;
  close(placeMarqueeFrame(cycle - 0.01, 90, 30).offset, distance - 0.0003);
  close(placeMarqueeFrame(cycle, 90, 30).offset, 0);
  close(placeMarqueeFrame(cycle + 600, 90, 30).nextFrameDelayMs, 600);
  close(placeMarqueeFrame(cycle * 20 + 600, 90, 30).offset, 0);
  close(placeMarqueeFrame(cycle + 1500, 90, 30).offset, 9);
});

test('classrooms with different lengths pause independently', () => {
  const shortCycle = 1200 + 100 / 30 * 1000;
  assert.equal(placeMarqueeFrame(shortCycle + 200, 90, 30).offset, 0);
  assert.ok(placeMarqueeFrame(shortCycle + 200, 180, 30).offset > 0);
  assert.equal(placeMarqueeFrame(shortCycle + 200, 180, 30).nextFrameDelayMs, 0);
});

test('60 Hz, 120 Hz and delayed rendering reach the same position at the same time', () => {
  const offsetAfter = times => times.map(t => placeMarqueeFrame(t, 200, 30).offset).at(-1);
  const sixty = Array.from({ length: 121 }, (_, i) => i * 2000 / 120);
  const highRefresh = Array.from({ length: 241 }, (_, i) => i * 2000 / 240);
  close(offsetAfter(sixty), offsetAfter(highRefresh));
  close(offsetAfter([0, 800, 1400, 2000]), offsetAfter(sixty));
  close(offsetAfter(sixty), 24);
});

function canvas() {
  const ctx = { calls: [], font: '', textBaseline: 'alphabetic' };
  for (const method of ['clearRect', 'fillRect', 'fillText', 'beginPath', 'moveTo', 'lineTo',
    'quadraticCurveTo', 'closePath', 'fill', 'stroke', 'setLineDash', 'save', 'restore', 'rect', 'clip']) {
    ctx[method] = (...args) => ctx.calls.push([method, ...args]);
  }
  ctx.paints = [];
  for (const method of ['fill', 'stroke', 'fillText']) {
    const record = ctx[method];
    ctx[method] = (...args) => {
      ctx.paints.push({ method, color: method === 'stroke' ? ctx.strokeStyle : ctx.fillStyle, args });
      record(...args);
    };
  }
  ctx.measureText = text => {
    ctx.calls.push(['measureText', text]);
    return { width: text.length * 7 };
  };
  return ctx;
}

function fixture() {
  const timetable = new EasTimetable();
  timetable.startTime = new Date(2026, 8, 28).getTime();
  const first = new EasEventItem();
  first.name = 'Course A';
  first.place = 'M-building-118';
  first.from = timetable.startTime + 8 * 3600000;
  first.to = first.from + 105 * 60000;
  const second = new EasEventItem();
  second.name = 'Course B';
  second.place = 'A1';
  second.from = timetable.startTime + 24 * 3600000 + 10 * 3600000;
  second.to = second.from + 105 * 60000;
  return { timetable, events: [first, second] };
}

function luminance(argb) {
  const linear = shift => {
    const value = ((argb >>> shift) & 255) / 255;
    return value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * linear(16) + 0.7152 * linear(8) + 0.0722 * linear(0);
}

test('saved pastel colors and custom colors retain readable white text without changing the model palette', () => {
  const models = fs.readFileSync(path.join(root, 'common/model/timetable/TimetableModels.ets'), 'utf8');
  const detail = fs.readFileSync(path.join(root, 'pages/TimetableDetailPage.ets'), 'utf8');
  const colors = [...models.matchAll(/0xFF[0-9A-F]{6}/gi),
    ...detail.matchAll(/0xFF[0-9A-F]{6}/gi)].map(match => Number(match[0]));
  for (let r = 0; r <= 255; r += 51) {
    for (let g = 0; g <= 255; g += 51) {
      for (let b = 0; b <= 255; b += 51) colors.push(0xFF000000 | r << 16 | g << 8 | b);
    }
  }
  colors.push(0, 0xFFFFFFFF, 0xFF14213D);
  for (const color of colors) {
    const result = timetableBlockColor(color);
    assert.ok(1.05 / (luminance(result) + 0.05) >= 4.5, result.toString(16));
    assert.equal(result >>> 24, 255);
    assert.equal(timetableBlockColor(result), result);
    if (color !== 0 && luminance(color) <= 0.18) assert.equal(result, color >>> 0);
  }
  assert.equal(timetableBlockColor(0), timetableBlockColor(0xFF2E86E8));
});

test('course cards are opaque and titles and classrooms stay white without altering saved colors', () => {
  const { timetable, events } = fixture();
  events[0].color = 0xFFFFB74D;
  events[1].color = 0xFF81C784;
  const originalColors = events.map(event => event.color);
  const base = canvas();
  const labels = drawTimetableWeek(base, 380, 830, timetable, events, 1, false, 50, 0, false);
  const fills = base.paints.filter(paint => paint.method === 'fill');
  assert.deepEqual(fills.map(paint => paint.color),
    originalColors.map(color => argbToCss(timetableBlockColor(color), 1)));
  const firstCard = base.paints.findIndex(paint => paint.method === 'fill');
  const cardText = base.paints.slice(firstCard).filter(paint => paint.method === 'fillText');
  assert.ok(cardText.length >= 3);
  assert.ok(cardText.every(paint => paint.color === '#FFFFFF'));
  const overlay = canvas();
  drawTimetablePlaces(overlay, 380, 830, labels, 1600);
  assert.ok(overlay.paints.length > 0);
  assert.ok(overlay.paints.every(paint => paint.color === TimetableDrawStyle.blockText));
  assert.deepEqual(events.map(event => event.color), originalColors);
});

test('static layout draws short classrooms but caches only overflowing labels for animation', () => {
  const { timetable, events } = fixture();
  const base = canvas();
  const labels = drawTimetableWeek(base, 380, 830, timetable, events, 1, false, 50, 0, false);
  assert.equal(labels.length, 1);
  assert.equal(labels[0].text, events[0].place);
  assert.ok(base.calls.some(c => c[0] === 'fillText' && c[1] === 'A1'));
  assert.ok(!base.calls.some(c => c[0] === 'fillText' && c[1] === events[0].place));
  assert.equal(base.calls.filter(c => c[0] === 'measureText').length, 2);
  const repeated = drawTimetableWeek(canvas(), 380, 830, timetable, events, 1, false, 50, 0, false);
  assert.ok(labels[0].matches(repeated[0]));
  repeated[0].text += ' changed';
  assert.ok(!labels[0].matches(repeated[0]));
});

test('events with only a start hour or one section keep readable title and place text', () => {
  const { timetable } = fixture();
  const hourOnly = new EasEventItem();
  hourOnly.name = '办公时间安排';
  hourOnly.place = 'N-118';
  hourOnly.from = timetable.startTime + 8 * 3600000;
  hourOnly.to = 0;
  const hourSpan = timetableEventSpan(timetable, hourOnly, 1);
  assert.ok(hourSpan);
  assert.equal(hourSpan.to - hourSpan.from, 3600000);
  const hourCanvas = canvas();
  const hourLabels = drawTimetableWeek(hourCanvas, 380, 830, timetable, [hourOnly], 1, false, 50, 0, false);
  const hourTitleCalls = hourCanvas.calls.filter(c =>
    c[0] === 'fillText' && c[3] >= 30 && c[3] <= 60);
  assert.equal(hourTitleCalls.length, 2);
  assert.ok(hourTitleCalls[1][3] > hourTitleCalls[0][3]);
  assert.ok(hourLabels.some(label => label.text === 'N-118') ||
    hourCanvas.calls.some(c => c[0] === 'fillText' && String(c[1]).includes('N-118')));

  const onePeriod = new EasEventItem();
  onePeriod.name = '单节课程';
  onePeriod.place = 'M-201';
  onePeriod.from = timetable.startTime + 8 * 3600000 + 30 * 60000;
  onePeriod.to = 0;
  onePeriod.fromNumber = 1;
  onePeriod.lastNumber = 1;
  const periodSpan = timetableEventSpan(timetable, onePeriod, 1);
  assert.ok(periodSpan);
  assert.equal(periodSpan.from, onePeriod.from);
  assert.equal(periodSpan.to - periodSpan.from, 50 * 60000);
  const periodCanvas = canvas();
  const periodLabels = drawTimetableWeek(periodCanvas, 380, 830, timetable, [onePeriod], 1, false, 50, 0, false);
  assert.ok(periodCanvas.calls.some(c => c[0] === 'fillText' && String(c[1]).includes('单节')));
  assert.ok(periodLabels.some(label => label.text === 'M-201') ||
    periodCanvas.calls.some(c => c[0] === 'fillText' && String(c[1]).includes('M-201')));
});

test('animation redraws only clipped classroom text without measuring text or repainting the grid', () => {
  const { timetable, events } = fixture();
  const labels = drawTimetableWeek(canvas(), 380, 830, timetable, events, 1, false, 50, 0, false);
  const overlay = canvas();
  assert.equal(drawTimetablePlaces(overlay, 380, 830, labels, 0), 1200);
  assert.equal(drawTimetablePlaces(overlay, 380, 830, labels, 1600), 0);
  assert.ok(!overlay.calls.some(c => ['measureText', 'fillRect', 'stroke'].includes(c[0])));
  assert.equal(overlay.calls.filter(c => c[0] === 'clip').length, 2);
  assert.ok(overlay.calls.filter(c => c[0] === 'fillText').every(c => c[1] === labels[0].text));
  const positions = overlay.calls.filter(c => c[0] === 'fillText');
  close(positions[0][2] - positions[2][2], 12);
  assert.equal(drawTimetablePlaces(canvas(), 380, 830, [], 0), -1);
});

test('the overlay preserves vp font units even when the native canvas getter normalizes to pixels', () => {
  const { timetable, events } = fixture();
  const base = canvas();
  Object.defineProperty(base, 'font', {
    get: () => '10px sans-serif',
    set: () => {}
  });
  const labels = drawTimetableWeek(base, 380, 830, timetable, events, 1, false, 50, 0, false);
  assert.equal(labels[0].font, '10vp sans-serif');
});

test('the next wake-up is the earliest label pause ending, or the next vsync while one moves', () => {
  const a = new TimetablePlaceLabel();
  a.text = 'A';
  a.textWidth = 90;
  a.width = 30;
  const b = new TimetablePlaceLabel();
  b.text = 'B';
  b.textWidth = 105;
  b.width = 30;
  const bothPausedAt = 1200 + 115 / 30 * 1000 + 100;
  close(drawTimetablePlaces(canvas(), 380, 830, [a, b], bothPausedAt), 600);
  assert.equal(drawTimetablePlaces(canvas(), 380, 830, [a, b], 4600), 0);
});

test('the host uses cancellable-by-generation vsync callbacks and a non-interactive overlay', () => {
  const home = fs.readFileSync(path.join(root, 'pages/Home.ets'), 'utf8');
  const loop = home.slice(home.indexOf('  private startTimetableMarquee()'), home.indexOf('  async refreshSummaries()'));
  assert.match(home, /frameTimeInNano \/ 1000000/);
  assert.match(loop, /postFrameCallback\(callback\)/);
  assert.match(loop, /postDelayedFrameCallback\(callback, Math\.ceil\(nextDelay\)\)/);
  assert.match(loop, /generation !== this\.timetableMarqueeGeneration/);
  assert.match(loop, /drawTimetablePlaces/);
  assert.doesNotMatch(loop, /drawTimetableNow|drawTimetableWeek\(|eventsOfWeek/);
  assert.doesNotMatch(home, /timetableMarqueeTimer|timetableMarqueeOffset/);
  assert.match(home, /onPageHide\(\): void \{[\s\S]*?this\.stopTimetableMarquee\(\)/);
  assert.match(home, /Canvas\(this\.timetablePlaceCanvas\)[\s\S]*?\.hitTestBehavior\(HitTestMode\.None\)/);
});

test('timetable taps open detail for exams as well as classes', () => {
  const home = fs.readFileSync(path.join(root, 'pages/Home.ets'), 'utf8');
  const tap = home.slice(home.indexOf('  private openCourseAt'), home.indexOf('  private courseProgressText'));
  assert.match(tap, /event\.type === EasEventType\.CLASS \|\| event\.type === EasEventType\.EXAM/);
  assert.match(tap, /timetableEventSpan/);
  const detail = home.slice(home.indexOf('  courseDetailSheet'), home.indexOf('  courseDetailRow'));
  assert.match(detail, /event\.type === EasEventType\.EXAM \? '考试详情' : '课程详情'/);
  assert.match(home, /event\.type === EasEventType\.EXAM \? '考场' : '教室'/);
  assert.match(home, /if \(event\.type !== EasEventType\.EXAM\) \{[\s\S]*?Home\.coursePeriodText\(event\)/);
  assert.match(home, /'类型', '考试'/);
});
