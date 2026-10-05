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
  const compiled = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const localRequire = name => {
    if (name in mocks) return mocks[name];
    if (name === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, warn() {}, error() {} } };
    if (name.startsWith('@kit.')) return {};
    assert.ok(name.startsWith('.'), name);
    return load(path.resolve(path.dirname(file), name + '.ets'), mocks, cache);
  };
  new Function('require', 'module', 'exports', compiled)(localRequire, mod, mod.exports);
  return mod.exports;
}

class Predicates {
  constructor(table) { this.table = table; this.clauses = []; this.args = []; this.order = ''; }
  equalTo(column, value) { this.clauses.push(`"${column}" = ?`); this.args.push(value); return this; }
  in(column, values) {
    this.clauses.push(`"${column}" IN (${values.map(() => '?').join(',')})`);
    this.args.push(...values);
    return this;
  }
  orderByAsc(column) { this.order = ` ORDER BY "${column}" ASC`; return this; }
  orderByDesc(column) { this.order = ` ORDER BY "${column}" DESC`; return this; }
  get where() { return this.clauses.length ? ` WHERE ${this.clauses.join(' AND ')}` : ''; }
}

function deferred() {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
}
const {
  EasTimetable, EasTermSubject, EasEventItem, EasEventType
} = load('common/model/timetable/TimetableModels.ets');
const { EasCourseItem, EasTermItem } = load('feature/eas/model/EasModels.ets');
const { EasCampus, EasSession } = load('feature/eas/EasSession.ets');
const { EasTimetableImporter } = load('feature/eas/EasTimetableImporter.ets');

function setup(t) {
  const sql = new DatabaseSync(':memory:');
  t.after(() => sql.close());
  const calls = { opens: 0, deletes: 0, commits: 0, rollbacks: 0 };
  const store = {
    failId: '',
    pause: undefined,
    executeSql: async statement => { sql.exec(statement); },
    insert: async (table, values, conflict) => {
      if (store.pause) { const pause = store.pause; store.pause = undefined; await pause; }
      if (values.id === store.failId) throw new Error('simulated disk write failure');
      const columns = Object.keys(values);
      const verb = conflict === 'REPLACE' ? 'INSERT OR REPLACE' : 'INSERT';
      const result = sql.prepare(`${verb} INTO "${table}" (${columns.map(c => `"${c}"`).join(',')})
        VALUES (${columns.map(() => '?').join(',')})`).run(...columns.map(c => values[c]));
      return Number(result.lastInsertRowid);
    },
    delete: async pred => {
      calls.deletes++;
      return Number(sql.prepare(`DELETE FROM "${pred.table}"${pred.where}`).run(...pred.args).changes);
    },
    query: async pred => {
      const rows = sql.prepare(`SELECT * FROM "${pred.table}"${pred.where}${pred.order}`).all(...pred.args);
      let index = -1;
      return {
        goToNextRow: () => ++index < rows.length,
        getColumnIndex: name => name,
        getString: name => rows[index][name],
        getLong: name => rows[index][name],
        getDouble: name => rows[index][name],
        close() {}
      };
    },
    beginTransaction: () => { sql.exec('BEGIN'); },
    commit: () => { sql.exec('COMMIT'); calls.commits++; },
    rollBack: () => { sql.exec('ROLLBACK'); calls.rollbacks++; }
  };
  const { RdbHelper } = load('common/db/RdbHelper.ets', {
    '@kit.ArkData': { relationalStore: {
      SecurityLevel: { S1: 1 }, RdbPredicates: Predicates,
      ConflictResolution: { ON_CONFLICT_REPLACE: 'REPLACE' },
      getRdbStore: async () => { calls.opens++; return store; }
    } }
  });
  const db = new RdbHelper();
  return { db, store, calls, sql };
}

function fixtures() {
  const timetable = Object.assign(new EasTimetable(), {
    id: 'table', code: 'WEIHAI:2026-20271', name: 'Original',
    startTime: new Date(2026, 7, 31).getTime(), createdAt: 12345678
  });
  const subject = Object.assign(new EasTermSubject(), { id: 'subject', timetableId: 'table', name: 'Math' });
  const event = (id, type = EasEventType.CLASS, timetableId = 'table') =>
    Object.assign(new EasEventItem(), {
      id, type, timetableId, subjectId: subject.id, name: 'Math',
      from: new Date(2026, 7, 31, 8).getTime(), to: new Date(2026, 7, 31, 9).getTime()
    });
  return { timetable, subject, event };
}

test('concurrent cold starts wait for the same complete database initialization', async t => {
  const { db, store, calls } = setup(t);
  const gate = deferred();
  const execute = store.executeSql;
  store.executeSql = async sql => { await gate.promise; await execute(sql); };
  const first = db.init({});
  await new Promise(resolve => setImmediate(resolve));
  let secondFinished = false;
  const second = db.init({}).then(() => { secondFinished = true; });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(secondFinished, false, 'init must not resolve while schema creation is pending');
  gate.resolve();
  await Promise.all([first, second]);
  assert.equal(calls.opens, 1);
  await db.saveTimetable(fixtures().timetable);
});

test('schema initialization failure is retryable without reinstalling the app', async t => {
  const { db, store } = setup(t);
  const execute = store.executeSql;
  store.executeSql = async () => { throw new Error('temporary storage failure'); };
  await assert.rejects(db.init({}));
  store.executeSql = execute;
  await db.init({});
  await db.saveTimetable(fixtures().timetable);
  assert.equal((await db.getTimetables()).length, 1);
});

test('a failed row replacement leaves the original timetable intact', async t => {
  const { db, store, calls } = setup(t);
  await db.init({});
  const { timetable } = fixtures();
  await db.saveTimetable(timetable);
  store.failId = timetable.id;
  timetable.name = 'New name';
  await assert.rejects(db.saveTimetable(timetable), /write failure/);
  assert.equal((await db.getTimetableById(timetable.id)).name, 'Original');
  assert.equal(calls.deletes, 0);
});

test('course import is atomic and preserves exams and other timetables', async t => {
  const { db, calls } = setup(t);
  await db.init({});
  const { timetable, subject, event } = fixtures();
  await db.saveTimetable(timetable);
  await db.saveEvent(event('old'));
  await db.saveEvent(event('exam', EasEventType.EXAM));
  await db.saveEvent(event('other', EasEventType.OTHER));
  await db.saveEvent(event('unrelated', EasEventType.CLASS, 'another'));
  await db.replaceImportedCourses(timetable, [subject], [event('new')]);
  assert.deepEqual((await db.getEventsOfTimetable('table')).map(e => e.id).sort(), ['exam', 'new', 'other']);
  assert.equal((await db.getEventsOfTimetable('another'))[0].id, 'unrelated');
  assert.equal(calls.commits, 1);
});

test('an import write failure rolls back metadata, subjects and all replaced lessons', async t => {
  const { db, store, calls } = setup(t);
  await db.init({});
  const { timetable, subject, event } = fixtures();
  await db.saveTimetable(timetable);
  await db.saveEvent(event('old'));
  store.failId = 'broken';
  timetable.name = 'Should roll back';
  await assert.rejects(db.replaceImportedCourses(timetable, [subject], [event('new'), event('broken')]));
  assert.equal((await db.getTimetableById('table')).name, 'Original');
  assert.equal((await db.getSubjectsOfTimetable('table')).length, 0);
  assert.deepEqual((await db.getEventsOfTimetable('table')).map(e => e.id), ['old']);
  assert.equal(calls.rollbacks, 1);
  store.failId = '';
  await db.saveEvent(event('after-failure'));
});

test('concurrent edits and reads cannot enter or observe an unfinished import transaction', async t => {
  const { db, store } = setup(t);
  await db.init({});
  const { timetable, subject, event } = fixtures();
  await db.saveTimetable(timetable);
  const gate = deferred();
  store.pause = gate.promise;
  store.failId = 'broken';
  const importing = assert.rejects(db.replaceImportedCourses(timetable, [subject], [event('broken')]));
  let readFinished = false;
  const manual = db.saveEvent(event('manual', EasEventType.EXAM));
  const reading = db.getEventsOfTimetable('table').then(events => { readFinished = true; return events; });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(readFinished, false);
  gate.resolve();
  await Promise.all([importing, manual]);
  assert.deepEqual((await reading).map(e => e.id), ['manual']);
});

test('empty or invalid parsed teaching weeks leave an existing timetable untouched', async t => {
  const { db } = setup(t);
  await db.init({});
  const { timetable, event } = fixtures();
  await db.saveTimetable(timetable);
  await db.saveEvent(event('old'));
  const session = Object.assign(new EasSession(), { campus: EasCampus.WEIHAI });
  const term = Object.assign(new EasTermItem(), { yearCode: '2026-2027', termCode: '1', termName: 'New term' });
  for (const weeks of [[], [0], [NaN], [Infinity], [1.5]]) {
    const course = Object.assign(new EasCourseItem(), {
      name: 'Math', dayOfWeek: 1, beginSection: 1, sectionCount: 2, weekNumbers: weeks
    });
    await assert.rejects(EasTimetableImporter.saveCourses(db, session, term, [course],
      EasTimetable.getWeihaiTimeStructure(), timetable.startTime));
    assert.equal((await db.getTimetableById('table')).name, 'Original');
    assert.deepEqual((await db.getEventsOfTimetable('table')).map(e => e.id), ['old']);
  }
});

test('reimport deduplicates weeks and preserves course colours and timetable identity', async t => {
  const { db } = setup(t);
  await db.init({});
  const { timetable, subject } = fixtures();
  await db.saveTimetable(timetable);
  await db.saveSubject(subject);
  const session = Object.assign(new EasSession(), { campus: EasCampus.WEIHAI });
  const term = Object.assign(new EasTermItem(), { yearCode: '2026-2027', termCode: '1' });
  const course = Object.assign(new EasCourseItem(), {
    name: 'Math', dayOfWeek: 1, beginSection: 1, sectionCount: 2, weekNumbers: [1, 1, 3]
  });
  const result = await EasTimetableImporter.saveCourses(db, session, term, [course],
    EasTimetable.getWeihaiTimeStructure(), timetable.startTime);
  assert.equal(result.id, timetable.id);
  assert.equal(result.createdAt, timetable.createdAt);
  assert.equal((await db.getSubjectsOfTimetable('table'))[0].color, subject.color);
  assert.equal((await db.getEventsOfTimetable('table')).length, 2);
});
