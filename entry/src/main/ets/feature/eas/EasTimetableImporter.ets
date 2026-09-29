/** Imports a legacy EAS timetable into the local timetable database. */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { RdbHelper } from '../../common/db/RdbHelper';
import {
  EasEventItem,
  EasEventType,
  EasSubjectType,
  EasTermSubject,
  EasTimePeriodInDay,
  EasTimetable,
  newId
} from '../../common/model/timetable/TimetableModels';
import { EasCampus, EasSession } from './EasSession';
import { EasSessionStore } from './EasSessionStore';
import { EasDataProvider } from './EasDataProvider';
import { EasCourseItem, EasTermItem } from './model/EasModels';
import { EasApiClient } from './EasApiClient';

const DOMAIN: number = 0x0000;
const TAG: string = 'HitaEasImport';

export class EasImportResult {
  success: boolean = false;
  message: string = '';
  timetable: EasTimetable | undefined = undefined;
  term: EasTermItem | undefined = undefined;
  courseCount: number = 0;
  eventCount: number = 0;
}

export class EasTimetableImporter {
  private static readonly BENBU_TIMES: number[][] = [
    [8, 0, 8, 50], [8, 55, 9, 45], [10, 5, 10, 55], [11, 0, 11, 50],
    [13, 30, 14, 20], [14, 25, 15, 15], [15, 25, 16, 15], [16, 20, 17, 10],
    [17, 20, 18, 10], [18, 30, 19, 20], [19, 30, 20, 20], [20, 30, 21, 20]
  ];

  static async importCurrent(context: common.Context): Promise<EasImportResult> {
    const result: EasImportResult = new EasImportResult();
    try {
      await EasSessionStore.getInstance().init(context);
      const rdb: RdbHelper = RdbHelper.getInstance();
      await rdb.init(context);
      const preferred: EasCampus | undefined = await EasSessionStore.getInstance().loadLastCampus();
      const order: EasCampus[] = [EasCampus.BENBU, EasCampus.WEIHAI, EasCampus.SHENZHEN];
      if (preferred !== undefined) {
        const index: number = order.indexOf(preferred);
        if (index > 0) {
          order.splice(index, 1);
          order.unshift(preferred);
        }
      }
      let session: EasSession | undefined = undefined;
      for (let i: number = 0; i < order.length; i++) {
        const loaded: EasSession | undefined = await EasSessionStore.getInstance().load(order[i]);
        if (loaded !== undefined && loaded.isLogin()) {
          session = loaded;
          break;
        }
      }
      if (session === undefined) {
        result.message = '请先登录统一身份认证';
        return result;
      }
      if (session.campus === EasCampus.BENBU && session.getStudentType() === '2') {
        result.message = '本部研究生课表接口暂未接入';
        return result;
      }
      const provider: EasDataProvider = new EasDataProvider(new EasApiClient());
      hilog.info(DOMAIN, TAG, 'loading terms campus=%{public}s', session.campus.toString());
      const terms: EasTermItem[] = await provider.getAllTerms(session);
      if (terms.length === 0) {
        result.message = '未找到可导入的学期';
        return result;
      }
      let term: EasTermItem = terms[0];
      for (let i: number = 0; i < terms.length; i++) {
        if (terms[i].isCurrent) {
          term = terms[i];
          break;
        }
      }
      result.term = term;
      const courses: EasCourseItem[] = await provider.getTimetableOfTerm(session, term);
      result.courseCount = courses.length;
      if (courses.length === 0) {
        result.message = '课表为空，未导入';
        return result;
      }
      let schedule: EasTimePeriodInDay[] = EasTimetableImporter.scheduleStructure(session.campus);
      if (session.campus === EasCampus.SHENZHEN) {
        try {
          const remoteSchedule: EasTimePeriodInDay[] = await provider.getShenzhenScheduleStructure(session, term);
          if (remoteSchedule.length > 0) {
            schedule = remoteSchedule;
          }
        } catch (e) {
          hilog.warn(DOMAIN, TAG, 'using fallback Shenzhen schedule %{public}s', String(e));
        }
      }
      const timetable: EasTimetable = await EasTimetableImporter.saveCourses(rdb, session, term, courses, schedule);
      result.timetable = timetable;
      const readback: EasEventItem[] = await rdb.getEventsOfTimetable(timetable.id);
      result.eventCount = readback.length;
      hilog.info(DOMAIN, TAG, 'RDB readback timetable=%{public}s subjects/events=%{public}d',
        timetable.id, readback.length);
      if (readback.length === 0) {
        result.message = '课表已请求，但本地写入失败';
        return result;
      }
      result.success = true;
      result.message = '已导入 ' + readback.length.toString() + ' 个课次';
      return result;
    } catch (e) {
      const text: string = e instanceof Error ? e.message : String(e);
      hilog.error(DOMAIN, TAG, 'import failed %{public}s', text);
      result.message = text.length > 0 ? text : '导入课表失败';
      return result;
    }
  }

  private static async saveCourses(rdb: RdbHelper, session: EasSession, term: EasTermItem,
    courses: EasCourseItem[], schedule: EasTimePeriodInDay[]): Promise<EasTimetable> {
    const code: string = session.campus.toString() + ':' + term.getCode();
    let timetable: EasTimetable | undefined = await rdb.getTimetableByEasCode(code);
    if (timetable === undefined) {
      timetable = new EasTimetable();
      timetable.code = code;
    }
    timetable.name = term.name;
    timetable.startTime = EasTimetableImporter.startOfTerm(term);
    let maxWeek: number = 25;
    for (let i = 0; i < courses.length; i++) {
      for (let j = 0; j < courses[i].weekNumbers.length; j++) {
        maxWeek = Math.max(maxWeek, courses[i].weekNumbers[j]);
      }
    }
    timetable.endTime = timetable.startTime + maxWeek * 7 * 24 * 60 * 60 * 1000;
    timetable.createdAt = Date.now();
    timetable.scheduleStructure = schedule.length > 0 ? schedule : EasTimetableImporter.scheduleStructure(session.campus);
    await rdb.saveTimetable(timetable);
    const savedTimetable: EasTimetable | undefined = await rdb.getTimetableById(timetable.id);
    if (savedTimetable === undefined) {
      throw new Error('本地课表数据库写入失败，请重试');
    }
    await rdb.deleteCourseFromTimetable(timetable.id);
    const subjects: EasTermSubject[] = await rdb.getSubjectsOfTimetable(timetable.id);
    let validCourseCount: number = 0;
    let savedEventCount: number = 0;
    for (let i: number = 0; i < courses.length; i++) {
      const course: EasCourseItem = courses[i];
      if (course.dayOfWeek < 1 || course.dayOfWeek > 7 || course.beginSection < 1 ||
        course.sectionCount < 1 || course.beginSection + course.sectionCount - 1 > timetable.scheduleStructure.length) {
        hilog.warn(DOMAIN, TAG, 'skip invalid course name=%{public}s day=%{public}d section=%{public}d count=%{public}d',
          course.name, course.dayOfWeek, course.beginSection, course.sectionCount);
        continue;
      }
      validCourseCount++;
      let subject: EasTermSubject | undefined = undefined;
      for (let j: number = 0; j < subjects.length; j++) {
        if (subjects[j].name === course.name) {
          subject = subjects[j];
          break;
        }
      }
      if (subject === undefined) {
        subject = new EasTermSubject();
        subject.timetableId = timetable.id;
        subject.name = course.name;
        subject.code = course.code;
        subject.type = EasSubjectType.COM_A;
        subjects.push(subject);
        await rdb.saveSubject(subject);
      }
      const weeks: number[] = course.weekNumbers;
      for (let w: number = 0; w < weeks.length; w++) {
        const week: number = weeks[w];
        if (week < 1 || week > maxWeek) continue;
        const timestamps: number[] = timetable.getTimestamps(week, course.dayOfWeek,
          course.beginSection, course.beginSection + course.sectionCount - 1);
        const event: EasEventItem = new EasEventItem();
        event.id = newId();
        event.type = EasEventType.CLASS;
        event.name = course.name;
        event.place = course.classroom;
        event.teacher = course.teacher;
        event.subjectId = subject.id;
        event.timetableId = timetable.id;
        event.from = timestamps[0];
        event.to = timestamps[1];
        event.fromNumber = course.beginSection;
        event.lastNumber = course.beginSection + course.sectionCount - 1;
        await rdb.saveEvent(event);
        savedEventCount++;
      }
    }
    hilog.info(DOMAIN, TAG, 'local save courses=%{public}d valid=%{public}d events=%{public}d',
      courses.length, validCourseCount, savedEventCount);
    if (courses.length > 0 && validCourseCount === 0) {
      throw new Error('课表已获取，但课程节次无法解析');
    }
    if (validCourseCount > 0 && savedEventCount === 0) {
      throw new Error('课表已解析，但本地没有写入任何课次');
    }
    return timetable;
  }

  private static scheduleStructure(campus: EasCampus = EasCampus.BENBU): EasTimePeriodInDay[] {
    if (campus === EasCampus.WEIHAI) {
      return EasTimetable.getWeihaiTimeStructure();
    }
    const source: number[][] = EasTimetableImporter.BENBU_TIMES;
    const out: EasTimePeriodInDay[] = [];
    for (let i: number = 0; i < source.length; i++) {
      const t: number[] = source[i];
      out.push(EasTimePeriodInDay.ofHour(t[0], t[1], t[2], t[3]));
    }
    return out;
  }

  private static startOfTerm(term: EasTermItem): number {
    const yearMatch: RegExpExecArray | null = /(\d{4})-(\d{4})/.exec(term.yearCode);
    const startYear: number = yearMatch === null ? new Date().getFullYear() : Number(yearMatch[1]);
    const endYear: number = yearMatch === null ? startYear + 1 : Number(yearMatch[2]);
    let month: number = 9;
    let year: number = startYear;
    if (term.termCode === '2') {
      month = 3;
      year = endYear;
    } else if (term.termCode === '3') {
      month = 7;
      year = endYear;
    } else if (term.termCode === '4') {
      month = 1;
      year = endYear;
    }
    const date: Date = new Date(year, month - 1, 1, 0, 0, 0, 0);
    const firstDay: number = date.getDay() === 0 ? 7 : date.getDay();
    date.setDate(1 + ((8 - firstDay) % 7) + 7);
    return date.getTime();
  }
}
