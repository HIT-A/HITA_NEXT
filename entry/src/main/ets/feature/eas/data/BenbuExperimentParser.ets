import { EasCourseItem } from '../model/EasModels';
import { normalizeHtmlSpaces } from '../../../common/util/HtmlSpaces';

interface ElectronicExperimentRow {
  subjectName?: string;
  classDate?: string;
  startTime?: string;
  endTime?: string;
  teacher?: string;
  address?: string;
  labsName?: string;
}

interface ElectronicExperimentResponse {
  code: number;
  data?: ElectronicExperimentRow[];
}

/** Port of Android BenbuScheduleParser and BenbuEASWebSource experiment parsing. */
export class BenbuExperimentParser {
  static timeMinutes(raw: string): number {
    const match: RegExpExecArray | null = /^(\d{1,2}):(\d{2})(?::\d{2})?$/.exec(raw.trim());
    if (match === null) return -1;
    const hour: number = Number(match[1]);
    const minute: number = Number(match[2]);
    return hour < 24 && minute < 60 ? hour * 60 + minute : -1;
  }

  static dateMs(raw: string): number {
    const m: RegExpExecArray | null = /^(\d{4})-(\d{2})-(\d{2})$/.exec(raw);
    if (m === null) return NaN;
    const date: Date = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
    return date.getFullYear() === Number(m[1]) && date.getMonth() === Number(m[2]) - 1 &&
      date.getDate() === Number(m[3]) ? date.getTime() : NaN;
  }

  private static timeText(minutes: number): string {
    return Math.floor(minutes / 60).toString().padStart(2, '0') + ':' +
      (minutes % 60).toString().padStart(2, '0');
  }

  static parseElectronic(json: string): EasCourseItem[] {
    const courses: EasCourseItem[] = [];
    try {
      const response: ElectronicExperimentResponse = JSON.parse(json) as ElectronicExperimentResponse;
      if (response.code !== 0 || !Array.isArray(response.data)) return courses;
      for (const row of response.data) {
        try {
          const course: EasCourseItem = new EasCourseItem();
          course.name = (row.subjectName || '').trim();
          course.scheduledDate = (row.classDate || '').trim();
          const date: number = BenbuExperimentParser.dateMs(course.scheduledDate);
          const start: number = BenbuExperimentParser.timeMinutes(row.startTime || '');
          const end: number = (row.endTime || '').trim().length === 0 ? start + 120 :
            BenbuExperimentParser.timeMinutes(row.endTime || '');
          if (!course.name || !Number.isFinite(date) || start < 0 || end <= start || end >= 1440) continue;
          course.startTime = BenbuExperimentParser.timeText(start);
          course.endTime = BenbuExperimentParser.timeText(end);
          course.dayOfWeek = new Date(date).getDay() || 7;
          course.teacher = (row.teacher || '').trim();
          course.classroom = (row.address || '').trim();
          const labs: string = (row.labsName || '').trim();
          if (labs) course.classroom += '(' + labs + ')';
          course.beginSection = -1;
          course.sectionCount = -1;
          courses.push(course);
        } catch (_) { /* One malformed record must not discard other experiments. */ }
      }
    } catch (_) { /* Unavailable auxiliary system. */ }
    return courses;
  }

  static parseHtml(html: string): EasCourseItem[] {
    const courses: EasCourseItem[] = [];
    const tables: RegExp = /<table\b([^>]*)>([\s\S]*?)<\/table>/gi;
    let table: RegExpExecArray | null = tables.exec(html);
    while (table !== null) {
      if (/\bclass\s*=\s*["'][^"']*\bdataTable\b/i.test(table[1]) ||
        /\bclass\s*=\s*dataTable\b/i.test(table[1])) break;
      table = tables.exec(html);
    }
    if (table === null) return courses;
    const rows: RegExp = /<tr\b[^>]*>([\s\S]*?)<\/tr>/gi;
    let row: RegExpExecArray | null = rows.exec(table[2]);
    while (row !== null) {
      const cells: string[] = [];
      const pattern: RegExp = /<td\b[^>]*>([\s\S]*?)<\/td>/gi;
      let cell: RegExpExecArray | null = pattern.exec(row[1]);
      while (cell !== null) { cells.push(cell[1]); cell = pattern.exec(row[1]); }
      if (cells.length >= 9) {
        for (let i: number = 2; i < 9; i++) courses.push(...BenbuExperimentParser.parseCell(cells[i], i - 1));
      }
      row = rows.exec(table[2]);
    }
    return courses;
  }

  private static parseCell(html: string, day: number): EasCourseItem[] {
    const courses: EasCourseItem[] = [];
    const lines: string[] = html.split(/<\s*\/?\s*br\s*\/?\s*>/i);
    let name: string = '';
    for (const raw of lines) {
      const line: string = normalizeHtmlSpaces(raw.replace(/<[^>]*>/g, '')
        .replace(/&amp;/gi, '&').replace(/&lt;/gi, '<').replace(/&gt;/gi, '>'));
      if (!line) continue;
      const week: RegExpExecArray | null = /\[(\d+)周第([\d，,\s]+)节\]/.exec(line);
      if (week === null) { name = line; continue; }
      let teacher: string = line.substring(0, week.index).trim();
      const split: number = teacher.lastIndexOf(' ');
      if (split > 0) { name = teacher.substring(0, split).trim(); teacher = teacher.substring(split + 1); }
      if (!name || !teacher || Number(week[1]) < 1) continue;
      const course: EasCourseItem = new EasCourseItem();
      course.name = name;
      course.teacher = teacher;
      course.dayOfWeek = day;
      course.weekNumbers = [Number(week[1])];
      course.weeks = week[1];
      const tail: string = line.substring(week.index + week[0].length);
      const time: RegExpExecArray | null = /(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})/.exec(tail);
      if (time !== null) {
        const start: number = BenbuExperimentParser.timeMinutes(time[1]);
        const end: number = BenbuExperimentParser.timeMinutes(time[2]);
        if (start < 0 || end <= start) continue;
        course.startTime = BenbuExperimentParser.timeText(start);
        course.endTime = BenbuExperimentParser.timeText(end);
        course.beginSection = -1;
        course.sectionCount = -1;
      } else {
        const periods: number[] = week[2].split(/[，,]/).map((part: string): number => Number(part.trim()));
        course.beginSection = periods[0];
        course.sectionCount = periods[periods.length - 1] - periods[0] + 1;
      }
      const location: RegExpExecArray | null = /上课形式\[[^\]]*\]\s*([^，,]*)/.exec(tail);
      if (location !== null) course.classroom = location[1].trim();
      courses.push(course);
    }
    return courses;
  }
}
