const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const settle = () => new Promise(setImmediate);

function load(file, mocks = {}, cache = new Map()) {
  file = path.resolve(root, file);
  if (cache.has(file)) return cache.get(file).exports;
  let source = fs.readFileSync(file, 'utf8');
  if (file.endsWith('TimetableDetailPage.ets')) {
    // Keep the actual controller and formatters, excluding ArkUI builders.
    source = source.slice(0, source.indexOf('\n  @Builder')) +
      source.slice(source.indexOf('\n  private static dateText'));
    source = source.replace(/^@(Entry|Component)\r?\n/gm, '')
      .replace(/@(State|StorageProp)(\([^)]*\))?\s*/g, '')
      .replace('struct TimetableDetailPage', 'export class TimetableDetailPage');
  }
  const mod = { exports: {} };
  cache.set(file, mod);
  const platform = name => {
    if (name in mocks) return mocks[name];
    if (name.endsWith('/RdbHelper') && mocks.db) return { RdbHelper: { getInstance: () => mocks.db } };
    if (name.endsWith('/ClassReminderStore')) return {
      ClassReminderStore: { getInstance: () => ({ loadEnabled: async () => false }) }
    };
    if (name.endsWith('/ClassReminderScheduler')) return { ClassReminderScheduler: { sync: async () => {} } };
    if (name.startsWith('@kit.')) return {};
    return load(path.resolve(path.dirname(file), name + '.ets'), mocks, cache);
  };
  const compiled = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  new Function('require', 'module', 'exports', '$r', 'Scroller', compiled)(
    platform, mod, mod.exports, name => name, class {});
  return mod.exports;
}

async function setup() {
  const { EasTermSubject, EasTimetable, EasEventItem } = load('common/model/timetable/TimetableModels.ets');
  const subject = Object.assign(new EasTermSubject(), {
    id: 'subject-a', timetableId: 'term-a', name: '高等数学', credit: 4,
    field: '专业课', color: 0xFF5C6BC0, type: 'COM_A'
  });
  const timetable = Object.assign(new EasTimetable(), { id: 'term-a', name: '秋季课表' });
  const session = Object.assign(new EasEventItem(), { id: 'class-a', subjectId: subject.id,
    timetableId: timetable.id, name: subject.name });
  const state = { saved: subject, writes: [], menus: [], toasts: [], failWrite: false, answer: undefined };
  const { RdbHelper } = load('common/db/RdbHelper.ets', {
    '@kit.ArkData': { relationalStore: { RdbPredicates: class {
      constructor(table) { this.table = table; }
      equalTo(column, value) { this.column = column; this.value = value; return this; }
    } } }
  });
  const rdb = RdbHelper.getInstance();
  rdb.store = {
    async update(values, predicate) {
      state.writes.push({ values, predicate });
      if (state.failWrite) throw Error('write failed');
      assert.equal(predicate.table, 'subject');
      assert.equal(predicate.column, 'id');
      if (!state.saved || predicate.value !== state.saved.id) return 0;
      state.saved = Object.assign(new EasTermSubject(), state.saved, values);
      return 1;
    }
  };
  const db = {
    init: async () => {},
    getTimetableById: async () => timetable,
    getSubjectsOfTimetable: async () => state.saved ?
      [Object.assign(new EasTermSubject(), state.saved)] : [],
    getClassesOfSubject: async () => [Object.assign(new EasEventItem(), session)],
    getEventsOfTimetable: async () => [Object.assign(new EasEventItem(), session)],
    updateSubjectType: (id, type) => rdb.updateSubjectType(id, type)
  };
  const { TimetableDetailPage: Page } = load('pages/TimetableDetailPage.ets', { db });
  const page = new Page();
  page.getUIContext = () => ({
    getHostContext: () => ({}),
    getPromptAction: () => ({
      showToast: item => state.toasts.push(item.message),
      showActionMenu: options => {
        state.menus.push(options);
        return new Promise((resolve, reject) => {
          state.answer = index => index === undefined ? reject(Error('cancel')) : resolve({ index });
        });
      }
    })
  });
  page.timetableId = timetable.id;
  await page.load();
  page.toggleSubject(page.subjectRows[0]);
  // Execute the actual ForEach key generator, which determines builder reuse.
  const match = read('pages/TimetableDetailPage.ets').match(
    /this\.courseGroupCard\(row\)[\s\S]*?\}, \(row: TimetableSubjectRow\) => ([^\r\n]+)\)/);
  assert.ok(match);
  const key = new Function('row', `return ${match[1]};`);
  return { page, state, db, rdb, key };
}

test('changing every course type refreshes both labels and persists after reopening', async () => {
  const h = await setup();
  const labels = ['必修·考试', '必修·考查', '选修·专选', '选修·任选', '慕课', '其他'];
  const types = ['COM_A', 'COM_B', 'OPT_A', 'OPT_B', 'MOOC', 'TAG'];
  for (const index of [1, 2, 3, 4, 5, 0]) {
    const before = h.page.subjectRows[0];
    const oldKey = h.key(before);
    h.page.chooseSubjectType(before);
    assert.deepEqual(h.state.menus.at(-1).buttons.map(item => item.text), labels);
    h.state.answer(index);
    await settle();
    const row = h.page.subjectRows[0];
    assert.equal(row.subject.type, types[index]);
    assert.equal(h.page.constructor.typeName(row.subject.type), labels[index]);
    assert.notEqual(h.key(row), oldKey, 'ForEach must not reuse the stale header builder');
    assert.equal(before.subject.type === row.subject.type, false, 'old UI state is not mutated before saving');
    assert.equal(h.state.saved.type, types[index]);
    assert.equal(h.page.expandedSubjectId, 'subject-a');
    assert.equal(h.page.creditDraft, '4.0');
    assert.equal(row.classCount, 1);
    assert.equal(row.sessions[0].id, 'class-a');
    assert.deepEqual(h.state.writes.at(-1).values, { type: types[index] });
    const savedKey = h.key(row);
    await h.page.load();
    assert.equal(h.key(h.page.subjectRows[0]), savedKey);
  }
  const source = read('pages/TimetableDetailPage.ets');
  assert.equal((source.match(/Text\(TimetableDetailPage\.typeName\(row\.subject\.type\)/g) || []).length, 2);
});

test('cancelling, invalid menu indices and selecting the existing type do not write data', async () => {
  const h = await setup();
  for (const index of [undefined, -1, 99, 0]) {
    const row = h.page.subjectRows[0];
    const oldKey = h.key(row);
    h.page.chooseSubjectType(row);
    h.state.answer(index);
    await settle();
    assert.equal(h.state.writes.length, 0);
    assert.equal(h.key(h.page.subjectRows[0]), oldKey);
    assert.equal(h.page.subjectTypeChanging, false);
  }
  assert.deepEqual(h.state.toasts, []);
});

test('failed saves retain the old type and show an error; retry can succeed', async () => {
  const h = await setup();
  h.state.failWrite = true;
  const row = h.page.subjectRows[0];
  h.page.chooseSubjectType(row);
  h.page.chooseSubjectType(row);
  assert.equal(h.state.menus.length, 1, 'rapid taps share one selection flow');
  h.state.answer(1);
  await settle();
  assert.equal(h.state.saved.type, 'COM_A');
  assert.equal(row.subject.type, 'COM_A');
  assert.equal(h.page.subjectTypeChanging, false);
  assert.match(h.state.toasts.at(-1), /课程类型未更新/);
  h.state.failWrite = false;
  h.page.chooseSubjectType(row);
  h.state.answer(1);
  await settle();
  assert.equal(h.page.subjectRows[0].subject.type, 'COM_B');
  assert.equal(h.state.saved.name, '高等数学');
  assert.equal(h.state.saved.credit, 4);
  assert.equal(h.state.saved.field, '专业课');
});

test('updating a deleted subject fails instead of silently recreating it', async () => {
  const h = await setup();
  h.state.saved = undefined;
  await assert.rejects(h.rdb.updateSubjectType('subject-a', 'COM_B'), /no longer exists/);
  assert.equal(h.state.saved, undefined);
});
