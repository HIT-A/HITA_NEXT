const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const cache = new Map();
const requests = [];
function load(file) {
  file = path.resolve(root, file);
  if (cache.has(file)) return cache.get(file).exports;
  const mod = { exports: {} };
  cache.set(file, mod);
  const req = name => {
    if (name === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, warn() {}, error() {} } };
    if (name === '@kit.NetworkKit') return { http: {
      createHttp: () => ({
        request: async (url, options) => { requests.push({ url, options }); return { responseCode: 200, result: '' }; },
        destroy() {}
      }), RequestMethod: { GET: 'GET', POST: 'POST' }, HttpDataType: { STRING: 'STRING' }
    } };
    if (name.startsWith('@kit.')) return {};
    assert.ok(name.startsWith('.'), name);
    return load(path.resolve(path.dirname(file), name + '.ets'));
  };
  const js = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  new Function('require', 'module', 'exports', js)(req, mod, mod.exports);
  return mod.exports;
}
const { EasDataProvider: Provider } = load('feature/eas/EasDataProvider.ets');
const { EasSession, EasCampus: Campus } = load('feature/eas/EasSession.ets');
const { EasSessionStatus: Status, isExpiredEasResponse } = load('feature/eas/EasSessionStatus.ets');
const { EasApiClient, EasApiClientOptions } = load('feature/eas/EasApiClient.ets');
const { easWebLoginConfigFor, EasCampusUrls } = load('feature/eas/webLogin/EasWebLoginConfig.ets');
const response = (body = '', statusCode = 200) => ({ body, statusCode });
const session = campus => {
  const saved = new EasSession();
  saved.campus = campus;
  saved.webBaseUrl = EasCampusUrls.SHENZHEN_PROXY_BASE;
  saved.webCookies.set('JSESSIONID', 'synthetic-session');
  return saved;
};
const terms = name => `<select name="${name}"><option value="2026-20271">秋季</option></select>`;
const shenzhenTerms = JSON.stringify({ code: 200, data: [{ xn: '2026-2027', xq: '1' }] });

test('all campuses require authenticated business data rather than the presence of saved credentials', async () => {
  for (const campus of Object.values(Campus)) {
    const saved = session(campus);
    const original = saved.encode();
    const calls = [];
    const provider = new Provider({ request: async (s, cfg, endpoint, options) => {
      calls.push(endpoint);
      assert.equal(s, saved);
      assert.equal(cfg.campus, campus);
      assert.equal(options.useCache, false);
      assert.equal(options.extraHeaders.get('Cache-Control'), 'no-cache');
      assert.ok(options.timeoutMs <= 6000);
      if (campus === Campus.SHENZHEN) {
        assert.equal(options.method, 'POST');
        assert.equal(options.extraHeaders.get('RoleCode'), '01');
        return response(shenzhenTerms);
      }
      assert.equal(options.method, 'GET');
      assert.match(options.extraHeaders.get('Accept'), /text\/html/);
      return response('<a href="/loginCAS">教务首页</a>' + terms('xnxq'));
    } });
    assert.equal(await provider.checkSessionStatus(saved), Status.CONNECTED);
    assert.equal(calls.length, 1);
    assert.equal(saved.encode(), original, 'verification does not mutate credentials');
  }
});

test('expired cookies return expired for HTTP 401, login forms, redirects and JSON authentication failures', async () => {
  const expired = [
    response('', 401),
    response('<form action="/loginCAS?service=/kbcx/queryGrkb"><input type="password"></form>'),
    response('<form><input name=mm></form>'),
    response('<script>top.location.href="/cas/login";</script>'),
    response('<script>window.location.replace("/authentication/require");</script>'),
    response('<meta http-equiv="refresh" content="0;url=/cas/login">'),
    response('<p>教务会话已过期，请重新登录</p>'),
    response(JSON.stringify({ code: 401, msg: 'Unauthorized' })),
    response(JSON.stringify({ code: -1, msg: '未登录' })),
    response(JSON.stringify({ code: 'LOGIN_EXPIRED', data: [] }))
  ];
  for (const campus of Object.values(Campus)) {
    const saved = session(campus);
    assert.equal(saved.isLogin(), true, 'old presence predicate is not a validity check');
    for (const value of expired) {
      let calls = 0;
      const provider = new Provider({ request: async () => { calls++; return value; } });
      assert.equal(await provider.checkSessionStatus(saved), Status.EXPIRED, value.body);
      assert.equal(calls, 1, 'do not retry invalid credentials');
    }
  }
});

test('offline, maintenance, permission failures and unrecognized pages are never claimed connected or expired', async () => {
  for (const value of [response('', 0), response('maintenance', 503),
    response('rate limited', 429), response('Forbidden', 403), response('<html>Portal</html>'),
    response('{"data":[]}'), response('{"code":200,"msg":"OK"}')]) {
    const provider = new Provider({ request: async () => value });
    assert.equal(await provider.checkSessionStatus(session(Campus.WEIHAI)), Status.UNKNOWN, value.body);
  }
  const provider = new Provider({ request: async () => { throw Error('offline'); } });
  assert.equal(await provider.checkSessionStatus(session(Campus.BENBU)), Status.UNKNOWN);
  assert.equal(isExpiredEasResponse(response('<a href="/loginCAS">退出登录</a>' + terms('xnxq'))), false);
});

test('fallback term endpoints still verify deployments with different schemas', async () => {
  for (const campus of [Campus.BENBU, Campus.WEIHAI, Campus.SHENZHEN]) {
    const paths = [];
    const provider = new Provider({ request: async (_s, _cfg, endpoint) => {
      paths.push(endpoint);
      if (paths.length === 1) return response('', 404);
      return response(campus === Campus.SHENZHEN ? shenzhenTerms : terms('pageXnxq'));
    } });
    assert.equal(await provider.checkSessionStatus(session(campus)), Status.CONNECTED);
    assert.equal(paths.length, 2);
  }
});

test('missing usable credentials expire locally without making requests', async () => {
  const provider = new Provider({ request: async () => { assert.fail('no credential, no request'); } });
  const saved = session(Campus.WEIHAI);
  saved.webCookies.clear();
  saved.accessToken = 'legacy-token';
  assert.equal(await provider.checkSessionStatus(saved), Status.EXPIRED);
});

test('bounded verification returns unknown on timeout even if an old response later succeeds', async () => {
  let release;
  const provider = new Provider({ request: () => new Promise(resolve => { release = resolve; }) });
  const pending = provider.checkSessionStatus(session(Campus.BENBU), 5);
  assert.equal(await pending, Status.UNKNOWN);
  release(response(terms('xnxq')));
  assert.equal(await pending, Status.UNKNOWN);
});

test('session probes disable the underlying HTTP response cache', async () => {
  requests.length = 0;
  const saved = session(Campus.WEIHAI);
  const options = new EasApiClientOptions();
  options.useCache = false;
  await new EasApiClient().request(saved, easWebLoginConfigFor(saved.campus, saved.getStudentType()),
    '/kbcx/queryGrkb', options);
  assert.equal(requests[0].options.usingCache, false);
  assert.match(requests[0].options.header.Cookie, /JSESSIONID=synthetic-session/);
});

const { EasSessionStore } = load('feature/eas/EasSessionStore.ets');
function storedSessions(data = new Map()) {
  const state = new Map();
  global.AppStorage = { get: key => state.get(key), setOrCreate: (key, value) => state.set(key, value) };
  const store = new EasSessionStore();
  store.store = {
    get: async (key, fallback) => data.has(key) ? data.get(key) : fallback,
    put: async (key, value) => { data.set(key, value); },
    delete: async key => { data.delete(key); }, flush: async () => {}
  };
  return { store, data, state };
}

test('saved expiry persists across store reloads and does not erase the account, cookies or selected campus', async () => {
  const { store, data } = storedSessions();
  const saved = session(Campus.SHENZHEN); saved.name = 'Fixture';
  await store.save(saved);
  await store.save(session(Campus.BENBU));
  await store.markExpired(saved);
  const current = await storedSessions(data).store.load(Campus.SHENZHEN);
  assert.equal(current.loginExpired, true);
  assert.equal(current.name, 'Fixture');
  assert.equal(current.webCookies.get('JSESSIONID'), 'synthetic-session');
  assert.equal(current.isLogin(), true);
  assert.equal(await store.loadLastCampus(), Campus.BENBU);
  assert.equal((await store.load(Campus.BENBU)).loginExpired, false);
  const legacy = JSON.parse(saved.encode()); delete legacy.loginExpired;
  assert.equal(EasSession.decode(JSON.stringify(legacy)).loginExpired, false);
});

test('real request path marks only definite authentication failures for each campus', async () => {
  const previousStore = EasSessionStore.instance;
  const previousHttp = EasApiClient.doHttp;
  try {
    for (const campus of Object.values(Campus)) {
      for (const result of [response('', 401), response('{"code":"LOGIN_EXPIRED"}'),
        response('<form action="/loginCAS"><input type="password"></form>')]) {
        const { store } = storedSessions(); EasSessionStore.instance = store;
        const saved = session(campus); await store.save(saved);
        EasApiClient.doHttp = async () => result;
        assert.equal(await new EasApiClient().request(saved, easWebLoginConfigFor(campus, '1'),
          '/fixture-business', new EasApiClientOptions()), result);
        assert.equal((await store.load(campus)).loginExpired, true);
      }
    }
  } finally { EasApiClient.doHttp = previousHttp; EasSessionStore.instance = previousStore; }
});

test('network and non-auth failures never mark an account expired; arbitrary success does not clear known expiry', async () => {
  const previousStore = EasSessionStore.instance;
  const previousHttp = EasApiClient.doHttp;
  try {
    for (const result of [response('', 0), response('maintenance', 503), response('Forbidden', 403),
      response('Not allowed', 405), response('rate limit', 429), response('unrecognized'),
      response('<a href="/loginCAS">退出登录</a>'+terms('xnxq'))]) {
      const { store } = storedSessions(); EasSessionStore.instance = store;
      const saved = session(Campus.WEIHAI); await store.save(saved);
      EasApiClient.doHttp = async () => result;
      await new EasApiClient().request(saved, easWebLoginConfigFor(saved.campus, '1'),
        '/fixture-business', new EasApiClientOptions());
      assert.equal((await store.load(saved.campus)).loginExpired, false);
    }
    const { store } = storedSessions(); EasSessionStore.instance = store;
    const saved = session(Campus.WEIHAI); await store.save(saved); await store.markExpired(saved);
    EasApiClient.doHttp = async () => response(terms('xnxq'));
    await new EasApiClient().request(saved, easWebLoginConfigFor(saved.campus, '1'),
      '/fixture-business', new EasApiClientOptions());
    assert.equal((await store.load(saved.campus)).loginExpired, true);
    await store.save(saved);
    assert.equal((await store.load(saved.campus)).loginExpired, false);
  } finally { EasApiClient.doHttp = previousHttp; EasSessionStore.instance = previousStore; }
});

test('late old request cannot expire a new login or recreate a logged-out session', async () => {
  const previousStore = EasSessionStore.instance;
  const previousHttp = EasApiClient.doHttp;
  try {
    const { store } = storedSessions(); EasSessionStore.instance = store;
    const saved = session(Campus.SHENZHEN); await store.save(saved);
    let release;
    EasApiClient.doHttp = () => new Promise(resolve => { release = resolve; });
    const pending = new EasApiClient().request(saved, easWebLoginConfigFor(saved.campus, '1'),
      '/fixture-business', new EasApiClientOptions());
    const renewed = session(saved.campus); await store.save(renewed);
    release(response('', 401)); await pending;
    assert.ok(renewed.sessionGeneration > saved.sessionGeneration);
    assert.equal((await store.load(saved.campus)).loginExpired, false);
    await store.clear(saved.campus); await store.markExpired(renewed);
    assert.equal(await store.load(saved.campus), undefined);
  } finally { EasApiClient.doHttp = previousHttp; EasSessionStore.instance = previousStore; }
});

test('login and expiry writes are serialized so a fresh login always clears the old flag', async () => {
  for (const expiryFirst of [true, false]) {
    const { store } = storedSessions();
    const old = session(Campus.BENBU); await store.save(old);
    const fresh = session(Campus.BENBU);
    const actions = expiryFirst ? [store.markExpired(old), store.save(fresh)] :
      [store.save(fresh), store.markExpired(old)];
    await Promise.all(actions);
    const loaded = await store.load(old.campus);
    assert.equal(loaded.loginExpired, false);
    assert.equal(loaded.sessionGeneration, fresh.sessionGeneration);
  }
});
