import { CreditIdentity, CreditRequirement, CreditGroup, CreditGroupCourse, CreditCourseRecord,
  OfficialCreditProgress } from './CreditModels';

// Field aliases and endpoint schemas follow Android ShenzhenCreditProgressParser.
type JsonRow = Record<string, Object>;

function row(value: Object | undefined | null): JsonRow | undefined {
  return value !== null && typeof value === 'object' && !Array.isArray(value) ? value as JsonRow : undefined;
}

function objectAt(value: JsonRow | undefined, keys: string[]): JsonRow | undefined {
  for (const key of keys) {
    const result = row(value?.[key]);
    if (result !== undefined) return result;
  }
  return undefined;
}

function arrayAt(value: JsonRow | undefined, keys: string[]): Object[] | undefined {
  for (const key of keys) {
    const result = value?.[key];
    if (Array.isArray(result)) return result as Object[];
  }
  return undefined;
}

function text(value: JsonRow | undefined, keys: string[]): string {
  for (const key of keys) {
    const found = value?.[key];
    if (typeof found !== 'string' && typeof found !== 'number' && typeof found !== 'boolean') continue;
    const result = String(found).trim();
    if (result.length > 0 && result.toLowerCase() !== 'null') return result;
  }
  return '';
}

function numberAt(value: JsonRow | undefined, keys: string[]): number | undefined {
  const raw = text(value, keys);
  const parsed = Number(raw);
  return raw.length > 0 && Number.isFinite(parsed) ? parsed : undefined;
}

function parse(body: string): Object | undefined {
  try { return JSON.parse(body) as Object; } catch (_) { return undefined; }
}

function allObjects(value: Object | undefined, depth: number = 0): JsonRow[] {
  if (value === undefined || value === null || depth > 20) return [];
  let result: JsonRow[] = [];
  if (Array.isArray(value)) {
    for (const child of value as Object[]) result = result.concat(allObjects(child, depth + 1));
  } else {
    const record = row(value);
    if (record !== undefined) {
      result.push(record);
      for (const key of Object.keys(record)) result = result.concat(allObjects(record[key], depth + 1));
    }
  }
  return result;
}

export class ShenzhenCreditParser {
  static identity(body: string): CreditIdentity {
    const result = new CreditIdentity();
    const source = allObjects(parse(body)).find((item: JsonRow) => text(item, ['XH', 'xh', 'YHDM', 'yhdm']).length > 0);
    result.studentNumber = text(source, ['XH', 'xh', 'YHDM', 'yhdm']);
    result.recordId = text(source, ['xjid', 'XJID', 'ID', 'id']);
    const type = text(source, ['pylx', 'PYLX']);
    result.studentType = type.includes('本科') ? '1' : type.includes('研究生') ? '2' : type;
    result.grade = /(?:19|20)\d{2}/.exec(text(source, ['NJ', 'nj', 'NJMC', 'njmc', 'NJDM', 'njdm']))?.[0] ?? '';
    return result;
  }

  static recordId(body: string): string {
    const rows = arrayAt(row(parse(body)), ['content']);
    return text(row(rows?.[0]), ['xjid', 'XJID', 'id', 'ID']);
  }

  static planId(body: string): string {
    const value = parse(body);
    const source = allObjects(value).find((item: JsonRow) => text(item, ['FAH', 'fah', 'PYFADM', 'pyfadm']).length > 0);
    if (source !== undefined) return text(source, ['FAH', 'fah', 'PYFADM', 'pyfadm']);
    const raw = typeof value === 'string' ? value.trim() : value === undefined ? body.trim() : '';
    return /^[A-Za-z0-9_-]{8,}$/.test(raw) ? raw : '';
  }

  static currentTerm(body: string): string {
    const source = row(parse(body));
    const year = text(source, ['XN', 'xn']);
    const term = text(source, ['XQ', 'xq']);
    return year.length > 0 && term.length > 0 ? year + term : '';
  }

  static recordTotal(body: string): number {
    return Math.max(0, numberAt(row(parse(body)), ['R', 'r']) ?? 0);
  }

  static summary(body: string): OfficialCreditProgress | undefined {
    const source = objectAt(row(parse(body)), ['content']);
    const required = objectAt(source, ['yqmsxf', 'YQMSXF']);
    const result = new OfficialCreditProgress();
    result.required = numberAt(required, ['YQXF', 'yqxf']);
    result.completed = numberAt(source, ['ywcxf', 'YWCXF']);
    result.remaining = numberAt(source, ['wwcxf', 'WWCXF']);
    if (result.remaining === undefined && result.required !== undefined && result.completed !== undefined) {
      result.remaining = Math.max(0, result.required - result.completed);
    }
    result.requiredCourses = numberAt(required, ['YQMS', 'yqms']);
    result.completedCourses = numberAt(source, ['ywcms', 'YWCMS']);
    result.remainingCourses = numberAt(source, ['wwcms', 'WWCMS']);
    result.average = numberAt(required, ['XFJ', 'xfj']);
    result.rank = numberAt(required, ['PM', 'pm']);
    result.cohortSize = numberAt(required, ['ZYRS', 'zyrs']);
    result.categories = ShenzhenCreditParser.categories(body) ?? [];
    return result.required !== undefined || result.completed !== undefined || result.categories.length > 0 ? result : undefined;
  }

  static categories(body: string): CreditRequirement[] | undefined {
    const root = row(parse(body));
    const content = objectAt(root, ['content']) ?? root;
    const container = objectAt(content, ['xflbyq', 'XFLBYQ']);
    const rows = arrayAt(container, ['list', 'rows']) ?? arrayAt(content, ['xflbyq', 'XFLBYQ']);
    if (rows === undefined) return undefined;
    const result: CreditRequirement[] = [];
    const seen = new Set<string>();
    for (const item of rows) {
      const source = row(item);
      const required = numberAt(source, ['yqwcxf', 'YQWCXF']);
      if (required === undefined) continue;
      const value = new CreditRequirement();
      value.name = text(source, ['kclbmc', 'KCLBMC']) || '未命名类别';
      value.direction = text(source, ['zyfxmc', 'ZYFXMC']);
      value.language = text(source, ['skyymc', 'SKYYMC']);
      value.nature = text(source, ['kcxzmc', 'KCXZMC']);
      value.id = [text(source, ['kcxzdm', 'KCXZDM']), text(source, ['kclbdm', 'KCLBDM']),
        text(source, ['skyydm', 'SKYYDM']), value.name, value.direction, value.language, value.nature].join('|');
      if (seen.has(value.id)) continue;
      seen.add(value.id);
      value.required = required;
      value.completed = numberAt(source, ['ywcxf', 'YWCXF']) ?? 0;
      value.remaining = numberAt(source, ['wwcxf', 'WWCXF']) ?? Math.max(0, required - value.completed);
      value.hours = numberAt(source, ['ywcxs', 'YWCXS']);
      value.creditedMooc = numberAt(source, ['moochdxf', 'MOOCHDXF']) ?? 0;
      value.earnedMooc = numberAt(source, ['moocsjhdxf', 'MOOCSJHDXF']) ?? 0;
      value.passed = value.remaining <= 0.0001 || value.completed + 0.0001 >= required;
      result.push(value);
    }
    return result;
  }

  static groups(body: string): CreditGroup[] | undefined {
    const root = row(parse(body));
    const content = objectAt(root, ['content']);
    const rows = arrayAt(root, ['content']) ?? arrayAt(content, ['list', 'mkyq', 'children']) ??
      arrayAt(root, ['mkyq', 'list', 'children']);
    if (rows === undefined) return undefined;
    const result: CreditGroup[] = [];
    ShenzhenCreditParser.visitGroups(rows, 0, result, new Set<string>());
    const parents = new Set<string>(result.map((group: CreditGroup) => group.parentId).filter((id: string) => id.length > 0));
    for (const group of result) group.hasChildren = group.hasChildren || parents.has(group.id);
    return result;
  }

  private static visitGroups(rows: Object[], depth: number, result: CreditGroup[], seen: Set<string>): void {
    if (depth > 20) return;
    for (const item of rows) {
      const source = row(item);
      const value = new CreditGroup();
      value.id = text(source, ['kzid', 'KZID']);
      value.parentId = text(source, ['fkzid', 'FKZID']);
      value.name = text(source, ['title', 'TITLE', 'kzmc', 'KZMC']);
      value.depth = depth;
      value.required = numberAt(source, ['yqxdxf', 'YQXDXF']);
      value.completed = numberAt(source, ['wc_xf', 'WC_XF']) ?? 0;
      value.requiredCourses = numberAt(source, ['yqxdms', 'YQXDMS']);
      value.completedCourses = numberAt(source, ['wc_ms', 'WC_MS']) ?? 0;
      const passed = text(source, ['sftg', 'SFTG']).toLowerCase();
      value.passed = ['1', 'true', 'yes', '是'].includes(passed) ? true :
        ['0', 'false', 'no', '否'].includes(passed) ? false :
        (value.required !== undefined || value.requiredCourses !== undefined) &&
          (value.required === undefined || value.completed + 0.0001 >= value.required) &&
          (value.requiredCourses === undefined || value.completedCourses >= value.requiredCourses);
      const children = arrayAt(source, ['children', 'CHILDREN']) ?? [];
      value.hasChildren = children.length > 0;
      if (value.id.length > 0 && value.name.length > 0 && !seen.has(value.id)) {
        seen.add(value.id);
        result.push(value);
      }
      ShenzhenCreditParser.visitGroups(children, depth + 1, result, seen);
    }
  }

  static pageCount(body: string): number {
    return Math.max(1, Math.floor(numberAt(objectAt(row(parse(body)), ['content']), ['pages', 'PAGES']) ?? 1));
  }

  static groupCourses(body: string): CreditGroupCourse[] | undefined {
    const rows = arrayAt(objectAt(row(parse(body)), ['content']), ['list']);
    if (rows === undefined) return undefined;
    const result: CreditGroupCourse[] = [];
    for (const item of rows) {
      const source = row(item);
      const value = new CreditGroupCourse();
      value.code = text(source, ['kcdm', 'KCDM']);
      value.name = text(source, ['kcmc', 'KCMC']) || value.code;
      if (!value.name) continue;
      value.credits = numberAt(source, ['xf', 'XF']) ?? 0;
      value.term = text(source, ['tjkkxnxq', 'TJKKXNXQ']);
      value.nature = text(source, ['kcxzmc', 'KCXZMC']);
      value.completed = text(source, ['sfyxkc', 'SFYXKC']) === '1' ||
        text(source, ['zpcj', 'ZPCJ', 'xscj', 'XSCJ']).length > 0;
      result.push(value);
    }
    return result;
  }

  static records(body: string): CreditCourseRecord[] | undefined {
    const rows = arrayAt(objectAt(row(parse(body)), ['content']), ['list']);
    if (rows === undefined) return undefined;
    const result: CreditCourseRecord[] = [];
    for (const item of rows) {
      const source = row(item);
      const value = new CreditCourseRecord();
      value.code = text(source, ['kcdm', 'KCDM']);
      value.name = text(source, ['kcmc', 'KCMC']) || value.code;
      if (!value.name) continue;
      value.term = text(source, ['xnxq', 'XNXQ', 'xnxqx', 'XNXQX']);
      value.id = text(source, ['rwh', 'RWH']) || [value.term, value.code, value.name].join('|');
      value.credits = numberAt(source, ['xf', 'XF']) ?? 0;
      value.score = text(source, ['xscj', 'XSCJ', 'zpcj', 'ZPCJ']);
      value.teacher = text(source, ['jsxm', 'JSXM']);
      value.nature = text(source, ['kcxzmc', 'KCXZMC']);
      value.category = text(source, ['kclbmc', 'KCLBMC']);
      result.push(value);
    }
    return result;
  }
}
