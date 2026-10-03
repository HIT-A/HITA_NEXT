/**
 * ICSExport.ets — 手写 iCal(.ics) 文本导出（RFC5545 最小子集，替代 HITA_X iCal4j+VAlarm）。
 *
 * 语义：DTSTART/DTEND 以本地时间 YYYYMMDDTHHMMSS（floating，无 TZID）；
 * 转义逗号/分号/反斜杠/换行；UID 用事件 id；可为每条附加 DESCRIPTION。
 * ⚠️ 校历显示（Recurrence）由各校区的“每周课程”按具体日期展开导出（events 已按实例展开）。
 */
import { EasEventItem, EasEventType } from '../model/timetable/TimetableModels';

function pad2(n: number): string {
  return n < 10 ? '0' + n.toString() : n.toString();
}

function fmt(ms: number): string {
  const d: Date = new Date(ms);
  return d.getFullYear().toString() +
    pad2(d.getMonth() + 1) + pad2(d.getDate()) + 'T' +
    pad2(d.getHours()) + pad2(d.getMinutes()) + pad2(d.getSeconds());
}

function esc(s: string): string {
  if (s === undefined || s === null) {
    return '';
  }
  let out: string = s;
  out = out.replace(/\\/g, '\\\\');
  out = out.replace(/;/g, '\\;');
  out = out.replace(/,/g, '\\,');
  out = out.replace(/\n/g, '\\n');
  return out;
}

/** 截断超长行（RFC5545 建议 ≤75 八位字节；文本行直接截断，不影响导入）。 */
function fold(line: string): string {
  return line.length <= 200 ? line : line.substring(0, 200);
}

export class IcsExporter {
  /** 由事件列表生成 .ics 文本。 */
  static fromEvents(events: EasEventItem[], calendarName: string): string {
    const lines: string[] = [];
    lines.push('BEGIN:VCALENDAR');
    lines.push('VERSION:2.0');
    lines.push('PRODID:-//HitaNEXT//HITA HarmonyOS NEXT//CN');
    lines.push('CALSCALE:GREGORIAN');
    lines.push('X-WR-CALNAME:' + esc(calendarName));
    for (let i = 0; i < events.length; i++) {
      const ev: EasEventItem = events[i];
      if (ev.from <= 0 || ev.to <= ev.from) {
        continue;
      }
      if (ev.type === EasEventType.TAG && ev.name.length === 0) {
        continue;
      }
      lines.push('BEGIN:VEVENT');
      lines.push('UID:' + (ev.id.length > 0 ? ev.id : 'ev-' + i.toString()) + '@hitanext');
      lines.push('DTSTART:' + fmt(ev.from));
      lines.push('DTEND:' + fmt(ev.to));
      lines.push('SUMMARY:' + esc(ev.name.length > 0 ? ev.name : '事件'));
      if (ev.place.length > 0) {
        lines.push('LOCATION:' + esc(ev.place));
      }
      if (ev.teacher.length > 0) {
        lines.push('DESCRIPTION:' + esc('教师：' + ev.teacher));
      }
      lines.push('END:VEVENT');
    }
    lines.push('END:VCALENDAR');
    return lines.join('\r\n');
  }
}
