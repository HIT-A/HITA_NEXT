/**
 * ShenzhenWebScores.ets — 深圳成绩 JSON 解析（1:1 移植新版 ShenzhenWebScoreParser.java）。
 *
 * 出处：.analysis/decomp/cn/limpu/hita/data/source/web/eas/ShenzhenWebScoreParser.java
 * 返回形态：{code, msg(message 兜底), content.list[]}；条目字段：
 *   xscj/zzcj/zpcj（三选一成绩文本）、kcdm、kcmc、xf、xs、kcxz/kcxzen、kclb/kclben、
 *   yxmc、khfs、xnxqmc（缺失时回填请求学期 term.name）
 * 注意：ShenzhenWebScoreParser 在数据端点 JSON 里的 text() 依次取首个非空字段，
 * 本文件实现同语义的 easText / easNumber。
 */
import { EasCourseScoreItem, EasTermItem } from '../model/EasModels';

/** parse() 返回结构（对应 ParsedShenzhenWebScores）。 */
export class ParsedShenzhenWebScores {
  code: number = 0;
  msg: string = '';
  list: EasCourseScoreItem[] = [];
}

/** 依次取键集合中首个“原始值且 trim 后非空且 != 'null'”的字符串（对应 parser.text）。 */
function easText(obj: Record<string, Object>, keys: string[]): string {
  for (let i = 0; i < keys.length; i++) {
    const v: Object | undefined = obj[keys[i]];
    if (v === undefined || v === null) {
      continue;
    }
    const t: string = typeof v === 'string' ? v : String(v);
    const trimmed: string = t.trim();
    if (trimmed.length > 0 && trimmed !== 'null') {
      return trimmed;
    }
  }
  return '';
}

/** 取数值（对应 parser.number）：null/缺失/不可解析 → undefined。 */
function easNumber(obj: Record<string, Object>, key: string): number | undefined {
  const v: Object | undefined = obj[key];
  if (v === undefined || v === null) {
    return undefined;
  }
  if (typeof v === 'number') {
    return v as number;
  }
  if (typeof v === 'string') {
    const n: number = Number((v as string).trim());
    if (!Number.isNaN(n)) {
      return n;
    }
  }
  return undefined;
}

function itemFromJson(item: Record<string, Object>, term: EasTermItem): EasCourseScoreItem {
  const out: EasCourseScoreItem = new EasCourseScoreItem();
  out.courseCode = easText(item, ['kcdm']);
  out.courseName = easText(item, ['kcmc']);
  const xf: number | undefined = easNumber(item, 'xf');
  out.credits = xf === undefined ? 0 : xf;
  const xs: number | undefined = easNumber(item, 'xs');
  out.hours = xs === undefined ? 0 : xs;
  // 成绩文本：xscj / zzcj / zpcj 依次取首个非空
  const scoreText: string = easText(item, ['xscj', 'zzcj', 'zpcj']);
  out.finalScoresText = scoreText;
  const parsed: number = Number(scoreText);
  out.finalScores = (scoreText.length > 0 && !Number.isNaN(parsed)) ? Math.trunc(parsed) : -1;
  out.courseProperty = easText(item, ['kcxz', 'kcxzen']);
  out.courseCategory = easText(item, ['kclb', 'kclben']);
  out.schoolName = easText(item, ['yxmc']);
  out.assessMethod = easText(item, ['khfs']);
  const t: string = easText(item, ['xnxqmc']);
  out.termName = t.length > 0 ? t : term.name;
  return out;
}

/**
 * 解析深圳成绩 JSON。入参非法/非对象 → undefined（对应 parser 返回 null）。
 */
export function parseShenzhenWebScores(body: string, term: EasTermItem): ParsedShenzhenWebScores | undefined {
  let root: Object;
  try {
    root = JSON.parse(body) as Object;
  } catch (e) {
    return undefined;
  }
  if (root === undefined || root === null) {
    return undefined;
  }
  if (typeof root !== 'object' || Array.isArray(root)) {
    return undefined; // 原 parser：非 JsonObject 即 null
  }
  const obj = root as Record<string, Object>;
  const parsed: ParsedShenzhenWebScores = new ParsedShenzhenWebScores();
  const code: number | undefined = easNumber(obj, 'code');
  parsed.code = code === undefined ? 0 : code;
  parsed.msg = easText(obj, ['msg', 'message']);
  const content = obj['content'] as Record<string, Object> | undefined;
  if (content !== undefined && content !== null) {
    const arr = content['list'] as Array<Record<string, Object>> | undefined;
    if (arr !== undefined && arr !== null) {
      for (let i = 0; i < arr.length; i++) {
        const it = arr[i];
        if (it !== undefined && it !== null) {
          parsed.list.push(itemFromJson(it, term));
        }
      }
    }
  }
  return parsed;
}

/**
 * 离线样例（用于开发期自检解析链路；真机端点与真实报文以 M0 抓包为准，勿当契约）。
 */
export const SHENZHEN_SCORES_SAMPLE: string =
  '{"code":0,"msg":"success","content":{"list":[' +
  '{"kcdm":"CS101","kcmc":"数据结构","xscj":"92","xf":4.0,"xs":64,' +
  '"kcxz":"必修","kclb":"专业基础课","yxmc":"计算机科学与技术学院","khfs":"考试","xnxqmc":"2023-2024-1"},' +
  '{"kcdm":"MA102","kcmc":"线性代数","xscj":"优秀","xf":3.5,"xs":48,' +
  '"kcxz":"必修","kclb":"学科基础课","yxmc":"数学学院","khfs":"考试"},' +
  '{"kcdm":"EN201","kcmc":"大学英语","zzcj":"88","xf":2.0,"xs":32,' +
  '"kcxz":"选修","kclb":"通识课","yxmc":"外国语学院","khfs":"考查","xnxqmc":"2023-2024-1"}' +
  ']}}';

/** 离线自检：解析样例并返回可读摘要（供开发页/调试）。 */
export function testShenzhenScoreParser(): string {
  const term: EasTermItem = new EasTermItem();
  term.yearName = '2023-2024';
  term.termName = '-1';
  const parsed: ParsedShenzhenWebScores | undefined = parseShenzhenWebScores(SHENZHEN_SCORES_SAMPLE, term);
  if (parsed === undefined) {
    return '解析失败：非 JSON/非对象';
  }
  const sb: string[] = [];
  sb.push('code=' + parsed.code.toString() + ' msg=' + parsed.msg + ' count=' + parsed.list.length.toString());
  for (let i = 0; i < parsed.list.length; i++) {
    const it: EasCourseScoreItem = parsed.list[i];
    sb.push((i + 1).toString() + '. ' + it.courseName + ' | ' + it.displayScore() +
      ' | 学分=' + it.credits.toString() + ' | ' + it.assessMethod + ' | ' + it.termName +
      ' | finalScores=' + it.finalScores.toString());
  }
  return sb.join('\n');
}
