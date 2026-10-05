/**
 * HOA 博客订阅与今日哈工大通知列表。
 */
import { util, xml } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';

const BASE_URL: string = 'https://today.hit.edu.cn';
const BLOG_FEED_URL: string = 'https://hoa.moe/blog/rss.xml';
const DESKTOP_UA: string =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36';

export class NewsCategory {
  id: string;
  name: string;

  constructor(id: string, name: string) {
    this.id = id;
    this.name = name;
  }
}

export class NewsItem {
  url: string = '';
  title: string = '';
  department: string = '';
  date: string = '';
}

export class NewsPage {
  items: NewsItem[] = [];
  ok: boolean = false;
  hasMore: boolean = false;
  message: string = '';
}

export class NewsService {
  static readonly CATEGORIES: NewsCategory[] = [
    new NewsCategory('blog', '博客'),
    new NewsCategory('10', '通知')
  ];

  static async fetchCategory(categoryId: string, page: number): Promise<NewsPage> {
    const result: NewsPage = new NewsPage();
    const blog: boolean = categoryId === 'blog';
    if ((!blog && categoryId !== '10') || page < 0 || !Number.isInteger(page)) {
      result.message = '暂时无法获取资讯，请稍后重试';
      return result;
    }
    // The blog feed contains the complete list; it has no next-page endpoint.
    if (blog && page > 0) {
      result.ok = true;
      return result;
    }
    const url: string = blog ? BLOG_FEED_URL :
      BASE_URL + '/category/10' + (page > 0 ? '?page=' + page.toString() : '');
    const header: Record<string, string> = {
      'User-Agent': DESKTOP_UA,
      'Accept': blog ? 'application/rss+xml,application/xml,text/xml' : 'text/html,application/xhtml+xml'
    };
    const request: http.HttpRequest = http.createHttp();
    try {
      const resp: http.HttpResponse = await request.request(url, {
        method: http.RequestMethod.GET,
        header: header,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 20000,
        usingCache: false
      });
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        result.message = '暂时无法获取资讯，请稍后重试';
        return result;
      }
      const body: string = resp.result === undefined || resp.result === null ? '' : String(resp.result);
      try {
        result.items = blog ? NewsService.parseBlogFeed(body) : NewsService.parseList(body);
      } catch (e) {
        result.message = '暂时无法解析资讯，请稍后重试';
        return result;
      }
      result.ok = true;
      result.hasMore = !blog && result.items.length > 0;
      if (result.items.length === 0) {
        result.message = '暂无可显示的资讯';
      }
    } catch (e) {
      result.message = '网络异常，请检查网络后重试';
    } finally {
      request.destroy();
    }
    return result;
  }

  static parseBlogFeed(feed: string): NewsItem[] {
    const data: Uint8Array = new util.TextEncoder().encodeInto(feed);
    const parser: xml.XmlPullParser = new xml.XmlPullParser(data.buffer as ArrayBuffer, 'UTF-8');
    const items: NewsItem[] = [];
    const seen: Set<string> = new Set<string>();
    const path: string[] = [];
    let channelFound: boolean = false;
    let current: NewsItem = new NewsItem();
    let fieldText: string = '';
    parser.parseXml({
      supportDoctype: false,
      ignoreNameSpace: true,
      tokenValueCallbackFunction: (event: xml.EventType, info: xml.ParseInfo): boolean => {
        if (event === xml.EventType.DOCDECL) {
          throw new Error('Unsupported feed document type');
        }
        if (event === xml.EventType.START_TAG) {
          path.push(info.getName());
          if (path.length === 2 && path[0] === 'rss' && path[1] === 'channel') {
            channelFound = true;
          }
          if (path.length === 3 && path[0] === 'rss' && path[1] === 'channel' && path[2] === 'item') {
            current = new NewsItem();
          }
          if (path.length === 4) {
            fieldText = '';
          }
        } else if (event === xml.EventType.TEXT || event === xml.EventType.CDSECT ||
          event === xml.EventType.ENTITY_REFERENCE || event === xml.EventType.WHITESPACE) {
          if (path.length === 4 && path[0] === 'rss' && path[1] === 'channel' && path[2] === 'item' &&
            ['title', 'link', 'pubDate', 'author', 'creator', 'dc:creator'].includes(path[3])) {
            fieldText += info.getText();
          }
        } else if (event === xml.EventType.END_TAG) {
          if (path[0] === 'rss' && path[1] === 'channel' && path[2] === 'item') {
            if (path.length === 4) {
              const value: string = fieldText.replace(/\s+/g, ' ').trim();
              switch (path[3]) {
                case 'title':
                  current.title = value;
                  break;
                case 'link':
                  current.url = value.startsWith('/blog/') ? 'https://hoa.moe' + value : value;
                  break;
                case 'pubDate':
                  const timestamp: number = Date.parse(value);
                  current.date = Number.isFinite(timestamp) ? new Date(timestamp).toISOString().substring(0, 10) : '';
                  break;
                case 'author':
                case 'creator':
                case 'dc:creator':
                  if (value.length > 0) {
                    current.department += (current.department.length > 0 ? '、' : '') + value;
                  }
                  break;
              }
            } else if (path.length === 3 && current.title.length > 0 &&
              /^https:\/\/hoa\.moe\/blog\/[^\s<>]+$/.test(current.url) && !seen.has(current.url)) {
              seen.add(current.url);
              if (current.department.length === 0) {
                current.department = 'HOA';
              }
              items.push(current);
            }
          }
          path.pop();
        }
        return true;
      }
    });
    if (!channelFound || path.length > 0) {
      throw new Error('Invalid blog feed');
    }
    return items;
  }

  static parseList(html: string): NewsItem[] {
    const out: NewsItem[] = [];
    const seen: Set<string> = new Set<string>();
    const itemPattern: RegExp = /<li>\s*<div class="pull-right">([\s\S]*?)<\/li>/g;
    let match: RegExpExecArray | null = itemPattern.exec(html);
    while (match !== null) {
      const block: string = match[1];
      match = itemPattern.exec(html);
      const article: RegExpExecArray | null = /<a href="(\/article\/[^"]+)"[^>]*>([\s\S]*?)<\/a>/.exec(block);
      if (article === null || seen.has(article[1])) {
        continue;
      }
      const title: string = NewsService.cleanText(article[2]);
      if (title.length === 0) {
        continue;
      }
      seen.add(article[1]);
      const item: NewsItem = new NewsItem();
      item.url = BASE_URL + article[1];
      item.title = title;
      const department: RegExpExecArray | null = /<a href="\/department\/\d+"[^>]*>([^<]+)<\/a>/.exec(block);
      item.department = department === null ? '' : NewsService.cleanText(department[1]);
      const pathDate: RegExpExecArray | null = /\/article\/(\d{4})\/(\d{2})\/(\d{2})\//.exec(article[1]);
      const relative: RegExpExecArray | null = /<span class="date">([^<]+)<\/span>/.exec(block);
      item.date = pathDate !== null ? pathDate[1] + '-' + pathDate[2] + '-' + pathDate[3] :
        (relative === null ? '' : NewsService.cleanText(relative[1]));
      out.push(item);
    }
    return out;
  }

  private static cleanText(raw: string): string {
    return raw.replace(/<[^>]+>/g, '')
      .replace(/&nbsp;/g, ' ')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&#039;/g, '\'')
      .replace(/\s+/g, ' ')
      .trim();
  }
}
