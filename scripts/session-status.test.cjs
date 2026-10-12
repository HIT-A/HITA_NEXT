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
