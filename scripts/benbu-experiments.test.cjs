const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');
global.$r = name => ({ id: -1, type: 10001, params: [name] });
const root = path.resolve(__dirname, '../entry/src/main/ets');
const cache = new Map();
function load(file) {
  file = path.resolve(root, file);
  if (cache.has(file)) return cache.get(file).exports;
  const mod = { exports: {} }; cache.set(file, mod);
  const req = name => {
    if (name === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, warn() {}, error() {} } };
    if (name.startsWith('@kit.')) return {};
    return load(path.resolve(path.dirname(file), name + '.ets'));
  };
  const js = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  new Function('require', 'module', 'exports', js)(req, mod, mod.exports);
  return mod.exports;
}
const { BenbuExperimentParser: parser } = load('feature/eas/data/BenbuExperimentParser.ets');
const { BenbuExperimentService: service } = load('feature/eas/BenbuExperimentService.ets');
const { EasApiClient: api } = load('feature/eas/EasApiClient.ets');
const { EasSession, EasCampus } = load('feature/eas/EasSession.ets');
const { EasTermItem, EasCourseItem } = load('feature/eas/model/EasModels.ets');
const { EasDataProvider } = load('feature/eas/EasDataProvider.ets');
const { EasTimetableImporter: importer } = load('feature/eas/EasTimetableImporter.ets');
const { EasTimetable } = load('common/model/timetable/TimetableModels.ets');
const grid = cell => '<table class="dataTable"><tr><th>课表</th></tr><tr><th>星期</th></tr><tr>' +
  ['下午', '第7,8节', cell, '', '', '', '', '', ''].map(x => '<td>' + x + '</td>').join('') + '</tr></table>';
const fixture = grid('<a>用拉伸法测定弹性模量</a><br>姚凤凤&nbsp;[11周第7，8节] 上课形式[线下]L622，<span class="red">15:40-18:10</span>');
const electronic = data => JSON.stringify({ code: 0, data });
const row = { subjectName: '电路实验', classDate: '2026-10-20', startTime: '13:00:00', teacher: '张三', address: '301', labsName: '电路实验室' };
const session = () => Object.assign(new EasSession(), { campus: EasCampus.BENBU,
  webCookies: new Map([['JSESSIONID', 'eas'], ['HIT', 'vpn']]), electronicExpToken: 'fixture-jwt' });

test('HTML retains names inside anchors, teachers, weeks, locations and exact free times', () => {
  const [course] = parser.parseHtml(fixture);
  assert.equal(course.name, '用拉伸法测定弹性模量');
  assert.equal(course.teacher, '姚凤凤'); assert.equal(course.classroom, 'L622');
  assert.deepEqual(course.weekNumbers, [11]); assert.equal(course.dayOfWeek, 1);
  assert.equal(course.startTime, '15:40'); assert.equal(course.endTime, '18:10');
  assert.equal(course.beginSection, -1);
});

test('HTML handles combined lines, repeated details, multiple courses and period fallback', () => {
  const courses = parser.parseHtml(grid('弹性模量 姚凤凤 [11周第7,8节] 上课形式[线下]L622，15:40-18:10<br>' +
    '电学实验<br>张三 [12周第5，6节] 上课形式[线下]L619<br>李四 [13周第5，6节] 上课形式[线下]L620'));
  assert.equal(courses.length, 3); assert.equal(courses[0].name, '弹性模量');
  assert.equal(courses[1].name, '电学实验'); assert.equal(courses[2].name, '电学实验');
  assert.equal(courses[1].beginSection, 5); assert.equal(courses[1].sectionCount, 2);
  assert.deepEqual(parser.parseHtml('<form>登录</form>'), []);
});

test('electronic dates are authoritative; missing end defaults to two hours; bad rows are isolated', () => {
  const courses = parser.parseElectronic(electronic([null, { ...row, classDate: '2026-02-30' },
    { ...row, startTime: '25:00' }, row, { ...row, endTime: '18:10:00' }]));
  assert.equal(courses.length, 2); assert.equal(courses[0].scheduledDate, '2026-10-20');
  assert.equal(courses[0].dayOfWeek, 2); assert.equal(courses[0].endTime, '15:00');
  assert.equal(courses[1].endTime, '18:10'); assert.equal(courses[0].classroom, '301(电路实验室)');
  assert.deepEqual(parser.parseElectronic('{"code":1}'), []);
});

test('requests exchange isolated experiment cookies and preserve Android electronic headers', async () => {
  const original = api.doHttp; const calls = []; const s = session();
  api.doHttp = async (url, method, headers, body, timeout, useCache) => {
    calls.push({ url, method, headers, body, timeout, useCache });
    return url.endsWith('loginSygl') ? { statusCode: 200, cookies: 'JSESSIONID=lab; Path=/; HttpOnly, other=ok; SameSite=Lax', body: '' } :
      { statusCode: 200, body: url.includes('queryXszkb') ? fixture : electronic([row]) };
  };
  try {
    assert.equal((await service.getExperiments(s)).length, 1);
    assert.match(calls[0].url, /jwts.*\/loginsysj\/loginSygl$/);
    assert.match(calls[1].url, /sjjx.*\/xskb\/queryXszkb$/);
    assert.match(calls[1].headers.get('Cookie'), /JSESSIONID=lab/);
    assert.doesNotMatch(calls[1].headers.get('Cookie'), /Path|SameSite/);
    assert.equal(s.webCookies.get('JSESSIONID'), 'eas');
    assert.equal((await service.getElectronicExperiments(s)).length, 1);
    assert.equal(calls[2].method, 'POST'); assert.equal(calls[2].headers.get('VcTchToken'), 'fixture-jwt');
    assert.equal(calls[2].headers.get('VcTchType'), 'stu'); assert.equal(calls[2].useCache, false);
    s.electronicExpToken = ''; await service.getElectronicExperiments(s); assert.equal(calls.length, 3);
    api.doHttp = async () => { throw Error('offline'); };
    assert.deepEqual(await service.getExperiments(s), []);
    assert.equal(s.loginExpired, false);
  } finally { api.doHttp = original; }
});

test('Benbu can import experiment-only schedules; other campuses never query experiments', async () => {
  const original = api.doHttp; let count = 0;
  api.doHttp = async url => { count++; return { statusCode: 200, body: url.includes('queryXszkb') ? fixture : electronic([row]) }; };
  const provider = new EasDataProvider({ request: async () => ({ statusCode: 200, body: '<table class="addlist_01"></table>' }) });
  try {
    assert.equal((await provider.getTimetableOfTerm(session(), new EasTermItem())).length, 2);
    assert.equal(count, 3);
    const s = session(); s.campus = EasCampus.WEIHAI;
    await assert.rejects(provider.getTimetableOfTerm(s, new EasTermItem())); assert.equal(count, 3);
  } finally { api.doHttp = original; }
});

test('save pipeline persists exact experimental timestamps, deduplicates and keeps ordinary periods', async () => {
  let saved;
  const db = { getTimetableByEasCode: async () => undefined, getSubjectsOfTimetable: async () => [],
    saveImportedTimetable: async (table, subjects, events) => { saved = { table, subjects, events }; } };
  const courses = [...parser.parseHtml(fixture), ...parser.parseHtml(fixture), ...parser.parseElectronic(electronic([row])),
    Object.assign(new EasCourseItem(), { name: '普通课', dayOfWeek: 3, weekNumbers: [2], beginSection: 1, sectionCount: 2 })];
  await importer.saveCourses(db, session(), new EasTermItem(), courses,
    EasTimetable.getBenbuTimeStructure(), new Date(2026, 7, 24).getTime());
  assert.equal(saved.events.length, 3);
  const lab = saved.events.find(x => x.name === '用拉伸法测定弹性模量');
  assert.equal(lab.from, new Date(2026, 10, 2, 15, 40).getTime());
  assert.equal(lab.to, new Date(2026, 10, 2, 18, 10).getTime()); assert.equal(lab.fromNumber, -1);
  const ee = saved.events.find(x => x.name === '电路实验');
  assert.equal(ee.from, new Date(2026, 9, 20, 13).getTime()); assert.equal(ee.lastNumber, -1);
  assert.equal(saved.events.find(x => x.name === '普通课').fromNumber, 1);
});
