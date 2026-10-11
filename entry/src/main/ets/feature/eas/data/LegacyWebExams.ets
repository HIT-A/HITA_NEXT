import { normalizeHtmlSpaces } from '../../../common/util/HtmlSpaces';
import { EasExamItem, EasTermItem } from '../model/EasModels';
import { ExamSchedule } from '../ExamSchedule';

class ExamColumns {
  course: number = -1;
  location: number = -1;
  time: number = -1;
}

/** Legacy undergraduate exam tables used by HITA Android and Aura. */
export class LegacyWebExams {
  static parse(html: string, term: EasTermItem, examType: string, campusName: string): EasExamItem[] {
    const clean: string = html.replace(/<!--[\s\S]*?-->/g, '')
      .replace(/<(script|style)\b[^>]*>[\s\S]*?<\/\1>/gi, '');
    const tables: RegExp = /<table\b[^>]*>([\s\S]*?)<\/table>/gi;
    let table: RegExpExecArray | null = tables.exec(clean);
    while (table !== null) {
      const result: EasExamItem[] | undefined = LegacyWebExams.parseTable(
        table[1], term, examType, campusName);
      if (result !== undefined) {
        return result;
      }
      table = tables.exec(clean);
    }
    throw new Error('考试页面无法识别，请稍后重试');
  }

  private static parseTable(html: string, term: EasTermItem, examType: string,
    campusName: string): EasExamItem[] | undefined {
    const rows: RegExp = /<tr\b[^>]*>([\s\S]*?)<\/tr>/gi;
    let row: RegExpExecArray | null = rows.exec(html);
    let columns: ExamColumns | undefined = undefined;
    let columnCount: number = 0;
    let explicitEmpty: boolean = false;
    const items: EasExamItem[] = [];
    while (row !== null) {
      const cells: string[] = LegacyWebExams.cells(row[1]);
      const header: ExamColumns | undefined = LegacyWebExams.columns(cells);
      if (header !== undefined) {
        columns = header;
        columnCount = cells.length;
      } else if (columns !== undefined && cells.length > 0) {
        if (cells.length === 1 && LegacyWebExams.isEmptyLabel(cells[0])) {
          explicitEmpty = true;
        } else {
          const required: number = Math.max(columns.course, columns.location, columns.time);
          if (cells.length < columnCount || required >= cells.length ||
            cells[columns.course].length === 0) {
            throw new Error('考试页面无法识别，请稍后重试');
          }
          const item: EasExamItem = new EasExamItem();
          item.courseName = cells[columns.course];
          item.examLocation = cells[columns.location];
          item.examType = examType;
          item.termName = term.name;
          item.campusName = campusName;
          LegacyWebExams.setDateTime(item, cells[columns.time]);
          items.push(item);
        }
      }
      row = rows.exec(html);
    }
    if (columns === undefined) {
      return undefined;
    }
    if (explicitEmpty && items.length > 0) {
      throw new Error('考试页面无法识别，请稍后重试');
    }
    // A recognized header with no data rows is also an authoritative empty result.
    return items;
  }

  private static columns(cells: string[]): ExamColumns | undefined {
    const out: ExamColumns = new ExamColumns();
    for (let i: number = 0; i < cells.length; i++) {
      const text: string = cells[i].replace(/\s+/g, '');
      if (/^(课程名称|科目名称|考试科目|课程名|科目|课程)$/.test(text)) {
        out.course = i;
      } else if (/^(考试地点|考试场地|考试教室|考场|地点)$/.test(text)) {
        out.location = i;
      } else if (/^(考试具体时间|考试日期时间|考试时间|具体时间)$/.test(text)) {
        out.time = i;
      }
    }
    return out.course >= 0 && out.location >= 0 && out.time >= 0 ? out : undefined;
  }

  private static cells(html: string): string[] {
    const cells: string[] = [];
    const pattern: RegExp = /<(?:td|th)\b[^>]*>([\s\S]*?)<\/(?:td|th)>/gi;
    let cell: RegExpExecArray | null = pattern.exec(html);
    while (cell !== null) {
      cells.push(LegacyWebExams.text(cell[1]));
      cell = pattern.exec(html);
    }
    return cells;
  }

  private static text(html: string): string {
    const raw: string = normalizeHtmlSpaces(html.replace(/<br\s*\/?>/gi, ' ')
      .replace(/<[^>]+>/g, ''));
    return normalizeHtmlSpaces(raw.replace(/&amp;/gi, '&')
      .replace(/&#(x[0-9a-f]+|\d+);/gi, (_match: string, code: string): string => {
        const value: number = code.toLowerCase().startsWith('x') ?
          parseInt(code.substring(1), 16) : parseInt(code, 10);
        return value > 0 && value <= 0x10ffff && !(value >= 0xd800 && value <= 0xdfff) ?
          String.fromCodePoint(value) : '';
      })
      .replace(/&lt;/gi, '<').replace(/&gt;/gi, '>')
      .replace(/&quot;/gi, '"').replace(/&apos;/gi, "'"));
  }

  private static isEmptyLabel(text: string): boolean {
    return /^(暂无(?:考试(?:安排)?|数据|记录)|没有(?:考试(?:安排)?|数据|记录)|无(?:考试(?:安排)?|数据|记录)|未查询到(?:考试(?:安排)?|数据|记录))[。！!.\s]*$/.test(text);
  }

  private static setDateTime(item: EasExamItem, raw: string): void {
    const date: RegExpExecArray | null = /(\d{4})\s*[-/.年]\s*(\d{1,2})\s*[-/.月]\s*(\d{1,2})/.exec(raw);
    if (date !== null) {
      item.examDate = date[1] + '-' + date[2].padStart(2, '0') + '-' + date[3].padStart(2, '0');
    }
    const clocks: RegExpExecArray | null =
      /(\d{1,2})\s*[:：]\s*(\d{2})\s*[-~—–－～至到]+\s*(\d{1,2})\s*[:：]\s*(\d{2})/.exec(raw);
    if (clocks !== null) {
      item.examTime = clocks[1].padStart(2, '0') + ':' + clocks[2] + '-' +
        clocks[3].padStart(2, '0') + ':' + clocks[4];
    }
    if (ExamSchedule.parseRange(item.examDate, item.examTime) === undefined) {
      // Keep unannounced/invalid times visible without creating a fabricated calendar event.
      item.examDate = '';
      item.examTime = raw;
    }
  }
}
