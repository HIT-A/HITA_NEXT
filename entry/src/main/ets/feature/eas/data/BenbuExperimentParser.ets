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

  static isElectronicResponse(json: string): boolean {
    try {
      const response: ElectronicExperimentResponse = JSON.parse(json) as ElectronicExperimentResponse;
      return response !== null && response.code !== undefined && response.code !== null &&
        Number(response.code) === 0 && Array.isArray(response.data);
    } catch (_) {
      return false;
    }
  }

  static parseElectronic(json: string): EasCourseItem[] {
    const courses: EasCourseItem[] = [];
    try {
      const response: ElectronicExperimentResponse = JSON.parse(json) as ElectronicExperimentResponse;
      if (response.code === undefined || response.code === null || Number(response.code) !== 0 ||
        !Array.isArray(response.data)) return courses;
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
    const source: string = html.replace(/<!--[\s\S]*?-->/g, '')
      .replace(/<(script|style)\b[^>]*>[\s\S]*?<\/\1>/gi, '');
    const tables: RegExp = /<table\b([^>]*)>/gi;
    let table: RegExpExecArray | null = tables.exec(source);
    while (table !== null) {
      if (/\bclass\s*=\s*["'][^"']*\bdataTable\b/i.test(table[1]) ||
        /\bclass\s*=\s*dataTable\b/i.test(table[1])) break;
      table = tables.exec(source);
    }
    if (table === null) return courses;
    // A layout table may wrap dataTable; match its own closing tag instead of the outer table's.
    const contentStart: number = tables.lastIndex;
    const tags: RegExp = /<\/?table\b[^>]*>/gi;
    tags.lastIndex = contentStart;
    let depth: number = 1;
    let tag: RegExpExecArray | null = tags.exec(source);
    while (tag !== null) {
      depth += /^<\//.test(tag[0]) ? -1 : 1;
      if (depth === 0) break;
      tag = tags.exec(source);
    }
    if (tag === null) return courses;
    const content: string = source.substring(contentStart, tag.index);
    const rows: RegExp = /<tr\b[^>]*>((?:(?!<tr\b)[\s\S])*?)<\/tr>/gi;
    let row: RegExpExecArray | null = rows.exec(content);
    const spans: number[] = [];
    let previousCells: string[] = [];
    while (row !== null) {
      const cells: string[] = [];
      const ownCells: boolean[] = [];
      const pattern: RegExp = /<(?:td|th)\b([^>]*)>([\s\S]*?)<\/(?:td|th)>/gi;
      let cell: RegExpExecArray | null = pattern.exec(row[1]);
      let column: number = 0;
      while (cell !== null && column < 9) {
        while ((spans[column] || 0) > 0 && column < 9) {
          cells[column] = previousCells[column];
          spans[column]--;
          column++;
        }
        const width: number = BenbuExperimentParser.span(cell[1], 'colspan', 9);
        const height: number = BenbuExperimentParser.span(cell[1], 'rowspan', 64);
        for (let i: number = 0; i < width && column < 9; i++) {
          cells[column] = cell[2];
          ownCells[column] = i === 0;
          spans[column] = height - 1;
          column++;
        }
        cell = pattern.exec(row[1]);
      }
      while (column < 9 && (spans[column] || 0) > 0) {
        cells[column] = previousCells[column];
        spans[column]--;
        column++;
      }
      if (cells.length >= 9) {
        for (let i: number = 2; i < 9; i++) {
          if (ownCells[i]) courses.push(...BenbuExperimentParser.parseCell(cells[i], i - 1));
        }
      }
      previousCells = cells;
      row = rows.exec(content);
    }
    return courses;
  }

  private static span(attrs: string, name: string, maximum: number): number {
    const match: RegExpExecArray | null = new RegExp('\\b' + name + '\\s*=\\s*["\']?(\\d+)', 'i').exec(attrs);
    return match === null ? 1 : Math.max(1, Math.min(maximum, Number(match[1])));
  }

  private static parseCell(html: string, day: number): EasCourseItem[] {
    const courses: EasCourseItem[] = [];
    const lines: string[] = html.split(/<\s*\/?\s*br\s*\/?\s*>/i).map((raw: string): string =>
      normalizeHtmlSpaces(raw.replace(/<[^>]*>/g, '')
        .replace(/&amp;/gi, '&').replace(/&lt;/gi, '<').replace(/&gt;/gi, '>'))).filter((line: string): boolean =>
          line.length > 0);
    let name: string = '';
    let separateName: boolean = false;
    for (let index: number = 0; index < lines.length; index++) {
      const line: string = lines[index];
      const week: RegExpExecArray | null = /\[(\d+)周第([\d，,\s]+)节\]/.exec(line);
      if (week === null) { name = line; separateName = true; continue; }
      let teacher: string = line.substring(0, week.index).trim();
      const split: number = teacher.lastIndexOf(' ');
      if (!separateName && split > 0) {
        name = teacher.substring(0, split).trim(); teacher = teacher.substring(split + 1);
      } else if (name && teacher.startsWith(name + ' ')) {
        teacher = teacher.substring(name.length).trim();
      }
      if (!name || !teacher || Number(week[1]) < 1) continue;
      const course: EasCourseItem = new EasCourseItem();
      course.name = name;
      course.teacher = teacher;
      course.dayOfWeek = day;
      course.weekNumbers = [Number(week[1])];
      course.weeks = week[1];
      let tail: string = line.substring(week.index + week[0].length);
      // Some pages put the red free-time range on the next line of the same detail.
      while (index + 1 < lines.length && /^\d{1,2}:\d{2}\s*-\s*\d{1,2}:\d{2}$/.test(lines[index + 1])) {
        tail += '，' + lines[++index];
      }
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
