const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');
const source = fs.readFileSync(path.resolve(__dirname, '../entry/src/main/ets/pages/TimetableManagerPage.ets'), 'utf8');
const between = (start, end) => source.slice(source.indexOf(start), source.indexOf(end));

function page(save) {
  const create = between('  private async createEmptyTimetable()', '  /** Export the selected/current');
  const menu = between('  private showExportMenu()', '  private confirmDelete()');
  const compiled = ts.transpileModule(`class TimetableManagerPage {
    adding = false; loading = false; deleting = false; exporting = false;
    static defaultName() { return 'Test term'; }
    ${create}
    ${menu}
  }`, { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText;
  const calls = { selected: [], routed: [], exported: [], toasts: [] };
  const host = new Function('RdbHelper', 'TimetableSelectionStore', 'EasTimetable', 'WEEK_MS',
    compiled + '; return new TimetableManagerPage();')(
    { getInstance: () => ({ saveTimetable: save }) },
    { getInstance: () => ({ save: async id => calls.selected.push(id) }) },
    class { id = 'new'; static mondayMsOf(time) { return time; } }, 7 * 86400000
  );
  host.getUIContext = () => ({
    getRouter: () => ({ pushUrl: options => calls.routed.push(options) }),
    getPromptAction: () => ({ showToast: options => calls.toasts.push(options.message) })
  });
  host.load = async () => {};
  host.exportTimetable = timetable => calls.exported.push(timetable.id);
  host.timetables = [{ id: 'newest' }, { id: 'current' }];
  host.activeTimetableId = 'current';
  return { host, calls };
}

test('rapid create clicks produce one timetable and only select it after the save succeeds', async () => {
  let finish, writes = 0;
  const { host, calls } = page(() => {
    writes++;
    return new Promise(resolve => { finish = resolve; });
  });
  const first = host.createEmptyTimetable();
  await host.createEmptyTimetable();
  assert.equal(writes, 1);
  assert.equal(host.adding, true);
  assert.deepEqual(calls.selected, []);
  finish();
  await first;
  assert.deepEqual(calls.selected, ['new']);
  assert.equal(calls.routed.length, 1);
  assert.equal(host.adding, false);
});

test('creation failures retain the current selection and release the action guard', async () => {
  const { host, calls } = page(async () => { throw Error('disk full'); });
  await host.createEmptyTimetable();
  assert.equal(host.activeTimetableId, 'current');
  assert.deepEqual(calls.selected, []);
  assert.deepEqual(calls.routed, []);
  assert.equal(calls.toasts.length, 1);
  assert.equal(host.adding, false);
});

test('export uses the current timetable rather than the first row and handles missing selections', () => {
  const { host, calls } = page(async () => {});
  host.showExportMenu();
  assert.deepEqual(calls.exported, ['current']);
  host.activeTimetableId = 'deleted';
  host.showExportMenu();
  assert.deepEqual(calls.exported, ['current', 'newest']);
  host.timetables = [];
  host.showExportMenu();
  assert.equal(calls.exported.length, 2);
  assert.equal(calls.toasts.length, 1);
});
