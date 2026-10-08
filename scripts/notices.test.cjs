const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const pageSource = read('pages/NoticesPage.ets');
const seed = { id: 'hello-2026', title: 'Old title', body: 'Old body', severity: 'info' };

function setup(cached = [seed]) {
  let cache = JSON.stringify(cached);
  const calls = { requests: [], destroyed: 0, writes: 0, warnings: [] };
  const network = { payload: { notices: [seed] }, status: 200, error: undefined };
  const store = {
    get: async () => cache,
    put: async (_, value) => { cache = value; calls.writes++; },
    flush: async () => {}
  };
  const mocks = {
    '@kit.AbilityKit': { bundleManager: {
      BundleFlag: { GET_BUNDLE_INFO_DEFAULT: 0 },
      getBundleInfoForSelfSync: () => ({ versionCode: 1000000, versionName: '0.1.0' })
    } },
    '@kit.ArkData': { preferences: { getPreferences: async () => store } },
    '@kit.PerformanceAnalysisKit': { hilog: {
      info: () => {}, warn: (...args) => calls.warnings.push(args)
    } },
    '@kit.NetworkKit': { http: {
      RequestMethod: { GET: 'GET' }, HttpDataType: { STRING: 'STRING' },
      createHttp: () => ({
        request: async (url, options) => {
          calls.requests.push({ url, options });
          if (network.error) throw network.error;
          return { responseCode: network.status,
            result: typeof network.payload === 'string' ?
              network.payload : JSON.stringify(network.payload) };
        },
        destroy: () => { calls.destroyed++; }
      })
    } },
    '../common/components/HeaderBackButton': {},
    '../common/theme/StatusBarInset': { STATUS_BAR_INSET_FALLBACK: 44 }
  };
  function load(source) {
    const output = ts.transpileModule(source, { compilerOptions: {
      module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020
    } }).outputText;
    const mod = { exports: {} };
    new Function('require', 'module', 'exports', '$r', 'Scroller', output)(name => {
      assert.ok(name in mocks, `Unexpected import ${name}`);
      return mocks[name];
    }, mod, mod.exports, name => name, class {});
    return mod.exports;
  }
  const model = load(read('feature/notice/AppNoticeCenter.ets'));
  mocks['../feature/notice/AppNoticeCenter'] = model;
  const source = (pageSource.slice(0, pageSource.indexOf('\n  build()')) + '\n}\n')
    .replace(/^@(Entry|Component)\r?\n/gm, '')
    .replace(/@(State|StorageProp)(\([^)]*\))?\s*/g, '')
    .replace('struct NoticesPage', 'export class NoticesPage');
  const { NoticesPage } = load(source);
  const page = new NoticesPage();
  page.getUIContext = () => ({ getHostContext: () => ({}) });
  return { ...model, page, network, calls, cache: () => JSON.parse(cache) };
}

test('same-id edits change the ForEach identity and replace cached content', async () => {
  const { AppNoticeCenter, page, network, cache, calls } = setup();
  const [old] = await AppNoticeCenter.cachedNotices({});
  network.payload = { notices: [{ ...seed, title: 'Launch announcement', body: 'New body\n\nQQ group' }] };
  await page.aboutToAppear();
  assert.equal(page.notices[0].id, old.id);
  assert.notEqual(page.notices[0].renderKey(), old.renderKey());
  assert.equal(page.notices[0].body, 'New body\n\nQQ group');
  assert.equal(cache()[0].title, 'Launch announcement');
  assert.equal(page.loading, false);
  assert.equal(page.refreshing, false);
  assert.equal(page.errorMessage, '');
  assert.match(pageSource, /\(notice: AppNotice\) => notice\.renderKey\(\)/);
  assert.equal(calls.requests[0].options.usingCache, false);
  assert.equal(calls.requests[0].options.header['Cache-Control'], 'no-cache');
  assert.equal(calls.destroyed, 1);
});

test('render identity changes for every displayed field, but remains stable otherwise', () => {
  const { AppNotice } = setup();
  const original = Object.assign(new AppNotice(), seed);
  for (const field of ['id', 'title', 'body', 'severity']) {
    const changed = Object.assign(new AppNotice(), seed, { [field]: 'different' });
    assert.notEqual(changed.renderKey(), original.renderKey(), field);
  }
  assert.equal(Object.assign(new AppNotice(), seed).renderKey(), original.renderKey());
});

test('network failures preserve cached notices and expose a retryable state', async () => {
  const { page, network, calls, cache } = setup();
  network.error = new Error('offline');
  await page.aboutToAppear();
  assert.equal(page.notices[0].title, seed.title);
  assert.equal(page.errorMessage, '公告更新失败，当前显示上次保存的内容');
  assert.equal(page.refreshing, false);
  assert.equal(calls.writes, 0);
  assert.equal(cache()[0].body, seed.body);
  network.error = undefined;
  network.payload = { notices: [{ ...seed, body: 'Recovered' }] };
  await page.refreshNotices();
  assert.equal(page.notices[0].body, 'Recovered');
  assert.equal(page.errorMessage, '');
  assert.equal(calls.destroyed, 2);
});

test('HTTP errors, malformed JSON and invalid envelopes do not erase last good cache', async () => {
  for (const variant of ['http', 'json', 'envelope']) {
    const { page, network, calls } = setup();
    if (variant === 'http') network.status = 503;
    if (variant === 'json') network.payload = '{"notices": [';
    if (variant === 'envelope') network.payload = { notices: {} };
    await page.aboutToAppear();
    assert.equal(page.notices[0].body, seed.body);
    assert.ok(page.errorMessage);
    assert.equal(calls.writes, 0);
    assert.equal(calls.destroyed, 1);
    assert.equal(calls.warnings.length, 1);
  }
});

test('first load failure is not confused with an empty feed', async () => {
  const { page, network } = setup([]);
  network.error = new Error('offline');
  await page.aboutToAppear();
  assert.equal(page.notices.length, 0);
  assert.equal(page.errorMessage, '公告暂时无法加载');
  assert.equal(page.loading, false);
});

test('a successful empty feed removes old announcements and clears the cache', async () => {
  const { page, network, cache } = setup();
  network.payload = { notices: [] };
  await page.aboutToAppear();
  assert.equal(page.notices.length, 0);
  assert.equal(cache().length, 0);
  assert.equal(page.errorMessage, '');
});

test('cached instances retain methods and active filtering after a fresh download', async () => {
  const { AppNoticeCenter, network } = setup();
  network.payload = { notices: [
    seed,
    { ...seed, id: 'urgent', severity: 'critical' },
    { ...seed, id: 'future', starts_at: Date.now() + 600000 },
    { ...seed, id: 'expired', ends_at: 1 },
    { ...seed, id: 'new-version', min_app_version: 2000000 }
  ] };
  await AppNoticeCenter.fetch({});
  const cached = await AppNoticeCenter.cachedNotices({});
  assert.equal(cached[1].isCritical(), true);
  assert.deepEqual(AppNoticeCenter.activeNotices(cached).map(item => item.id), ['urgent', seed.id]);
});
