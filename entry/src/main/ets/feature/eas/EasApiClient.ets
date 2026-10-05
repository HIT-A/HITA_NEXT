/**
 * EasApiClient.ets — 教务数据 HTTP 客户端：Cookie 注入与会话失效判定。
 *
 * 校区数据端点形态：
 *  - 深圳：JSON（ParsedShenzhenWebScores: code/msg/content.list[] …）
 *  - 威海：webvpn 编码前缀下的端点（kjscx/queryJxlListBySjid、cjcx/queryQmcj …），带 JSESSIONID
 *  - 本部：ivpn 内网域名 + CAS 会话（HIT / JSESSIONID）
 * 请求路径由 EasDataProvider 配置。
 */
import { http } from '@kit.NetworkKit';
import { EasCampusConfig, EasCampusUrls, EasUserAgent } from './webLogin/EasWebLoginConfig';
import { EasSession } from './EasSession';

export enum EasHttpMethod {
  GET = 'GET',
  POST = 'POST'
}

export class EasApiResponse {
  statusCode: number = 0;
  body: string = '';
}

export class EasApiClientOptions {
  method: EasHttpMethod = EasHttpMethod.GET;
  /** POST body（JSON 字符串或表单串）。 */
  body: string = '';
  /** 追加请求头。 */
  extraHeaders: Map<string, string> = new Map<string, string>();
  /** 超时 ms。 */
  timeoutMs: number = 20000;
  /** 是否跟随重定向（http 模块默认跟随，保留开关以便抓包期关闭）。 */
  followRedirects: boolean = true;
}

/**
 * 失效重登回调由外部注入：返回 true 表示已重登成功（调用方自行重试），
 * false 表示放弃。对应 sessionGeneration +1 的重登协议。
 */
export type EasReloginHandler = (reason: string) => Promise<boolean>;

export class EasApiClient {
  private reloginHandler: EasReloginHandler | undefined = undefined;

  setReloginHandler(handler: EasReloginHandler): void {
    this.reloginHandler = handler;
  }

  /**
   * 发起数据请求：合并校区 Cookie 到请求头，遇到会话失效（HTTP 401 / 302 到登录页 / JSESSIONID 缺失）
   * 触发重登回调。
   */
  async request(session: EasSession, cfg: EasCampusConfig, path: string,
    options: EasApiClientOptions): Promise<EasApiResponse> {
    const base: string = this.dataBaseUrl(session, cfg);
    const url: string = EasApiClient.joinUrl(base, path);
    const attempts: number = 2;
    for (let i = 0; i < attempts; i++) {
      const header: Map<string, string> = new Map<string, string>();
      options.extraHeaders.forEach((value: string, key: string) => {
        header.set(key, value);
      });
      const cookieHeader: string = EasSession.buildCookieHeader(session.webCookies);
      if (cookieHeader.length > 0) {
        header.set('Cookie', cookieHeader);
      }
      if (!header.has('User-Agent')) {
        header.set('User-Agent', this.userAgentFor(session, cfg));
      }
      // Keep the endpoint-specific Accept header.  Weihai returns HTML pages
      // for terms and the timetable; overriding it with JSON makes WebVPN
      // occasionally return the login shell instead of the business page.
      if (!header.has('Accept')) {
        header.set('Accept', 'application/json, text/plain, */*');
      }
      if (options.body.length > 0) {
        if (!header.has('Content-Type')) {
          header.set('Content-Type', 'application/x-www-form-urlencoded; charset=UTF-8');
        }
      }
      const resp: EasApiResponse = await EasApiClient.doHttp(url, options.method, header, options.body,
        options.timeoutMs);
      if (resp.statusCode === 401 || this.isSessionInvalidResponse(resp, cfg)) {
        if (this.reloginHandler !== undefined && i + 1 < attempts) {
          const ok: boolean = await this.reloginHandler('session invalid on ' + path);
          if (ok) {
            continue; // 重登成功后重试一次
          }
        }
        return resp;
      }
      return resp;
    }
    return new EasApiResponse(); // 理论不可达
  }

  /** 是否命中登录页重定向（302 → 门户登录特征，抓包期校准）。 */
  private isSessionInvalidResponse(resp: EasApiResponse, cfg: EasCampusConfig): boolean {
    if (cfg.campus.toString() === 'SHENZHEN') {
      const t: string = resp.body;
      return resp.statusCode === 302 || (t.indexOf('authentication/require') >= 0) ||
        (t.indexOf('/cas/login') >= 0);
    }
    if (resp.statusCode === 302 || resp.statusCode === 303) {
      return true;
    }
    const body: string = resp.body.toLowerCase();
    // Do not treat ordinary EAS pages as expired just because their menu
    // contains a link back to loginCAS.  Match the actual login/re-auth form.
    const hasLoginForm: boolean = (body.indexOf('<form') >= 0 &&
      (body.indexOf('logincas') >= 0 || body.indexOf('name="password"') >= 0 ||
        body.indexOf('name="mm"') >= 0 || body.indexOf('action="/login') >= 0));
    const hasReAuthPage: boolean = body.indexOf('reauth') >= 0 &&
      body.indexOf('reauth_success') < 0;
    const explicitExpired: boolean = body.indexOf('会话已失效') >= 0 ||
      body.indexOf('会话超时') >= 0 || body.indexOf('未登录') >= 0;
    return hasLoginForm || hasReAuthPage || explicitExpired;
  }

  /** 数据基址：深圳用 webBaseUrl；威海用 webvpn 前缀；本部按培养层次选 jwts/yjsgl 域。 */
  private dataBaseUrl(session: EasSession, cfg: EasCampusConfig): string {
    if (session.campus.toString() === 'SHENZHEN' && session.webBaseUrl.length > 0) {
      return session.webBaseUrl;
    }
    if (session.campus.toString() === 'WEIHAI') {
      return EasCampusUrls.WEIHAI_EAS_PREFIX;
    }
    if (session.getStudentType() === '2') {
      return EasCampusUrls.GRADUATE_BASE;
    }
    return EasCampusUrls.JWTS_BASE;
  }

  private userAgentFor(session: EasSession, cfg: EasCampusConfig): string {
    // Android EASWebSource 对新版深圳 Web 接口固定使用桌面 UA；旧校区
    // 沿用移动 UA 以兼容旧教务页面。
    if (session.campus.toString() === 'SHENZHEN') {
      return EasUserAgent.SHENZHEN_DESKTOP;
    }
    return EasUserAgentFallback.value;
  }

  static joinUrl(base: string, path: string): string {
    if (path.length === 0) {
      return base;
    }
    if (path.indexOf('http://') === 0 || path.indexOf('https://') === 0) {
      return path;
    }
    return base.replace(/\/+$/, '') + '/' + path.replace(/^\/+/, '');
  }

  static async doHttp(url: string, method: EasHttpMethod, header: Map<string, string>, body: string,
    timeoutMs: number): Promise<EasApiResponse> {
    const httpRequest: http.HttpRequest = http.createHttp();
    const opts: http.HttpRequestOptions = {
      method: method === EasHttpMethod.POST ? http.RequestMethod.POST : http.RequestMethod.GET,
      header: EasApiClient.headerToObject(header),
      connectTimeout: timeoutMs,
      readTimeout: timeoutMs,
      expectDataType: http.HttpDataType.STRING
    };
    if (body.length > 0) {
      opts.extraData = body;
    }
    try {
      const resp: http.HttpResponse = await httpRequest.request(url, opts);
      const out: EasApiResponse = new EasApiResponse();
      out.statusCode = resp.responseCode;
      out.body = resp.result === undefined ? '' : String(resp.result);
      return out;
    } catch (e) {
      const out: EasApiResponse = new EasApiResponse();
      out.statusCode = 0;
      out.body = '';
      return out;
    } finally {
      httpRequest.destroy();
    }
  }

  private static headerToObject(header: Map<string, string>): Object {
    const o: Record<string, string> = {};
    header.forEach((value: string, key: string) => {
      o[key] = value;
    });
    return o;
  }
}

/** UA 回退常量（避免与 config 循环依赖的临时归属，后续并入 EasWebLoginConfig）。 */
export class EasUserAgentFallback {
  static readonly value: string =
    // Android's legacy Weihai/Benbu source deliberately uses a desktop UA;
    // the old EAS renders a different mobile shell that the HTML parser cannot
    // use for terms and timetable pages.
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15';
}
