const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');
const { DatabaseSync } = require('node:sqlite');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const cache = new Map();
function load(file) {
  file = path.resolve(root, file);
  if (cache.has(file)) return cache.get(file).exports;
  const mod = { exports: {} };
  cache.set(file, mod);
  const compiled = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const localRequire = name => {
    if (name === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, warn() {}, error() {} } };
    if (name === '@kit.ArkData') return { relationalStore: { RdbPredicates: class { constructor(table) { this.table = table; this.filters = []; } equalTo(key, value) { this.filters.push([key,value]); return this; } } } };
    if (name.startsWith('@kit.')) return {};
    assert.ok(name.startsWith('.'), `Unexpected import ${name}`);
    return load(path.resolve(path.dirname(file), name + '.ets'));
  };
  new Function('require', 'module', 'exports', compiled)(localRequire, mod, mod.exports);
  return mod.exports;
}

const { RdbHelper } = load('common/db/RdbHelper.ets');
const { EasEventItem, EasEventType } = load('common/model/timetable/TimetableModels.ets');
test('course color is constrained to its subject and timetable; errors reach editor', async () => {
  const db = new RdbHelper();
  const calls = [];
  db.store = { update: async (values, pred) => { calls.push({values, pred}); return 1; } };
  await db.saveCourseColor('subject-a', 'table-a', 0xFF123456);
  assert.deepEqual(calls[0].values, {color: 0xFF123456});
  assert.equal(calls[0].pred.table, 'subject');
  assert.deepEqual(calls[0].pred.filters, [['id', 'subject-a'], ['timetableId', 'table-a']]);
  await assert.rejects(db.saveCourseColor('', 'table-a', 0), /identity/);
  db.store.update = async () => 0;
  await assert.rejects(db.saveCourseColor('deleted', 'table-a', 0), /no longer exists/);
  db.store.update = async () => { throw new Error('disk full'); };
  await assert.rejects(db.saveCourseColor('subject-a', 'table-a', 0), /disk full/);
});
test('saving recolors every instance of the subject without changing other courses or week', async () => {
  const source = fs.readFileSync(path.join(root, 'pages/Home.ets'), 'utf8');
  const method = source.slice(source.indexOf('  private async saveCourseColor('), source.indexOf('  private eventDetailEndTime(')).replace('private async', 'async');
  const js = ts.transpileModule('class Host { ' + method + ' }; module.exports = Host;', {compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText;
  const mod = {exports:{}};
  let fail = false;
  new Function('RdbHelper','EasEventType','module',js)({getInstance:()=>({saveCourseColor:async()=>{if(fail) throw Error('failed');}})},EasEventType,mod);
  const host = new mod.exports();
  host.timetableWeek = 7;
  host.timetableEvents = [
    {id:'one',subjectId:'a',timetableId:'t',color:1},
    {id:'other-week',subjectId:'a',timetableId:'t',color:1},
    {id:'other-course',subjectId:'b',timetableId:'t',color:2},
    {id:'other-table',subjectId:'a',timetableId:'u',color:3}
  ];
  host.activeSheetVisible = true;
  host.courseColorEditing = true;
  host.selectedCourse = host.timetableEvents[0];
  let redraw = 0;
  host.drawTimetableNow = () => redraw++;
  await host.saveCourseColor(host.selectedCourse, 0xFF123456);
  assert.deepEqual(host.timetableEvents.map(e=>e.color), [0xFF123456,0xFF123456,2,3]);
  assert.equal(host.timetableWeek,7);
  assert.equal(host.courseColorEditing,false);
  assert.equal(redraw,1);
  fail = true;
  await assert.rejects(host.saveCourseColor(host.selectedCourse,0));
  assert.equal(host.selectedCourse.color,0xFF123456);
  assert.equal(redraw,1);
});

test('timetable exam color updates only the selected event, including exams linked to a course', async () => {
  const source = fs.readFileSync(path.join(root, 'pages/Home.ets'), 'utf8');
  const method = source.slice(source.indexOf('  private async saveCourseColor('),
    source.indexOf('  private eventDetailEndTime(')).replace('private async', 'async');
  const js = ts.transpileModule('class Host { ' + method + ' }; module.exports = Host;',
    { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText;
  const mod = { exports: {} };
  const saved = [];
  new Function('RdbHelper', 'EasEventType', 'module', js)({ getInstance: () => ({
    saveExamColor: async (...args) => saved.push(args),
    saveCourseColor: async () => assert.fail('Exam color must not recolor the course')
  }) }, EasEventType, mod);
  const host = new mod.exports();
  host.timetableEvents = [
    { id: 'exam', type: 'EXAM', subjectId: 'a', timetableId: 't', color: 1 },
    { id: 'retake', type: 'EXAM', subjectId: 'a', timetableId: 't', color: 2 },
    { id: 'course', type: 'CLASS', subjectId: 'a', timetableId: 't', color: 3 }
  ];
  host.selectedCourse = host.timetableEvents[0];
  host.activeSheetVisible = true;
  host.drawTimetableNow = () => {};
  host.timetableWeek = 7;
  await host.saveCourseColor(host.selectedCourse, 0xFF123456);
  assert.deepEqual(saved, [['exam', 't', 0xFF123456]]);
  assert.deepEqual(host.timetableEvents.map(event => event.color), [0xFF123456, 2, 3]);
  assert.equal(host.timetableWeek, 7);
});

test('existing databases gain exam colors without losing records and the migration is repeatable', async () => {
  const sql = new DatabaseSync(':memory:');
  const source = fs.readFileSync(path.join(root, 'common/db/RdbHelper.ets'), 'utf8');
  const schema = source.slice(source.indexOf('const CREATE_EVENTS:'), source.indexOf('export class RdbHelper'));
  const js = ts.transpileModule(schema + '\nmodule.exports = CREATE_EVENTS;', {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const mod = { exports: {} };
  new Function('module', js)(mod);
  const legacySchema = mod.exports.replace(', color INTEGER NOT NULL DEFAULT 0', '');
  sql.exec(legacySchema);
  const event = Object.assign(new EasEventItem(), {
    id: 'existing-exam', type: EasEventType.EXAM, timetableId: 't', name: 'Exam', from: 10, to: 20
  });
  const original = RdbHelper.eventValues(event);
  delete original.color;
  const keys = Object.keys(original);
  sql.prepare(`INSERT INTO events (${keys.join(',')}) VALUES (${keys.map(() => '?').join(',')})`)
    .run(...keys.map(key => original[key]));
  const db = new RdbHelper();
  let closed = 0;
  db.store = {
    executeSql: async statement => sql.exec(statement),
    querySql: async statement => {
      const rows = sql.prepare(statement).all();
      let index = -1;
      return { goToNextRow: () => ++index < rows.length, getColumnIndex: key => key,
        getString: key => rows[index][key], close: () => closed++ };
    },
    update: async (values, pred) => {
      const keys = Object.keys(values);
      return sql.prepare(`UPDATE ${pred.table} SET ${keys.map(key => `${key}=?`).join(',')} WHERE ` +
        pred.filters.map(([key]) => `${key}=?`).join(' AND '))
        .run(...keys.map(key => values[key]), ...pred.filters.map(([, value]) => value)).changes;
    }
  };
  try {
    await db.ensureEventColorColumn();
    await db.ensureEventColorColumn();
    assert.equal(closed, 2);
    const migrated = sql.prepare('SELECT * FROM events').get();
    assert.deepEqual({ ...migrated }, { ...original, color: 0 });
    await db.saveExamColor(event.id, event.timetableId, 0xFF123456);
    const stored = sql.prepare('SELECT * FROM events').get();
    const restored = RdbHelper.eventMapper(key => ({
      str: () => String(stored[key] ?? ''), num: () => Number(stored[key] ?? 0)
    }));
    assert.equal(restored.color, 0xFF123456);
    assert.equal(restored.from, 10);
    await assert.rejects(db.saveExamColor(event.id, 'another-table', 0), /no longer exists/);
    await assert.rejects(db.saveExamColor('', event.timetableId, 0), /identity/);
    sql.prepare("UPDATE events SET type='CLASS'").run();
    await assert.rejects(db.saveExamColor(event.id, event.timetableId, 0), /no longer exists/);
    assert.equal(sql.prepare('SELECT color FROM events').get().color, 0xFF123456);
  } finally {
    sql.close();
  }
});

test('database initialization waits for migration and retries after a failed upgrade', async () => {
  const db = new RdbHelper();
  let finish;
  let opens = 0;
  db.openStore = async () => {
    opens++;
    db.store = {};
    await new Promise(resolve => { finish = resolve; });
  };
  let secondFinished = false;
  const first = db.init({});
  const second = db.init({}).then(() => { secondFinished = true; });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(opens, 1);
  assert.equal(secondFinished, false);
  finish();
  await Promise.all([first, second]);
  assert.equal(secondFinished, true);
  const failing = new RdbHelper();
  failing.openStore = async () => { failing.store = {}; throw new Error('migration failed'); };
  await assert.rejects(failing.init({}), /migration failed/);
  assert.equal(failing.store, undefined);
  assert.equal(failing.initializing, undefined);
  failing.openStore = async () => { failing.store = {}; };
  await failing.init({});
  assert.ok(failing.store);
});

test('color panel publishes live previews without saving until confirmation', async () => {
  let source = fs.readFileSync(path.join(root, 'feature/timetable/views/CourseColorEditor.ets'), 'utf8');
  source = source.slice(source.indexOf('@Component'), source.indexOf('\n  build()')) + '\n}\n';
  source = source.replace(/^@Component\r?\n/gm, '').replace(/@(State|Prop)\s+/g, '')
    .replace('export struct CourseColorEditor', 'class Editor');
  const js = ts.transpileModule(source + '\nmodule.exports = Editor;', {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const mod = { exports: {} };
  const { CourseColorModel } = load('feature/timetable/views/CourseColorModel.ets');
  new Function('CourseColorModel', 'module', js)(CourseColorModel, mod);
  const editor = new mod.exports();
  const previews = [];
  const saves = [];
  editor.onPreview = color => previews.push(color);
  editor.onSave = async color => saves.push(color);
  editor.aboutToAppear();
  editor.selectColor(0xFFFF0000);
  editor.pickAt(editor.panelWidth, 0);
  assert.equal(previews.at(-1), 0xFFFF0000);
  editor.dragColor({ fingerList: [{ localX: editor.panelWidth, localY: editor.panelHeight }] });
  assert.equal(previews.at(-1), 0xFF000000);
  assert.equal(saves.length, 0);
  await editor.save();
  assert.deepEqual(saves, [0xFF000000]);
});
test('color panel round trips existing RGB colors and handles hue edges and grayscale', () => {
  const { CourseColorModel: M } = load('feature/timetable/views/CourseColorModel.ets');
  for (const color of [0xFF000000,0xFFFFFFFF,0xFF808080,0xFF4DB6AC,0xFFF2B6AC,0xFF0000FF]) {
    const hsv = M.fromColor(color);
    assert.equal(M.toColor(hsv.hue,hsv.saturation,hsv.brightness),color);
  }
  assert.equal(M.toColor(0,1,1),0xFFFF0000);
  assert.equal(M.toColor(360,1,1),0xFFFF0000);
  assert.equal(M.toColor(120,1,1),0xFF00FF00);
  assert.equal(M.toColor(240,1,1),0xFF0000FF);
  assert.equal(M.toColor(180,0,1),0xFFFFFFFF);
  assert.equal(M.toColor(180,1,0),0xFF000000);
});
