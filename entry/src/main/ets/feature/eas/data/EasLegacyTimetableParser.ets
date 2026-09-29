/**
 * Parser for the legacy HIT educational-system HTML timetable pages used by
 * Benbu and Weihai. The rules mirror the Android HITA BenbuScheduleParser:
 * split teacher/week/location elements at top-level commas, expand odd/even
 * week ranges, and carry shared teacher/location information across elements.
 */
import { EasCourseItem, EasTermItem } from '../model/EasModels';

export class EasLegacyTimetableParser {
  private static readonly WEEK_PATTERN: RegExp = /\[[^\]]+\](?:单|双)?周(?:\((?:单|双)\))?/;

  static parseTerms(html: string): EasTermItem[] {
    let terms: EasTermItem[] = EasLegacyTimetableParser.parseTermsBySelect(html, 'xnxq');
    if (terms.length === 0) {
      terms = EasLegacyTimetableParser.parseTermsBySelect(html, 'pageXnxq');
    }
    return terms;
  }

  static parseTermsBySelect(html: string, selectName: string): EasTermItem[] {
    const out: EasTermItem[] = [];
    const seen: Set<string> = new Set<string>();
    const select: string = EasLegacyTimetableParser.findSelect(html, selectName);
    if (select.length === 0) {
      return out;
    }

    const selectedValue: string = EasLegacyTimetableParser.currentTermValue(select);
    const optionPattern: RegExp = /<option\b([^>]*)>([\s\S]*?)<\/option>/gi;
    let match: RegExpExecArray | null = optionPattern.exec(select);
    let index: number = 0;
    while (match !== null) {
      const attrs: string = match[1];
      const value: string = EasLegacyTimetableParser.attribute(attrs, 'value').trim();
      const label: string = EasLegacyTimetableParser.decodeHtml(match[2]).trim();
      const term: EasTermItem | undefined = EasLegacyTimetableParser.termFromValue(value, label);
      if (term !== undefined) {
        const key: string = term.getCode();
        if (!seen.has(key)) {
          term.isCurrent = value === selectedValue ||
            (selectedValue.length === 0 && /\bselected\b/i.test(attrs)) ||
            (selectedValue.length === 0 && index === 0);
          out.push(term);
          seen.add(key);
          index++;
        }
      }
      match = optionPattern.exec(select);
    }
    return out;
  }

  static parseScheduleHtml(html: string): EasCourseItem[] {
    const out: EasCourseItem[] = [];
    const table: string = EasLegacyTimetableParser.findScheduleTable(html);
    if (table.length === 0) {
      return out;
    }

    const rows: string[] = EasLegacyTimetableParser.tagContents(table, 'tr');
    for (let rowIndex: number = 1; rowIndex < rows.length; rowIndex++) {
      const cells: string[] = EasLegacyTimetableParser.tableCells(rows[rowIndex]);
      if (cells.length < 3) {
        continue;
      }
      const periodInfo: string = EasLegacyTimetableParser.textFromHtml(cells[1]);
      for (let cellIndex: number = 2; cellIndex < cells.length && cellIndex <= 8; cellIndex++) {
        const cellText: string = EasLegacyTimetableParser.textFromHtml(cells[cellIndex]);
        if (cellText.length < 2) {
          continue;
        }
        const dow: number = cellIndex - 1;
        out.push(...EasLegacyTimetableParser.parseCellCourses(cells[cellIndex], dow, rowIndex, periodInfo));
      }
    }
    return EasLegacyTimetableParser.mergeAdjacent(out);
  }

  private static parseCellCourses(cellHtml: string, dow: number, periodHint: number,
    periodInfo: string): EasCourseItem[] {
    const courses: EasCourseItem[] = [];
    let cleanedHtml: string = cellHtml.replace(/<a\b[^>]*>[\s\S]*?<\/a>/gi, '');
    cleanedHtml = cleanedHtml.replace(/<(?!\/?br\b)[^>]+>/gi, '');
    const rawParts: string[] = cleanedHtml.split(/<\s*\/?\s*br\s*\/?\s*>/i);
    const parts: string[] = [];
    for (let i: number = 0; i < rawParts.length; i++) {
      const part: string = EasLegacyTimetableParser.decodeHtml(rawParts[i].replace(/<[^>]+>/g, ''))
        .replace(/\u00a0/g, ' ')
        .replace(/\s+/g, ' ')
        .trim();
      if (part.length > 0 && part !== '&nbsp;') {
        parts.push(part);
      }
    }
    if (parts.length === 0) {
      return courses;
    }

    let index: number = 0;
    while (index < parts.length) {
      const line: string = parts[index];
      if (EasLegacyTimetableParser.hasWeekPattern(line)) {
        index++;
        continue;
      }

      const courseName: string = line.trim();
      index++;
      const teacherLocationLines: string[] = [];
      while (index < parts.length) {
        const nextLine: string = parts[index];
        const lineHasWeeks: boolean = EasLegacyTimetableParser.hasWeekPattern(nextLine);
        if (lineHasWeeks) {
          teacherLocationLines.push(nextLine);
          index++;
          continue;
        }
        const afterNext: string = index + 1 < parts.length ? parts[index + 1] : '';
        if (teacherLocationLines.length > 0 && !EasLegacyTimetableParser.hasWeekPattern(afterNext)) {
          teacherLocationLines.push(nextLine);
          index++;
        }
        break;
      }

      if (teacherLocationLines.length > 0) {
        const combined: string = teacherLocationLines.join('');
        const elements: string[] = EasLegacyTimetableParser.splitTeacherLocationPairs(combined);
        const parsedForCourse: EasCourseItem[] = [];
        for (let j: number = 0; j < elements.length; j++) {
          parsedForCourse.push(...EasLegacyTimetableParser.parseCourseElement(courseName, elements[j], dow,
            periodHint, periodInfo));
        }
        courses.push(...EasLegacyTimetableParser.normalizeCourseElementParts(parsedForCourse));
      }
    }
    return courses;
  }

  private static splitTeacherLocationPairs(text: string): string[] {
    const elements: string[] = [];
    let current: string = '';
    let bracketDepth: number = 0;
    for (let i: number = 0; i < text.length; i++) {
      const ch: string = text.charAt(i);
      if (ch === '[') {
        bracketDepth++;
      } else if (ch === ']') {
        bracketDepth = Math.max(0, bracketDepth - 1);
      } else if ((ch === ',' || ch === '，') && bracketDepth === 0) {
        if (current.trim().length > 0) {
          elements.push(current.trim());
          current = '';
        }
        continue;
      }
      current += ch;
    }
    if (current.trim().length > 0) {
      elements.push(current.trim());
    }
    return elements;
  }

  private static parseCourseElement(courseName: string, element: string, dow: number, periodHint: number,
    periodInfo: string): EasCourseItem[] {
    const out: EasCourseItem[] = [];
    const weekPattern: RegExp = /([^,，\[]*)\[([^\]]+?)\](?:(单|双)周)?(?:\((单|双)\))?([^,，]*)/g;
    let match: RegExpExecArray | null = weekPattern.exec(element);
    while (match !== null) {
      const teacherRaw: string = match[1] === undefined ? '' : match[1].trim();
      const weeksRaw: string = match[2] === undefined ? '' : match[2].trim();
      const oddEvenOutside: string = match[3] === undefined ? '' : match[3].trim();
      const oddEvenInside: string = match[4] === undefined ? '' : match[4].trim();
      let classroom: string = match[5] === undefined ? '' : match[5].trim();
      if (classroom.indexOf('周') === 0) {
        classroom = classroom.substring(1).trim();
      }
      classroom = EasLegacyTimetableParser.cleanClassroom(classroom);
      let oddEvenHint: string = '';
      if (oddEvenOutside.length > 0) {
        oddEvenHint = oddEvenOutside + '周';
      } else if (oddEvenInside.length > 0) {
        oddEvenHint = oddEvenInside + '周';
      }
      const weeks: number[] = EasLegacyTimetableParser.parseWeeksString(weeksRaw, oddEvenHint);
      if (weeks.length > 0) {
        const period: number[] = EasLegacyTimetableParser.resolvePeriod(periodInfo, periodHint);
        const item: EasCourseItem = new EasCourseItem();
        item.name = courseName.trim();
        item.rawName = item.name;
        item.weekNumbers = weeks;
        item.weeks = weeks.join(',');
        item.teacher = EasLegacyTimetableParser.sanitizeTeacher(courseName, teacherRaw);
        item.classroom = classroom;
        item.dayOfWeek = dow;
        item.beginSection = period[0];
        item.sectionCount = period[1];
        out.push(item);
      }
      match = weekPattern.exec(element);
    }
    return out;
  }

  private static normalizeCourseElementParts(items: EasCourseItem[]): EasCourseItem[] {
    if (items.length <= 1) {
      return items;
    }
    let teacherFallback: string = '';
    for (let i: number = 0; i < items.length; i++) {
      if (items[i].teacher.length > 0) {
        teacherFallback = items[i].teacher;
        break;
      }
    }
    const rooms: string[] = [];
    for (let i: number = 0; i < items.length; i++) {
      if (items[i].classroom.length > 0 && rooms.indexOf(items[i].classroom) < 0) {
        rooms.push(items[i].classroom);
      }
    }
    const classroomFallback: string = rooms.length === 1 ? rooms[0] : '';
    for (let i: number = 0; i < items.length; i++) {
      if (items[i].teacher.length === 0 && teacherFallback.length > 0) {
        items[i].teacher = teacherFallback;
      }
      if (items[i].classroom.length === 0 && classroomFallback.length > 0) {
        items[i].classroom = classroomFallback;
      }
    }
    return items;
  }

  private static parseWeeksString(weeksStr: string, oddEvenHint: string): number[] {
    let source: string = weeksStr.replace(/\u00a0/g, ' ').replace(/\s/g, '');
    if (source.length === 0) {
      return [];
    }
    const odd: boolean = oddEvenHint.indexOf('单') >= 0 || source.indexOf('单') >= 0;
    const even: boolean = oddEvenHint.indexOf('双') >= 0 || source.indexOf('双') >= 0;
    source = source.replace(/单周/g, '').replace(/双周/g, '').replace(/单/g, '').replace(/双/g, '')
      .replace(/周/g, '').replace(/[()（）]/g, '');

    const result: Set<number> = new Set<number>();
    const segments: string[] = source.split(/[,，、]/);
    for (let i: number = 0; i < segments.length; i++) {
      const part: string = segments[i].trim();
      if (part.length === 0) {
        continue;
      }
      const range: RegExpExecArray | null = /^(\d+)\s*[-至]\s*(\d+)$/.exec(part);
      if (range !== null) {
        const start: number = Number(range[1]);
        const end: number = Number(range[2]);
        if (start <= 0 || end < start) {
          continue;
        }
        const step: number = odd || even ? 2 : 1;
        let first: number = start;
        if (odd && first % 2 === 0) {
          first++;
        }
        if (even && first % 2 !== 0) {
          first++;
        }
        for (let week: number = first; week <= end; week += step) {
          result.add(week);
        }
      } else {
        const value: number = Number(part);
        if (value > 0 && ((!odd && !even) || (odd && value % 2 === 1) || (even && value % 2 === 0))) {
          result.add(value);
        }
      }
    }
    return Array.from(result).sort((a: number, b: number): number => a - b);
  }

  private static resolvePeriod(raw: string, fallback: number): number[] {
    const normalized: string = raw.replace(/\u00a0/g, '').replace(/\s/g, '')
      .replace(/第/g, '').replace(/节/g, '').replace(/，/g, ',');
    const range: RegExpExecArray | null = /(\d+)\s*[-,]\s*(\d+)/.exec(normalized);
    if (range !== null) {
      const begin: number = Number(range[1]);
      const end: number = Number(range[2]);
      if (begin > 0 && end >= begin) {
        return [begin, end - begin + 1];
      }
    }
    const single: RegExpExecArray | null = /(\d+)/.exec(normalized);
    if (single !== null && Number(single[1]) > 0) {
      return [Number(single[1]), 1];
    }
    return [fallback, 2];
  }

  private static sanitizeTeacher(courseName: string, teacherRaw: string): string {
    let candidate: string = teacherRaw.trim();
    if (candidate.length === 0) {
      return '';
    }
    if (candidate.indexOf('】') >= 0 && candidate.indexOf('【') === 0) {
      candidate = candidate.substring(candidate.indexOf('】') + 1).replace(/^[\/／\s]+/, '');
    }
    if (candidate.indexOf(courseName) === 0) {
      candidate = candidate.substring(courseName.length).replace(/^[\/／\s]+/, '');
    }
    const slash: number = candidate.indexOf('/');
    if (slash >= 0) {
      candidate = candidate.substring(0, slash);
    }
    return candidate.replace(/^第[一二三四五六七八九十0-9]+批/, '')
      .replace(/^[\/／\s]+/, '').trim();
  }

  private static cleanClassroom(raw: string): string {
    return raw.replace(/上课形式\s*\[[^\]]*\]/g, '')
      .replace(/第\s*\d+\s*[-至,，]\s*\d+\s*节/g, '')
      .replace(/^[\/／\s]+/, '').trim();
  }

  private static hasWeekPattern(text: string): boolean {
    return EasLegacyTimetableParser.WEEK_PATTERN.test(text);
  }

  private static findSelect(html: string, selectName: string): string {
    const pattern: RegExp = new RegExp("<select\\b[^>]*\\bname\\s*=\\s*[\\\"']?" + selectName +
      "[\\\"']?[^>]*>([\\s\\S]*?)<\\/select>", 'i');
    const match: RegExpExecArray | null = pattern.exec(html);
    return match === null ? '' : match[1];
  }

  private static currentTermValue(selectHtml: string): string {
    const selectedPattern: RegExp = /<option\b([^>]*)>([\s\S]*?)<\/option>/gi;
    let match: RegExpExecArray | null = selectedPattern.exec(selectHtml);
    let firstValue: string = '';
    while (match !== null) {
      const value: string = EasLegacyTimetableParser.attribute(match[1], 'value').trim();
      if (firstValue.length === 0) {
        firstValue = value;
      }
      if (/\bselected\b/i.test(match[1])) {
        return value;
      }
      match = selectedPattern.exec(selectHtml);
    }
    return firstValue;
  }

  private static findScheduleTable(html: string): string {
    const pattern: RegExp = /<table\b[^>]*class\s*=\s*["'][^"']*addlist_01[^"']*["'][^>]*>[\s\S]*?<\/table>/i;
    const match: RegExpExecArray | null = pattern.exec(html);
    return match === null ? '' : match[0];
  }

  private static tableCells(html: string): string[] {
    const pattern: RegExp = /<(?:td|th)\b[^>]*>([\s\S]*?)<\/(?:td|th)>/gi;
    const out: string[] = [];
    let match: RegExpExecArray | null = pattern.exec(html);
    while (match !== null) {
      out.push(match[1]);
      match = pattern.exec(html);
    }
    return out;
  }

  private static tagContents(html: string, tag: string): string[] {
    const pattern: RegExp = new RegExp('<' + tag + '\\b[^>]*>([\\s\\S]*?)<\\/' + tag + '>', 'gi');
    const out: string[] = [];
    let match: RegExpExecArray | null = pattern.exec(html);
    while (match !== null) {
      out.push(match[1]);
      match = pattern.exec(html);
    }
    return out;
  }

  private static textFromHtml(html: string): string {
    return EasLegacyTimetableParser.decodeHtml(html.replace(/<br\s*\/?\s*>/gi, ' ')
      .replace(/<[^>]+>/g, ' ')).replace(/\u00a0/g, ' ').replace(/\s+/g, ' ').trim();
  }

  private static attribute(attrs: string, name: string): string {
    const quoted: RegExpExecArray | null = new RegExp("\\b" + name +
      "\\s*=\\s*[\\\"']([^\\\"']*)[\\\"']", 'i').exec(attrs);
    if (quoted !== null) {
      return quoted[1];
    }
    const bare: RegExpExecArray | null = new RegExp('\\b' + name + '\\s*=\\s*([^\\s>]+)', 'i').exec(attrs);
    return bare === null ? '' : bare[1];
  }

  private static decodeHtml(raw: string): string {
    return raw.replace(/&nbsp;|&#160;/gi, ' ')
      .replace(/&amp;/gi, '&').replace(/&lt;/gi, '<').replace(/&gt;/gi, '>')
      .replace(/&quot;/gi, '"').replace(/&#39;|&apos;/gi, "'");
  }

  private static termFromValue(rawValue: string, label: string): EasTermItem | undefined {
    const value: string = EasLegacyTimetableParser.decodeHtml(rawValue).replace(/\s+/g, '').trim();
    if (value.length === 0) {
      return undefined;
    }
    let year: string = '';
    let termCode: string = '';
    const dashed: RegExpExecArray | null = /(\d{4}-\d{4})(\d*)/.exec(value);
    if (dashed !== null) {
      year = dashed[1];
      termCode = dashed[2];
    } else {
      const compact: RegExpExecArray | null = /(\d{4})(\d{4})(\d*)/.exec(value);
      if (compact !== null) {
        year = compact[1] + '-' + compact[2];
        termCode = compact[3];
      }
    }
    if (termCode.length === 0) {
      const end: RegExpExecArray | null = /(\d{1,2})$/.exec(value);
      if (end !== null) {
        termCode = end[1];
      }
    }
    if (year.length === 0 || termCode.length === 0) {
      return undefined;
    }
    const item: EasTermItem = new EasTermItem();
    item.yearCode = year;
    item.yearName = year;
    item.termCode = termCode;
    item.termName = EasLegacyTimetableParser.termLabel(label, termCode);
    return item;
  }

  private static termLabel(label: string, code: string): string {
    const compact: string = label.replace(/\s+/g, '').trim();
    if (compact.indexOf('秋') >= 0 || compact.indexOf('第一') >= 0 || compact.indexOf('上学期') >= 0 ||
      code.indexOf('1') === 0) {
      return '秋季学期';
    }
    if (compact.indexOf('春') >= 0 || compact.indexOf('第二') >= 0 || compact.indexOf('下学期') >= 0 ||
      code.indexOf('2') === 0) {
      return '春季学期';
    }
    if (compact.indexOf('夏') >= 0 || compact.indexOf('第三') >= 0 || code.indexOf('3') === 0) {
      return '夏季学期';
    }
    if (compact.indexOf('冬') >= 0 || compact.indexOf('寒') >= 0 || compact.indexOf('第四') >= 0 ||
      code.indexOf('4') === 0) {
      return '冬季学期';
    }
    return '第' + code + '学期';
  }

  private static mergeAdjacent(items: EasCourseItem[]): EasCourseItem[] {
    const sorted: EasCourseItem[] = items.slice().sort((a: EasCourseItem, b: EasCourseItem): number => {
      if (a.dayOfWeek !== b.dayOfWeek) {
        return a.dayOfWeek - b.dayOfWeek;
      }
      if (a.beginSection !== b.beginSection) {
        return a.beginSection - b.beginSection;
      }
      if (a.name !== b.name) {
        return a.name.localeCompare(b.name);
      }
      return EasLegacyTimetableParser.weekKey(a).localeCompare(EasLegacyTimetableParser.weekKey(b));
    });
    const out: EasCourseItem[] = [];
    for (let i: number = 0; i < sorted.length; i++) {
      const current: EasCourseItem = sorted[i];
      const previous: EasCourseItem | undefined = out.length === 0 ? undefined : out[out.length - 1];
      if (previous !== undefined && previous.dayOfWeek === current.dayOfWeek &&
        previous.name === current.name && previous.teacher === current.teacher &&
        previous.classroom === current.classroom &&
        EasLegacyTimetableParser.weekKey(previous) === EasLegacyTimetableParser.weekKey(current) &&
        previous.beginSection + previous.sectionCount === current.beginSection) {
        previous.sectionCount += current.sectionCount;
      } else {
        out.push(current);
      }
    }
    return out;
  }

  private static weekKey(item: EasCourseItem): string {
    return item.weekNumbers.slice().sort((a: number, b: number): number => a - b).join(',');
  }
}
