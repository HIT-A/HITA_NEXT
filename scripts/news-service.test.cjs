const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');

const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/feature/news/NewsService.ets'), 'utf8');
const compiled = ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;
const EventType = Object.fromEntries([
  'START_TAG', 'END_TAG', 'TEXT', 'CDSECT', 'ENTITY_REFERENCE', 'WHITESPACE', 'DOCDECL'
].map(name => [name, name]));
const tag = (name, contents = []) => [['START_TAG', name], ...contents, ['END_TAG', name]];
const field = (name, value, event = 'TEXT') => tag(name, [[event, '', value]]);
const item = (title, link, extra = []) => tag('item', [
  ...field('title', title, 'CDSECT'), ...field('link', link), ...extra
]);
const feed = items => tag('rss', tag('channel', items));

// The native XML parser is exercised on-device; these tests cover our callback and HTTP behavior.
function loadService(options = {}) {
  const state = { requests: [], destroyed: 0, parsed: [] };
  const platform = name => {
    if (name === '@kit.ArkTS') return {
      util: { TextEncoder: class {
        encodeInto(value) { return new TextEncoder().encode(value); }
      } },
      xml: {
        EventType,
        XmlPullParser: class {
          constructor(data) { state.parsed.push(new TextDecoder().decode(data)); }
          parseXml(config) {
            assert.equal(config.supportDoctype, false);
            if (options.xmlError) throw Error('invalid XML');
            for (const [event, name, text = ''] of options.events || feed([])) {
              config.tokenValueCallbackFunction(event, {
                getName: () => name, getText: () => text
              });
            }
          }
        }
      }
    };
    if (name === '@kit.NetworkKit') return { http: {
      RequestMethod: { GET: 'GET' }, HttpDataType: { STRING: 'string' },
      createHttp: () => ({
        request: async (url, config) => {
          state.requests.push({ url, config });
          if (options.offline) throw Error('offline');
          return options.response || { responseCode: 200, result: '<rss version="2.0"><channel/></rss>' };
        },
        destroy: () => { state.destroyed++; }
      })
    } };
    throw Error(`Unexpected import: ${name}`);
  };
  const mod = { exports: {} };
  new Function('require', 'module', 'exports', compiled)(platform, mod, mod.exports);
  return { NewsService: mod.exports.NewsService, state };
}

test('blog XML tokens preserve CDATA, decoded entities, multiple authors and publication dates', () => {
  const events = feed([
    ...field('title', 'Channel title'),
    ...tag('image', field('title', 'Channel image')),
    ...tag('item', [
      ...tag('title', [['CDSECT', '', '课程 <攻略>'], ['ENTITY_REFERENCE', '', '&'], ['TEXT', '', ' 笔记']]),
      ...field('link', 'https://hoa.moe/blog/guide?a=1&b=2'),
      ...field('pubDate', 'Mon, 14 Sep 2026 00:00:00 GMT'),
      ...field('author', '作者甲'),
      ...field('author', '作者乙'),
      ...field('description', 'This is not the title'),
      ...field('content:encoded', '<h1>正文与 <item> 标签不应进入列表</h1>', 'CDSECT')
    ]),
    ...item('相对链接', '/blog/second', [...field('dc:creator', '作者丙'), ...field('pubDate', 'invalid')])
  ]);
  const { NewsService } = loadService({ events });
  const result = NewsService.parseBlogFeed('feed body');
  assert.deepEqual(result.map(entry => ({ ...entry })), [
    { title: '课程 <攻略>& 笔记', url: 'https://hoa.moe/blog/guide?a=1&b=2', department: '作者甲、作者乙', date: '2026-09-14' },
    { title: '相对链接', url: 'https://hoa.moe/blog/second', department: '作者丙', date: '' }
  ]);
});

test('blog entries skip duplicates, empty titles and links outside the HOA blog', () => {
  const { NewsService } = loadService({ events: feed([
    ...item('First', 'https://hoa.moe/blog/first'),
    ...item('Duplicate', 'https://hoa.moe/blog/first'),
    ...item('  ', 'https://hoa.moe/blog/empty'),
    ...item('Wrong section', 'https://hoa.moe/docs/course'),
    ...item('Wrong domain', 'https://hoa.moe.invalid/blog/a'),
    ...item('Unsafe', 'javascript:alert(1)'),
    ...item('Missing URL', ''),
    ...item('Second', '/blog/second')
  ]) });
  assert.deepEqual(NewsService.parseBlogFeed('feed').map(entry => [entry.title, entry.department]),
    [['First', 'HOA'], ['Second', 'HOA']]);
});

test('an empty RSS feed is valid, while HTML, truncated feeds and doctypes are rejected', () => {
  assert.deepEqual(loadService().NewsService.parseBlogFeed('empty feed'), []);
  for (const events of [
    tag('html', tag('body', field('title', 'Challenge page'))),
    [['START_TAG', 'rss'], ['START_TAG', 'channel']],
    [['DOCDECL', '', 'external entity'], ...feed([])]
  ]) {
    assert.throws(() => loadService({ events }).NewsService.parseBlogFeed('not a valid feed'));
  }
});

test('blogs use the HOA RSS endpoint once and never request the former news category or a second feed page', async () => {
  const { NewsService, state } = loadService({ events: feed([
    ...item('Blog', 'https://hoa.moe/blog/example')
  ]) });
  const result = await NewsService.fetchCategory('blog', 0);
  assert.equal(result.ok, true);
  assert.equal(result.hasMore, false);
  assert.equal(result.items.length, 1);
  assert.equal(state.requests[0].url, 'https://hoa.moe/blog/rss.xml');
  assert.match(state.requests[0].config.header.Accept, /application\/rss\+xml/);
  assert.equal(state.requests[0].config.usingCache, false);
  assert.equal(state.parsed.length, 1);
  assert.equal(state.destroyed, 1);
  assert.deepEqual({ ...await NewsService.fetchCategory('blog', 1) },
    { items: [], ok: true, hasMore: false, message: '' });
  assert.equal(state.requests.length, 1);
});

test('notifications retain the original HTML source, metadata parsing and page-number convention', async () => {
  const html = '<li><div class="pull-right"><a href="/department/123">教务处</a>' +
    '<span class="date">今天</span></div><a href="/article/2026/10/05/123">课程 &amp; 考试通知</a></li>';
  const { NewsService, state } = loadService({ response: { responseCode: 200, result: html } });
  const result = await NewsService.fetchCategory('10', 0);
  assert.equal(result.ok, true);
  assert.equal(result.hasMore, true);
  assert.deepEqual({ ...result.items[0] }, {
    title: '课程 & 考试通知', url: 'https://today.hit.edu.cn/article/2026/10/05/123',
    department: '教务处', date: '2026-10-05'
  });
  await NewsService.fetchCategory('10', 2);
  assert.deepEqual(state.requests.map(request => request.url),
    ['https://today.hit.edu.cn/category/10', 'https://today.hit.edu.cn/category/10?page=2']);
  assert.equal(state.parsed.length, 0);
  assert.equal(state.destroyed, 2);
  const empty = await loadService({ response: { responseCode: 200, result: '<ul></ul>' } })
    .NewsService.fetchCategory('10', 1);
  assert.equal(empty.ok, true);
  assert.equal(empty.hasMore, false);
});

test('HTTP failures, offline requests and invalid XML remain retryable errors and release the request', async () => {
  for (const options of [
    { response: { responseCode: 503, result: '' } },
    { offline: true },
    { xmlError: true },
    { events: tag('html', []) }
  ]) {
    const { NewsService, state } = loadService(options);
    const result = await NewsService.fetchCategory('blog', 0);
    assert.equal(result.ok, false);
    assert.equal(result.hasMore, false);
    assert.ok(result.message.length > 0);
    assert.notEqual(result.message, '暂无可显示的资讯');
    assert.equal(state.destroyed, 1);
  }
});

test('unknown categories and invalid pages do not issue HTTP requests', async () => {
  const { NewsService, state } = loadService();
  for (const [id, page] of [['11', 0], ['blog', -1], ['10', 0.5], ['10', NaN]]) {
    assert.equal((await NewsService.fetchCategory(id, page)).ok, false);
  }
  assert.equal(state.requests.length, 0);
});
