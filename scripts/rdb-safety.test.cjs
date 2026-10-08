const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const { DatabaseSync } = require('node:sqlite');
const ts = require('typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');

function load(file, mocks = {}, cache = new Map()) {
  file = path.resolve(root, file);
  if (cache.has(file)) return cache.get(file).exports;
  const mod = { exports: {} };
  cache.set(file, mod);
  const code = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const requireLocal = name => {
    if (name in mocks) return mocks[name];
    if (name === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, warn() {}, error() {} } };
    if (name.startsWith('@kit.')) return {};
    return load(path.resolve(path.dirname(file), name + '.ets'), mocks, cache);
  };
  new Function('require', 'module', 'exports', code)(requireLocal, mod, mod.exports);
  return mod.exports;
}
class Predicates {
  constructor(table) { this.table = table; this.clauses = []; this.args = []; this.order = ''; }
  equalTo(column, value) { this.clauses.push(`"${column}" = ?`); this.args.push(value); return this; }
  in(column, values) {
    this.clauses.push(`"${column}" IN (${values.map(() => '?').join(',')})`);
    this.args.push(...values); return this;
  }
  orderByAsc(column) { this.order = ` ORDER BY "${column}" ASC`; return this; }
  orderByDesc(column) { this.order = ` ORDER BY "${column}" DESC`; return this; }
  get where() { return this.clauses.length ? ` WHERE ${this.clauses.join(' AND ')}` : ''; }
}
const { EasTimetable, EasTermSubject, EasEventItem } = load('common/model/timetable/TimetableModels.ets');
const { EasCourseItem, EasTermItem } = load('feature/eas/model/EasModels.ets');
const { EasCampus, EasSession } = load('feature/eas/EasSession.ets');
const { EasTimetableImporter } = load('feature/eas/EasTimetableImporter.ets');
const settle = () => new Promise(setImmediate);
function deferred() {
  let resolve;
  return { promise: new Promise(done => { resolve = done; }), resolve: () => resolve() };
}
function setup(t) {
  const sql = new DatabaseSync(':memory:');
  t.after(() => sql.close());
  const calls = { opens: 0, deletes: 0, commits: 0, rollbacks: 0 };
  const store = {
    failId: '', pause: undefined,
    executeSql: async statement => { sql.exec(statement); },
    insert: async (table, values, conflict) => {
      if (store.pause) { const pause = store.pause; store.pause = undefined; await pause; }
      if (values.id === store.failId) throw Error('simulated write failure');
      const columns = Object.keys(values);
      const verb = conflict === 'REPLACE' ? 'INSERT OR REPLACE' : 'INSERT';
      return Number(sql.prepare(`${verb} INTO "${table}" (${columns.map(c => `"${c}"`).join(',')})
        VALUES (${columns.map(() => '?').join(',')})`).run(...columns.map(c => values[c])).lastInsertRowid);
    },
    update: async (values, pred) => Number(sql.prepare(
      `UPDATE "${pred.table}" SET ${Object.keys(values).map(c => `"${c}" = ?`).join(',')}${pred.where}`)
      .run(...Object.values(values), ...pred.args).changes),
    delete: async pred => {
      calls.deletes++;
      return Number(sql.prepare(`DELETE FROM "${pred.table}"${pred.where}`).run(...pred.args).changes);
    },
    query: async pred => {
      const rows = sql.prepare(`SELECT * FROM "${pred.table}"${pred.where}${pred.order}`).all(...pred.args);
      let index = -1;
      return { goToNextRow: () => ++index < rows.length, getColumnIndex: name => name,
        getString: name => rows[index][name], getLong: name => rows[index][name],
        getDouble: name => rows[index][name], close() {} };
    },
    beginTransaction: () => sql.exec('BEGIN'),
    commit: () => { sql.exec('COMMIT'); calls.commits++; },
    rollBack: () => { sql.exec('ROLLBACK'); calls.rollbacks++; }
  };
  const { RdbHelper } = load('common/db/RdbHelper.ets', {
    '@kit.ArkData': { relationalStore: { SecurityLevel: { S1: 1 }, RdbPredicates: Predicates,
      ConflictResolution: { ON_CONFLICT_REPLACE: 'REPLACE' },
      getRdbStore: async () => { calls.opens++; return store; } } }
  });
  return { db: new RdbHelper(), store, calls, sql };
}
function fixtures() {
  const timetable = Object.assign(new EasTimetable(), { id: 'table', code: 'WEIHAI:2026-20271',
    name: 'Original', startTime: new Date(2026, 7, 31).getTime(), createdAt: 12345678 });
  const subject = Object.assign(new EasTermSubject(), { id: 'subject', timetableId: 'table', name: 'Math' });
  const event = (id, type = 'CLASS', timetableId = 'table') => Object.assign(new EasEventItem(), {
    id, type, timetableId, subjectId: subject.id, name: 'Math', from: 1000, to: 2000
  });
  return { timetable, subject, event };
}
test('concurrent cold starts wait for schema completion and a failed startup can retry', async t => {
  const { db, store, calls } = setup(t);
  const gate = deferred(), execute = store.executeSql;
  store.executeSql = async sql => { await gate.promise; await execute(sql); };
  const first = db.init({});
  await settle();
  let finished = false;
  const second = db.init({}).then(() => { finished = true; });
  await settle();
  assert.equal(finished, false);
  gate.resolve();
  await Promise.all([first, second]);
  assert.equal(calls.opens, 1);
  const failed = setup(t), original = failed.store.executeSql;
  failed.store.executeSql = async () => { throw Error('temporary storage failure'); };
  await assert.rejects(failed.db.init({}));
  failed.store.executeSql = original;
  await failed.db.init({});
  await failed.db.saveTimetable(fixtures().timetable);
});
test('failed row replacement preserves the original data without a delete', async t => {
  const { db, store, calls } = setup(t);
  await db.init({});
  const { timetable } = fixtures();
  await db.saveTimetable(timetable);
  store.failId = timetable.id;
  timetable.name = 'Modified';
  await assert.rejects(db.saveTimetable(timetable));
  assert.equal((await db.getTimetableById(timetable.id)).name, 'Original');
  assert.equal(calls.deletes, 0);
});
test('atomic course import preserves exams, other events and unrelated timetables', async t => {
  const { db, calls } = setup(t);
  await db.init({});
  const { timetable, subject, event } = fixtures();
  await db.saveTimetable(timetable);
  for (const item of [event('old'), event('exam', 'EXAM'), event('other', 'OTHER'),
    event('unrelated', 'CLASS', 'another')]) await db.saveEvent(item);
  await db.replaceImportedCourses(timetable, [subject], [event('new')]);
  assert.deepEqual((await db.getEventsOfTimetable('table')).map(e => e.id).sort(), ['exam', 'new', 'other']);
  assert.equal((await db.getEventsOfTimetable('another'))[0].id, 'unrelated');
  assert.equal(calls.commits, 1);
});
test('failed import rolls back all data; concurrent edits and reads wait outside the transaction', async t => {
  const { db, store, calls } = setup(t);
  await db.init({});
  const { timetable, subject, event } = fixtures();
  await db.saveTimetable(timetable);
  await db.saveEvent(event('old'));
  const gate = deferred();
  store.pause = gate.promise;
  store.failId = 'broken';
  timetable.name = 'Must roll back';
  const importing = assert.rejects(db.replaceImportedCourses(timetable, [subject], [event('new'), event('broken')]));
  const manual = db.saveEvent(event('exam', 'EXAM'));
  let finished = false;
  const reading = db.getEventsOfTimetable('table').then(rows => { finished = true; return rows; });
  await settle();
  assert.equal(finished, false);
  gate.resolve();
  await Promise.all([importing, manual]);
  assert.deepEqual((await reading).map(e => e.id).sort(), ['exam', 'old']);
  assert.equal((await db.getTimetableById('table')).name, 'Original');
  assert.equal((await db.getSubjectsOfTimetable('table')).length, 0);
  assert.equal(calls.rollbacks, 1);
});
test('invalid teaching weeks leave the old timetable intact before any write', async t => {
  const { db } = setup(t);
  await db.init({});
  const { timetable, event } = fixtures();
  await db.saveTimetable(timetable);
  await db.saveEvent(event('old'));
  const session = Object.assign(new EasSession(), { campus: EasCampus.WEIHAI });
  const term = Object.assign(new EasTermItem(), { yearCode: '2026-2027', termCode: '1' });
  for (const weeks of [[], [0], [NaN], [Infinity], [1.5], [100]]) {
    const course = Object.assign(new EasCourseItem(), {
      name: 'Math', dayOfWeek: 1, beginSection: 1, sectionCount: 2, weekNumbers: weeks
    });
    await assert.rejects(EasTimetableImporter.saveCourses(db, session, term, [course],
      EasTimetable.getWeihaiTimeStructure(), timetable.startTime));
    assert.equal((await db.getTimetableById('table')).name, 'Original');
    assert.deepEqual((await db.getEventsOfTimetable('table')).map(e => e.id), ['old']);
  }
});
test('reimport merges duplicate times and keeps identity, colours and teacher/place variants', async t => {
  const { db } = setup(t);
  await db.init({});
  const { timetable, subject } = fixtures();
  await db.saveTimetable(timetable);
  await db.saveSubject(subject);
  const session = Object.assign(new EasSession(), { campus: EasCampus.WEIHAI });
  const term = Object.assign(new EasTermItem(), { yearCode: '2026-2027', termCode: '1' });
  const first = Object.assign(new EasCourseItem(), { name: 'Math', dayOfWeek: 1,
    beginSection: 1, sectionCount: 2, weekNumbers: [1, 1, 3], teacher: 'A', classroom: '101' });
  const second = Object.assign(new EasCourseItem(), first, { teacher: 'B', classroom: '102' });
  const result = await EasTimetableImporter.saveCourses(db, session, term, [first, second],
    EasTimetable.getWeihaiTimeStructure(), timetable.startTime);
  assert.equal(result.id, timetable.id);
  assert.equal(result.createdAt, timetable.createdAt);
  assert.equal((await db.getSubjectsOfTimetable('table'))[0].color, subject.color);
  const events = await db.getEventsOfTimetable('table');
  assert.equal(events.length, 2);
  assert.equal(events[0].teacher, 'A/B');
  assert.equal(events[0].place, '101/102');
});
