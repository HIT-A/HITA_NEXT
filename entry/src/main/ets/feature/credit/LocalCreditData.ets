import { EasSubjectType, EasTermSubject } from '../../common/model/timetable/TimetableModels';
import { CreditField, LocalCreditCategory, LocalCreditSummary } from './CreditModels';

export const CREDIT_TYPES: EasSubjectType[] = [
  EasSubjectType.COM_A, EasSubjectType.COM_B, EasSubjectType.OPT_A, EasSubjectType.OPT_B, EasSubjectType.MOOC
];
const CREDIT_LABELS: string[] = ['必修', '必修（考查）', '限选', '任选', 'MOOC'];
const CREDIT_COLORS: string[] = ['#3390EC', '#737ACB', '#26A69A', '#58A55C', '#E97845'];

export function creditTypeName(type: EasSubjectType): string {
  return CREDIT_LABELS[CREDIT_TYPES.indexOf(type)] ?? '其他';
}

export function creditTypeColor(type: EasSubjectType): string {
  return CREDIT_COLORS[CREDIT_TYPES.indexOf(type)] ?? '#84919F';
}

export function creditNumber(value: number | undefined): string {
  return value === undefined || !Number.isFinite(value) ? '—' : Number(value.toFixed(2)).toString();
}

export function creditPercent(completed: number | undefined, required: number | undefined): number {
  return required !== undefined && required > 0 && completed !== undefined ?
    Math.max(0, Math.min(100, completed / required * 100)) : 0;
}

export function aggregateLocalCredits(subjects: EasTermSubject[], goals: Map<string, number>): LocalCreditSummary {
  const summary = new LocalCreditSummary();
  const seen = new Set<string>();
  const unique: EasTermSubject[] = [];
  for (const subject of subjects) {
    if (subject.type === EasSubjectType.TAG || CREDIT_TYPES.indexOf(subject.type) < 0) continue;
    const key = subject.code.trim() || subject.name.trim();
    if (key.length === 0 || seen.has(key)) continue;
    seen.add(key);
    unique.push(subject);
  }
  for (const type of CREDIT_TYPES) {
    const items = unique.filter((subject: EasTermSubject) => subject.type === type);
    if (items.length === 0) continue;
    const category = new LocalCreditCategory();
    category.type = type;
    category.goal = goals.get(type) ?? 0;
    category.subjects = items;
    const fields = new Map<string, number>();
    for (const subject of items) {
      const credits = Number.isFinite(subject.credit) ? Math.max(0, subject.credit) : 0;
      category.credits += credits;
      const field = subject.field.trim() || '未分类';
      fields.set(field, (fields.get(field) ?? 0) + credits);
      if (subject.countInSPA) summary.spaCredits += credits;
      else summary.nonSpaCredits += credits;
    }
    fields.forEach((credits: number, name: string) => {
      const field = new CreditField();
      field.name = name;
      field.credits = credits;
      category.fields.push(field);
    });
    category.fields.sort((a: CreditField, b: CreditField) => b.credits - a.credits);
    summary.categories.push(category);
    summary.credits += category.credits;
    summary.count += items.length;
  }
  return summary;
}
