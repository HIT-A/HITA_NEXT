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
    if (name.startsWith('@kit.')) return {};
    assert.ok(name.startsWith('.'), `Unexpected import ${name}`);
    return load(path.resolve(path.dirname(file), name + '.ets'));
  };
  new Function('require', 'module', 'exports', compiled)(localRequire, mod, mod.exports);
  return mod.exports;
}

const { EasLegacyTimetableParser: parser } = load('feature/eas/data/EasLegacyTimetableParser.ets');
const { RdbHelper } = load('common/db/RdbHelper.ets');
const name = '\u9ad8\u7b49\u6570\u5b66';
const teacher = '\u738b\u8001\u5e08';
const week = '\u5468';
const campusLabel = '\u672c\u90e8';
const spaces = [
  '&nbsp', '&nbsp;', '&NBSP;', '&#160;', '&#160', '&#xA0;', '&#xa0',
  '&amp;nbsp;', '&amp;nbsp', '&amp;amp;nbsp;', '&amp;#160;', '&amp;#xA0;',
  '&#38;nbsp;', '&#x26;nbsp;', '\u00a0', '\u202f', ' '
];

function schedule(room, suffix = '') {
  return `<table class="addlist_01"><tr><th>Period</th><th>Time</th><th>Mon</th></tr>` +
    `<tr><td>AM</td><td>1-2</td><td>${name}<br>${teacher}[1-2]${week}${room}${suffix}</td></tr></table>`;
}

function storedEvent(place, type = 'CLASS') {
  const row = {
    id: 'existing-course', type, name, place, teacher, subjectId: 'subject',
    timetableId: 'saved-timetable', fromTime: 1000, toTime: 2000,
    fromNumber: 1, lastNumber: 2, createdAt: 500
  };
  return RdbHelper.eventMapper(key => ({
    str: () => String(row[key] ?? ''),
    num: () => Number(row[key] ?? 0)
  }));
}

for (const space of spaces) {
  test(`legacy classrooms decode whitespace ${JSON.stringify(space)}`, () => {
    const courses = parser.parseScheduleHtml(schedule(space));
    assert.equal(courses.length, 1);
    assert.equal(courses[0].classroom, '');
    assert.equal(courses[0].name, name);
    assert.equal(courses[0].teacher, teacher);
    assert.deepEqual(courses[0].weekNumbers, [1, 2]);
    assert.equal(courses[0].dayOfWeek, 1);
    assert.equal(courses[0].beginSection, 1);
    assert.equal(courses[0].sectionCount, 2);
  });
}

test('actual room names survive whitespace cleanup and blank separator lines', () => {
  for (const space of spaces) {
    const courses = parser.parseScheduleHtml(schedule(`A${space} 101`, `<br>${space}<br>`));
    assert.equal(courses.length, 1);
    assert.equal(courses[0].classroom, 'A 101');
  }
  assert.equal(parser.parseScheduleHtml(schedule('A&amp;B-101'))[0].classroom, 'A&B-101');
});

test('placeholder classrooms do not prevent shared-room fallback within a course', () => {
  const courses = parser.parseScheduleHtml(schedule(`&amp;nbsp;,[3-4]${week}A-101`));
  assert.equal(courses.length, 2);
  assert.deepEqual(courses.map(course => course.classroom), ['A-101', 'A-101']);
  assert.deepEqual(courses.map(course => course.teacher), [teacher, teacher]);
});

test('already imported classrooms are cleaned without changing event identity or schedule', () => {
  for (const space of spaces) {
    const event = storedEvent(space);
    assert.equal(event.place, '');
    assert.equal(event.id, 'existing-course');
    assert.equal(event.name, name);
    assert.equal(event.teacher, teacher);
    assert.equal(event.subjectId, 'subject');
    assert.equal(event.timetableId, 'saved-timetable');
    assert.equal(event.from, 1000);
    assert.equal(event.to, 2000);
    assert.equal(event.fromNumber, 1);
    assert.equal(event.lastNumber, 2);
    assert.equal(event.createdAt, 500);
    assert.equal(storedEvent(`A${space} 101`).place, 'A 101');
  }
});

test('classroom cleanup preserves unrelated text and non-course events', () => {
  for (const place of ['A&B-101', 'A&amp;B-101', '&nbspBuilding', '&#1600;', '&#xA01;']) {
    assert.equal(storedEvent(place).place, place);
  }
  assert.equal(storedEvent('&nbsp;', 'OTHER').place, '&nbsp;');
});

test('campus labels use the main-campus name without changing the campus key', () => {
  const { ExamSchedule } = load('feature/eas/ExamSchedule.ets');
  const { EasCampus } = load('feature/eas/EasSession.ets');
  const { easWebLoginConfigFor } = load('feature/eas/webLogin/EasWebLoginConfig.ets');
  assert.equal(ExamSchedule.campusName('BENBU'), campusLabel);
  for (const studentType of ['1', '2']) {
    const config = easWebLoginConfigFor(EasCampus.BENBU, studentType);
    assert.equal(config.campus, 'BENBU');
    assert.ok(config.displayName.startsWith(campusLabel));
  }
  const home = fs.readFileSync(path.join(root, 'pages/Home.ets'), 'utf8');
  const scores = fs.readFileSync(path.join(root, 'pages/ScorePage.ets'), 'utf8');
  assert.ok(home.includes(`return '${campusLabel}'`));
  assert.ok(home.includes(`sessionCampusButton('BENBU', '${campusLabel}')`));
  assert.ok(!home.includes('\u672c\u90e8\u6821\u533a'));
  assert.ok(!home.includes('\u6821\u672c\u90e8'));
  assert.ok(scores.includes(`return '${campusLabel}'`));
});
