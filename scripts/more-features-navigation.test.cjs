const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');

test('assistant, news and campus links are registered routes in More, after academic tools and before settings', () => {
  const home = read('pages/Home.ets');
  const more = home.slice(home.indexOf('  tabMine()'), home.indexOf('  userCard()'));
  const academic = more.indexOf("this.moreSectionTitle('教务功能')");
  const extras = more.indexOf("this.moreSectionTitle('更多')");
  const settings = more.indexOf("this.moreSectionTitle('设置')");
  assert.ok(academic >= 0 && academic < extras && extras < settings);
  const section = more.slice(extras, settings);
  const routes = JSON.parse(fs.readFileSync(path.join(root, '../resources/base/profile/main_pages.json'))).src;
  for (const [page, label, symbol] of [
    ['AssistantPage', '助手', 'AI_message'], ['NewsPage', '资讯', 'doc_text'],
    ['PortalsPage', '常用入口', 'link']
  ]) {
    assert.ok(section.includes(`this.moreNavigationRow($r('sys.symbol.${symbol}'), '${label}'`));
    assert.ok(section.includes(`getRouter().pushUrl({ url: 'pages/${page}' })`));
    assert.ok(routes.includes(`pages/${page}`));
    const source = read(`pages/${page}.ets`);
    assert.match(source, /@Entry\s+@Component/);
    assert.match(source, /Row\(\) \{\s*HeaderBackButton\(\{/);
    assert.match(source, /getRouter\(\)\.back\(\)/);
    assert.doesNotMatch(source, /replaceUrl|Tabs\(|TabContent\(|dockPageInset/);
  }
});

function deferred() {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
}

// Exercise actual route controller methods without ArkUI builders or live services.
function pageClass(name, mocks = {}, moduleCache = new Map()) {
  let source = read(`pages/${name}.ets`);
  source = source.slice(0, source.indexOf('\n  build()')) + '\n}\n';
  source = source.replace(/^@(Entry|Component|Observed)\r?\n/gm, '')
    .replace(/@(State|StorageProp|Watch)(\([^)]*\))?\s*/g, '')
    .replace(`struct ${name}`, `export class ${name}`);
  const mod = { exports: {} };
  const timers = new Map();
  let timerId = 0;
  const ui = {
    modes: [], scrolls: [], routes: [], stopped: 0, cleared: 0,
    getHostContext: () => ({}),
    setKeyboardAvoidMode: value => ui.modes.push(value),
    getFocusController: () => ({ clearFocus: () => { ui.cleared++; } }),
    getRouter: () => ({ pushUrl: route => ui.routes.push(route) })
  };
  const settings = class {
    provider = 'deepseek';
    apiKey = '';
    hasCloudModel() { return false; }
  };
  const platform = spec => {
    if (spec.endsWith('/AssistantConversation')) {
      if (!moduleCache.has(spec)) {
        const state = { exports: {} };
        const code = ts.transpileModule(read('feature/assistant/AssistantConversation.ets')
          .replace(/^@Observed\r?\n/gm, ''), {
          compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
        }).outputText;
        new Function('require', 'module', 'exports', code)(platform, state, state.exports);
        moduleCache.set(spec, state.exports);
      }
      return moduleCache.get(spec);
    }
    if (spec === '@kit.ArkUI') return { KeyboardAvoidMode: { NONE: 'none', OFFSET: 'offset' } };
    if (spec.endsWith('/StatusBarInset')) return {
      STATUS_BAR_INSET_FALLBACK: 44, NAV_BAR_INSET_FALLBACK: 28, KEYBOARD_INSET_FALLBACK: 0
    };
    if (spec.endsWith('/AssistantService')) return {
      AssistantService: {
        welcome: () => ({ content: 'welcome', role: 'assistant' }),
        reply: mocks.reply
      },
      AssistantRole: { USER: 'user', ASSISTANT: 'assistant' },
      AssistantMessage: { of: (role, content) => ({ role, content }) }
    };
    if (spec.endsWith('/AssistantSettingsStore')) return {
      AssistantProvider: { DEEPSEEK: 'deepseek' }, AssistantSettings: settings,
      AssistantSettingsStore: { getInstance: () => ({
        init: async () => {}, load: async () => new settings()
      }) }
    };
    if (spec.endsWith('/NewsService')) {
      const service = { exports: {} };
      const code = ts.transpileModule(read('feature/news/NewsService.ets'), {
        compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
      }).outputText;
      new Function('require', 'module', 'exports', code)(platform, service, service.exports);
      return { NewsService: {
        CATEGORIES: service.exports.NewsService.CATEGORIES, fetchCategory: mocks.fetchCategory
      } };
    }
    return {};
  };
  const compiled = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  new Function('require', 'module', 'exports', 'Scroller', 'TextInputController', 'Edge',
    'setTimeout', 'clearTimeout', compiled)(
    platform, mod, mod.exports,
    class { scrollEdge(edge) { ui.scrolls.push(edge); } },
    class { stopEditing() { ui.stopped++; } },
    { Bottom: 'bottom', Top: 'top' },
    callback => { timers.set(++timerId, callback); return timerId; },
    id => timers.delete(id));
  const Page = mod.exports[name];
  Page.prototype.getUIContext = () => ui;
  return { Page, ui, timers, moduleCache };
}

test('assistant input follows the keyboard and reclaims the former dock space', () => {
  const { Page, ui, timers } = pageClass('AssistantPage');
  const page = new Page();
  assert.equal(page.inputBarBottom(), 28);
  page.navBarInset = 20;
  assert.equal(page.inputBarBottom(), 20);
  page.keyboardInset = 302;
  assert.equal(page.inputBarBottom(), 302);
  page.onPageShow();
  assert.equal(ui.modes.at(-1), 'none');
  assert.equal(timers.size, 1);
  page.onPageHide();
  assert.equal(ui.modes.at(-1), 'offset');
  assert.equal(timers.size, 0);
  assert.equal(ui.stopped, 2);
  assert.equal(ui.cleared, 1);
  page.scrollToLatest();
  assert.equal(timers.size, 0);
});

test('leaving and reopening assistant preserves messages and an in-flight reply without resending', async () => {
  const pending = deferred();
  let requests = 0;
  const { Page, moduleCache } = pageClass('AssistantPage', {
    reply: () => { requests++; return pending.promise; }
  });
  const first = new Page();
  const sending = first.send('明天有什么课');
  assert.equal(first.chat.sending, true);
  first.onPageHide();
  first.aboutToDisappear();
  // ArkUI evaluates an @Entry page again on pushUrl; only imported modules retain state.
  const { Page: ReopenedPage } = pageClass('AssistantPage', {}, moduleCache);
  const reopened = new ReopenedPage();
  assert.equal(reopened.chat.messages.at(-1).content, '明天有什么课');
  assert.equal(reopened.chat.sending, true);
  await reopened.send('重复请求');
  reopened.clearChat();
  assert.equal(requests, 1);
  assert.equal(reopened.chat.messages.length, 2);
  pending.resolve({ role: 'assistant', content: '课表回答' });
  await sending;
  assert.equal(reopened.chat.messages.at(-1).content, '课表回答');
  assert.equal(reopened.chat.sending, false);
  reopened.clearChat();
  assert.equal(reopened.chat.messages.length, 1);
});

test('assistant reply errors release the shared sending state after leaving', async () => {
  const { Page } = pageClass('AssistantPage', { reply: async () => { throw Error('offline'); } });
  const first = new Page();
  const sending = first.send('问题');
  first.aboutToDisappear();
  await sending;
  const reopened = new Page();
  assert.equal(reopened.chat.sending, false);
  assert.match(reopened.chat.messages.at(-1).content, /稍后再试/);
});

test('a late news response cannot update a page that was closed', async () => {
  const pending = deferred();
  const { Page } = pageClass('NewsPage', { fetchCategory: () => pending.promise });
  const page = new Page();
  const loading = page.reload();
  page.aboutToDisappear();
  pending.resolve({ ok: true, items: [{ url: 'https://example.invalid/article', title: 'Late article' }] });
  await loading;
  assert.deepEqual(page.items, []);
  assert.equal(page.page, 0);
});

test('news contains only the two news categories, with no campus links or portal tab', () => {
  const news = read('pages/NewsPage.ets');
  assert.doesNotMatch(news, /PORTAL_TAB|portalScroller|portalList|portalItems|常用入口|CampusPortal|NewsPortal/);
  assert.match(news, /ForEach\(NewsService\.CATEGORIES/);
  assert.match(news, /this\.newsList\(\)/);
  assert.match(news, /accessibilityText\('刷新'\)/);
  assert.match(news, /Text\('博客与通知'\)/);
  assert.doesNotMatch(news, /今日哈工大/);
  const service = read('feature/news/NewsService.ets');
  assert.deepEqual([...service.matchAll(/new NewsCategory\('([^']+)', '([^']+)'\)/g)]
    .map(match => [match[1], match[2]]), [['blog', '博客'], ['10', '通知']]);
  assert.doesNotMatch(service, /NewsPortal|PORTALS/);
});

test('news opens on blogs and refreshing or reopening preserves the correct category mapping', async () => {
  const requests = [];
  const { Page } = pageClass('NewsPage', {
    fetchCategory: async (id, page) => {
      requests.push([id, page]);
      return { ok: true, items: [], message: '', hasMore: false };
    }
  });
  const page = new Page();
  assert.equal(page.selected, 0);
  page.aboutToAppear();
  await page.reload();
  assert.deepEqual(requests, [['blog', 0], ['blog', 0]]);

  page.selectTab(1);
  await page.reload();
  assert.deepEqual(requests.slice(2), [['10', 0], ['10', 0]]);
  page.aboutToDisappear();

  const reopened = new Page();
  reopened.aboutToAppear();
  assert.equal(reopened.selected, 0);
  assert.deepEqual(requests.at(-1), ['blog', 0]);
});

test('six campus links are grouped into school sites and course resources, and open in the in-app browser', () => {
  const source = read('feature/portal/CampusPortal.ets');
  const mod = { exports: {} };
  const compiled = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  new Function('module', 'exports', compiled)(mod, mod.exports);
  const groups = mod.exports.CampusPortal.GROUPS;
  assert.deepEqual(groups.map(group => [group.title, group.portals.length]),
    [['学校官网', 3], ['课程资源', 3]]);
  const entries = groups.flatMap(group => group.portals);
  assert.deepEqual(entries.map(portal => [portal.title, portal.url]), [
    ['哈工大官网', 'https://www.hit.edu.cn/'],
    ['哈工大深圳', 'https://www.hitsz.edu.cn/'],
    ['哈工大威海', 'https://www.hitwh.edu.cn/'],
    ['HOA 课程攻略', 'https://hoa.moe/'],
    ['薪火笔记', 'https://fireworks.jwyihao.top/'],
    ['深校课程平台', 'https://course.hitsz.edu.cn/']
  ]);
  assert.doesNotMatch(source, /今日哈工大|today\.hit\.edu\.cn/);
  const portals = read('pages/PortalsPage.ets');
  assert.match(portals, /ForEach\(CampusPortal\.GROUPS/);
  assert.match(portals, /ListItemGroup\(\{ header: this\.groupHeader\(group\.title\)/);
  assert.match(portals, /ForEach\(group\.portals/);
  assert.match(portals, /this\.open\(portal\)/);
  assert.doesNotMatch(portals, /NewsService|fetchCategory|aboutToAppear|Refresh\(/);
  const { Page, ui } = pageClass('PortalsPage');
  const page = new Page();
  for (const portal of entries) page.open(portal);
  assert.deepEqual(ui.routes, entries.map(portal => ({
    url: 'pages/WebBrowserPage', params: { url: portal.url, title: portal.title }
  })));
});

test('switching news categories resets scrolling and ignores stale responses', async () => {
  const pending = [];
  const { Page, ui } = pageClass('NewsPage', {
    fetchCategory: (id, page) => {
      const request = { id, page, ...deferred() };
      pending.push(request);
      return request.promise;
    }
  });
  const page = new Page();
  const original = page.reload();
  page.selectTab(1);
  page.selectTab(2);
  page.selectTab(-1);
  assert.equal(page.selected, 1);
  assert.deepEqual(pending.map(request => [request.id, request.page]), [['blog', 0], ['10', 0]]);
  assert.deepEqual(ui.scrolls, ['top']);
  pending[1].resolve({ ok: true, items: [{ url: 'notice', title: 'Notice' }] });
  await pending[1].promise;
  pending[0].resolve({ ok: true, items: [{ url: 'news', title: 'Old blog' }] });
  await original;
  assert.deepEqual(page.items.map(item => item.url), ['notice']);
  assert.equal(page.loading, false);
});

test('the complete blog feed stops pagination while notifications still load subsequent pages', async () => {
  const requests = [];
  const { Page } = pageClass('NewsPage', {
    fetchCategory: async (id, page) => {
      requests.push([id, page]);
      return {
        ok: true, hasMore: id === '10' && page === 0, message: '',
        items: [{ url: `${id}/${page}`, title: 'Article' }]
      };
    }
  });
  const page = new Page();
  await page.reload();
  assert.equal(page.hasMore, false);
  page.selectTab(1);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(page.hasMore, true);
  await page.loadPage();
  assert.equal(page.hasMore, false);
  assert.deepEqual(requests, [['blog', 0], ['10', 0], ['10', 1]]);
  assert.deepEqual(page.items.map(item => item.url), ['10/0', '10/1']);
});
