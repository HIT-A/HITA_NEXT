const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');
global.$r = name => ({ id: -1, type: 10001, params: [name] });

const root = path.resolve(__dirname, '../entry/src/main/ets');
const flush = async () => { for (let i = 0; i < 60; i++) await Promise.resolve(); };
function setup(apiVersion = 26) {
  const timers = new Map();
  const cache = new Map();
  const state = { now: 10000, syncReads: 0, reads: 0, cookie: '', navigations: [],
    finished: [], errors: [], mfa: [], requests: 0, exchanges: 0, resetCookies: 0, resetStorage: 0, allReads: 0 };
  let timerId = 0;
  const setTimer = (callback, delay) => {
    const id = ++timerId;
    timers.set(id, { callback, time: state.now + delay });
    return id;
  };
  const clearTimer = id => timers.delete(id);
  const clock = class extends Date { static now() { return state.now; } };
  const web = {
    getUserAgent: () => 'test UA', setCustomUserAgent() {},
    loadUrl: url => state.navigations.push(url), refresh() {}, stop() {}, removeCache() {},
    runJavaScript: async () => 'false', accessBackward: () => false
  };
  const webview = {
    WebviewController: class {
      constructor() { return web; }
      static addIntelligentTrackingPreventionBypassingList() {}
    },
    WebCookieManager: {
      fetchAllCookies: () => {
        state.allReads++;
        return state.fetchAllCookies ? state.fetchAllCookies() : Promise.resolve([]);
      },
      fetchCookieSync: () => { state.syncReads++; return state.cookie; },
      fetchCookie: (...args) => {
        state.reads++;
        return state.fetchCookie ? state.fetchCookie(...args) : Promise.resolve(state.cookie);
      },
      clearAllCookies: async () => {
        state.resetCookies++;
        if (state.clearCookies) await state.clearCookies();
        state.cookie = '';
      },
      putAcceptCookieEnabled() {}, putAcceptThirdPartyCookieEnabled() {},
      isThirdPartyCookieAllowed: () => true
    },
    WebStorage: { deleteAllData: () => state.resetStorage++ }
  };
  const http = {
    RequestMethod: { GET: 'GET' }, HttpDataType: { STRING: 'STRING' },
    createHttp: () => ({
      request: url => {
        state.requests++;
        if (url.includes('/wengine-vpn/cookie')) {
          state.exchanges++;
          return state.httpResponse ? state.httpResponse() :
            Promise.resolve({ responseCode: 200, result: 'JSESSIONID=inner-session' });
        }
        return Promise.resolve({
          responseCode: state.verificationStatus ?? 200,
          result: state.verificationBody ?? '<select name="xnxq"><option value="2026-20271">2026秋季</option></select>'
        });
      }, destroy() {}
    })
  };
  function load(file) {
    file = path.resolve(root, file);
    if (cache.has(file)) return cache.get(file).exports;
    let source = fs.readFileSync(file, 'utf8');
    if (file.endsWith('EasLoginPage.ets')) {
      source = source.slice(0, source.indexOf('\n  build()')) + '\n}';
      source = source.replace(/^@Component\r?\n/gm, '')
        .replace(/@(State|Prop|StorageProp)(\([^)]*\))?\s+/g, '')
        .replace('export struct ', 'export class ');
    }
    const mod = { exports: {} };
    cache.set(file, mod);
    const localRequire = name => {
      if (name === '@kit.ArkWeb') return { webview };
      if (name === '@kit.NetworkKit') return { http };
      if (name === '@kit.BasicServicesKit') return { deviceInfo: { apiAvailable: () => apiVersion >= 26, sdkApiVersion: apiVersion } };
      if (name === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, warn() {}, error() {} } };
      if (name.startsWith('@kit.')) return {};
      assert.ok(name.startsWith('.'), name);
      return load(path.resolve(path.dirname(file), name + '.ets'));
    };
    const output = ts.transpileModule(source, {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
    }).outputText;
    new Function('require', 'module', 'exports', 'setTimeout', 'clearTimeout', 'Date', output)(
      localRequire, mod, mod.exports, setTimer, clearTimer, clock);
    return mod.exports;
  }
  const { EasWebLoginController } = load('feature/eas/webLogin/EasWebLoginController.ets');
  const { EasCampusUrls: urls } = load('feature/eas/webLogin/EasWebLoginConfig.ets');
  const ctrl = new EasWebLoginController();
  ctrl.attachWeb(web);
  ctrl.onFinished = session => state.finished.push(session);
  ctrl.onError = text => { if (text) state.errors.push(text); };
  ctrl.onMfaStateChanged = value => state.mfa.push({ ...value });
  async function tick(ms) {
    const end = state.now + ms;
    for (let guard = 0; guard < 1000; guard++) {
      await flush();
      const next = [...timers.entries()].filter(([, timer]) => timer.time <= end)
        .sort((a, b) => a[1].time - b[1].time)[0];
      if (!next) break;
      const [id, timer] = next;
      timers.delete(id);
      state.now = timer.time;
      timer.callback();
    }
    state.now = end;
    await flush();
  }
  async function page(url) {
    ctrl.notifyPageBegin(url);
    ctrl.notifyPageEnd(url);
    await flush();
  }
  return { ctrl, state, web, urls, tick, page, load, timers };
}

test('returning from authentication to the portal opens EAS again instead of keeping the old navigation latch', async () => {
  const { ctrl, state, urls, page } = setup();
  ctrl.start('WEIHAI', '1');
  await page(urls.WEIHAI_LOGIN);
  await page('https://ids.hitwh.edu.cn/authserver/login');
  await page(urls.WEIHAI_LOGIN);
  assert.equal(state.navigations.filter(url => url === urls.WEIHAI_JWTS).length, 2);
  ctrl.stop();
});

test('stale cookies on a login intermediary cannot finish authentication', async () => {
  const { ctrl, state, urls, page, tick } = setup();
  state.cookie = 'wengine_vpn_ticket_test=old-ticket; JSESSIONID=old-session';
  state.verificationStatus = 401;
  ctrl.start('WEIHAI', '1');
  await page(urls.WEIHAI_JWTS);
  await tick(600);
  assert.equal(state.finished.length, 0);
  assert.equal(state.exchanges, 1);
  ctrl.stop();
});

test('cookie probes never use synchronous reads on the UI thread', async () => {
  const { ctrl, state, urls, page } = setup();
  ctrl.start('WEIHAI', '1');
  await page(urls.WEIHAI_EAS_PREFIX + '/kbcx/queryGrkb');
  assert.equal(state.syncReads, 0);
  assert.ok(state.reads > 0);
  ctrl.stop();
});

test('late MFA detection cannot cover the next page after navigation', async () => {
  const { ctrl, state, urls, page, load } = setup();
  const { EasWebMfaBridge, EasMfaOverlayState } = load('feature/eas/webLogin/EasWebMfaBridge.ets');
  let resolve;
  EasWebMfaBridge.detect = () => new Promise(done => { resolve = done; });
  ctrl.start('WEIHAI', '1');
  await page('https://webvpn.hitwh.edu.cn/authserver/reAuthCheck/index');
  assert.ok(resolve);
  ctrl.notifyPageBegin(urls.WEIHAI_EAS_PREFIX + '/index');
  resolve(Object.assign(new EasMfaOverlayState(), { visible: true }));
  await flush();
  assert.equal(state.mfa.filter(value => value.visible).length, 0);
  ctrl.stop();
});

test('late MFA actions cannot change the next page or schedule another overlay', async () => {
  const { ctrl, state, urls, load, tick } = setup();
  const { EasWebMfaBridge } = load('feature/eas/webLogin/EasWebMfaBridge.ets');
  ctrl.start('WEIHAI', '1');
  ctrl.mfaState.visible = true;
  const pending = [];
  for (const method of ['submit', 'sendCode', 'switchMethod']) {
    EasWebMfaBridge[method] = () => new Promise(resolve => pending.push(resolve));
  }
  const actions = [ctrl.submitMfaInput('123456'), ctrl.sendMfaCode(), ctrl.switchMfaMethod()];
  ctrl.notifyPageBegin(urls.WEIHAI_EAS_PREFIX + '/index');
  pending.forEach(resolve => resolve({ ok: true }));
  await Promise.all(actions);
  await tick(2000);
  assert.equal(state.errors.length, 0);
  assert.equal(state.mfa.filter(value => value.visible).length, 0);
  ctrl.stop();
});

test('authentication/portal redirect loops stop with a recovery message', async () => {
  const { ctrl, state, urls, page } = setup();
  ctrl.start('WEIHAI', '1');
  for (let i = 0; i < 5; i++) {
    await page('https://ids.hitwh.edu.cn/authserver/login');
    await page(urls.WEIHAI_LOGIN);
  }
  assert.equal(state.navigations.length, 3);
  assert.ok(state.errors.some(error => error.includes('重置')));
  ctrl.stop();
});

test('duplicate page-end events run one cookie exchange and finish once', async () => {
  const { ctrl, state, urls } = setup();
  state.cookie = 'wengine_vpn_ticket_test=ticket; JSESSIONID=session';
  ctrl.start('WEIHAI', '1');
  const url = urls.WEIHAI_EAS_PREFIX + '/kbcx/queryGrkb';
  ctrl.notifyPageBegin(url);
  ctrl.notifyPageEnd(url);
  ctrl.notifyPageEnd(url);
  await flush();
  assert.equal(state.exchanges, 1);
  assert.equal(state.requests, 2);
  assert.equal(state.finished.length, 1);
});

test('slow cookie reads do not block cancellation or finish a later login', async () => {
  const { ctrl, state, urls, tick } = setup();
  const pending = [];
  state.fetchCookie = () => new Promise(resolve => pending.push(resolve));
  ctrl.start('WEIHAI', '1');
  const url = urls.WEIHAI_EAS_PREFIX + '/index';
  ctrl.notifyPageBegin(url);
  ctrl.notifyPageEnd(url);
  assert.ok(pending.length > 0);
  ctrl.stop();
  ctrl.start('BENBU', '1');
  pending.forEach(resolve => resolve('wengine_vpn_ticket_test=ticket; JSESSIONID=old'));
  await tick(4000);
  assert.equal(state.finished.length, 0);
  assert.equal(state.requests, 0);
  assert.equal(state.syncReads, 0);
  ctrl.stop();
});

test('Weihai VPN-only browser cookies exchange the server-side session before validating EAS', async () => {
  const { ctrl, state, urls, page } = setup();
  state.cookie = 'wengine_vpn_ticket_test=ticket';
  ctrl.start('WEIHAI', '1');
  await page(urls.WEIHAI_JWTS);
  assert.equal(state.exchanges, 1);
  assert.equal(state.requests, 2);
  assert.equal(state.finished.length, 1);
  assert.equal(state.finished[0].webCookies.get('JSESSIONID'), 'inner-session');
});

test('quoted cookie responses are decoded and a verified VPN-only session remains usable', async () => {
  for (const result of ['"JSESSIONID=quoted-session"', '']) {
    const { ctrl, state, urls, page } = setup();
    state.cookie = 'wengine_vpn_ticket_test=ticket';
    state.httpResponse = async () => ({ responseCode: 200, result });
    ctrl.start('WEIHAI', '1');
    await page(urls.WEIHAI_JWTS);
    assert.equal(state.finished.length, 1);
    assert.equal(state.finished[0].isLogin(), true);
    if (result) assert.equal(state.finished[0].webCookies.get('JSESSIONID'), 'quoted-session');
  }
});

test('gateway success or stale inner cookies without an authenticated timetable never finishes login', async () => {
  const { ctrl, state, urls, page, tick } = setup();
  state.cookie = 'wengine_vpn_ticket_test=ticket';
  state.verificationBody = '<form action="/login"><input name="password"></form>';
  ctrl.start('WEIHAI', '1');
  await page(urls.WEIHAI_JWTS);
  await tick(4000);
  assert.equal(state.exchanges, 3);
  assert.equal(state.finished.length, 0);
  assert.ok(state.errors.some(error => error.includes('教务会话尚未就绪')));
  ctrl.stop();
});

test('never-settling cookie and JavaScript operations time out asynchronously', async () => {
  const { state, load, web, tick } = setup();
  state.fetchCookie = () => new Promise(() => {});
  web.runJavaScript = () => new Promise(() => {});
  const { EasWebLoginController } = load('feature/eas/webLogin/EasWebLoginController.ets');
  const { EasWebMfaBridge } = load('feature/eas/webLogin/EasWebMfaBridge.ets');
  const cookie = EasWebLoginController.tryFetchCookie('https://webvpn.hitwh.edu.cn/');
  const script = EasWebMfaBridge.runJs(web, 'test');
  await tick(5000);
  assert.equal(await cookie, '');
  assert.equal(await script, '');
  assert.equal(state.syncReads, 0);
});

test('late cookie exchange responses cannot complete a cancelled or restarted login', async () => {
  const { ctrl, state, urls, page } = setup();
  state.cookie = 'wengine_vpn_ticket_test=ticket; JSESSIONID=session';
  let resolve;
  state.httpResponse = () => new Promise(done => { resolve = done; });
  ctrl.start('WEIHAI', '1');
  await page(urls.WEIHAI_EAS_PREFIX + '/index');
  assert.equal(state.requests, 1);
  ctrl.stop();
  ctrl.start('SHENZHEN', '1');
  resolve({ responseCode: 200, result: 'JSESSIONID=old-inner' });
  await flush();
  assert.equal(state.finished.length, 0);
  ctrl.stop();
});

test('the active EAS host takes precedence over stale cookies from another probe URL', async () => {
  const { ctrl, state, urls, page } = setup();
  state.fetchCookie = url => Promise.resolve(url.startsWith(urls.SHENZHEN_DIRECT_BASE) ?
    'JSESSIONID=current; route=current-route' : 'JSESSIONID=stale; route=stale-route');
  ctrl.start('SHENZHEN', '1');
  await page(urls.SHENZHEN_DIRECT_BASE + '/student_index');
  assert.equal(state.finished.length, 1);
  assert.equal(state.finished[0].webCookies.get('JSESSIONID'), 'current');
});

test('Weihai reauthentication and unrelated sites cannot be success pages even with old cookies', () => {
  const { load, urls } = setup();
  const { isWeihaiAuthenticatedPage } = load('feature/eas/webLogin/EasWebLoginProbe.ets');
  const cookies = new Map([['wengine_vpn_ticket_test', 'ticket'], ['JSESSIONID', 'session']]);
  for (const url of [urls.WEIHAI_JWTS, urls.WEIHAI_EAS_PREFIX + '/reAuth',
    'https://other.example/index', 'https://webvpn.hitwh.edu.cn/authserver/reAuthCheck/index']) {
    assert.equal(isWeihaiAuthenticatedPage(url, cookies), false, url);
  }
  assert.equal(isWeihaiAuthenticatedPage(urls.WEIHAI_EAS_PREFIX + '/index', cookies), true);
});

function loginPage(harness) {
  const { EasLoginPage } = harness.load('feature/eas/webLogin/EasLoginPage.ets');
  const page = new EasLoginPage();
  page.getUIContext = () => ({ getPromptAction: () => ({
    showDialog: async () => ({ index: 0 })
  }) });
  page.campusCode = 'WEIHAI';
  page.aboutToAppear();
  return page;
}

test('a page that never finishes loading releases the overlay and offers recovery', async () => {
  const h = setup();
  const page = loginPage(h);
  page.watchPageLoad(h.urls.WEIHAI_LOGIN);
  await h.tick(20000);
  assert.equal(page.webReady, true);
  assert.match(page.errorText, /重置/);
  page.aboutToDisappear();
  assert.equal(h.timers.size, 0);
});

test('recovery waits for a blank page before clearing only Web storage and restarting login', async () => {
  const h = setup();
  const page = loginPage(h);
  page.beginRecovery();
  assert.equal(h.state.resetCookies, 0);
  assert.equal(h.state.navigations.at(-1), 'about:blank');
  page.pageEnded(h.urls.WEIHAI_LOGIN);
  assert.equal(h.state.resetCookies, 0);
  page.pageEnded('about:blank');
  await flush();
  assert.equal(h.state.resetCookies, 1);
  assert.equal(h.state.resetStorage, 1);
  assert.equal(h.state.navigations.at(-1), h.urls.WEIHAI_LOGIN);
  assert.equal(page.recoveryBusy, false);
  const source = fs.readFileSync(path.join(root, 'feature/eas/webLogin/EasLoginPage.ets'), 'utf8');
  const reset = source.slice(source.indexOf('  private beginRecovery'), source.indexOf('  private updateWebNavigation'));
  assert.doesNotMatch(reset, /RdbHelper|\.clear\(|\.delete\(|EasSessionStore|preferences/);
  page.aboutToDisappear();
});

test('reset completion after cancelling the login window cannot reopen it', async () => {
  const h = setup();
  let resolve;
  h.state.clearCookies = () => new Promise(done => { resolve = done; });
  const page = loginPage(h);
  page.beginRecovery();
  page.pageEnded('about:blank');
  page.cancelLogin();
  resolve();
  await flush();
  assert.deepEqual(h.state.navigations, ['about:blank']);
  assert.equal(h.state.resetStorage, 0);
  assert.equal(h.timers.size, 0);
});

test('a hung reset times out without leaving the login window busy forever', async () => {
  const h = setup();
  h.state.clearCookies = () => new Promise(() => {});
  const page = loginPage(h);
  page.beginRecovery();
  page.pageEnded('about:blank');
  await h.tick(15000);
  assert.equal(page.recoveryBusy, false);
  assert.equal(page.webReady, true);
  assert.match(page.errorText, /超时/);
  page.aboutToDisappear();
});

function storedCookie(overrides = {}) {
  return { name: 'JSESSIONID', value: 'session', domain: 'jwts.hit.edu.cn', path: '/',
    isSessionCookie: true, isSecure: true, isHttpOnly: true, expiresDate: '', samesitePolicy: 0, ...overrides };
}

test('API 23 supplements URL-scoped cookies without replacing the authoritative session', async () => {
  const h = setup(23);
  const { EasWebLoginController } = h.load('feature/eas/webLogin/EasWebLoginController.ets');
  const calls = [];
  h.state.fetchCookie = (...args) => { calls.push(args); return Promise.resolve('JSESSIONID=current'); };
  h.state.fetchAllCookies = async () => [storedCookie({ value: 'stale' }), storedCookie({ name: 'ticket', value: 'extra' })];
  assert.equal(await EasWebLoginController.tryFetchCookieWithPartitioned('https://jwts.hit.edu.cn/index'),
    'JSESSIONID=current; ticket=extra');
  assert.deepEqual(calls, [['https://jwts.hit.edu.cn/index']]);
  assert.equal(h.state.allReads, 1);
  assert.equal(h.state.syncReads, 0);
  assert.equal(h.timers.size, 0);
});

test('API 26 keeps partition-aware native reads and never enumerates the old cookie store', async () => {
  const h = setup(26);
  const { EasWebLoginController } = h.load('feature/eas/webLogin/EasWebLoginController.ets');
  const calls = [];
  h.state.fetchCookie = (...args) => { calls.push(args); return Promise.resolve(args.length === 3 ? 'ticket=partitioned' : 'sid=normal'); };
  assert.equal(await EasWebLoginController.tryFetchCookieWithPartitioned('https://jwts.hit.edu.cn/'), 'sid=normal; ticket=partitioned');
  assert.deepEqual(calls, [['https://jwts.hit.edu.cn/'], ['https://jwts.hit.edu.cn/', false, true]]);
  assert.equal(h.state.allReads, 0);
});

test('legacy cookie selection respects domain, path case, Secure, expiry and ambiguous partition values', () => {
  const { LegacyCookieReader } = setup(23).load('feature/eas/webLogin/LegacyCookieReader.ets');
  const cookies = [
    storedCookie({ name: 'good', path: '/EAS' }),
    storedCookie({ name: 'httpOnly' }),
    storedCookie({ name: 'parent', domain: '.hit.edu.cn' }),
    storedCookie({ name: 'other', domain: 'evilhit.edu.cn' }),
    storedCookie({ name: 'hostOnly', domain: 'hit.edu.cn' }),
    storedCookie({ name: 'wrongCase', path: '/eas' }),
    storedCookie({ name: 'prefix', path: '/EA' }),
    storedCookie({ name: 'expired', isSessionCookie: false, expiresDate: '1970-01-01T00:00:01Z' }),
    storedCookie({ name: 'badExpiry', isSessionCookie: false, expiresDate: 'bad' }),
    storedCookie({ name: 'conflict', value: 'partition-a' }),
    storedCookie({ name: 'conflict', value: 'partition-b' }),
    storedCookie({ name: 'injected', value: 'value; another=bad' })
  ];
  assert.equal(LegacyCookieReader.select(cookies, 'https://jwts.hit.edu.cn/EAS/index', 10000),
    'good=session; httpOnly=session; parent=session');
  assert.equal(LegacyCookieReader.select(cookies, 'http://jwts.hit.edu.cn/EAS/index', 10000), '');
});

test('API 23 supplement stays on the active first-party host and times out without losing normal cookies', async () => {
  const h = setup(23);
  const { EasWebLoginController } = h.load('feature/eas/webLogin/EasWebLoginController.ets');
  h.state.cookie = 'sid=normal';
  assert.equal(await EasWebLoginController.tryFetchCookieWithPartitioned('https://jwts.hit.edu.cn/', 'https://ids.hit.edu.cn/'), 'sid=normal');
  assert.equal(h.state.allReads, 0);
  h.state.fetchAllCookies = () => new Promise(() => {});
  const pending = EasWebLoginController.tryFetchCookieWithPartitioned('https://jwts.hit.edu.cn/');
  await h.tick(3000);
  assert.equal(await pending, 'sid=normal');
  assert.equal(h.timers.size, 0);
  h.state.fetchAllCookies = async () => [storedCookie()];
  assert.equal(await EasWebLoginController.tryFetchCookieWithPartitioned('https://jwts.hit.edu.cn/'), 'sid=normal; JSESSIONID=session');
});
