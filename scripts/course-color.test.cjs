const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

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
  new Function('RdbHelper','module',js)({getInstance:()=>({saveCourseColor:async()=>{if(fail) throw Error('failed');}})},mod);
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