const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const settle = () => new Promise(setImmediate);

function setup(name) {
  const calls = { queries: [], imports: 0, back: 0, toasts: [], selection: [] };
  const state = { terms: [{ name: 'Next', isCurrent: false }, { name: 'Current', isCurrent: true }],
    scores: async () => ({ ok: true, items: [{ courseCode: 'a', score: '90' }] }),
    imported: async () => ({ success: true, timetable: { id: 'new' }, message: '已导入' }) };
  const session = { campus: 'WEIHAI' };
  class Provider {
    async getAllTerms() { return state.terms; }
    async getPersonalScores(received, term) {
      calls.queries.push({ session: received, term });
      return state.scores();
    }
  }
  const timers = new Map();
  let timerId = 0;
  const mocks = {
    '../common/theme/StatusBarInset': { STATUS_BAR_INSET_FALLBACK: 44 },
    '../feature/eas/EasSession': { EasCampus: { SHENZHEN: 'SHENZHEN', WEIHAI: 'WEIHAI', BENBU: 'BENBU' } },
    '../feature/eas/EasSessionStore': { EasSessionStore: { getInstance: () => ({
      init: async () => {}, loadPreferred: async () => session
    }) } },
    '../feature/eas/EasDataProvider': { EasDataProvider: Provider },
    '../feature/eas/EasApiClient': { EasApiClient: class {} },
    '../feature/eas/EasTimetableImporter': { EasTimetableImporter: {
      importCurrent: async () => { calls.imports++; return state.imported(); }
    } },
    '../feature/eas/EasUserMessages': { EasUserMessages: { fromError: (_, fallback) => fallback } },
    '../feature/timetable/data/TimetableSelectionStore': { TimetableSelectionStore: { getInstance: () => ({
      init: async () => {}, save: async id => calls.selection.push(id)
    }) } }
  };
  let source = fs.readFileSync(path.join(root, `pages/${name}.ets`), 'utf8');
  const helper = name === 'ScorePage' ? '\n  static campusText' : '\n  private static dateText';
  source = source.slice(0, source.indexOf('\n  build()')) + source.slice(source.indexOf(helper));
  source = source.replace(/^@(Entry|Component)\r?\n/gm, '')
    .replace(/@(State|StorageProp)(\([^)]*\))?\s*/g, '')
    .replace(`struct ${name}`, `export class ${name}`);
  const mod = { exports: {} };
  const code = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  new Function('require', 'module', 'exports', '$r', 'Scroller', 'setTimeout', 'clearTimeout', code)(
    spec => mocks[spec] || {}, mod, mod.exports, name => name, class {},
    callback => { timers.set(++timerId, callback); return timerId; }, id => timers.delete(id));
  const page = new mod.exports[name]();
  page.getUIContext = () => ({
    getHostContext: () => ({}),
    getPromptAction: () => ({ showToast: item => calls.toasts.push(item.message) }),
    getRouter: () => ({ back: () => { calls.back++; } })
  });
  return { page, calls, state, session, timers };
}

test('scores use the preferred campus and current term, not the first term in the list', async () => {
  const h = setup('ScorePage');
  await h.page.aboutToAppear();
  await h.page.queryReal();
  assert.equal(h.page.hasSession, true);
  assert.equal(h.calls.queries[0].session, h.session);
  assert.equal(h.calls.queries[0].term, h.state.terms[1]);
  assert.equal(h.page.scores[0].score, '90');
});
test('scores cannot query twice and a response after leaving cannot modify the page', async () => {
  const h = setup('ScorePage');
  await h.page.aboutToAppear();
  let release;
  h.state.scores = () => new Promise(resolve => { release = resolve; });
  const querying = h.page.queryReal();
  await settle();
  await h.page.queryReal();
  assert.equal(h.calls.queries.length, 1);
  h.page.onPageHide();
  release({ ok: true, items: [{ courseCode: 'late' }] });
  await querying;
  assert.deepEqual(h.page.scores, []);
  assert.equal(h.page.loading, false);
});
test('a score query failure releases loading and presents the error in the empty state', async () => {
  const h = setup('ScorePage');
  await h.page.aboutToAppear();
  h.state.scores = async () => { throw Error('offline'); };
  await h.page.queryReal();
  assert.match(h.page.msg, /成绩查询失败/);
  assert.equal(h.page.loading, false);
  const source = fs.readFileSync(path.join(root, 'pages/ScorePage.ets'), 'utf8');
  assert.match(source, /Text\(this\.msg\.length > 0 \? this\.msg/);
});
test('finishing an import after leaving preserves data without popping another page', async () => {
  const h = setup('ImportTimetablePage');
  Object.assign(h.page, { pageActive: true, startTime: 1000, session: h.session,
    terms: h.state.terms, selectedTermIndex: 1 });
  let release;
  h.state.imported = () => new Promise(resolve => { release = resolve; });
  const importing = h.page.import();
  await settle();
  h.page.aboutToDisappear();
  release({ success: true, timetable: { id: 'new' }, message: '已导入' });
  await importing;
  assert.deepEqual(h.calls.selection, ['new']);
  assert.equal(h.calls.back, 0);
  assert.equal(h.calls.toasts.length, 0);
  assert.equal(h.timers.size, 0);
});
test('a completed import cannot be started twice and closing cancels its delayed return', async () => {
  const h = setup('ImportTimetablePage');
  Object.assign(h.page, { pageActive: true, startTime: 1000, session: h.session,
    terms: h.state.terms, selectedTermIndex: 1 });
  await h.page.import();
  assert.equal(h.timers.size, 1);
  await h.page.import();
  assert.equal(h.calls.imports, 1);
  const lateCallback = [...h.timers.values()][0];
  h.page.aboutToDisappear();
  assert.equal(h.timers.size, 0);
  lateCallback();
  assert.equal(h.calls.back, 0);
});
