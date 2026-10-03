/**
 * NewsService.ets — 今日哈工大（today.hit.edu.cn）资讯列表抓取与解析。
 *
 * 列表页每条为 <li>：右侧部门链接 + 相对日期，左侧 /article/yyyy/MM/dd/id 标题链接；
 * 每页 20 条，?page= 从 0 开始。
 */
import { http } from '@kit.NetworkKit';

const BASE_URL: string = 'https://today.hit.edu.cn';
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

export class NewsPortal {
  title: string;
  subtitle: string;
  url: string;

  constructor(title: string, subtitle: string, url: string) {
    this.title = title;
    this.subtitle = subtitle;
    this.url = url;
  }
}

export class NewsPage {
  items: NewsItem[] = [];
  ok: boolean = false;
  message: string = '';
}

export class NewsService {
  static readonly CATEGORIES: NewsCategory[] = [
    new NewsCategory('10', '公告公示'),
    new NewsCategory('11', '新闻快讯')
  ];

  static readonly PORTALS: NewsPortal[] = [
    new NewsPortal('今日哈工大', 'today.hit.edu.cn · 校园新闻与公告', BASE_URL + '/'),
    new NewsPortal('哈工大官网', 'www.hit.edu.cn', 'https://www.hit.edu.cn/'),
    new NewsPortal('HOA 课程攻略', 'hoa.moe · 课程资料与经验分享', 'https://hoa.moe/'),
    new NewsPortal('哈工大威海', 'www.hitwh.edu.cn', 'https://www.hitwh.edu.cn/'),
    new NewsPortal('哈工大深圳', 'www.hitsz.edu.cn', 'https://www.hitsz.edu.cn/')
  ];

  static async fetchCategory(categoryId: string, page: number): Promise<NewsPage> {
    const result: NewsPage = new NewsPage();
    const url: string = BASE_URL + '/category/' + categoryId + (page > 0 ? '?page=' + page.toString() : '');
    const header: Record<string, string> = {
      'User-Agent': DESKTOP_UA,
      'Accept': 'text/html,application/xhtml+xml'
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
        result.message = '今日哈工大返回 HTTP ' + resp.responseCode.toString();
        return result;
      }
      const body: string = resp.result === undefined || resp.result === null ? '' : String(resp.result);
      result.items = NewsService.parseList(body);
      result.ok = true;
      if (result.items.length === 0) {
        result.message = '没有解析到资讯，可能是页面改版';
      }
    } catch (e) {
      result.message = '网络异常，请检查网络后重试';
    } finally {
      request.destroy();
    }
    return result;
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
