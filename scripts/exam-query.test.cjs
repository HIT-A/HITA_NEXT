const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');

function load(file, mocks = {}, cache = new Map()) {
  file = path.resolve(root, file);
  if (cache.has(file)) return cache.get(file).exports;
  const source = fs.readFileSync(file, 'utf8');
  const mod = { exports: {} };
  cache.set(file, mod);
  const compiled = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const localRequire = name => {
    if (name in mocks) return mocks[name];
    assert.ok(name.startsWith('.'), `Unexpected platform import ${name}`);
    return load(path.resolve(path.dirname(file), name + '.ets'), mocks, cache);
  };
  new Function('require', 'module', 'exports', compiled)(localRequire, mod, mod.exports);
  return mod.exports;
}

const { EasEventItem, EasEventType } = load('common/model/timetable/TimetableModels.ets');
const { EasExamItem, EasTermItem } = load('feature/eas/model/EasModels.ets');
const { parseShenzhenWebExams } = load('feature/eas/data/ShenzhenWebExams.ets');
const { ExamSchedule } = load('feature/eas/ExamSchedule.ets');

function term() {
  const item = new EasTermItem();
  item.yearCode = '2026-2027';
  item.yearName = '2026-2027学年';
  item.termCode = '1';
  item.termName = '秋季';
  return item;
}

test('shenzhen exam parser reads content.list and semantic field aliases', () => {
  const body = JSON.stringify({
    code: 0,
    msg: 'ok',
    content: {
      list: [{
        kcmc: '大学物理',
        ksrq: '2026-12-18',
        kssjms: '14:00-16:00',
        kscd: 'T4-203',
        kslxmc: '期末考试',
        xnxqmc: '2026-2027学年秋季'
      }]
    }
  });
  const parsed = parseShenzhenWebExams(body, term());
  assert.equal(parsed.list.length, 1);
  assert.equal(parsed.list[0].courseName, '大学物理');
  assert.equal(parsed.list[0].examLocation, 'T4-203');
  assert.equal(parsed.list[0].examType, '期末考试');
  assert.equal(parsed.list[0].termName, '2026-2027学年秋季');
});

test('exam schedule parses Chinese dates and countdown labels', () => {
  const range = ExamSchedule.parseRange('2026年12月20日', '9:00-11:00');
  assert.ok(range);
  assert.equal(ExamSchedule.dateOf(range[0]), '2026-12-20');
  assert.equal(ExamSchedule.timeOf(range[0]), '09:00');
  assert.equal(ExamSchedule.timeOf(range[1]), '11:00');
  const now = new Date(2026, 11, 18, 8).getTime();
  assert.equal(ExamSchedule.remainingLabel(range[0], range[1], now), '还有 2 天');
  assert.equal(ExamSchedule.remainingLabel(range[0], range[1], range[0] + 1000), '进行中');
  assert.equal(ExamSchedule.remainingLabel(range[0], range[1], range[1] + 1000), '已结束');
});

test('imported exams keep identity fields and skip already saved courses', () => {
  const item = Object.assign(new EasExamItem(), {
    courseName: '线性代数',
    examDate: '2026-12-20',
    examTime: '09:00-11:00',
    examLocation: 'A-101',
    examType: '期末'
  });
  const event = ExamSchedule.toEvent(item, 'current');
  assert.equal(event.type, EasEventType.EXAM);
  assert.equal(event.timetableId, 'current');
  assert.equal(event.place, 'A-101');
  assert.equal(ExamSchedule.sameAsEvent(item, event), true);
  const other = Object.assign(new EasEventItem(), event);
  other.name = '高等数学';
  assert.equal(ExamSchedule.sameAsEvent(item, other), false);
});
