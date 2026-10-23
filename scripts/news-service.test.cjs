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
const EasCampus = { BENBU: 'BENBU', SHENZHEN: 'SHENZHEN', WEIHAI: 'WEIHAI' };
const blogListHtml = `<main><div class="divide-y border-y">
  <div class="group relative flex flex-col"><a class="absolute inset-0" href="/blog/macbook-guide">
    <span class="sr-only">MacBook 配置指北</span></a><div><h2 class="font-medium">MacBook 配置指北</h2>
    <p class="text-sm">如何正确使用一台 MacBook</p><div class="mt-2"><a href="/blog/tags/%E7%94%B5%E8%84%91">#<!-- -->电脑设置</a>
    <a href="/blog/tags/%E6%95%88%E7%8E%87">#<!-- -->效率工具</a><a href="/blog/tags/%E6%95%88%E7%8E%87">#效率工具</a></div></div>
    <time dateTime="2026-09-14T00:00:00.000Z">2026 年 9 月 14 日</time></div>
  <div class="group relative flex flex-col"><a href="/blog/no-standard-answer">
    <span class="sr-only">大学从来没有标准答案</span></a><div><h2>大学从来没有标准答案</h2></div>
    <time dateTime="2026-09-12T00:00:00.000Z">2026 年 9 月 12 日</time></div>
  </div></main>`;

// The native XML parser is exercised on-device; these tests cover our callback and HTTP behavior.
function loadService(options = {}) {
  const state = { requests: [], destroyed: 0, parsed: [], cookieReads: [] };
  const platform = name => {
    if (name === '../eas/EasSession') return { EasCampus };
    if (name === '@kit.ArkWeb') return { webview: { WebCookieManager: {
      fetchCookie: async url => {
        state.cookieReads.push(url);
        if (options.cookieError) throw Error('cookie store unavailable');
        return options.cookie || '';
      }
    } } };
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
          if (url === 'https://hoa.moe/blog' && options.blogListResponse) return options.blogListResponse;
          if (url === 'https://hoa.moe/blog/rss.xml' && options.blogFeedResponse) return options.blogFeedResponse;
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
      ...field('description', '<p>摘要 &amp; 说明</p>', 'CDSECT'),
      ...field('content:encoded', '<h1>正文与 <item> 标签不应进入列表</h1>', 'CDSECT')
    ]),
    ...item('相对链接', '/blog/second', [...field('dc:creator', '作者丙'), ...field('pubDate', 'invalid')])
  ]);
  const { NewsService } = loadService({ events });
  const result = NewsService.parseBlogFeed('feed body');
  assert.deepEqual(result.map(entry => ({ ...entry })), [
    { title: '课程 <攻略>& 笔记', url: 'https://hoa.moe/blog/guide?a=1&b=2', department: '作者甲、作者乙', date: '2026-09-14',
      summary: '摘要 & 说明', tags: [] },
    { title: '相对链接', url: 'https://hoa.moe/blog/second', department: '作者丙', date: '', summary: '', tags: [] }
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

test('HOA blog list parses its lightweight cards, dates and only same-site articles', () => {
  const { NewsService } = loadService();
  const html = blogListHtml.replace('</div></main>', `
    <a href="/blog/tags"><span class="sr-only">标签</span></a><h2>标签</h2><time dateTime="2026-01-01"></time>
    <a href="https://evil.example/blog/a"><span class="sr-only">外链</span></a><h2>外链</h2><time dateTime="2026-01-01"></time>
  </div></main>`);
  assert.deepEqual(NewsService.parseBlogList(html).map(value => ({ ...value })), [
    { url: 'https://hoa.moe/blog/macbook-guide', title: 'MacBook 配置指北', department: 'HOA', date: '2026-09-14',
      summary: '如何正确使用一台 MacBook', tags: ['电脑设置', '效率工具'] },
    { url: 'https://hoa.moe/blog/no-standard-answer', title: '大学从来没有标准答案', department: 'HOA', date: '2026-09-12',
      summary: '', tags: [] }
  ]);
  assert.throws(() => NewsService.parseBlogList('<html>Service unavailable</html>'), /Unrecognized/);
});

test('normal blog refresh uses HOA list only and has no second page', async () => {
  const { NewsService, state } = loadService({ blogListResponse: { responseCode: 200, result: blogListHtml } });
  const result = await NewsService.fetchCategory('blog', 0);
  assert.equal(result.ok, true);
  assert.equal(result.hasMore, false);
  assert.equal(result.items.length, 2);
  assert.equal(state.requests[0].url, 'https://hoa.moe/blog');
  assert.match(state.requests[0].config.header.Accept, /text\/html/);
  assert.equal(state.requests[0].config.usingCache, false);
  assert.equal(state.parsed.length, 0);
  assert.equal(state.destroyed, 1);
  assert.deepEqual({ ...await NewsService.fetchCategory('blog', 1) },
    { items: [], ok: true, hasMore: false, message: '', sourceUrl: '' });
  assert.equal(state.requests.length, 1);
});

test('changed blog list markup falls back to HOA RSS and still releases both requests', async () => {
  const { NewsService, state } = loadService({
    blogListResponse: { responseCode: 200, result: '<html>Changed markup</html>' },
    blogFeedResponse: { responseCode: 200, result: '<rss><channel/></rss>' },
    events: feed([...item('Blog', 'https://hoa.moe/blog/example')])
  });
  const result = await NewsService.fetchCategory('blog', 0);
  assert.equal(result.ok, true);
  assert.equal(result.items[0].url, 'https://hoa.moe/blog/example');
  assert.deepEqual(state.requests.map(request => request.url),
    ['https://hoa.moe/blog', 'https://hoa.moe/blog/rss.xml']);
  assert.equal(state.parsed.length, 1);
  assert.equal(state.destroyed, 2);
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
    department: '教务处', date: '2026-10-05', summary: '', tags: []
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
    assert.equal(state.destroyed, 2);
  }
});

test('unknown categories and invalid pages do not issue HTTP requests', async () => {
  const { NewsService, state } = loadService();
  for (const [id, page] of [['11', 0], ['blog', -1], ['10', 0.5], ['10', NaN]]) {
    assert.equal((await NewsService.fetchCategory(id, page)).ok, false);
  }
  assert.equal(state.requests.length, 0);
});

// WebPlus markup captured from the public Weihai list; VSB cases model its li/table templates.
const weihaiHtml = `<ul>
  <li><a href='/1024/list.htm'>通知公告</a></li>
  <li><span class="news-time2">2026-10-10</span><a href='/2026/1010/c1024a221174/page.htm'
    target='_blank' title='【心理健康教育】“沐浴书香，润泽心灵”心理读书会第十期招募公告'>【心理健康教育】“沐浴书香，润泽心灵”心理读书会第十期招募公...</a></li>
  <li><span class="news-time2">2026-10-08</span><a href='/2026/1008/c1024a221069/page.htm'
    target='_blank' title='关于开展2026年哈尔滨工业大学（威海）支部大舞台活动的通知'>关于开展2026年哈尔滨工业大学（威海）支部大舞台活动的通知</a></li>
  </ul><a class="next" href="/1024/list2.htm"><span>下一页&gt;&gt;</span></a>
  <em class="curr_page">1</em>/<em class="all_pages">410</em>`;
const shenzhenHtml = `<ul>
  <li><a href="list.jsp?wbtreeid=1053">通知公告</a></li>
  <li><span>2026-10-11</span><a target="_blank" title="课程 &amp; 考试完整通知"
    href="info/1053/12345.htm"><b>课程通知…</b></a></li>
  <li><a href='../info/1053/12346.htm'>2026年10月20日活动通知</a><span>2026/10/9</span></li>
  <li><a href='/info/1053/12345.htm'>重复</a></li>
  <li><a href='javascript:alert(1)'>无效</a></li>
  <li><a href='https://info.hitsz.edu.cn.invalid/info/1053/123.htm'>其他域名</a></li>
  </ul><a href='list.jsp?totalpage=308&amp;PAGENUM=2&amp;wbtreeid=1053'>下页</a>`;

test('Shenzhen notifications start at page one, preserve full titles and dates, and use dynamic pagination', async () => {
  const { NewsService, state } = loadService({ response: { responseCode: 200, result: shenzhenHtml } });
  const result = await NewsService.fetchCategory('10', 0, EasCampus.SHENZHEN);
  assert.equal(result.ok, true);
  assert.equal(result.hasMore, true);
  assert.deepEqual(result.items.map(value => ({ ...value })), [
    { url: 'http://info.hitsz.edu.cn/info/1053/12345.htm', title: '课程 & 考试完整通知', date: '2026-10-11', department: '',
      summary: '', tags: [] },
    { url: 'http://info.hitsz.edu.cn/info/1053/12346.htm', title: '2026年10月20日活动通知', date: '2026-10-09', department: '',
      summary: '', tags: [] }
  ]);
  await NewsService.fetchCategory('10', 2, EasCampus.SHENZHEN);
  const last = await NewsService.fetchCategory('10', 307, EasCampus.SHENZHEN);
  assert.equal(last.hasMore, false);
  assert.deepEqual(state.requests.map(value => value.url), [
    'http://info.hitsz.edu.cn/list.jsp?PAGENUM=1&urltype=tree.TreeTempUrl&wbtreeid=1053',
    'http://info.hitsz.edu.cn/list.jsp?PAGENUM=3&urltype=tree.TreeTempUrl&wbtreeid=1053',
    'http://info.hitsz.edu.cn/list.jsp?PAGENUM=308&urltype=tree.TreeTempUrl&wbtreeid=1053'
  ]);
  assert.equal(result.sourceUrl, state.requests[0].url);
  assert.equal(state.destroyed, 3);
});

test('VSB table rows and content.jsp links decode ampersands without accepting navigation links', () => {
  const { NewsService } = loadService();
  const parsed = NewsService.parseList(`<table>
    <tr><td><a href='content.jsp?urltype=news.NewsContentUrl&amp;wbtreeid=1053&amp;wbnewsid=567'>通知 &quot;A&quot;</a></td><td>2026年9月2日</td></tr>
    <tr><td><a href='//info.hitsz.edu.cn/info/1053/568.htm' title='完整标题'>...</a></td><td>2026.09.01</td></tr>
    </table>`, EasCampus.SHENZHEN);
  assert.equal(parsed.length, 2);
  assert.equal(parsed[0].url, 'http://info.hitsz.edu.cn/content.jsp?urltype=news.NewsContentUrl&wbtreeid=1053&wbnewsid=567');
  assert.equal(parsed[0].title, '通知 "A"');
  assert.equal(parsed[0].date, '2026-09-02');
  assert.equal(parsed[1].url, 'http://info.hitsz.edu.cn/info/1053/568.htm');
});

test('Weihai uses WebPlus pages, full title attributes and real dates, and stops on the last page', async () => {
  const { NewsService, state } = loadService({ response: { responseCode: 200, result: weihaiHtml } });
  const result = await NewsService.fetchCategory('10', 0, EasCampus.WEIHAI);
  assert.equal(result.ok, true);
  assert.equal(result.hasMore, true);
  assert.equal(result.items.length, 2);
  assert.equal(result.items[0].title, '【心理健康教育】“沐浴书香，润泽心灵”心理读书会第十期招募公告');
  assert.equal(result.items[0].date, '2026-10-10');
  assert.equal(result.items[0].url, 'http://today.hitwh.edu.cn/2026/1010/c1024a221174/page.htm');
  await NewsService.fetchCategory('10', 1, EasCampus.WEIHAI);
  assert.equal((await NewsService.fetchCategory('10', 409, EasCampus.WEIHAI)).hasMore, false);
  assert.deepEqual(state.requests.map(value => value.url), [
    'http://today.hitwh.edu.cn/1024/list.htm', 'http://today.hitwh.edu.cn/1024/list2.htm',
    'http://today.hitwh.edu.cn/1024/list410.htm'
  ]);
  assert.equal(result.sourceUrl, state.requests[0].url);
  assert.deepEqual(state.cookieReads, []);
});

test('campus lists without total counts follow enabled next links and stop at disabled links', async () => {
  for (const campus of [EasCampus.SHENZHEN, EasCampus.WEIHAI]) {
    const row = campus === EasCampus.SHENZHEN ?
      '<li><a href="info/1053/123.htm">通知</a></li>' :
      '<li><a href="/2026/1010/c1024a123/page.htm">通知</a></li>';
    const href = campus === EasCampus.SHENZHEN ? 'list.jsp?PAGENUM=2&wbtreeid=1053' : '/1024/list2.htm';
    for (const [next, more] of [[href, true], ['javascript:void(0);', false], ['', false]]) {
      const { NewsService } = loadService({ response: { responseCode: 200, result: row + `<a href='${next}'>下一页</a>` } });
      assert.equal((await NewsService.fetchCategory('10', 0, campus)).hasMore, more);
    }
  }
});

test('authentication pages and changed markup are actionable failures instead of empty successful lists', async () => {
  for (const campus of [EasCampus.SHENZHEN, EasCampus.WEIHAI]) {
    for (const response of [
      { responseCode: 200, result: '<title>统一身份认证平台</title><form action="/authserver/login"></form>' },
      { responseCode: 403, result: '' },
      { responseCode: 200, result: '<html><body>Service unavailable</body></html>' }
    ]) {
      const { NewsService, state } = loadService({ response });
      const result = await NewsService.fetchCategory('10', 0, campus);
      assert.equal(result.ok, false);
      assert.equal(result.hasMore, false);
      assert.ok(result.sourceUrl.startsWith('http://'));
      assert.notEqual(result.message, '暂无可显示的资讯');
      assert.equal(state.destroyed, 1);
    }
    const { NewsService } = loadService({ response: { responseCode: 200, result: '<div>暂无通知</div>' } });
    const empty = await NewsService.fetchCategory('10', 0, campus);
    assert.equal(empty.ok, true);
    assert.equal(empty.hasMore, false);
  }
});

test('only Shenzhen reads its own site cookies; blog and Benbu requests stay independent of campus', async () => {
  const { NewsService, state } = loadService({ cookie: 'site_session=test',
    response: { responseCode: 200, result: shenzhenHtml },
    blogListResponse: { responseCode: 200, result: blogListHtml } });
  await NewsService.fetchCategory('10', 0, EasCampus.SHENZHEN);
  assert.deepEqual(state.cookieReads, [state.requests[0].url]);
  assert.equal(state.requests[0].config.header.Cookie, 'site_session=test');
  for (const campus of Object.values(EasCampus)) await NewsService.fetchCategory('blog', 0, campus);
  await NewsService.fetchCategory('10', 0, EasCampus.BENBU);
  assert.equal(state.cookieReads.length, 1);
  assert.ok(state.requests.slice(1).every(value => value.config.header.Cookie === undefined));
  assert.deepEqual(state.requests.slice(1, 4).map(value => value.url), Array(3).fill('https://hoa.moe/blog'));
  const unavailable = loadService({ cookieError: true, response: { responseCode: 200, result: shenzhenHtml } });
  assert.equal((await unavailable.NewsService.fetchCategory('10', 0, EasCampus.SHENZHEN)).ok, true);
});
