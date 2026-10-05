/**
 * ShenzhenWebScores.ets — 深圳成绩 JSON 解析（1:1 移植新版 ShenzhenWebScoreParser.java）。
 *
 * 成绩字段与回退顺序参考 HITA Android。
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
