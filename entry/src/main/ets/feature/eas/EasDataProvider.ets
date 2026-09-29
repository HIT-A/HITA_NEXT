/**
 * EasDataProvider.ets - legacy EAS data access used by the timetable importer.
 *
 * Benbu/Weihai undergraduate endpoints mirror Android HITA:
 * GET /cjcx/queryQmcj, GET /kbcx/queryGrkb, POST /kbcx/queryGrkb.
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { EasCampus, EasSession } from './EasSession';
import { EasApiClient, EasApiClientOptions, EasApiResponse, EasHttpMethod } from './EasApiClient';
import { EasCourseItem, EasCourseScoreItem, EasExamItem, EasTermItem } from './model/EasModels';
import { EasTimePeriodInDay } from '../../common/model/timetable/TimetableModels';
import { easWebLoginConfigFor, EasCampusUrls } from './webLogin/EasWebLoginConfig';
import { EasLegacyTimetableParser } from './data/EasLegacyTimetableParser';
import { ParsedShenzhenWebScores, parseShenzhenWebScores, testShenzhenScoreParser } from './data/ShenzhenWebScores';
import {
  parseShenzhenWebSelectedSubjects,
  parseShenzhenWebTerms,
  parseShenzhenWebTimetable,
  ShenzhenSubjectMeta,
  parseShenzhenWebScheduleStructure,
  testShenzhenTimetableParser
} from './data/ShenzhenWebTimetableParser';

const DOMAIN: number = 0x0000;
const TAG: string = 'HitaEasImport';

export class EasShenzhenEndpoints {
  /** 新版深圳 Web 教务接口（Android EASWebSource.kt 同源）。 */
  static termsPath: string = '/component/queryXnxq';
  static timetablePath: string = '/xszykb/queryxszykbzong';
  static selectedSubjectsPath: string = '/Xsxk/queryYxkc?sf_request_type=ajax';
  static scheduleStructurePath: string = '/component/queryKbjg';
  static scoresPath: string = '/cjgl/grcjcx/grcjcx';
}

export class EasWeihaiEndpoints {
  static termsPath: string = '/kbcx/queryGrkb';
  static scoreTermsPath: string = '/cjcx/queryQmcj';
  static timetableTermsPath: string = '/kbcx/queryGrkb';
  static timetablePath: string = '/kbcx/queryGrkb';
  static scoresPath: string = '';
}

export class EasBenbuEndpoints {
  static termsPath: string = '/kbcx/queryGrkb';
  static scoreTermsPath: string = '/cjcx/queryQmcj';
  static timetableTermsPath: string = '/kbcx/queryGrkb';
  static timetablePath: string = '/kbcx/queryGrkb';
  static scoresPath: string = '';
}

export class EasScoresResult {
  code: number = 0;
  msg: string = '';
  items: EasCourseScoreItem[] = [];
  ok: boolean = false;
}

export class EasDataProvider {
  private api: EasApiClient;

  constructor(api: EasApiClient) {
    this.api = api;
  }

  async getAllTerms(session: EasSession): Promise<EasTermItem[]> {
    if (session.campus === EasCampus.SHENZHEN) {
      return await this.getShenzhenTerms(session);
    }
    if (session.campus === EasCampus.BENBU && session.getStudentType() === '2') {
      throw new Error('本部研究生课表接口暂未接入');
    }

    const scorePath: string = EasDataProvider.scoreTermsPathOf(session);
    const timetablePath: string = EasDataProvider.timetableTermsPathOf(session);
    const scoreResp: EasApiResponse = await this.getHtml(session, scorePath);
    const timetableResp: EasApiResponse = await this.getHtml(session, timetablePath);

    hilog.info(DOMAIN, TAG, 'terms score path=%{public}s status=%{public}d len=%{public}d',
      scorePath, scoreResp.statusCode, scoreResp.body.length);
    hilog.info(DOMAIN, TAG, 'terms timetable path=%{public}s status=%{public}d len=%{public}d',
      timetablePath, timetableResp.statusCode, timetableResp.body.length);

    const scoreAuth: boolean = EasDataProvider.isLoginResponse(scoreResp.body) ||
      scoreResp.statusCode === 401 || scoreResp.statusCode === 403;
    const timetableAuth: boolean = EasDataProvider.isLoginResponse(timetableResp.body) ||
      timetableResp.statusCode === 401 || timetableResp.statusCode === 403;
    if (scoreAuth && timetableAuth) {
      throw new Error('教务会话已失效，请重新登录');
    }

    const scoreTerms: EasTermItem[] = EasDataProvider.isHttpOk(scoreResp) ?
      EasLegacyTimetableParser.parseTermsBySelect(scoreResp.body, 'pageXnxq') : [];
    const timetableTerms: EasTermItem[] = EasDataProvider.isHttpOk(timetableResp) ?
      EasLegacyTimetableParser.parseTermsBySelect(timetableResp.body, 'xnxq') : [];
    const terms: EasTermItem[] = EasDataProvider.mergeTerms(scoreTerms, timetableTerms);
    hilog.info(DOMAIN, TAG, 'terms parsed score=%{public}d timetable=%{public}d merged=%{public}d',
      scoreTerms.length, timetableTerms.length, terms.length);
    if (terms.length === 0) {
      throw new Error('未获取到学期列表');
    }
    return terms;
  }

  async getTimetableOfTerm(session: EasSession, term: EasTermItem): Promise<EasCourseItem[]> {
    if (session.campus === EasCampus.SHENZHEN) {
      return await this.getShenzhenTimetable(session, term);
    }
    if (session.campus === EasCampus.BENBU && session.getStudentType() === '2') {
      throw new Error('本部研究生课表接口暂未接入');
    }

    const path: string = EasDataProvider.timetablePathOf(session);
    const opts: EasApiClientOptions = new EasApiClientOptions();
    opts.method = EasHttpMethod.POST;
    opts.timeoutMs = 25000;
    opts.body = 'fhlj=' + encodeURIComponent('kbcx/queryGrkb') + '&xnxq=' + encodeURIComponent(term.getCode());
    opts.extraHeaders.set('Content-Type', 'application/x-www-form-urlencoded; charset=UTF-8');
    opts.extraHeaders.set('Accept', 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
    opts.extraHeaders.set('Accept-Language', 'zh-CN,zh-Hans;q=0.9');
    if (session.campus === EasCampus.WEIHAI) {
      opts.extraHeaders.set('Origin', EasCampusUrls.WEIHAI_BASE);
      opts.extraHeaders.set('Referer', EasApiClient.joinUrl(EasCampusUrls.WEIHAI_EAS_PREFIX, path));
    }
    const cfg = easWebLoginConfigFor(session.campus, session.getStudentType());
    const resp: EasApiResponse = await this.api.request(session, cfg, path, opts);

    hilog.info(DOMAIN, TAG, 'timetable term=%{public}s path=%{public}s status=%{public}d len=%{public}d',
      term.getCode(), path, resp.statusCode, resp.body.length);
    if (resp.statusCode === 0) {
      throw new Error('课表请求网络失败');
    }
    if (!EasDataProvider.isHttpOk(resp)) {
      throw new Error('课表请求失败 HTTP ' + resp.statusCode.toString());
    }
    if (EasDataProvider.isLoginResponse(resp.body)) {
      throw new Error('教务会话已失效，请重新登录');
    }
    if (resp.body.indexOf('addlist_01') < 0) {
      if (resp.body.indexOf('name="xnxq"') >= 0 || resp.body.indexOf("name='xnxq'") >= 0) {
        throw new Error('课表页返回异常，未找到课表表格');
      }
      throw new Error('返回的不是课表页，请重新登录后再试');
    }

    const courses: EasCourseItem[] = EasLegacyTimetableParser.parseScheduleHtml(resp.body);
    hilog.info(DOMAIN, TAG, 'timetable parsed term=%{public}s courses=%{public}d',
      term.getCode(), courses.length);
    if (courses.length === 0) {
      throw new Error('课表解析为空，请检查该学期是否已有课表');
    }
    return courses;
  }

  private async getHtml(session: EasSession, path: string): Promise<EasApiResponse> {
    const opts: EasApiClientOptions = new EasApiClientOptions();
    opts.method = EasHttpMethod.GET;
    opts.timeoutMs = 20000;
    opts.extraHeaders.set('Accept', 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
    opts.extraHeaders.set('Accept-Language', 'zh-CN,zh-Hans;q=0.9');
    if (session.campus === EasCampus.WEIHAI) {
      opts.extraHeaders.set('Origin', EasCampusUrls.WEIHAI_BASE);
      opts.extraHeaders.set('Referer', EasApiClient.joinUrl(EasCampusUrls.WEIHAI_EAS_PREFIX, path));
    }
    const cfg = easWebLoginConfigFor(session.campus, session.getStudentType());
    return await this.api.request(session, cfg, path, opts);
  }

  /** 深圳新版 Web 端点：学期列表 + 课程选择学期校准。 */
  private async getShenzhenTerms(session: EasSession): Promise<EasTermItem[]> {
    if (!session.hasShenzhenWebSession()) {
      throw new Error('深圳教务会话已失效，请重新登录');
    }
    const cfg = easWebLoginConfigFor(session.campus, session.getStudentType());
    const paths: string[] = [EasShenzhenEndpoints.termsPath, '/component/queryxnxqdata'];
    let terms: EasTermItem[] = [];
    for (let i = 0; i < paths.length; i++) {
      const refererPath: string = paths[i] === EasShenzhenEndpoints.termsPath ? '/Xsxk/query/1' : '/authentication/main';
      const opts: EasApiClientOptions = EasDataProvider.shenzhenFormOptions(
        session, EasDataProvider.shenzhenTermBody(session), 20000, refererPath);
      const resp: EasApiResponse = await this.api.request(session, cfg, paths[i], opts);
      hilog.info(DOMAIN, TAG, 'shenzhen terms path=%{public}s status=%{public}d len=%{public}d',
        paths[i], resp.statusCode, resp.body.length);
      if (resp.statusCode === 401 || resp.statusCode === 403 || EasDataProvider.isLoginResponse(resp.body)) {
        throw new Error('深圳教务会话已失效，请重新登录');
      }
      if (EasDataProvider.isHttpOk(resp)) {
        terms = parseShenzhenWebTerms(resp.body);
      }
      if (terms.length > 0) {
        break;
      }
    }
    if (terms.length === 0) {
      throw new Error('未获取到深圳学期列表');
    }

    // Android 端还会调用 queryXkdqXnxq 校准“选课当前学期”；失败时不阻断课表导入。
    try {
      const selectOpts: EasApiClientOptions = EasDataProvider.shenzhenFormOptions(
        session, 'p_pylx=' + encodeURIComponent(session.getStudentType()), 10000, '/Xsxk/query/1');
      const selectResp: EasApiResponse = await this.api.request(session, cfg,
        '/Xsxk/queryXkdqXnxq', selectOpts);
      const selectedId: string = EasDataProvider.extractShenzhenSelectionTermId(selectResp.body);
      if (selectedId.length > 0) {
        for (let i = 0; i < terms.length; i++) {
          terms[i].isCurrent = terms[i].getCode() === selectedId ||
            (terms[i].yearCode + '-' + terms[i].termCode) === selectedId;
        }
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'shenzhen current term probe failed %{public}s', String(e));
    }
    terms.sort((a: EasTermItem, b: EasTermItem): number => {
      if (a.isCurrent !== b.isCurrent) {
        return a.isCurrent ? -1 : 1;
      }
      return (b.yearCode + b.termCode).localeCompare(a.yearCode + a.termCode);
    });
    return terms;
  }

  /** 深圳新版 Web 端点：读取已选课程元数据，再读取个人总课表。 */
  private async getShenzhenTimetable(session: EasSession, term: EasTermItem): Promise<EasCourseItem[]> {
    if (!session.hasShenzhenWebSession()) {
      throw new Error('深圳教务会话已失效，请重新登录');
    }
    const cfg = easWebLoginConfigFor(session.campus, session.getStudentType());
    let subjects: ShenzhenSubjectMeta[] = [];
    try {
      const subjectOpts: EasApiClientOptions = EasDataProvider.shenzhenFormOptions(
        session, EasDataProvider.shenzhenSelectionBody(session, term), 30000);
      const subjectResp: EasApiResponse = await this.api.request(session, cfg,
        EasShenzhenEndpoints.selectedSubjectsPath, subjectOpts);
      if (subjectResp.statusCode === 401 || subjectResp.statusCode === 403 ||
        EasDataProvider.isLoginResponse(subjectResp.body)) {
        throw new Error('深圳教务会话已失效，请重新登录');
      }
      if (EasDataProvider.isHttpOk(subjectResp)) {
        subjects = parseShenzhenWebSelectedSubjects(subjectResp.body);
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'shenzhen selected subject probe failed %{public}s', String(e));
    }

    const timetableOpts: EasApiClientOptions = EasDataProvider.shenzhenFormOptions(
      session, 'xn=' + encodeURIComponent(term.yearCode) + '&xq=' + encodeURIComponent(term.termCode),
      60000, '/xszykb/queryxszykb');
    timetableOpts.extraHeaders.set('Referer', EasApiClient.joinUrl(
      session.webBaseUrl, '/xszykb/queryxszykb'));
    const timetableResp: EasApiResponse = await this.api.request(session, cfg,
      EasShenzhenEndpoints.timetablePath, timetableOpts);
    hilog.info(DOMAIN, TAG, 'shenzhen timetable term=%{public}s status=%{public}d len=%{public}d',
      term.getCode(), timetableResp.statusCode, timetableResp.body.length);
    if (timetableResp.statusCode === 401 || timetableResp.statusCode === 403 ||
      EasDataProvider.isLoginResponse(timetableResp.body)) {
      throw new Error('深圳教务会话已失效，请重新登录');
    }
    if (!EasDataProvider.isHttpOk(timetableResp)) {
      throw new Error('深圳课表请求失败 HTTP ' + timetableResp.statusCode.toString());
    }
    const courses: EasCourseItem[] | undefined = parseShenzhenWebTimetable(timetableResp.body, subjects);
    if (courses === undefined || courses.length === 0) {
      throw new Error('深圳课表解析为空，请检查该学期是否已有课表');
    }
    return courses;
  }

  /** 供成绩/课表结构页面复用的深圳节次接口。 */
  async getShenzhenScheduleStructure(session: EasSession, term: EasTermItem): Promise<EasTimePeriodInDay[]> {
    const cfg = easWebLoginConfigFor(session.campus, session.getStudentType());
    const body: string = 'xn=' + encodeURIComponent(term.yearCode) + '&xq=' +
      encodeURIComponent(term.termCode) + '&pylx=' + encodeURIComponent(session.getStudentType());
    const resp: EasApiResponse = await this.api.request(session, cfg,
      EasShenzhenEndpoints.scheduleStructurePath,
      EasDataProvider.shenzhenFormOptions(session, body, 20000));
    const parsed = parseShenzhenWebScheduleStructure(resp.body);
    return parsed === undefined ? [] : parsed;
  }

  private static shenzhenFormOptions(session: EasSession, body: string, timeoutMs: number,
    refererPath: string = '/authentication/main'): EasApiClientOptions {
    const opts: EasApiClientOptions = new EasApiClientOptions();
    opts.method = EasHttpMethod.POST;
    opts.body = body;
    opts.timeoutMs = timeoutMs;
    opts.extraHeaders.set('Content-Type', 'application/x-www-form-urlencoded; charset=UTF-8');
    opts.extraHeaders.set('Accept', 'application/json, text/plain, */*');
    opts.extraHeaders.set('Accept-Language', 'zh-CN,zh;q=0.9');
    opts.extraHeaders.set('RoleCode', '01');
    opts.extraHeaders.set('X-Requested-With', 'XMLHttpRequest');
    if (session.webBaseUrl.length > 0) {
      opts.extraHeaders.set('Origin', session.webBaseUrl);
      opts.extraHeaders.set('Referer', EasApiClient.joinUrl(session.webBaseUrl, refererPath));
    }
    return opts;
  }

  private static shenzhenTermBody(session: EasSession): string {
    // Android jwFormPost(queryXnxq) sends no form fields; keep the body empty
    // so the portal can apply its own current-role defaults.
    return '';
  }

  private static shenzhenSelectionBody(session: EasSession, term: EasTermItem): string {
    const pylx: string = encodeURIComponent(session.getStudentType());
    const value = (key: string, raw: string): string => key + '=' + encodeURIComponent(raw);
    const fields: string[] = [
      value('cxsfmt', '0'), value('p_pylx', session.getStudentType()), value('mxpylx', session.getStudentType()),
      value('p_sfgldjr', '0'), value('p_sfredis', '0'), value('p_sfsyxkgwc', '0'), value('p_xktjz', ''),
      value('p_chaxunxh', ''), value('p_gjz', ''), value('p_skjs', ''), value('p_xn', term.yearCode),
      value('p_xq', term.termCode), value('p_xnxq', term.getCode()), value('p_xkfsdm', 'yixuan'),
      value('p_xiaoqu', ''), value('p_kkyx', ''), value('p_kclb', ''), value('p_xkxs', ''), value('p_dyc', ''),
      value('p_kkxnxq', ''), value('p_id', ''), value('p_sfhlctkc', '0'), value('p_sfhllrlkc', '0'),
      value('p_kxsj_xqj', ''), value('p_kxsj_ksjc', ''), value('p_kxsj_jsjc', ''), value('p_kcdm_js', ''),
      value('p_kcdm_cxrw', ''), value('p_kcdm_cxrw_zckc', ''), value('p_kc_gjz', ''), value('p_xzcxtjz_nj', ''),
      value('p_xzcxtjz_yx', ''), value('p_xzcxtjz_zy', ''), value('p_xzcxtjz_zyfx', ''), value('p_xzcxtjz_bj', ''),
      value('p_sfxsgwckb', '1'), value('p_skyy', ''), value('p_sfmxzj', ''), value('p_chaxunxkfsdm', ''),
      value('pageNum', '1'), value('pageSize', '200')
    ];
    return fields.join('&') + '&studentType=' + pylx;
  }

  private static extractShenzhenSelectionTermId(body: string): string {
    try {
      const root: Record<string, Object> = JSON.parse(body) as Record<string, Object>;
      const scan = (value: Object | undefined): string => {
        if (value === undefined || value === null || typeof value !== 'object') {
          return '';
        }
        const record: Record<string, Object> = value as Record<string, Object>;
        const year: string = EasDataProvider.objectText(record, ['p_xn', 'xn', 'XN', 'p_dqxn', 'dqxn']);
        const term: string = EasDataProvider.objectText(record, ['p_xq', 'xq', 'XQ', 'p_dqxq', 'dqxq']);
        if (year.length > 0 && term.length > 0) {
          return year + '-' + term;
        }
        const keys: string[] = Object.keys(record);
        for (let i = 0; i < keys.length; i++) {
          const found: string = scan(record[keys[i]]);
          if (found.length > 0) {
            return found;
          }
        }
        return '';
      };
      return scan(root);
    } catch (e) {
      return '';
    }
  }

  private static objectText(record: Record<string, Object>, keys: string[]): string {
    for (let i = 0; i < keys.length; i++) {
      const raw: Object | undefined = record[keys[i]];
      if (raw !== undefined && raw !== null) {
        const text: string = String(raw).trim();
        if (text.length > 0 && text.toLowerCase() !== 'null') {
          return text;
        }
      }
    }
    return '';
  }

  private static scoreTermsPathOf(session: EasSession): string {
    return session.campus === EasCampus.WEIHAI ? EasWeihaiEndpoints.scoreTermsPath :
      session.campus === EasCampus.BENBU ? EasBenbuEndpoints.scoreTermsPath : EasShenzhenEndpoints.termsPath;
  }

  private static timetableTermsPathOf(session: EasSession): string {
    return session.campus === EasCampus.WEIHAI ? EasWeihaiEndpoints.timetableTermsPath :
      session.campus === EasCampus.BENBU ? EasBenbuEndpoints.timetableTermsPath : EasShenzhenEndpoints.termsPath;
  }

  private static timetablePathOf(session: EasSession): string {
    return session.campus === EasCampus.WEIHAI ? EasWeihaiEndpoints.timetablePath : EasBenbuEndpoints.timetablePath;
  }

  private static mergeTerms(scoreTerms: EasTermItem[], timetableTerms: EasTermItem[]): EasTermItem[] {
    const merged: Map<string, EasTermItem> = new Map<string, EasTermItem>();
    for (let i: number = 0; i < timetableTerms.length; i++) {
      merged.set(timetableTerms[i].getCode(), timetableTerms[i]);
    }
    for (let i: number = 0; i < scoreTerms.length; i++) {
      const key: string = scoreTerms[i].getCode();
      const existing: EasTermItem | undefined = merged.get(key);
      if (existing === undefined) {
        merged.set(key, scoreTerms[i]);
      } else {
        if (scoreTerms[i].termName.length > 0) {
          existing.termName = scoreTerms[i].termName;
        }
        existing.isCurrent = existing.isCurrent || scoreTerms[i].isCurrent;
      }
    }
    const out: EasTermItem[] = [];
    merged.forEach((value: EasTermItem) => out.push(value));
    return out;
  }

  private static isHttpOk(resp: EasApiResponse): boolean {
    return resp.statusCode >= 200 && resp.statusCode < 300;
  }

  private static isLoginResponse(body: string): boolean {
    const text: string = body.toLowerCase();
    // A normal legacy EAS page can contain a loginCAS link in its menu.  Only
    // classify it as expired when the response looks like an actual login or
    // re-auth page, while preserving the JSON/CAS checks used by Shenzhen.
    const hasBusinessPage: boolean = text.indexOf('addlist_01') >= 0 ||
      text.indexOf('name="xnxq"') >= 0 || text.indexOf('name="pagexnxq"') >= 0 ||
      text.indexOf('querygrkb') >= 0 || text.indexOf('queryqmcj') >= 0;
    if (hasBusinessPage) {
      return false;
    }
    const hasLoginForm: boolean = text.indexOf('<form') >= 0 &&
      (text.indexOf('logincas') >= 0 || text.indexOf('name="password"') >= 0 ||
        text.indexOf('name="mm"') >= 0 || text.indexOf('action="/login') >= 0);
    const hasReAuthPage: boolean = text.indexOf('reauth') >= 0 &&
      text.indexOf('reauth_success') < 0;
    const explicitExpired: boolean = text.indexOf('会话已失效') >= 0 ||
      text.indexOf('会话超时') >= 0 || text.indexOf('未登录') >= 0;
    return hasLoginForm || hasReAuthPage || explicitExpired ||
      (text.indexOf('/common/caslogin') >= 0 && text.indexOf('<form') >= 0) ||
      (text.indexOf('/cas/login') >= 0 && text.indexOf('<form') >= 0) ||
      text.indexOf('统一身份认证登录') >= 0;
  }

  async getPersonalScores(session: EasSession, term: EasTermItem): Promise<EasScoresResult> {
    if (session.campus === EasCampus.SHENZHEN) {
      return await this.getShenzhenScores(session, term);
    }
    const campus = session.campus.toString();
    const path: string = EasDataProvider.scoresPathOf(session);
    if (path.length === 0) {
      throw new Error('EAS_SCORES_ENDPOINT_NOT_CAPTURED：请按 docs/eas-api-capture.md 抓包回填 ' +
        (campus === 'WEIHAI' ? 'EasWeihaiEndpoints' :
          campus === 'BENBU' ? 'EasBenbuEndpoints' : 'EasShenzhenEndpoints') + '.scoresPath');
    }
    const opts: EasApiClientOptions = new EasApiClientOptions();
    opts.method = EasHttpMethod.POST;
    opts.body = JSON.stringify({ 'termCode': term.getCode() });
    opts.extraHeaders.set('Content-Type', 'application/json; charset=UTF-8');
    const cfg = easWebLoginConfigFor(session.campus, session.getStudentType());
    const resp: EasApiResponse = await this.api.request(session, cfg, path, opts);
    if (resp.statusCode === 0) {
      throw new Error('成绩请求网络失败');
    }
    const parsed: ParsedShenzhenWebScores | undefined = parseShenzhenWebScores(resp.body, term);
    const result: EasScoresResult = new EasScoresResult();
    if (parsed === undefined) {
      result.ok = false;
      result.msg = '成绩响应解析失败（HTTP ' + resp.statusCode.toString() + '）';
      return result;
    }
    result.code = parsed.code;
    result.msg = parsed.msg;
    result.items = parsed.list;
    result.ok = parsed.code === 0;
    return result;
  }

  /** 深圳新版 Web 成绩查询，参数与 Android EASWebSource.fetchShenzhenWebScoreItems 对齐。 */
  private async getShenzhenScores(session: EasSession, term: EasTermItem): Promise<EasScoresResult> {
    if (!session.hasShenzhenWebSession()) {
      throw new Error('深圳教务会话已失效，请重新登录');
    }
    const cfg = easWebLoginConfigFor(session.campus, session.getStudentType());
    const opts: EasApiClientOptions = new EasApiClientOptions();
    opts.method = EasHttpMethod.POST;
    opts.timeoutMs = 60000;
    opts.body = '{"xn":"' + EasDataProvider.jsonEscape(term.yearCode) +
      '","xq":"' + EasDataProvider.jsonEscape(term.termCode) +
      '","kcmc":null,"cxbj":"-1","pylx":"' + session.getStudentType() +
      '","current":1,"pageSize":1000,"xscjlb":null,"sffx":null}';
    opts.extraHeaders.set('Content-Type', 'application/json;charset=UTF-8');
    opts.extraHeaders.set('Accept', '*/*');
    opts.extraHeaders.set('RoleCode', '01');
    opts.extraHeaders.set('X-Requested-With', 'XMLHttpRequest');
    const resp: EasApiResponse = await this.api.request(session, cfg,
      EasShenzhenEndpoints.scoresPath, opts);
    if (resp.statusCode === 401 || resp.statusCode === 403 || EasDataProvider.isLoginResponse(resp.body)) {
      throw new Error('深圳教务会话已失效，请重新登录');
    }
    if (resp.statusCode === 0) {
      throw new Error('成绩请求网络失败');
    }
    const parsed: ParsedShenzhenWebScores | undefined = parseShenzhenWebScores(resp.body, term);
    const result: EasScoresResult = new EasScoresResult();
    if (parsed === undefined) {
      result.ok = false;
      result.msg = '成绩响应解析失败（HTTP ' + resp.statusCode.toString() + '）';
      return result;
    }
    result.code = parsed.code;
    result.msg = parsed.msg;
    result.items = parsed.list;
    result.ok = parsed.code === 0 || parsed.code === 200;
    return result;
  }

  private static jsonEscape(raw: string): string {
    return raw.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
  }

  private static scoresPathOf(session: EasSession): string {
    return session.campus === EasCampus.WEIHAI ? EasWeihaiEndpoints.scoresPath :
      session.campus === EasCampus.BENBU ? EasBenbuEndpoints.scoresPath : EasShenzhenEndpoints.scoresPath;
  }

  async getExamItems(session: EasSession, term: EasTermItem | undefined): Promise<EasExamItem[]> {
    return [];
  }

  static runParserSelfCheck(): string {
    return testShenzhenScoreParser() + '\n' + testShenzhenTimetableParser();
  }
}
