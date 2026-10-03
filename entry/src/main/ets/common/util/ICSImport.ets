/**
 * ICSImport.ets — iCal(.ics) 文本解析（RFC5545 子集，与 ICSExport 对称）。
 *
 * 支持：折行、文本转义、DTSTART/DTEND（本地浮动时间、TZID 视为本地、UTC 'Z'、全天 DATE）、
 * DURATION、RRULE（FREQ=DAILY/WEEKLY，INTERVAL/COUNT/UNTIL/BYDAY）、EXDATE、
 * RECURRENCE-ID 单次改期；VALARM 等嵌套组件整体忽略。重复事件按实例展开。
 */

const DAY_MS: number = 24 * 60 * 60 * 1000;
/** 单个重复事件最多展开的实例数，防止无界 RRULE 撑爆本地库。 */
const MAX_OCCURRENCES: number = 400;
/** 无 COUNT/UNTIL 的重复事件最多展开到起始后 1 年。 */
const MAX_HORIZON_MS: number = 366 * DAY_MS;
const BYDAY_CODES: string[] = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

export class IcsEventInstance {
  uid: string = '';
  summary: string = '';
  location: string = '';
  description: string = '';
  from: number = 0;
  to: number = 0;
}

export class IcsCalendarData {
  name: string = '';
  events: IcsEventInstance[] = [];
  /** 全天事件（节假日等）不作为课程导入。 */
  skippedAllDay: number = 0;
}

class IcsProperty {
  name: string = '';
  params: Map<string, string> = new Map<string, string>();
  value: string = '';
}

class IcsDate {
  ms: number = NaN;
  allDay: boolean = false;
}

class IcsRawEvent {
  uid: string = '';
  summary: string = '';
  location: string = '';
  description: string = '';
  from: number = NaN;
  to: number = NaN;
  allDay: boolean = false;
  durationMs: number = -1;
  rrule: string = '';
  exdates: number[] = [];
  recurrenceId: number = NaN;
}

export class IcsParser {
  static parse(text: string): IcsCalendarData {
    const out: IcsCalendarData = new IcsCalendarData();
    const lines: string[] = IcsParser.unfold(text);
    const raws: IcsRawEvent[] = [];
    let current: IcsRawEvent | undefined = undefined;
    let nested: number = 0;
    for (let i: number = 0; i < lines.length; i++) {
      const prop: IcsProperty | undefined = IcsParser.splitProperty(lines[i]);
      if (prop === undefined) {
        continue;
      }
      const upperValue: string = prop.value.trim().toUpperCase();
      if (prop.name === 'BEGIN') {
        if (upperValue === 'VEVENT' && current === undefined) {
          current = new IcsRawEvent();
        } else if (current !== undefined) {
          nested++;
        }
        continue;
      }
      if (prop.name === 'END') {
        if (current !== undefined && nested > 0) {
          nested--;
        } else if (upperValue === 'VEVENT' && current !== undefined) {
          raws.push(current);
          current = undefined;
        }
        continue;
      }
      if (current === undefined) {
        if (prop.name === 'X-WR-CALNAME' && out.name.length === 0) {
          out.name = IcsParser.unescapeText(prop.value).trim();
        }
        continue;
      }
      if (nested > 0) {
        continue;
      }
      IcsParser.applyProperty(current, prop);
    }

    const overridden: Map<string, Set<number>> = new Map<string, Set<number>>();
    for (let i: number = 0; i < raws.length; i++) {
      if (!Number.isNaN(raws[i].recurrenceId) && raws[i].uid.length > 0) {
        const set: Set<number> = overridden.get(raws[i].uid) ?? new Set<number>();
        set.add(IcsParser.minuteKey(raws[i].recurrenceId));
        overridden.set(raws[i].uid, set);
      }
    }
    for (let i: number = 0; i < raws.length; i++) {
      const raw: IcsRawEvent = raws[i];
      if (Number.isNaN(raw.from)) {
        continue;
      }
      if (raw.allDay) {
        out.skippedAllDay++;
        continue;
      }
      let duration: number = 0;
      if (!Number.isNaN(raw.to) && raw.to > raw.from) {
        duration = raw.to - raw.from;
      } else if (raw.durationMs > 0) {
        duration = raw.durationMs;
      } else {
        duration = 60 * 60 * 1000;
      }
      const skip: Set<number> = Number.isNaN(raw.recurrenceId) ?
        (overridden.get(raw.uid) ?? new Set<number>()) : new Set<number>();
      const starts: number[] = Number.isNaN(raw.recurrenceId) ? IcsParser.expand(raw) : [raw.from];
      for (let j: number = 0; j < starts.length; j++) {
        const key: number = IcsParser.minuteKey(starts[j]);
        if (skip.has(key) || raw.exdates.indexOf(key) >= 0) {
          continue;
        }
        const item: IcsEventInstance = new IcsEventInstance();
        item.uid = raw.uid;
        item.summary = raw.summary;
        item.location = raw.location;
        item.description = raw.description;
        item.from = starts[j];
        item.to = starts[j] + duration;
        out.events.push(item);
      }
    }
    out.events.sort((a: IcsEventInstance, b: IcsEventInstance): number => a.from - b.from);
    return out;
  }

  private static applyProperty(ev: IcsRawEvent, prop: IcsProperty): void {
    if (prop.name === 'UID') {
      ev.uid = prop.value.trim();
    } else if (prop.name === 'SUMMARY') {
      ev.summary = IcsParser.unescapeText(prop.value).trim();
    } else if (prop.name === 'LOCATION') {
      ev.location = IcsParser.unescapeText(prop.value).trim();
    } else if (prop.name === 'DESCRIPTION') {
      ev.description = IcsParser.unescapeText(prop.value).trim();
    } else if (prop.name === 'DTSTART') {
      const date: IcsDate = IcsParser.parseDate(prop);
      ev.from = date.ms;
      ev.allDay = date.allDay;
    } else if (prop.name === 'DTEND') {
      ev.to = IcsParser.parseDate(prop).ms;
    } else if (prop.name === 'DURATION') {
      ev.durationMs = IcsParser.parseDuration(prop.value);
    } else if (prop.name === 'RRULE') {
      ev.rrule = prop.value.trim().toUpperCase();
    } else if (prop.name === 'EXDATE') {
      const values: string[] = prop.value.split(',');
      for (let i: number = 0; i < values.length; i++) {
        const one: IcsProperty = new IcsProperty();
        one.params = prop.params;
        one.value = values[i];
        const date: IcsDate = IcsParser.parseDate(one);
        if (!Number.isNaN(date.ms)) {
          ev.exdates.push(IcsParser.minuteKey(date.ms));
        }
      }
    } else if (prop.name === 'RECURRENCE-ID') {
      ev.recurrenceId = IcsParser.parseDate(prop).ms;
    }
  }

  /** 展开 RRULE；不支持的频率只保留首个实例。 */
  private static expand(ev: IcsRawEvent): number[] {
    if (ev.rrule.length === 0) {
      return [ev.from];
    }
    const rule: Map<string, string> = new Map<string, string>();
    const parts: string[] = ev.rrule.split(';');
    for (let i: number = 0; i < parts.length; i++) {
      const eq: number = parts[i].indexOf('=');
      if (eq > 0) {
        rule.set(parts[i].substring(0, eq), parts[i].substring(eq + 1));
      }
    }
    const freq: string = rule.get('FREQ') ?? '';
    if (freq !== 'WEEKLY' && freq !== 'DAILY') {
      return [ev.from];
    }
    const intervalRaw: number = Number(rule.get('INTERVAL') ?? '1');
    const interval: number = Number.isNaN(intervalRaw) || intervalRaw < 1 ? 1 : Math.floor(intervalRaw);
    const countRaw: number = Number(rule.get('COUNT') ?? '');
    const count: number = Number.isNaN(countRaw) || countRaw < 1 ? MAX_OCCURRENCES :
      Math.min(MAX_OCCURRENCES, Math.floor(countRaw));
    let until: number = ev.from + MAX_HORIZON_MS;
    const untilRaw: string = rule.get('UNTIL') ?? '';
    if (untilRaw.length > 0) {
      const p: IcsProperty = new IcsProperty();
      p.value = untilRaw;
      const date: IcsDate = IcsParser.parseDate(p);
      if (!Number.isNaN(date.ms)) {
        until = date.allDay ? date.ms + DAY_MS - 1 : date.ms;
      }
    }

    const start: Date = new Date(ev.from);
    const at = (dayOffset: number): number => new Date(start.getFullYear(), start.getMonth(),
      start.getDate() + dayOffset, start.getHours(), start.getMinutes(), start.getSeconds(), 0).getTime();
    const out: number[] = [];
    if (freq === 'DAILY') {
      for (let k: number = 0; out.length < count; k++) {
        const t: number = at(k * interval);
        if (t > until) {
          break;
        }
        out.push(t);
      }
      return out;
    }

    const startDow: number = start.getDay() === 0 ? 7 : start.getDay();
    const days: number[] = [];
    const byDay: string[] = (rule.get('BYDAY') ?? '').split(',');
    for (let i: number = 0; i < byDay.length; i++) {
      const code: string = byDay[i].replace(/[^A-Z]/g, '');
      const dow: number = BYDAY_CODES.indexOf(code) + 1;
      if (dow > 0 && days.indexOf(dow) < 0) {
        days.push(dow);
      }
    }
    if (days.length === 0) {
      days.push(startDow);
    }
    days.sort((a: number, b: number): number => a - b);
    for (let week: number = 0; out.length < count; week++) {
      let passedUntil: boolean = false;
      for (let i: number = 0; i < days.length && out.length < count; i++) {
        const t: number = at(week * interval * 7 + days[i] - startDow);
        if (t < ev.from) {
          continue;
        }
        if (t > until) {
          passedUntil = true;
          break;
        }
        out.push(t);
      }
      if (passedUntil || week * interval * 7 * DAY_MS > MAX_HORIZON_MS * 2) {
        break;
      }
    }
    return out;
  }

  /** RFC5545 折行：以空格或制表符开头的行续接上一行。 */
  private static unfold(text: string): string[] {
    const raw: string[] = text.replace(/^\uFEFF/, '').split(/\r\n|\n|\r/);
    const out: string[] = [];
    for (let i: number = 0; i < raw.length; i++) {
      const line: string = raw[i];
      if ((line.startsWith(' ') || line.startsWith('\t')) && out.length > 0) {
        out[out.length - 1] += line.substring(1);
      } else if (line.length > 0) {
        out.push(line);
      }
    }
    return out;
  }

  private static splitProperty(line: string): IcsProperty | undefined {
    let inQuote: boolean = false;
    let colon: number = -1;
    for (let i: number = 0; i < line.length; i++) {
      const ch: string = line.charAt(i);
      if (ch === '"') {
        inQuote = !inQuote;
      } else if (ch === ':' && !inQuote) {
        colon = i;
        break;
      }
    }
    if (colon <= 0) {
      return undefined;
    }
    const prop: IcsProperty = new IcsProperty();
    const head: string[] = line.substring(0, colon).split(';');
    prop.name = head[0].trim().toUpperCase();
    for (let i: number = 1; i < head.length; i++) {
      const eq: number = head[i].indexOf('=');
      if (eq > 0) {
        prop.params.set(head[i].substring(0, eq).trim().toUpperCase(),
          head[i].substring(eq + 1).replace(/"/g, '').trim());
      }
    }
    prop.value = line.substring(colon + 1);
    return prop;
  }

  /** TZID 按设备本地时区解释（课表文件绝大多数为 Asia/Shanghai）。 */
  private static parseDate(prop: IcsProperty): IcsDate {
    const out: IcsDate = new IcsDate();
    const m: RegExpExecArray | null =
      /^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?(Z)?)?$/.exec(prop.value.trim().toUpperCase());
    if (m === null) {
      return out;
    }
    const y: number = Number(m[1]);
    const mo: number = Number(m[2]) - 1;
    const d: number = Number(m[3]);
    if (m[4] === undefined || prop.params.get('VALUE') === 'DATE') {
      out.ms = new Date(y, mo, d, 0, 0, 0, 0).getTime();
      out.allDay = true;
      return out;
    }
    const h: number = Number(m[4]);
    const mi: number = Number(m[5]);
    const s: number = m[6] === undefined ? 0 : Number(m[6]);
    out.ms = m[7] === 'Z' ? Date.UTC(y, mo, d, h, mi, s) : new Date(y, mo, d, h, mi, s, 0).getTime();
    return out;
  }

  private static parseDuration(raw: string): number {
    const m: RegExpExecArray | null =
      /^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$/.exec(raw.trim().toUpperCase());
    if (m === null) {
      return -1;
    }
    const n = (v: string | undefined): number => v === undefined ? 0 : Number(v);
    const ms: number = (((n(m[2]) * 7 + n(m[3])) * 24 + n(m[4])) * 60 + n(m[5])) * 60000 + n(m[6]) * 1000;
    return m[1] === '-' ? -1 : ms;
  }

  private static unescapeText(raw: string): string {
    return raw.replace(/\\[nN]/g, '\n').replace(/\\([,;\\])/g, '$1');
  }

  private static minuteKey(ms: number): number {
    return Math.round(ms / 60000);
  }
}
