const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const cache = new Map();

class Predicates {
  constructor(table) {
    this.table = table;
    this.filters = [];
  }
  equalTo(column, value) {
    this.filters.push([column, value]);
    return this;
  }
}

function load(file) {
  file = path.resolve(root, file);
  if (cache.has(file)) return cache.get(file).exports;
  const mod = { exports: {} };
  cache.set(file, mod);
  const source = fs.readFileSync(file, 'utf8');
  const js = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  new Function('require', 'module', 'exports', js)(name => {
    if (name === '@kit.PerformanceAnalysisKit') return { hilog: { error() {} } };
    if (name === '@kit.ArkData') return { relationalStore: { RdbPredicates: Predicates } };
    if (name.startsWith('@kit.')) return {};
    return load(path.resolve(path.dirname(file), name + '.ets'));
  }, mod, mod.exports);
  return mod.exports;
}

const { RdbHelper } = load('common/db/RdbHelper.ets');

function database(options = {}) {
  const rows = {
    subject: [
      { id: 'course-a', timetableId: 'table-a' },
      { id: 'course-a', timetableId: 'table-b' },
      { id: 'course-b', timetableId: 'table-a' }
    ],
    events: [
      { id: 'one', subjectId: 'course-a', timetableId: 'table-a', type: 'CLASS' },
      { id: 'two', subjectId: 'course-a', timetableId: 'table-a', type: 'CLASS' },
      { id: 'exam', subjectId: 'course-a', timetableId: 'table-a', type: 'EXAM' },
      { id: 'other-table', subjectId: 'course-a', timetableId: 'table-b', type: 'CLASS' },
      { id: 'other-course', subjectId: 'course-b', timetableId: 'table-a', type: 'CLASS' }
    ]
  };
  const calls = [];
  const db = new RdbHelper();
  db.store = {
    createTransaction: async () => {
      const snapshot = structuredClone(rows);
      return {
        delete: async pred => {
          calls.push(['delete', pred.table, pred.filters]);
          if (options.failOn === pred.table) throw Error('disk full');
          const before = rows[pred.table].length;
          rows[pred.table] = rows[pred.table].filter(row =>
            !pred.filters.every(([column, value]) => row[column] === value));
          return before - rows[pred.table].length;
        },
        commit: async () => { calls.push(['commit']); },
        rollback: async () => {
          calls.push(['rollback']);
          rows.subject = snapshot.subject;
          rows.events = snapshot.events;
        }
      };
    }
  };
  return { db, rows, calls };
}

test('whole-course deletion removes only matching CLASS sessions and preserves linked exams', async () => {
  const { db, rows, calls } = database();
  await db.deleteCourseWithClasses('course-a', 'table-a');
  assert.deepEqual(rows.subject.map(row => row.timetableId + ':' + row.id),
    ['table-b:course-a', 'table-a:course-b']);
  assert.deepEqual(rows.events.map(row => row.id),
    ['exam', 'other-table', 'other-course']);
  assert.deepEqual(calls, [
    ['delete', 'subject', [['id', 'course-a'], ['timetableId', 'table-a']]],
    ['delete', 'events', [['subjectId', 'course-a'], ['timetableId', 'table-a'], ['type', 'CLASS']]],
    ['commit']
  ]);
});

test('failed deletion and missing course roll back without touching other rows', async () => {
  const failed = database({ failOn: 'events' });
  const before = structuredClone(failed.rows);
  await assert.rejects(failed.db.deleteCourseWithClasses('course-a', 'table-a'), /disk full/);
  assert.deepEqual(failed.rows, before);
  assert.deepEqual(failed.calls.at(-1), ['rollback']);

  const missing = database();
  await assert.rejects(missing.db.deleteCourseWithClasses('missing', 'table-a'), /no longer exists/);
  assert.deepEqual(missing.calls.map(call => call[0]), ['delete', 'rollback']);
  await assert.rejects(missing.db.deleteCourseWithClasses('', 'table-a'), /identity/);
});

async function confirmCourse(choice, fail = false, reminderFail = false) {
  const source = fs.readFileSync(path.join(root, 'pages/TimetableDetailPage.ets'), 'utf8');
  const method = source.slice(source.indexOf('  private confirmDeleteCourse('),
    source.indexOf('  private cycleColor(')).replace('private confirmDeleteCourse', 'confirmDeleteCourse');
  const js = ts.transpileModule('class Host { ' + method + ' }; module.exports = Host;', {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const mod = { exports: {} };
  const calls = { deleted: [], closed: 0, animated: 0, reminders: 0, dialogs: [], toasts: [] };
  const rdb = { getInstance: () => ({ deleteCourseWithClasses: async (...ids) => {
    calls.deleted.push(ids);
    if (fail) throw Error('disk full');
  } }) };
  new Function('RdbHelper', 'HitaColors', '$r', 'Curve', 'EasEventType', 'module', js)(
    rdb, { error: 'red' }, value => value, { EaseInOut: 'ease' }, { CLASS: 'CLASS' }, mod);
  const host = new mod.exports();
  host.detailScroller = { closeAllSwipeActions() { calls.closed++; } };
  host.subjectRows = [
    { subject: { id: 'course-a', timetableId: 'table-a', name: '物理' }, classCount: 2 },
    { subject: { id: 'course-b', timetableId: 'table-a', name: '数学' }, classCount: 1 }
  ];
  host.eventRows = [
    { subjectId: 'course-a', timetableId: 'table-a', type: 'CLASS' },
    { subjectId: 'course-a', timetableId: 'table-a', type: 'EXAM' },
    { subjectId: 'course-a', timetableId: 'table-b', type: 'CLASS' },
    { subjectId: 'course-b', timetableId: 'table-a', type: 'CLASS' }
  ];
  host.expandedSubjectId = 'course-a';
  host.resyncReminders = async () => {
    calls.reminders++;
    if (reminderFail) throw Error('notification unavailable');
  };
  host.getUIContext = () => ({
    animateTo: (_options, callback) => { calls.animated++; callback(); },
    getPromptAction: () => ({
      showDialog: async options => { calls.dialogs.push(options); return { index: choice }; },
      showToast: options => { calls.toasts.push(options.message); }
    })
  });
  host.confirmDeleteCourse(host.subjectRows[0]);
  await new Promise(resolve => setImmediate(resolve));
  return { host, calls };
}

test('cancel and write failure leave the course visible; success removes only its class rows', async () => {
  const cancelled = await confirmCourse(0);
  assert.equal(cancelled.calls.closed, 1);
  assert.match(cancelled.calls.dialogs[0].message, /全部 2 次课/);
  assert.deepEqual(cancelled.calls.deleted, []);
  assert.equal(cancelled.host.subjectRows.length, 2);

  const failed = await confirmCourse(1, true);
  assert.deepEqual(failed.calls.deleted, [['course-a', 'table-a']]);
  assert.equal(failed.host.subjectRows.length, 2);
  assert.equal(failed.calls.animated, 0);
  assert.deepEqual(failed.calls.toasts, ['删除失败，请重试']);

  const saved = await confirmCourse(1);
  assert.deepEqual(saved.host.subjectRows.map(row => row.subject.id), ['course-b']);
  assert.deepEqual(saved.host.eventRows.map(row => row.type), ['EXAM', 'CLASS', 'CLASS']);
  assert.equal(saved.host.expandedSubjectId, '');
  assert.equal(saved.calls.animated, 1);
  assert.equal(saved.calls.reminders, 1);
  assert.deepEqual(saved.calls.toasts, ['课程及全部课时已删除']);

  const reminderFailed = await confirmCourse(1, false, true);
  assert.equal(reminderFailed.host.subjectRows.length, 1);
  assert.deepEqual(reminderFailed.calls.toasts, ['课程已删除，但提醒同步失败']);
});

test('detail page uses native left swipe, confirmation and animated expansion', () => {
  const source = fs.readFileSync(path.join(root, 'pages/TimetableDetailPage.ets'), 'utf8');
  const build = source.slice(source.indexOf('  build()'), source.indexOf('  private static dateText('));
  const toggle = source.slice(source.indexOf('  private toggleSubject('),
    source.indexOf('  private async saveSubjectCredit('));
  const deleteAction = source.slice(source.indexOf('  private courseDeleteAction('),
    source.indexOf('  private sessionRow('));
  assert.match(build, /List\(\{ scroller: this\.detailScroller \}\)/);
  assert.match(build, /ListItem\(\) \{\s*this\.courseGroupCard\(row\)\s*\}\s*\.swipeAction\(\{\s*end:/);
  assert.match(build, /edgeEffect: SwipeEdgeEffect\.None/);
  assert.match(source, /deleteCourseWithClasses\(subjectId, timetableId\)/);
  assert.match(source, /if \(ret\.index !== 1\)/);
  assert.match(source, /event\.type !== EasEventType\.CLASS/);
  assert.match(source, /private confirmDeleteEvent\(event: EasEventItem\)/);
  assert.match(toggle, /animateTo\(\{ duration: 220, curve: Curve\.EaseInOut \}/);
  assert.match(source, /\.transition\(TransitionEffect\.OPACITY\)/);
  assert.match(deleteAction, /SymbolGlyph\(\$r\('sys\.symbol\.trash'\)\)/);
  assert.doesNotMatch(deleteAction, /\.shadow\(/);
});
