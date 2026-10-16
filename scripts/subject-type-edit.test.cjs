const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');
const { DatabaseSync } = require('node:sqlite');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const compile = source => ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;
const cache = new Map();
function load(file) {
  file = path.resolve(root, file);
  if (cache.has(file)) return cache.get(file).exports;
  const mod = { exports: {} };
  cache.set(file, mod);
  new Function('require', 'module', 'exports', compile(fs.readFileSync(file, 'utf8')))(name => {
    if (name === '@kit.ArkData') return { relationalStore: { RdbPredicates: class {
      constructor(table) { this.table = table; this.filters = []; }
      equalTo(key, value) { this.filters.push([key, value]); return this; }
    } } };
    if (name === '@kit.PerformanceAnalysisKit') return { hilog: { error() {}, info() {} } };
    if (name.startsWith('@kit.')) return {};
    return load(path.resolve(path.dirname(file), name + '.ets'));
  }, mod, mod.exports);
  return mod.exports;
}
const { RdbHelper } = load('common/db/RdbHelper.ets');
const { EasTermSubject, EasSubjectType } = load('common/model/timetable/TimetableModels.ets');
const source = read('pages/TimetableDetailPage.ets');

function harness() {
  const methods = source.slice(source.indexOf('  private async chooseSubjectType('),
    source.indexOf('  @Builder\n  private infoCard('));
  const rowModel = source.slice(source.indexOf('class TimetableSubjectRow'), source.indexOf('@Entry'));
  const typeName = source.slice(source.indexOf('  private static typeName('),
    source.indexOf('  private static sessionDateText('));
  const calls = { writes: [], scrolls: [], toasts: [], menus: [] };
  const db = { saveSubjectType: async (...args) => calls.writes.push(args) };
  const make = new Function('EasTermSubject', 'EasSubjectType', 'RdbHelper', 'HitaColors', '$r',
    compile(`${rowModel}
    class TimetableDetailPage {
      subjectTypeMenuOpen = false;
      ${methods}
      ${typeName}
    }
    return new TimetableDetailPage();`));
  const page = make(EasTermSubject, EasSubjectType, { getInstance: () => db },
    { primary: 'blue' }, value => value);
  page.subjectRows = ['first', 'target', 'last'].map(id => ({
    subject: Object.assign(new EasTermSubject(), {
      id, timetableId: 'term', name: id, type: EasSubjectType.COM_A, credit: 2,
      color: 1234, code: 'course-' + id, field: 'field', school: 'school', key: 'key',
      countInSPA: true, createdAt: 10
    }),
    classCount: 30, sessions: Array.from({ length: 30 }, (_, n) => ({ id: id + n }))
  }));
  page.expandedSubjectId = 'target';
  page.creditDraft = '2';
  page.eventRows = [{ id: 'lesson' }];
  page.load = () => assert.fail('Changing a type must not reload or reorder the whole list');
  page.detailScroller = { scrollToIndex: (...args) => calls.scrolls.push(args) };
  page.getUIContext = () => ({ getPromptAction: () => ({
    showActionMenu: async options => { calls.menus.push(options); return { index: 1 }; },
    showToast: options => calls.toasts.push(options.message)
  }) });
  return { page, db, calls };
}

test('type selection refreshes the course summary while keeping expansion, drafts and scroll unchanged', async () => {
  const { page, calls } = harness();
  const previous = page.subjectRows.slice();
  const events = page.eventRows;
  await page.chooseSubjectType(previous[1]);
  assert.deepEqual(calls.writes, [['target', 'term', EasSubjectType.COM_B]]);
  assert.deepEqual(page.subjectRows.map(row => row.subject.id), ['first', 'target', 'last']);
  assert.equal(page.subjectRows[0], previous[0]);
  assert.equal(page.subjectRows[2], previous[2]);
  assert.notEqual(page.subjectRows[1], previous[1]);
  assert.deepEqual(page.subjectRows[1].subject, {
    ...previous[1].subject, type: EasSubjectType.COM_B
  });
  assert.equal(previous[1].subject.type, EasSubjectType.COM_A, 'no mutation through stale builder arguments');
  assert.equal(page.subjectRows[1].sessions, previous[1].sessions);
  assert.equal(page.eventRows, events);
  assert.equal(page.expandedSubjectId, 'target');
  assert.equal(page.creditDraft, '2');
  assert.equal(page.subjectTypeMenuOpen, false);
  assert.deepEqual(calls.scrolls, [], 'changing a type must not reposition the page');
  assert.deepEqual(calls.toasts, []);
  page.expandedSubjectId = 'target';
  await page.chooseSubjectType(page.subjectRows[1]);
  assert.equal(calls.writes.length, 1, 'selecting the current type requires no additional write');
  assert.equal(calls.menus[1].buttons[1].color, 'blue', 'reopened selection uses the saved type');
  assert.equal(page.expandedSubjectId, 'target');
});

test('cancel and a failed save leave the original type, expansion and scroll untouched', async () => {
  for (const cancel of [true, false]) {
    const { page, db, calls } = harness();
    const rows = page.subjectRows;
    db.saveSubjectType = async () => { throw Error('disk full'); };
    if (cancel) page.getUIContext = () => ({ getPromptAction: () => ({
      showActionMenu: async () => { throw Error('cancel'); }
    }) });
    await page.chooseSubjectType(rows[1]);
    assert.equal(page.subjectRows, rows);
    assert.equal(rows[1].subject.type, EasSubjectType.COM_A);
    assert.equal(page.expandedSubjectId, 'target');
    assert.equal(page.subjectTypeMenuOpen, false);
    assert.deepEqual(calls.scrolls, []);
    assert.deepEqual(calls.toasts, cancel ? [] : ['课程类型保存失败，请重试']);
  }
});

test('a pending save does not publish success early or collapse another opened course', async () => {
  const { page, db, calls } = harness();
  let finish;
  db.saveSubjectType = () => new Promise(resolve => { finish = resolve; });
  const pending = page.chooseSubjectType(page.subjectRows[1]);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(page.subjectRows[1].subject.type, EasSubjectType.COM_A);
  await page.chooseSubjectType(page.subjectRows[1]);
  assert.equal(calls.menus.length, 1, 'prevent overlapping type menus');
  page.expandedSubjectId = 'last';
  finish();
  await pending;
  assert.equal(page.subjectRows[1].subject.type, EasSubjectType.COM_B);
  assert.equal(page.expandedSubjectId, 'last');
  assert.deepEqual(calls.scrolls, []);
});

test('a course removed during a write is not reinserted into the visible list', async () => {
  const { page, db, calls } = harness();
  db.saveSubjectType = async () => {
    page.subjectRows = page.subjectRows.filter(row => row.subject.id !== 'target');
  };
  await page.chooseSubjectType(page.subjectRows[1]);
  assert.deepEqual(page.subjectRows.map(row => row.subject.id), ['first', 'last']);
  assert.deepEqual(calls.scrolls, []);
});

test('both nested builders receive reactive state by reference, without changing course identity keys', () => {
  assert.match(source, /ForEach\(this\.subjectRows, \(row: TimetableSubjectRow\)/);
  assert.match(source, /this\.courseGroupCard\(\{\s*subject: this\.currentSubjectRow\(row\)\.subject,\s*classCount: this\.currentSubjectRow\(row\)\.classCount,\s*sessions: this\.currentSubjectRow\(row\)\.sessions\s*\}\)/);
  assert.match(source, /this\.subjectCard\(\{ subject: row\.subject, classCount: row\.classCount, sessions: row\.sessions \}\)/);
  assert.match(source, /\}, \(row: TimetableSubjectRow\) => row\.subject\.id\)/);
});

test('database type update preserves SQLite row order and every other subject field', async () => {
  const sql = new DatabaseSync(':memory:');
  const databaseSource = read('common/db/RdbHelper.ets');
  const schema = databaseSource.slice(databaseSource.indexOf('const CREATE_SUBJECT:'),
    databaseSource.indexOf('const CREATE_EVENTS:'));
  sql.exec(new Function(compile(schema + '\nreturn CREATE_SUBJECT;'))());
  const rows = harness().page.subjectRows;
  for (const row of rows) {
    const values = RdbHelper.subjectValues(row.subject);
    const fields = Object.keys(values);
    sql.prepare(`INSERT INTO subject (${fields.join(',')}) VALUES (${fields.map(() => '?').join(',')})`)
      .run(...fields.map(key => values[key]));
  }
  const db = new RdbHelper();
  db.store = { update: async (values, pred) => {
    const fields = Object.keys(values);
    return sql.prepare(`UPDATE ${pred.table} SET ${fields.map(key => key + '=?').join(',')} WHERE ` +
      pred.filters.map(([key]) => key + '=?').join(' AND '))
      .run(...fields.map(key => values[key]), ...pred.filters.map(([, value]) => value)).changes;
  } };
  try {
    const before = sql.prepare('SELECT rowid, * FROM subject ORDER BY credit DESC').all();
    await db.saveSubjectType('target', 'term', EasSubjectType.OPT_A);
    const after = sql.prepare('SELECT rowid, * FROM subject ORDER BY credit DESC').all();
    assert.deepEqual(after.map(row => ({ ...row })), before.map(row => ({
      ...row, type: row.id === 'target' ? 'OPT_A' : row.type
    })));
    assert.equal(RdbHelper.subjectTypeOf(after[1].type), EasSubjectType.OPT_A);
    await assert.rejects(db.saveSubjectType('target', 'wrong-term', EasSubjectType.MOOC), /no longer exists/);
    await assert.rejects(db.saveSubjectType('missing', 'term', EasSubjectType.MOOC), /no longer exists/);
    await assert.rejects(db.saveSubjectType('', 'term', EasSubjectType.MOOC), /identity/);
    sql.exec("CREATE TRIGGER reject_type BEFORE UPDATE ON subject BEGIN SELECT RAISE(ABORT, 'disk failure'); END;");
    await assert.rejects(db.saveSubjectType('target', 'term', EasSubjectType.MOOC), /disk failure/);
    assert.equal(sql.prepare("SELECT type FROM subject WHERE id='target'").get().type, 'OPT_A');
    assert.equal(sql.prepare('SELECT COUNT(*) AS n FROM subject').get().n, 3);
  } finally {
    sql.close();
  }
});
