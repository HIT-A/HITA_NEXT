const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const source = fs.readFileSync(path.join(root, 'common/util/DockNavigationGuard.ets'), 'utf8');
const output = ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;
const TouchType = { Down: 0, Up: 1, Move: 2, Cancel: 3 };
const mod = { exports: {} };
new Function('module', 'exports', 'TouchType', output)(mod, mod.exports, TouchType);
const Guard = mod.exports.DockNavigationGuard;
const point = (x = 100, y = 700, id = 0) => ({ windowX: x, windowY: y, id });
let timestamp = 0;
function event(type, points = [point()], history = []) {
  return { type, timestamp: ++timestamp, changedTouches: points,
    touches: type === TouchType.Up ? [] : points,
    getHistoricalPoints: () => history.map(touchObject => ({ touchObject })) };
}
function down(guard) {
  const e = event(TouchType.Down);
  guard.begin(e, false); // parent hit test
  guard.begin(e, true); // native bar hit test
  guard.observe(e);
}
function click(guard, index = 1) {
  const ticket = guard.requestClick();
  assert.equal(guard.allowsChange(index), false, 'native automatic change must be vetoed');
  const changes = [];
  guard.commitClick(ticket, index, i => {
    assert.equal(guard.allowsChange(i), true, 'only the validated controller call is authorized');
    assert.equal(guard.allowsChange((i + 1) % 3), false);
    changes.push(i);
  });
  assert.equal(guard.allowsChange(index), false, 'authorization must not leak to later native changes');
  return changes;
}

test('Dock changes only after a released, validated icon click, exactly once', () => {
  const guard = new Guard();
  down(guard);
  assert.deepEqual(click(guard), [], 'holding is not a click');
  guard.observe(event(TouchType.Up));
  assert.equal(guard.allowsChange(1), false, 'Up by itself is not a click');
  assert.deepEqual(click(guard), [1]);
  assert.deepEqual(click(guard), [], 'duplicate native callbacks cannot change twice');
  down(guard);
  guard.observe(event(TouchType.Move, [point(103, 702)]));
  guard.observe(event(TouchType.Up, [point(103, 702)]));
  assert.deepEqual(click(guard, 2), [2], 'ordinary stationary tap jitter remains usable');
});

for (const [name, points] of [
  ['short left', [point(85)]], ['short right', [point(115)]],
  ['long left', [point(-500)]], ['long right', [point(800)]],
  ['leave Dock vertically', [point(100, 200)]],
  ['diagonal', [point(400, 300)]],
  ['out and back', [point(500), point()]],
  ['reverse repeatedly', [point(500), point(-500), point(500), point()]]
]) {
  test('Dock never changes during or after a drag: ' + name, () => {
    const guard = new Guard();
    down(guard);
    for (const p of points) {
      guard.observe(event(TouchType.Move, [p]));
      for (const index of [0, 1, 2]) assert.equal(guard.allowsChange(index), false);
      assert.deepEqual(click(guard), [], 'even a synthesized click while dragging must fail');
    }
    guard.observe(event(TouchType.Up, [points.at(-1)]));
    for (const index of [0, 1, 2]) assert.deepEqual(click(guard, index), []);
  });
}

test('coalesced out-and-back movement and a fling whose only displacement is in Up are rejected', () => {
  for (const release of [event(TouchType.Up, [point()], [point(500)]),
    event(TouchType.Up, [point(500)])]) {
    const guard = new Guard();
    down(guard);
    guard.observe(release);
    assert.deepEqual(click(guard), []);
  }
});

test('cancel and multiple fingers never turn into a Dock click', () => {
  for (const invalid of [event(TouchType.Cancel),
    event(TouchType.Down, [point(), point(150, 700, 1)])]) {
    const guard = new Guard();
    down(guard);
    guard.begin(invalid, true);
    guard.observe(invalid);
    guard.observe(event(TouchType.Up));
    assert.deepEqual(click(guard), []);
  }
});

test('click-before-Up callback ordering works after dispatch but movement invalidates it', () => {
  for (const moved of [false, true]) {
    const guard = new Guard();
    down(guard);
    const ticket = guard.requestClick();
    assert.equal(guard.allowsChange(1), false);
    guard.observe(event(TouchType.Up, [moved ? point(500) : point()]));
    const changes = [];
    guard.commitClick(ticket, 1, i => changes.push(i));
    assert.deepEqual(changes, moved ? [] : [1]);
  }
});

test('API 26 duplicate native callbacks select the final clicked item rather than index zero', () => {
  for (const target of [0, 1, 2]) {
    const guard = new Guard();
    down(guard);
    const early = guard.requestClick(); // floating bar callback: index 0
    guard.observe(event(TouchType.Up));
    const actual = guard.requestClick(); // actual item callback
    const changes = [];
    guard.commitClick(early, 0, i => changes.push(i));
    guard.commitClick(actual, target, i => changes.push(i));
    assert.deepEqual(changes, [target]);
  }
});

test('duplicate API 26 callbacks cannot authorize a drag or restore an obsolete click', () => {
  const guard = new Guard();
  down(guard);
  guard.observe(event(TouchType.Move, [point(500)]));
  const early = guard.requestClick();
  guard.observe(event(TouchType.Up, [point()]));
  const actual = guard.requestClick();
  guard.commitClick(early, 0, () => assert.fail('early callback after drag'));
  guard.commitClick(actual, 2, () => assert.fail('actual callback after drag'));
  down(guard);
  guard.observe(event(TouchType.Up));
  assert.deepEqual(click(guard, 1), [1]);
});

test('new content gestures restore page swiping and invalidate any deferred Dock click', () => {
  const guard = new Guard();
  down(guard);
  guard.observe(event(TouchType.Up));
  const ticket = guard.requestClick();
  guard.begin(event(TouchType.Down, [point(100, 100)]), false);
  assert.equal(guard.isDock(), false);
  for (const index of [0, 1, 2]) assert.equal(guard.allowsChange(index), true);
  guard.commitClick(ticket, 1, () => assert.fail('stale click'));
  // A child can stop bubbling Up. A genuinely new Down must still recover.
  down(guard);
  guard.observe(event(TouchType.Up));
  assert.deepEqual(click(guard), [1]);
});

test('Home wires both Dock renderers through the change veto and deferred click guard', () => {
  const home = fs.readFileSync(path.join(root, 'pages/Home.ets'), 'utf8');
  assert.match(home, /onContentWillChange[\s\S]*?return this\.dockNavigation\.allowsChange\(comingIndex\)/);
  assert.match(home, /onTabBarClick[\s\S]*?this\.requestDockClick\(index\)/);
  assert.match(home, /onSelect:[\s\S]*?this\.requestDockClick\(index\)/);
  assert.match(home, /onDockTouch:[\s\S]*?this\.dockNavigation\.observe\(event\)/);
  assert.match(home, /setTimeout\(\(\) => \{\s*this\.dockNavigation\.commitClick/);
  assert.equal((home.match(/tabsController\.changeIndex/g) || []).length, 1);
});
