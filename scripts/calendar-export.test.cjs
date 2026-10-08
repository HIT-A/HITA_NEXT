const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
function harness() {
  const state = { timetables: new Map(), events: [], calendars: [], permissions: [0, 0],
    permissionCalls: 0, calendarCalls: 0, nextId: 1, failAt: 0, failAfterInsert: false,
    failRead: false, failDelete: false, failCreate: false, permissionGate: undefined, queryArgs: [] };
  const makeCalendar = account => ({
    id: state.calendars.length + 1, rows: [], getAccount: () => account,
    async getEvents(...args) {
      state.queryArgs.push(args);
      // Match native overload dispatch: an omitted filter works, explicit undefined does not.
      if (args.length > 0 && (args[0] === undefined || args[0] === null)) {
        throw Object.assign(new Error('Parameter error: invalid event filter'), { code: 401 });
      }
      if (state.failRead) throw new Error('Read failed');
      return this.rows.map(row => ({ ...row }));
    },
    async addEvent(event) {
      if (state.failAt === state.nextId && !state.failAfterInsert) return -1;
      const id = state.nextId++;
      this.rows.push({ ...event, id });
      if (state.failAfterInsert) {
        state.failAfterInsert = false;
        throw new Error('Committed but response lost');
      }
      return id;
    },
    async updateEvent(event) {
      const index = this.rows.findIndex(row => row.id === event.id);
      assert.ok(index >= 0);
      this.rows[index] = { ...event };
    },
    async deleteEvent(id) {
      if (state.failDelete) throw new Error('Delete failed');
      this.rows = this.rows.filter(row => row.id !== id);
    }
  });
  const api = {
    CalendarType: { LOCAL: 'local' }, EventType: { NORMAL: 0 },
    getCalendarManager() {
      state.calendarCalls++;
      return {
        async getAllCalendars() { return state.calendars; },
        async createCalendar(account) {
          if (state.failCreate) return { id: -1 };
          const calendar = makeCalendar(account);
          state.calendars.push(calendar);
          return calendar;
        }
      };
    }
  };
  const rdb = {
    async init() {},
    async getTimetableById(id) { return state.timetables.get(id); },
    async getEventsOfTimetable(id) { return state.events.filter(event => event.timetableId === id); }
  };
  const cache = new Map();
  function load(file) {
    file = path.resolve(root, file);
    if (cache.has(file)) return cache.get(file).exports;
    const mod = { exports: {} };
    cache.set(file, mod);
    const platform = name => {
      if (name.endsWith('/db/RdbHelper')) return { RdbHelper: { getInstance: () => rdb } };
      if (name === '@kit.CalendarKit') return { calendarManager: api };
      if (name === '@kit.AbilityKit') return { abilityAccessCtrl: { createAtManager: () => ({
        async requestPermissionsFromUser(ctx, permissions) {
          state.permissionCalls++;
          assert.deepEqual(permissions, ['ohos.permission.READ_CALENDAR', 'ohos.permission.WRITE_CALENDAR']);
          if (state.permissionGate) await state.permissionGate;
          return { authResults: state.permissions };
        }
      }) } };
      if (name === '@kit.PerformanceAnalysisKit') return { hilog: { error() {}, info() {} } };
      if (name.startsWith('@kit.')) return {};
      return load(path.resolve(path.dirname(file), name + '.ets'));
    };
    const compiled = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
    }).outputText;
    new Function('require', 'module', 'exports', compiled)(platform, mod, mod.exports);
    return mod.exports;
  }
  const { EasTimetable, EasEventItem } = load('common/model/timetable/TimetableModels.ets');
  const { TimetableCalendarExporter: exporter } = load('feature/timetable/data/TimetableCalendarExporter.ets');
  const timetable = Object.assign(new EasTimetable(), { id: 'term-a', name: '2026 秋季' });
  state.timetables.set(timetable.id, timetable);
  const course = (overrides = {}) => Object.assign(new EasEventItem(), {
    timetableId: timetable.id, name: '高等数学', teacher: '张老师', place: 'A101',
    from: Date.parse('2026-10-05T08:30:00+08:00'), to: Date.parse('2026-10-05T10:15:00+08:00'),
    fromNumber: 1, lastNumber: 2
  }, overrides);
  const run = (selected = timetable) => exporter.exportTimetable({}, selected);
  return { state, course, timetable, run, exporter, makeCalendar };
}

test('exports exact occurrences, including nonconsecutive weeks, exams, locations and teacher', async () => {
  const h = harness();
  h.state.events = [h.course(), h.course({ from: Date.parse('2026-10-19T18:45:00+08:00'),
    to: Date.parse('2026-10-19T20:30:00+08:00') }), h.course({ type: 'EXAM', name: '数学考试' }),
    h.course({ type: 'OTHER', name: '研讨会' }), h.course({ type: 'TAG' }),
    h.course({ timetableId: 'another' })];
  const result = await h.run();
  assert.equal(result.success, true);
  assert.equal(result.total, 4);
  const rows = h.state.calendars[0].rows;
  assert.equal(rows[0].startTime, Date.parse('2026-10-05T00:30:00Z'));
  assert.equal(rows[0].endTime, Date.parse('2026-10-05T02:15:00Z'));
  assert.equal(rows[0].timeZone, 'Asia/Shanghai');
  assert.equal(rows[0].isAllDay, false);
  assert.equal(rows[0].location.location, 'A101');
  assert.equal(rows[0].description, '课表：2026 秋季\n教师：张老师\n节次：第 1-2 节');
  assert.equal(rows[1].startTime, Date.parse('2026-10-19T10:45:00Z'));
  assert.equal(rows[1].recurrenceRule, undefined);
  assert.equal(h.state.calendars[0].getAccount().displayName, 'HITA · 2026 秋季');
});

test('native calendar query accepts omitted filters and returns identifiers for duplicate detection', async () => {
  const h = harness();
  h.state.events = [h.course()];
  assert.equal((await h.run()).success, true);
  const calendar = h.state.calendars[0];
  const firstId = calendar.rows[0].id;
  await assert.rejects(calendar.getEvents(undefined, ['id', 'identifier']), { code: 401 });
  assert.equal((await h.run()).success, true);
  assert.deepEqual(h.state.queryArgs, [[], [undefined, ['id', 'identifier']], []]);
  assert.equal(calendar.rows.length, 1);
  assert.equal(calendar.rows[0].id, firstId);
});

test('repeated exports and regenerated local IDs reuse the same calendar events', async () => {
  const h = harness();
  h.state.events = [h.course(), h.course()];
  assert.equal((await h.run()).total, 1);
  const id = h.state.calendars[0].rows[0].id;
  h.state.events = [h.course({ teacher: '李老师', place: 'B202' })];
  assert.equal((await h.run()).success, true);
  assert.equal(h.state.calendars.length, 1);
  assert.equal(h.state.calendars[0].rows.length, 1);
  assert.equal(h.state.calendars[0].rows[0].id, id);
  assert.equal(h.state.calendars[0].rows[0].location.location, 'B202');
  assert.match(h.state.calendars[0].rows[0].description, /李老师/);
});

test('changed dates replace stale exports while preserving user events and other timetables', async () => {
  const h = harness();
  h.state.events = [h.course()];
  await h.run();
  const calendar = h.state.calendars[0];
  const oldId = calendar.rows[0].id;
  calendar.rows.push({ id: 999, title: 'Personal' });
  const unrelated = h.makeCalendar({ name: 'personal', type: 'local' });
  unrelated.rows.push({ id: 1000, title: 'Appointment' });
  h.state.calendars.push(unrelated);
  const shifted = h.course({ from: h.course().from + 86400000, to: h.course().to + 86400000 });
  h.state.events = [shifted];
  assert.equal((await h.run()).success, true);
  assert.equal(calendar.rows.some(row => row.id === oldId), false);
  assert.equal(calendar.rows.some(row => row.id === 999), true);
  assert.deepEqual(unrelated.rows, [{ id: 1000, title: 'Appointment' }]);
  const second = { ...h.timetable, id: 'term-b' };
  h.state.timetables.set(second.id, second);
  h.state.events.push(h.course({ timetableId: second.id }));
  await h.run(second);
  assert.equal(h.state.calendars.length, 3);
  assert.equal(calendar.rows.length, 2);
});

test('permission denial, empty and deleted timetables do not access or mutate calendars', async () => {
  const h = harness();
  assert.equal((await h.exporter.exportTimetable({}, undefined)).success, false);
  assert.match((await h.run()).message, /没有可导出/);
  assert.equal(h.state.permissionCalls, 0);
  h.state.events = [h.course()];
  for (const permissions of [[0, -1], [-1, 0], [-1, -1], []]) {
    h.state.permissions = permissions;
    assert.match((await h.run()).message, /日历权限/);
  }
  assert.equal(h.state.calendarCalls, 0);
  h.state.timetables.clear();
  assert.match((await h.run()).message, /已删除/);
});

test('invalid event times fail before requesting permissions or exporting partial data', async () => {
  for (const overrides of [{ from: NaN }, { to: Infinity }, { from: 0 },
    { from: 10, to: 10 }, { from: 20, to: 10 }, { from: 1e20, to: 2e20 }]) {
    const h = harness();
    h.state.events = [h.course(), h.course(overrides)];
    assert.match((await h.run()).message, /无效的课程时间/);
    assert.equal(h.state.permissionCalls, 0);
    assert.equal(h.state.calendars.length, 0);
  }
});

test('partial failure can be retried without duplicates and does not prune previous exports', async () => {
  const h = harness();
  h.state.events = [h.course({ name: 'Old course' })];
  await h.run();
  h.state.events = [h.course(), h.course({ name: 'Physics' })];
  h.state.failAt = 3;
  const failed = await h.run();
  assert.equal(failed.success, false);
  assert.match(failed.message, /1\/2/);
  assert.equal(h.state.calendars[0].rows.length, 2);
  h.state.failAt = 0;
  assert.equal((await h.run()).success, true);
  assert.deepEqual(h.state.calendars[0].rows.map(row => row.title), ['高等数学', 'Physics']);
});

test('a committed write with a lost response is discovered on retry', async () => {
  const h = harness();
  h.state.events = [h.course()];
  h.state.failAfterInsert = true;
  assert.equal((await h.run()).success, false);
  assert.equal((await h.run()).success, true);
  assert.equal(h.state.calendars[0].rows.length, 1);
});

test('failed reads do not cause duplicate inserts; failed calendar creation is not success', async () => {
  const h = harness();
  h.state.events = [h.course()];
  h.state.failCreate = true;
  assert.equal((await h.run()).success, false);
  h.state.failCreate = false;
  await h.run();
  h.state.failRead = true;
  assert.equal((await h.run()).success, false);
  assert.equal(h.state.calendars[0].rows.length, 1);
});

test('failed stale-event deletion reports incomplete export and recovers on retry', async () => {
  const h = harness();
  h.state.events = [h.course()];
  await h.run();
  h.state.events = [h.course({ name: 'New course' })];
  h.state.failDelete = true;
  assert.equal((await h.run()).success, false);
  h.state.failDelete = false;
  assert.equal((await h.run()).success, true);
  assert.deepEqual(h.state.calendars[0].rows.map(row => row.title), ['New course']);
});

test('simultaneous exports share a lock that is released after completion', async () => {
  const h = harness();
  h.state.events = [h.course()];
  let release;
  h.state.permissionGate = new Promise(resolve => { release = resolve; });
  const first = h.run();
  assert.match((await h.run()).message, /正在导出/);
  release();
  assert.equal((await first).success, true);
  assert.equal((await h.run()).success, true);
  assert.equal(h.state.calendars[0].rows.length, 1);
});

function confirmationHarness() {
  const h = harness();
  h.state.events = [h.course()];
  const source = fs.readFileSync(path.join(root, 'pages/Home.ets'), 'utf8');
  const start = source.indexOf('  private openCalendarExportSheet()');
  const end = source.indexOf('  private async importIcsTimetable()', start);
  assert.ok(start >= 0 && end > start);
  const compiled = ts.transpileModule(`class Confirmation {
    ${source.slice(start, end)}
  }`, { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText;
  const Page = new Function('TimetableCalendarExporter', compiled + '\nreturn Confirmation;')(h.exporter);
  const page = new Page();
  const toasts = [];
  Object.assign(page, {
    currentTimetable: h.timetable, calendarExporting: false, calendarExportSheetOpen: false,
    activeSheetVisible: false, calendarExportConfirmed: false
  });
  page.getUIContext = () => ({
    getHostContext: () => ({}), getPromptAction: () => ({ showToast: item => toasts.push(item.message) })
  });
  const dismiss = async () => {
    page.activeSheetVisible = false;
    page.finishCalendarExportSheet();
    await new Promise(setImmediate);
  };
  return { ...h, page, toasts, dismiss, source };
}

test('export entry opens a bottom sheet; only explicit confirmation can start a calendar export', async () => {
  const h = confirmationHarness();
  const { page } = h;
  assert.match(h.source, /this\.currentTimetable\.name, \(\) => \{\s*this\.openCalendarExportSheet\(\);/);
  assert.match(h.source, /onDisappear: \(\) => \{[\s\S]*?this\.finishCalendarExportSheet\(\);/);
  assert.match(h.source, /else if \(this\.calendarExportSheetOpen[\s\S]*?this\.calendarExportSheet\(/);
  assert.match(h.source, /Button\('取消'\)[\s\S]*?this\.activeSheetVisible = false;/);
  assert.match(h.source, /Button\('确认导出'\)[\s\S]*?this\.confirmCalendarExport\(\);/);
  page.openCalendarExportSheet();
  assert.equal(page.activeSheetVisible, true);
  assert.equal(page.calendarExportTimetable, h.timetable);
  assert.equal(h.state.permissionCalls, 0);
  assert.equal(h.state.calendarCalls, 0);
  page.confirmCalendarExport();
  assert.equal(page.activeSheetVisible, false);
  assert.equal(page.calendarExportSheetOpen, true, 'content remains during dismissal animation');
  assert.equal(h.state.permissionCalls, 0, 'permission UI waits for sheet dismissal');
  await h.dismiss();
  assert.equal(h.state.permissionCalls, 1);
  assert.equal(h.state.calendars[0].rows.length, 1);
  assert.equal(page.calendarExportSheetOpen, false);
  assert.equal(page.calendarExportTimetable, undefined);
  assert.equal(page.calendarExportConfirmed, false);
  assert.match(h.toasts.at(-1), /已将 1 条日程导出/);
});

test('cancel, swipe dismissal and reopening never carry over consent', async () => {
  const h = confirmationHarness();
  for (let i = 0; i < 2; i++) {
    h.page.openCalendarExportSheet();
    await h.dismiss();
    h.page.confirmCalendarExport();
    assert.equal(h.state.permissionCalls, 0);
    assert.equal(h.state.calendarCalls, 0);
  }
  h.page.openCalendarExportSheet();
  h.page.confirmCalendarExport();
  await h.dismiss();
  h.page.openCalendarExportSheet();
  assert.equal(h.page.calendarExportConfirmed, false);
  await h.dismiss();
  assert.equal(h.state.permissionCalls, 1);
});

test('confirmation exports the displayed timetable, not a subsequently changed selection', async () => {
  const h = confirmationHarness();
  h.page.openCalendarExportSheet();
  h.page.currentTimetable = { ...h.timetable, id: 'different' };
  h.page.confirmCalendarExport();
  await h.dismiss();
  assert.equal(h.state.calendars[0].getAccount().name, 'hita-timetable-term-a');
});

test('rapid taps and repeated dismissal callbacks cannot duplicate a confirmed export', async () => {
  const h = confirmationHarness();
  let release;
  h.state.permissionGate = new Promise(resolve => { release = resolve; });
  h.page.openCalendarExportSheet();
  h.page.confirmCalendarExport();
  h.page.confirmCalendarExport();
  h.page.openCalendarExportSheet();
  assert.equal(h.page.activeSheetVisible, false);
  await h.dismiss();
  assert.equal(h.page.calendarExporting, true);
  h.page.openCalendarExportSheet();
  h.page.confirmCalendarExport();
  await h.dismiss();
  assert.equal(h.page.activeSheetVisible, false);
  assert.equal(h.state.permissionCalls, 1);
  release();
  await new Promise(setImmediate);
  assert.equal(h.page.calendarExporting, false);
  assert.equal(h.state.calendars[0].rows.length, 1);
});

test('missing or deleted timetables do not request calendar permissions', async () => {
  const h = confirmationHarness();
  h.page.currentTimetable = undefined;
  h.page.openCalendarExportSheet();
  assert.equal(h.page.activeSheetVisible, false);
  assert.match(h.toasts.at(-1), /请先新建或导入/);
  h.page.currentTimetable = h.timetable;
  h.page.openCalendarExportSheet();
  h.state.timetables.clear();
  h.page.confirmCalendarExport();
  await h.dismiss();
  assert.equal(h.state.permissionCalls, 0);
  assert.equal(h.page.calendarExporting, false);
  assert.match(h.toasts.at(-1), /已删除/);
});
