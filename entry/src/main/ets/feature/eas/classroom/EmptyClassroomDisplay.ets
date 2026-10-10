import { EasTimePeriodInDay } from '../../../common/model/timetable/TimetableModels';
import { EasTermItem } from '../model/EasModels';
import { ClassroomAvailability, ClassroomRoom, EmptyClassroomData } from './EmptyClassroomData';

export class ClassroomScheduleRow {
  number: number = 0;
  time: string = '';
  state: string = '';
}

/** HITA Android 3.0.0 EmptyClassroomActivity / DetailFragment presentation rules. */
export class EmptyClassroomDisplay {
  static readonly PICKER_WEEKS: number = 20;

  static state(room: ClassroomRoom, day: number, current: number, hasSchedule: boolean): string {
    if (!hasSchedule) {
      return '未知';
    }
    const period: number = current / 10;
    if (current % 10 === 0 && period >= 1) {
      const state: ClassroomAvailability = EmptyClassroomData.availability(room, day, period, period);
      if (state === ClassroomAvailability.OCCUPIED) {
        return '被占';
      }
      if (state === ClassroomAvailability.UNKNOWN) {
        return '未知';
      }
    }
    const next: number = Math.floor(period) + 1;
    if (next <= room.periodCount) {
      const state: ClassroomAvailability = EmptyClassroomData.availability(room, day, next, next);
      if (state === ClassroomAvailability.OCCUPIED) {
        return '将占';
      }
      if (state === ClassroomAvailability.UNKNOWN) {
        return '未知';
      }
    }
    return '空闲';
  }

  static rows(room: ClassroomRoom, day: number, schedule: EasTimePeriodInDay[]): ClassroomScheduleRow[] {
    return schedule.map((time: EasTimePeriodInDay, index: number): ClassroomScheduleRow => {
      const row: ClassroomScheduleRow = new ClassroomScheduleRow();
      row.number = index + 1;
      row.time = time.from.toString() + ' - ' + time.to.toString();
      const state: ClassroomAvailability = EmptyClassroomData.availability(room, day, row.number, row.number);
      row.state = state === ClassroomAvailability.FREE ? '空' :
        state === ClassroomAvailability.OCCUPIED ? '占用' : '未知';
      return row;
    });
  }

  static termName(term: EasTermItem): string {
    const source: string = term.termName + ' ' + term.name;
    const seasons: string[] = ['春', '夏', '秋', '冬', '寒'];
    const names: string[] = ['春季', '夏季', '秋季', '冬季', '寒假'];
    let season: string = '';
    for (let i: number = 0; i < seasons.length; i++) {
      if (source.indexOf(seasons[i]) >= 0) {
        season = names[i];
        break;
      }
    }
    if (season.length === 0) {
      const defaults: string[] = ['', '秋季', '春季', '夏季', '冬季'];
      season = defaults[Number(term.termCode)] || term.termName.trim();
    }
    return ((term.yearCode.trim() || term.yearName.trim()) + ' ' + season).trim();
  }

  static currentYearTerms(terms: EasTermItem[], now: Date = new Date()): EasTermItem[] {
    const year: string = now.getFullYear().toString();
    const filtered: EasTermItem[] = terms.filter((term: EasTermItem): boolean =>
      (term.yearCode + term.yearName + term.name).indexOf(year) >= 0);
    return filtered.length > 0 ? filtered : terms;
  }

  static pickerTerms(terms: EasTermItem[], grade: string, now: Date = new Date()): EasTermItem[] {
    const match: RegExpMatchArray | null = grade.match(/20\d{2}/);
    const enrollment: number = match === null ? now.getFullYear() - 3 : Number(match[0]);
    const current: EasTermItem | undefined = terms.find((term: EasTermItem): boolean => term.isCurrent);
    const end: number = current === undefined ? now.getFullYear() - (now.getMonth() < 7 ? 1 : 0) :
      parseInt(current.yearCode, 10);
    const filtered: EasTermItem[] = terms.filter((term: EasTermItem): boolean => {
      const year: number = parseInt(term.yearCode, 10);
      return year >= enrollment && (match === null || year <= end);
    });
    const selected: EasTermItem[] = filtered.length > 0 ? filtered : terms.slice();
    return selected.sort((a: EasTermItem, b: EasTermItem): number =>
      b.yearCode.localeCompare(a.yearCode) || b.termCode.localeCompare(a.termCode));
  }
}
