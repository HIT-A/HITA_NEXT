const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');
const root = path.resolve(__dirname, '../entry/src/main');
function load(file, overrides = {}, cache = new Map()) {
  file = path.resolve(root, 'ets', file);
  if (cache.has(file)) return cache.get(file).exports;
  const module = { exports: {} };
  cache.set(file, module);
  const code = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  new Function('require', 'module', 'exports', code)(name => {
    if (overrides[name]) return overrides[name];
    if (name === '@kit.PerformanceAnalysisKit') return { hilog: { warn() {} } };
    if (name.startsWith('@kit.')) return {};
    return load(path.resolve(path.dirname(file), name + '.ets'), overrides, cache);
  }, module, module.exports);
  return module.exports;
}
const { NextClassModel } = load('feature/widget/NextClassModel.ets');
const now = new Date(2026, 9, 16, 8, 0).getTime();
const minute = 60000;
const course = (id, offset, overrides = {}) => ({
  id, type: 'CLASS', name: '高等数学', place: '正心楼 101', teacher: '王老师',
  from: now + offset * minute, to: now + (offset + 45) * minute, ...overrides
});
function view(events, at = now, exists = true) {
  const data = NextClassModel.snapshot(events, exists, now);
  return NextClassModel.view(data.scheduleJson, data.hasTimetable, data.dataState, at);
}
test('prefers an ongoing class over the next class and excludes exams and invalid events', () => {
  const result = view([course('late', 90), course('exam', 1, { type: 'EXAM' }),
    course('started', -10, { name: '当前课程', teacher: '李老师', place: '博学楼 101' }),
    course('negative', 2, { to: now }), course('bad', NaN),
    course('next', 15, { name: '大学物理', teacher: '陈老师', place: '格物楼 202' })]);
  assert.equal(result.title, '当前课程');
  assert.equal(result.isOngoing, true);
  assert.equal(result.countdown, '35');
  assert.equal(result.countdownUnit, '分钟后下课');
  assert.equal(result.progressPercent, 22);
  assert.equal(result.place, '博学楼 101');
  assert.equal(result.teacher, '李老师');
});
test('cached payload shows ongoing course progress and advances when the class ends', () => {
  const events = [course('one', -30, { place: '正心楼 101', teacher: '王老师' }),
    course('two', 30, { name: '英语', place: '格物楼 202', teacher: '陈老师' })];
  const current = view(events);
  assert.equal(current.title, '高等数学');
  assert.equal(current.isOngoing, true);
  assert.equal(current.countdown, '15');
  assert.equal(current.countdownUnit, '分钟后下课');
  assert.equal(current.progressPercent, 66);
  assert.equal(current.place, '正心楼 101');
  assert.equal(current.teacher, '王老师');
  const next = view(events, now + 15 * minute);
  assert.equal(next.title, '英语');
  assert.equal(next.isOngoing, false);
  assert.equal(next.countdown, '15');
  assert.equal(next.countdownUnit, '分钟后上课');
  assert.equal(next.place, '格物楼 202');
  assert.equal(next.teacher, '陈老师');
  const started = view(events, now + 30 * minute);
  assert.equal(started.title, '英语');
  assert.equal(started.isOngoing, true);
  assert.equal(started.countdown, '45');
  assert.equal(started.countdownUnit, '分钟后下课');
  assert.equal(started.progressPercent, 0);
});
test('rounds up partial minutes and displays hours, days and cross-day start times', () => {
  assert.equal(view([course('one', 0.1)]).countdown, '1');
  assert.equal(view([course('hour', 61)]).countdown, '1小时1分');
  assert.equal(view([course('tomorrow', 1440)]).title, '暂无待上课程');
  assert.equal(view([course('later', 2880 + 60)]).title, '暂无待上课程');
});

test('only displays the earliest upcoming class from the current calendar day', () => {
  const result = view([course('tomorrow', 1440), course('today', 90)]);
  assert.equal(result.title, '高等数学');
  assert.equal(result.countdown, '1小时30分');
});
test('represents no timetable, no upcoming classes, loading and read failures separately', () => {
  assert.equal(view([], now, false).title, '还没有课表');
  assert.equal(view([]).title, '暂无待上课程');
  assert.equal(NextClassModel.view('[]', false, 'loading', now).title, '正在读取课表');
  assert.equal(NextClassModel.view('[]', false, 'error', now).title, '课表暂不可用');
  assert.equal(NextClassModel.view('bad json', true, 'ready', now).title, '课表暂不可用');
  assert.equal(NextClassModel.view('{}', true, 'ready', now).title, '课表暂不可用');
});
test('uses fallbacks for missing fields and never exposes credentials in its bounded payload', () => {
  const result = view([course('one', 10, { name: ' NULL ', place: ' ', teacher: '' })]);
  assert.equal(result.title, '未命名课程');
  assert.equal(result.place, '地点待定');
  assert.equal(result.teacher, '教师待定');
  const events = Array.from({ length: 90 }, (_, i) => course(String(i), i + 1, { cookie: 'secret' }));
  const snapshot = NextClassModel.snapshot(events, true, now);
  assert.equal(JSON.parse(snapshot.scheduleJson).length, 64);
  assert.ok(!snapshot.scheduleJson.includes('cookie'));
  assert.ok(!snapshot.scheduleJson.includes('secret'));
  assert.equal(NextClassModel.snapshot(events, false, now).scheduleJson, '[]');
});
test('reads the chosen timetable, falls back when deleted, and never requests academic login', async () => {
  let selected = 'chosen';
  let exists = true;
  const readIds = [];
  const { NextClassWidgetService: service } = load('feature/widget/NextClassWidgetService.ets', {
    '../../common/db/RdbHelper': { RdbHelper: { getInstance: () => ({
      init: async () => {},
      getTimetableById: async id => exists ? { id } : undefined,
      getEventsOfTimetable: async id => { readIds.push(id); return []; }
    }) } },
    '../timetable/data/TimetableSelectionStore': { TimetableSelectionStore: { getInstance: () => ({
      init: async () => {}, load: async () => selected
    }) } },
    '../timetable/data/TimetableResolver': { TimetableResolver: { getForDisplay: async () => ({ id: 'fallback' }) } }
  });
  assert.equal((await service.load({})).dataState, 'ready');
  exists = false;
  await service.load({});
  assert.deepEqual(readIds, ['chosen', 'fallback']);
  const source = fs.readFileSync(path.join(root, 'ets/feature/widget/NextClassWidgetService.ets'), 'utf8');
  assert.doesNotMatch(source, /EasApiClient|EasSessionStore|fetch/);
});
test('refreshes each published card and tolerates a card removed during refresh', async () => {
  const published = [];
  const { NextClassWidgetService: service } = load('feature/widget/NextClassWidgetService.ets', {
    '@kit.FormKit': {
      formBindingData: { createFormBindingData: value => value },
      formProvider: {
        getPublishedRunningFormInfos: async () => [
          { formId: '1', formName: 'NextClassCard', moduleName: 'entry' },
          { formId: '2', formName: 'NextClassCard', moduleName: 'entry' },
          { formId: '3', formName: 'AnotherCard', moduleName: 'entry' }
        ],
        updateForm: async (id, data) => { published.push([id, data.dataState]); if (id === '1') throw Error('removed'); }
      }
    }
  });
  service.context = {};
  service.load = async () => ({ scheduleJson: '[]', dataState: 'ready', hasTimetable: false });
  await service.refreshAll();
  assert.deepEqual(published, [['1', 'ready'], ['2', 'ready']]);
});
test('publishes the latest schedule when edits race a slow database read', async () => {
  const published = [];
  const { NextClassWidgetService: service } = load('feature/widget/NextClassWidgetService.ets', {
    '@kit.FormKit': { formBindingData: { createFormBindingData: value => value }, formProvider: {
      getPublishedRunningFormInfos: async () => [{ formId: '1', formName: 'NextClassCard', moduleName: 'entry' }],
      updateForm: async (_id, data) => published.push(data.scheduleJson)
    } }
  });
  service.context = {};
  let reads = 0;
  service.load = async () => {
    if (++reads === 1) { service.revision++; return { scheduleJson: 'old' }; }
    return { scheduleJson: 'new' };
  };
  await service.refreshAll();
  assert.deepEqual(published, ['new']);
});
test('registers both sizes, dynamic clock and periodic provider refresh', () => {
  const config = JSON.parse(fs.readFileSync(path.join(root, 'resources/base/profile/next_class_form_config.json'))).forms[0];
  assert.deepEqual(config.supportDimensions, ['2*2', '2*4']);
  assert.equal(config.isDynamic, true);
  assert.equal(config.updateEnabled, true);
  assert.equal(config.updateDuration, 1);
  const module = JSON.parse(fs.readFileSync(path.join(root, 'module.json5')));
  assert.equal(module.module.extensionAbilities.find(item => item.name === 'NextClassFormAbility').type, 'form');
  const ui = fs.readFileSync(path.join(root, 'ets/widget/pages/NextClassCard.ets'), 'utf8');
  assert.ok(ui.includes('TextClock()'));
  assert.match(ui, /onDateChange/);
  assert.ok(ui.includes('@Entry(storage)'));
  assert.match(ui, /@State place: string/);
  assert.match(ui, /@State teacher: string/);
  assert.match(ui, /@State progressPercent: number/);
  assert.match(ui, /this\.place = nextView\.place/);
  assert.match(ui, /this\.teacher = nextView\.teacher/);
  assert.match(ui, /this\.progressPercent = nextView\.progressPercent/);
  assert.match(ui, /Text\(this\.progressPercent\.toString\(\) \+ '%'\)/);
  assert.match(ui, /Progress\(\{ value: this\.progressPercent, total: 100, type: ProgressType\.Ring \}\)/);
  assert.match(ui, /\.width\(compact \? 44 : 52\)/);
  assert.match(ui, /\.height\(compact \? 44 : 52\)/);
  assert.match(ui, /\.color\('#2365B2'\)/);
  assert.match(ui, /Stack\(\{ alignContent: Alignment\.Center \}\)/);
  assert.doesNotMatch(ui, /this\.view\.(place|teacher)/);
  assert.doesNotMatch(ui, /setInterval|setTimeout/);
});

test('passes each requested widget size to initial storage without resetting it on schedule updates', () => {
  const refreshed = [];
  const { default: Ability } = load('widget/NextClassFormAbility.ets', {
    '@kit.FormKit': {
      FormExtensionAbility: class {},
      formBindingData: { createFormBindingData: value => value },
      formInfo: { FormParam: { IDENTITY_KEY: 'id', DIMENSION_KEY: 'dimension' } }
    },
    '../feature/widget/NextClassWidgetService': {
      NextClassWidgetService: { refreshForm: async (_context, id) => refreshed.push(id) }
    }
  });
  const ability = new Ability();
  assert.equal(ability.onAddForm({ parameters: { id: 'compact', dimension: 2 } }).formDimension, 2);
  assert.equal(ability.onAddForm({ parameters: { id: 'wide', dimension: 3 } }).formDimension, 3);
  assert.deepEqual(refreshed, ['compact', 'wide']);
  assert.equal(Object.hasOwn(NextClassModel.snapshot([], false, now), 'formDimension'), false);
});

test('a provider update retries when the selected timetable changes during its read', async () => {
  const published = [];
  const { NextClassWidgetService: service } = load('feature/widget/NextClassWidgetService.ets', {
    '@kit.FormKit': { formBindingData: { createFormBindingData: value => value }, formProvider: {
      updateForm: async (id, data) => published.push([id, data.scheduleJson])
    } }
  });
  let reads = 0;
  service.load = async () => {
    if (++reads === 1) { service.revision++; return { scheduleJson: 'old' }; }
    return { scheduleJson: 'new' };
  };
  await service.refreshForm({}, 'wide');
  assert.deepEqual(published, [['wide', 'new']]);
});
