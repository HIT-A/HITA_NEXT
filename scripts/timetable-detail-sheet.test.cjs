const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const source = fs.readFileSync(path.resolve(__dirname,
  '../entry/src/main/ets/pages/TimetableDetailPage.ets'), 'utf8').replace(/\r\n/g, '\n');
const binding = source.slice(source.indexOf('.bindSheet('), source.indexOf('  private static dateText('));
function callback(name) {
  return binding.match(new RegExp(name + ': \\(\\) => \\{([\\s\\S]*?)\\n      \\}'))?.[1] || '';
}
function harness() {
  const methods = source.slice(source.indexOf('  private openEventDetail('),
    source.indexOf('  private toggleSubject('));
  const code = ts.transpileModule(`class DetailPage {
    sheetVisible = false;
    eventSheetMode = 0;
    selectedEvent;
    sheetEventId = '';
    ${methods}
    willDisappear() { ${callback('onWillDisappear')} }
    didDisappear() { ${callback('onDisappear')} }
  }`, { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText;
  const target = new Function(code + '; return new DetailPage();')();
  const emptyVisibleStates = [];
  const page = new Proxy(target, {
    set(object, key, value) {
      Reflect.set(object, key, value);
      if (object.sheetVisible && object.eventSheetMode !== 2 && !object.selectedEvent) {
        emptyVisibleStates.push(String(key));
      }
      return true;
    }
  });
  return { page, emptyVisibleStates };
}

test('native dismissal hides the sheet before clearing its selected lesson', () => {
  const { page, emptyVisibleStates } = harness();
  page.openEventDetail({ id: 'lesson-a' });
  // A system dismissal must work even when no application close button ran.
  page.didDisappear();
  assert.equal(page.sheetVisible, false);
  assert.equal(page.eventSheetMode, 0);
  assert.equal(page.selectedEvent, undefined);
  assert.equal(page.sheetEventId, '');
  assert.deepEqual(emptyVisibleStates, [], 'reactive updates must not create an empty visible sheet');
});

test('outside tap, back and drag dismissal keep exit content stable and allow reopening', () => {
  assert.match(binding, /\.bindSheet\(\$\$this\.sheetVisible,/);
  for (const reason of ['outside tap', 'back', 'drag']) {
    const { page, emptyVisibleStates } = harness();
    const event = { id: reason };
    page.openEventDetail(event);
    page.willDisappear();
    assert.equal(page.sheetVisible, false, reason);
    assert.equal(page.eventSheetMode, 1, 'retain fit-content mode through exit animation');
    assert.equal(page.selectedEvent, event);
    assert.equal(page.sheetEventId, event.id);
    page.didDisappear();
    assert.deepEqual(emptyVisibleStates, []);
    const next = { id: 'next-lesson' };
    page.openEventDetail(next);
    assert.equal(page.sheetVisible, true);
    assert.equal(page.selectedEvent, next);
    assert.equal(page.sheetEventId, next.id);
  }
});

test('programmatic editor close keeps its height and event until exit finishes', () => {
  const { page, emptyVisibleStates } = harness();
  const event = { id: 'editing-lesson' };
  page.openEventDetail(event);
  page.eventSheetMode = 2;
  page.closeSheet();
  assert.equal(page.sheetVisible, false);
  assert.equal(page.eventSheetMode, 2);
  assert.equal(page.selectedEvent, event);
  page.willDisappear();
  assert.equal(page.eventSheetMode, 2);
  page.didDisappear();
  assert.equal(page.eventSheetMode, 0);
  assert.equal(page.sheetEventId, '');
  assert.deepEqual(emptyVisibleStates, []);
});
