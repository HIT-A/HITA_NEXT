import { EasApiClient, EasApiResponse, EasHttpMethod, EasUserAgentFallback } from './EasApiClient';
import { EasSession } from './EasSession';
import { EasCampusUrls } from './webLogin/EasWebLoginConfig';
import { EasCourseItem } from './model/EasModels';
import { BenbuExperimentParser } from './data/BenbuExperimentParser';
import { hilog } from '@kit.PerformanceAnalysisKit';

/** Auxiliary sessions belong to their own hosts, never overwrite the EAS JSESSIONID. */
export class BenbuExperimentService {
  static readonly EXPERIMENT_BASE: string = 'http://sjjx-hit-edu-cn.ivpn.hit.edu.cn:1080';

  static mergeCookies(target: Map<string, string>, raw: string): void {
    const parts: string[] = raw.split(/[;\r\n]|,(?=\s*[^\s;,=]+=)/);
    for (const part of parts) {
      const equal: number = part.indexOf('=');
      if (equal < 1) continue;
      const key: string = part.substring(0, equal).trim();
      if (/^(path|domain|expires|max-age|samesite|secure|httponly)$/i.test(key)) continue;
      target.set(key, part.substring(equal + 1).trim());
    }
  }

  private static headers(cookies: Map<string, string>): Map<string, string> {
    const headers: Map<string, string> = new Map<string, string>();
    headers.set('Cookie', EasSession.buildCookieHeader(cookies));
    headers.set('User-Agent', EasUserAgentFallback.value);
    headers.set('Accept', 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
    headers.set('Accept-Language', 'zh-CN,zh-Hans;q=0.9');
    headers.set('Upgrade-Insecure-Requests', '1');
    return headers;
  }

  static async getExperiments(session: EasSession): Promise<EasCourseItem[]> {
    try {
      const cookies: Map<string, string> = new Map<string, string>(session.webCookies);
      const login: EasApiResponse = await EasApiClient.doHttp(EasCampusUrls.JWTS_BASE + '/loginsysj/loginSygl',
        EasHttpMethod.GET, BenbuExperimentService.headers(cookies), '', 20000, false);
      BenbuExperimentService.mergeCookies(cookies, login.cookies || '');
      const response: EasApiResponse = await EasApiClient.doHttp(
        BenbuExperimentService.EXPERIMENT_BASE + '/xskb/queryXszkb', EasHttpMethod.GET,
        BenbuExperimentService.headers(cookies), '', 20000, false);
      // Android queries this endpoint without xnxq; it serves the experimental system's schedule.
      if (response.statusCode !== 200 || /页面过期|请重新登录/.test(response.body)) return [];
      return BenbuExperimentParser.parseHtml(response.body);
    } catch (_) {
      hilog.warn(0x0000, 'HitaEasImport', 'experiment request failed');
      return [];
    }
  }

  static async getElectronicExperiments(session: EasSession): Promise<EasCourseItem[]> {
    if (!session.electronicExpToken.trim()) return [];
    try {
      const base: string = EasCampusUrls.EELABINFO_URL;
      const headers: Map<string, string> = BenbuExperimentService.headers(session.webCookies);
      headers.set('Accept', '*/*');
      headers.set('Content-Type', 'application/x-www-form-urlencoded');
      headers.set('Origin', base);
      headers.set('Referer', base + '/stu_ckkb.html');
      headers.set('X-Requested-With', 'XMLHttpRequest');
      headers.set('VcTchType', 'stu');
      headers.set('VcTchToken', session.electronicExpToken);
      const response: EasApiResponse = await EasApiClient.doHttp(base + '/api/stu/viewCKKB?sf_request_type=ajax',
        EasHttpMethod.POST, headers, '', 5000, false);
      return response.statusCode === 200 ? BenbuExperimentParser.parseElectronic(response.body) : [];
    } catch (_) {
      hilog.warn(0x0000, 'HitaEasImport', 'electronic experiment request failed');
      return [];
    }
  }
}
