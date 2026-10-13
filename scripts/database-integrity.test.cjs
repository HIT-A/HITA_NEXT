const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');
const { DatabaseSync } = require('node:sqlite');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const compile = source => ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;

class Predicates {
  constructor(table) { this.table = table; this.filters = []; this.values = []; this.order = ''; this.limit = ''; }
  equalTo(key, value) { this.filters.push(`${key} = ?`); this.values.push(value); return this; }
  in(key, values) {
    this.filters.push(`${key} IN (${values.map(() => '?').join(',')})`);
    this.values.push(...values); return this;
  }
  orderByDesc(key) { this.order = ` ORDER BY ${key} DESC`; return this; }
  orderByAsc(key) { this.order = ` ORDER BY ${key} ASC`; return this; }
  limitAs(value) { this.limit = ` LIMIT ${value}`; return this; }
  where() { return this.filters.length ? ' WHERE ' + this.filters.join(' AND ') : ''; }
}

function load(file, overrides = {}, cache = new Map()) {
  file = path.resolve(root, file);
  if (cache.has(file)) return cache.get(file).exports;
  const mod = { exports: {} };
  cache.set(file, mod);
  new Function('require', 'module', 'exports', compile(fs.readFileSync(file, 'utf8')))(name => {
    if (overrides[name]) return overrides[name];
    if (name === '@kit.ArkData') return { relationalStore: { RdbPredicates: Predicates } };
    if (name === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, warn() {}, error() {} } };
    if (name.startsWith('@kit.')) return {};
    assert.ok(name.startsWith('.'), name);
    return load(path.resolve(path.dirname(file), name + '.ets'), overrides, cache);
  }, mod, mod.exports);
  return mod.exports;
}

const { RdbHelper } = load('common/db/RdbHelper.ets');
const { EasTimetable, EasTermSubject, EasEventItem, EasEventType } = load('common/model/timetable/TimetableModels.ets');
const { EasTimetableImporter } = load('feature/eas/EasTimetableImporter.ets');
const { EasSession, EasCampus } = load('feature/eas/EasSession.ets');
const { EasCourseItem, EasTermItem } = load('feature/eas/model/EasModels.ets');
const day = 86400000;
const start = new Date(2026, 7, 31).getTime();

function rowsResult(rows) {
  let index = -1;
  return {
    goToFirstRow: () => { index = 0; return rows.length > 0; },
    goToNextRow: () => ++index < rows.length,
    getColumnIndex: name => name,
    getLong: name => Number(rows[index][name]),
    getDouble: name => Number(rows[index][name]),
    getString: name => String(rows[index][name] ?? ''),
    close() {}
  };
}

function database() {
  const sql = new DatabaseSync(':memory:');
  const source = read('common/db/RdbHelper.ets');
  const schemas = source.slice(source.indexOf('const CREATE_TIMETABLE:'), source.indexOf('export class RdbHelper'));
  for (const schema of new Function(compile(schemas + '\nreturn [CREATE_TIMETABLE, CREATE_SUBJECT, CREATE_EVENTS];'))()) {
    sql.exec(schema);
  }
  const ops = {
    insert: async (table, values) => {
      const keys = Object.keys(values);
      return Number(sql.prepare(`INSERT INTO ${table} (${keys.join(',')}) VALUES (${keys.map(() => '?').join(',')})`)
        .run(...keys.map(key => values[key])).lastInsertRowid);
    },
    update: async (values, pred) => {
      const keys = Object.keys(values);
      return sql.prepare(`UPDATE ${pred.table} SET ${keys.map(key => `${key}=?`).join(',')}${pred.where()}`)
        .run(...keys.map(key => values[key]), ...pred.values).changes;
    },
    delete: async pred => sql.prepare(`DELETE FROM ${pred.table}${pred.where()}`).run(...pred.values).changes,
    query: async (pred, columns = ['*']) => rowsResult(sql.prepare(
      `SELECT ${columns.join(',')} FROM ${pred.table}${pred.where()}${pred.order}${pred.limit}`).all(...pred.values)),
    execute: async (text, values = []) => sql.prepare(text).run(...values).changes
  };
  let failCommit = false;
  const db = new RdbHelper();
  db.store = { ...ops, createTransaction: async () => {
    sql.exec('BEGIN IMMEDIATE');
    return {
      ...ops,
      commit: async () => { if (failCommit) throw Error('commit failed'); sql.exec('COMMIT'); },
      rollback: async () => sql.exec('ROLLBACK')
    };
  } };
  const snapshot = () => ['timetable', 'subject', 'events'].map(table =>
    sql.prepare(`SELECT rowid, * FROM ${table} ORDER BY id`).all());
  return { db, sql, ops, snapshot, rejectCommit: () => { failCommit = true; } };
}

function table(id = 'a') {
  return Object.assign(new EasTimetable(), {
    id, code: id === 'a' ? 'BENBU:2026-20271' : 'LOCAL:' + id,
    name: 'Term ' + id, startTime: start, endTime: start + 21 * day - 1
  });
}
function subject(id = 'math', timetableId = 'a') {
  return Object.assign(new EasTermSubject(), { id, timetableId, name: 'Math', color: 0xff446688, credit: 3 });
}
function event(id, type = EasEventType.CLASS, timetableId = 'a', offset = 0) {
  return Object.assign(new EasEventItem(), {
    id, type, timetableId, subjectId: 'math', name: id, place: 'A101',
    from: start + offset + 8 * 3600000, to: start + offset + 10 * 3600000,
    fromNumber: 1, lastNumber: 2, color: type === EasEventType.EXAM ? 0xffee1111 : 0
  });
}
async function seed(db) {
  await db.saveTimetable(table());
  await db.saveTimetable(table('b'));
  await db.saveSubject(subject());
  await db.saveSubject(subject('other-subject', 'b'));
  for (const item of [
    event('old-one'), event('old-two', EasEventType.CLASS, 'a', day),
    event('exam', EasEventType.EXAM, 'a', 28 * day),
    event('memo', EasEventType.OTHER), event('other-table', EasEventType.CLASS, 'b')
  ]) await db.saveEvent(item);
}

test('failed single-row edits preserve timetable, subject and event identities and contents', async () => {
  for (const [tableName, item, save] of [
    ['timetable', table(), 'saveTimetable'],
    ['subject', subject(), 'saveSubject'],
    ['events', event('old-one'), 'saveEvent']
  ]) {
    const fixture = database();
    try {
      await seed(fixture.db);
      const before = fixture.snapshot();
      item.name = 'Changed';
      fixture.sql.exec(`CREATE TRIGGER fail_write BEFORE UPDATE ON ${tableName} BEGIN SELECT RAISE(ABORT, 'disk full'); END`);
      await assert.rejects(fixture.db[save](item), /disk full/);
      assert.deepEqual(fixture.snapshot(), before);
      fixture.sql.exec('DROP TRIGGER fail_write');
      await fixture.db[save](item);
      const saved = fixture.sql.prepare(`SELECT rowid, name FROM ${tableName} WHERE id=?`).get(item.id);
      assert.equal(saved.name, 'Changed');
      assert.equal(saved.rowid, before[['timetable', 'subject', 'events'].indexOf(tableName)].find(row => row.id === item.id).rowid);
    } finally { fixture.sql.close(); }
  }
});

test('batch timetable deletion rolls back every table on a midway failure', async () => {
  const f = database();
  try {
    await seed(f.db);
    const before = f.snapshot();
    f.sql.exec("CREATE TRIGGER fail_delete BEFORE DELETE ON subject BEGIN SELECT RAISE(ABORT, 'disk full'); END");
    await assert.rejects(f.db.deleteTimetablesCascade(['a']), /disk full/);
    assert.deepEqual(f.snapshot(), before);
    f.sql.exec('DROP TRIGGER fail_delete');
    await f.db.deleteTimetablesCascade(['a']);
    assert.deepEqual(f.snapshot(), before.map(rows => rows.filter(row =>
      (row.timetableId ?? row.id) !== 'a')));
    await f.db.deleteTimetablesCascade([]);
    assert.equal(f.sql.prepare('SELECT count(*) AS n FROM timetable').get().n, 1);
  } finally { f.sql.close(); }
});

test('re-import rolls back failed writes, then replaces courses without deleting exams or other tables', async () => {
  const f = database();
  try {
    await seed(f.db);
    const before = f.snapshot();
    const incoming = [event('new-one'), event('new-two', EasEventType.CLASS, 'a', 2 * day)];
    const edited = Object.assign(subject(), { credit: 4 });
    f.sql.exec("CREATE TRIGGER fail_import BEFORE INSERT ON events WHEN NEW.id = 'new-two' BEGIN SELECT RAISE(ABORT, 'disk full'); END");
    await assert.rejects(f.db.saveImportedTimetable(table(), [edited], incoming, true), /disk full/);
    assert.deepEqual(f.snapshot(), before);
    f.sql.exec('DROP TRIGGER fail_import');
    const imported = table();
    await f.db.saveImportedTimetable(imported, [edited], incoming, true);
    const after = f.snapshot();
    assert.deepEqual(after[2].filter(row => ['exam', 'memo', 'other-table'].includes(row.id)),
      before[2].filter(row => ['exam', 'memo', 'other-table'].includes(row.id)));
    assert.deepEqual(after[2].filter(row => row.timetableId === 'a' && row.type === 'CLASS').map(row => row.id),
      ['new-one', 'new-two']);
    assert.equal(after[1].find(row => row.id === 'math').color, subject().color);
    assert.equal(after[1].find(row => row.id === 'math').credit, 4);
    assert.equal(imported.endTime, start + 35 * day - 1, 'retained later exams remain inside the term');
    assert.equal(after[0].find(row => row.id === 'a').endTime, imported.endTime);
  } finally { f.sql.close(); }
});

test('new imports cannot leave partial records, overwrite another term, or report success after commit failure', async () => {
  const f = database();
  try {
    await seed(f.db);
    const before = f.snapshot();
    f.sql.exec("CREATE TRIGGER fail_import BEFORE INSERT ON events BEGIN SELECT RAISE(ABORT, 'disk full'); END");
    await assert.rejects(f.db.saveImportedTimetable(table('new'), [subject('new-subject', 'new')],
      [event('new-event', EasEventType.CLASS, 'new')], false), /disk full/);
    assert.deepEqual(f.snapshot(), before);
    f.sql.exec('DROP TRIGGER fail_import');
    await assert.rejects(f.db.saveImportedTimetable(table(), [subject()], [event('bad', EasEventType.CLASS, 'b')], true),
      /Invalid timetable/);
    await assert.rejects(f.db.saveImportedTimetable(table('missing'), [], [event('new', EasEventType.EXAM, 'missing')], true),
      /Invalid timetable/);
    await assert.rejects(f.db.saveImportedTimetable(table('missing'), [subject('m', 'missing')],
      [event('new', EasEventType.CLASS, 'missing')], true), /no longer exists/);
    assert.deepEqual(f.snapshot(), before);
    f.rejectCommit();
    await assert.rejects(f.db.saveImportedTimetable(table(), [subject()], [event('new')], true), /commit failed/);
    assert.deepEqual(f.snapshot(), before);
  } finally { f.sql.close(); }
});

test('start date changes roll back partial shifts and reject stale editor dates', async () => {
  const f = database();
  try {
    await seed(f.db);
    const before = f.snapshot();
    const old = table();
    const next = start + 7 * day;
    f.sql.exec("CREATE TRIGGER fail_shift BEFORE UPDATE ON events WHEN OLD.id='old-two' BEGIN SELECT RAISE(ABORT, 'disk full'); END");
    await assert.rejects(f.db.shiftTimetableStart('a', old.startTime, old.endTime, next), /disk full/);
    assert.deepEqual(f.snapshot(), before);
    f.sql.exec('DROP TRIGGER fail_shift');
    await f.db.shiftTimetableStart('a', old.startTime, old.endTime, next);
    const shifted = f.snapshot();
    assert.equal(shifted[0].find(row => row.id === 'a').startTime, next);
    for (const row of shifted[2]) {
      const original = before[2].find(item => item.id === row.id);
      assert.deepEqual({ ...row }, { ...original,
        fromTime: original.fromTime + (row.timetableId === 'a' ? 7 * day : 0),
        toTime: original.toTime + (row.timetableId === 'a' ? 7 * day : 0) });
    }
    await assert.rejects(f.db.shiftTimetableStart('a', old.startTime, old.endTime, next + 7 * day), /reload/);
    assert.deepEqual(f.snapshot(), shifted);
  } finally { f.sql.close(); }
});

test('invalid academic courses leave existing data intact and duplicate teaching rows merge before committing', async () => {
  const f = database();
  try {
    await seed(f.db);
    const session = Object.assign(new EasSession(), { campus: EasCampus.BENBU });
    const term = Object.assign(new EasTermItem(), { yearCode: '2026-2027', termCode: '1', yearName: '2026-2027', termName: 'Autumn' });
    const course = () => Object.assign(new EasCourseItem(), {
      name: 'Math', dayOfWeek: 1, beginSection: 1, sectionCount: 2, weekNumbers: [1, 2], teacher: 'Teacher A', classroom: 'A101'
    });
    const before = f.snapshot();
    for (const override of [{ dayOfWeek: 8 }, { beginSection: 99 }, { weekNumbers: [] }]) {
      await assert.rejects(EasTimetableImporter.saveCourses(f.db, session, term, [Object.assign(course(), override)],
        EasTimetableImporter.scheduleStructure(EasCampus.BENBU), start));
      assert.deepEqual(f.snapshot(), before);
    }
    await EasTimetableImporter.saveCourses(f.db, session, term,
      [course(), Object.assign(course(), { teacher: 'Teacher B', classroom: 'A102' })],
      EasTimetableImporter.scheduleStructure(EasCampus.BENBU), start);
    const lessons = f.sql.prepare("SELECT * FROM events WHERE timetableId='a' AND type='CLASS'").all();
    assert.equal(lessons.length, 2);
    assert.ok(lessons.every(row => row.teacher === 'Teacher A/Teacher B' && row.place === 'A101/A102'));
    assert.equal(f.sql.prepare("SELECT count(*) AS n FROM events WHERE id='exam'").get().n, 1);
  } finally { f.sql.close(); }
});

test('ICS imports publish all records before changing the active timetable', async () => {
  for (const fail of [true, false]) {
    const f = database();
    try {
      await seed(f.db);
      const before = f.snapshot();
      const selected = [];
      const { TimetableIcsImporter } = load('feature/timetable/data/TimetableIcsImporter.ets', {
        '../../../common/db/RdbHelper': { RdbHelper: { getInstance: () => f.db } },
        './TimetableSelectionStore': { TimetableSelectionStore: {
          getInstance: () => ({ init: async () => {}, save: async id => selected.push(id) })
        } }
      });
      if (fail) f.sql.exec("CREATE TRIGGER fail_ics BEFORE INSERT ON events WHEN NEW.name='Second' BEGIN SELECT RAISE(ABORT, 'disk full'); END");
      const ics = ['BEGIN:VCALENDAR', 'VERSION:2.0',
        'BEGIN:VEVENT', 'UID:first', 'DTSTART:20260831T080000', 'DTEND:20260831T090000', 'SUMMARY:First', 'END:VEVENT',
        'BEGIN:VEVENT', 'UID:second', 'DTSTART:20260901T080000', 'DTEND:20260901T090000', 'SUMMARY:Second', 'END:VEVENT',
        'END:VCALENDAR'].join('\r\n');
      if (fail) {
        await assert.rejects(TimetableIcsImporter.importText({}, ics, 'Imported'), /disk full/);
        assert.deepEqual(f.snapshot(), before);
        assert.deepEqual(selected, []);
      } else {
        const result = await TimetableIcsImporter.importText({}, ics, 'Imported');
        assert.equal(result.success, true);
        assert.deepEqual(selected, [result.timetableId]);
        assert.equal(f.sql.prepare('SELECT count(*) AS n FROM events WHERE timetableId=?').get(result.timetableId).n, 2);
      }
    } finally { f.sql.close(); }
  }
});
