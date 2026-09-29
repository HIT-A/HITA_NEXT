/**
 * TimetableLocalDemo.ets — 本地课表演示/自检（M3 开发用）：
 *  - 运行时验证 RdbHelper（timetable/subject/events 三表 写→读）
 *  - 生成一份演示课表数据，作为 Canvas 周视图的离网数据源
 */
import { common } from '@kit.AbilityKit';
import { RdbHelper } from '../../../common/db/RdbHelper';
import {
  EasEventItem,
  EasEventType,
  EasSubjectType,
  EasTermSubject,
  EasTimetable,
  WEEK_MILLIS,
  DAY_MILLIS,
  EasTimeInDay
} from '../../../common/model/timetable/TimetableModels';

/** 一周中单次课程槽位（周内第 dow 天、第 start 节起 last 节）。 */
class DemoSlot {
  dow: number = 1;
  start: number = 1;
  last: number = 1;
  place: string = '';
  teacher: string = '';

  constructor(dow: number, start: number, last: number, place: string, teacher: string) {
    this.dow = dow;
    this.start = start;
    this.last = last;
    this.place = place;
    this.teacher = teacher;
  }
}

/** 演示数据组装结果。 */
export class DemoBundle {
  timetable: EasTimetable = new EasTimetable();
  subjects: EasTermSubject[] = [];
  events: EasEventItem[] = [];
}

export class TimetableLocalDemo {
  static readonly DEMO_CODE: string = 'LOCAL_DEMO_001';
  static readonly DEMO_NAME: string = '演示课表';

  /** 造演示课表：起点=本周周一 -2 周，跨度 12 周。 */
  static async runSelfCheck(context: common.Context): Promise<string> {
    const rdb: RdbHelper = RdbHelper.getInstance();
    await rdb.init(context);
    const existed: EasTimetable | undefined = await rdb.getTimetableByEasCode(TimetableLocalDemo.DEMO_CODE);
    if (existed !== undefined) {
      await rdb.deleteTimetablesInIds([existed.id]);
    }
    const data = TimetableLocalDemo.build();
    const extras: EasEventItem[] = TimetableLocalDemo.buildTodayExtras(data.timetable);
    await rdb.saveTimetable(data.timetable);
    for (let i = 0; i < data.subjects.length; i++) {
      await rdb.saveSubject(data.subjects[i]);
    }
    const allEvents: EasEventItem[] = data.events.concat(extras);
    for (let i = 0; i < allEvents.length; i++) {
      await rdb.saveEvent(allEvents[i]);
    }
    // 读回校验
    const all: EasTimetable[] = await rdb.getTimetables();
    const subjects: EasTermSubject[] = await rdb.getSubjectsOfTimetable(data.timetable.id);
    const events: EasEventItem[] = await rdb.getEventsOfTimetable(data.timetable.id);
    const first: EasTimetable | undefined = await rdb.getTimetableByEasCode(TimetableLocalDemo.DEMO_CODE);
    if (first === undefined) {
      return '自检失败：课表读回为空';
    }
    return 'RDB 自检通过：课表=' + all.length.toString() +
      ' 演示科目=' + subjects.length.toString() +
      ' 课程实例=' + events.length.toString() +
      ' | 第1节 ' + first.scheduleStructure[0].toString() +
      ' | 周末 ' + TimetableLocalDemo.weekLabel(first);
  }

  /** 造“今天/明天”的事件（时间线页演示用），返回追加列表。 */
  static buildTodayExtras(timetable: EasTimetable): EasEventItem[] {
    const out: EasEventItem[] = [];
    const at = (dayOffset: number, h: number, m: number): number => {
      const d: Date = new Date(Date.now());
      d.setDate(d.getDate() + dayOffset);
      d.setHours(h, m, 0, 0);
      return d.getTime();
    };
    const exam: EasEventItem = new EasEventItem();
    exam.type = EasEventType.EXAM;
    exam.name = '高数期中复习（考试准备）';
    exam.place = 'H-201';
    exam.teacher = '';
    exam.timetableId = timetable.id;
    exam.from = at(0, 9, 0);
    exam.to = at(0, 11, 0);
    exam.color = 0xFFD93025;
    out.push(exam);

    const meet: EasEventItem = new EasEventItem();
    meet.type = EasEventType.OTHER;
    meet.name = '课程设计小组会';
    meet.place = '在线会议';
    meet.timetableId = timetable.id;
    meet.from = at(0, 19, 0);
    meet.to = at(0, 20, 30);
    meet.color = 0xFF5C6BC0;
    out.push(meet);

    const tag: EasEventItem = new EasEventItem();
    tag.type = EasEventType.TAG;
    tag.name = '归还图书馆图书';
    tag.place = '图书馆';
    tag.timetableId = timetable.id;
    tag.from = at(1, 12, 30);
    tag.to = at(1, 13, 0);
    tag.color = 0xFF26A69A;
    out.push(tag);

    const gym: EasEventItem = new EasEventItem();
    gym.type = EasEventType.OTHER;
    gym.name = '健身';
    gym.place = '体育馆';
    gym.timetableId = timetable.id;
    gym.from = at(1, 18, 0);
    gym.to = at(1, 19, 0);
    gym.color = 0xFFEF8E5A;
    out.push(gym);
    return out;
  }

  static weekLabel(t: EasTimetable): string {
    const monday: number = EasTimetable.mondayMsOf(Date.now());
    const w: number = t.getWeekNumber(monday);
    return w > 0 ? '本周=第' + w.toString() + '周' : '（学期未开始）';
  }

  /** 若已存在演示课表则返回之，否则自检后返回新建。 */
  static async getOrCreateDemo(context: common.Context): Promise<EasTimetable | undefined> {
    const rdb: RdbHelper = RdbHelper.getInstance();
    await rdb.init(context);
    const existed: EasTimetable | undefined = await rdb.getTimetableByEasCode(TimetableLocalDemo.DEMO_CODE);
    if (existed !== undefined) {
      return existed;
    }
    await TimetableLocalDemo.runSelfCheck(context);
    return await RdbHelper.getInstance().getTimetableByEasCode(TimetableLocalDemo.DEMO_CODE);
  }

  /** 构造演示数据（内存，未落库前用）。 */
  static build(): DemoBundle {
    const bundle: DemoBundle = new DemoBundle();
    const timetable: EasTimetable = new EasTimetable();
    timetable.name = TimetableLocalDemo.DEMO_NAME;
    timetable.code = TimetableLocalDemo.DEMO_CODE;
    const mondayNow: number = EasTimetable.mondayMsOf(Date.now());
    timetable.startTime = mondayNow - 2 * WEEK_MILLIS;
    timetable.endTime = timetable.startTime + 12 * WEEK_MILLIS;
    timetable.createdAt = Date.now();

    // 三个科目
    const subA: EasTermSubject = new EasTermSubject();
    subA.timetableId = timetable.id;
    subA.name = '高等数学A';
    subA.type = EasSubjectType.COM_A;
    subA.credit = 5;
    subA.field = '科学技术';
    subA.school = '理学院';
    subA.code = 'MATH101';
    subA.color = 0xFF5C6BC0;

    const subB: EasTermSubject = new EasTermSubject();
    subB.timetableId = timetable.id;
    subB.name = '数据结构';
    subB.type = EasSubjectType.COM_B;
    subB.credit = 3.5;
    subB.field = '计算机';
    subB.school = '计算机学院';
    subB.code = 'CS201';
    subB.color = 0xFF26A69A;

    const subC: EasTermSubject = new EasTermSubject();
    subC.timetableId = timetable.id;
    subC.name = '大学英语';
    subC.type = EasSubjectType.OPT_A;
    subC.credit = 2;
    subC.field = '人文艺术';
    subC.school = '外国语学院';
    subC.code = 'EN102';
    subC.color = 0xFFEF8E5A;

    // 每周课表（周次 1..10）
    const events: EasEventItem[] = [];
    const slots: DemoSlot[] = [
      new DemoSlot(1, 1, 2, 'H-201', '李教授'),   // 高数
      new DemoSlot(3, 5, 2, 'H-201', '李教授'),   // 高数
      new DemoSlot(2, 3, 2, 'T-306', '王老师'),   // 数据结构
      new DemoSlot(5, 7, 2, 'T-306', '王老师'),   // 数据结构
      new DemoSlot(4, 9, 2, 'F-105', '陈老师')    // 英语
    ];
    for (let week = 1; week <= 10; week++) {
      const subjects: EasTermSubject[] = [subA, subA, subB, subB, subC];
      for (let s = 0; s < slots.length; s++) {
        const sl = slots[s];
        const ev: EasEventItem = new EasEventItem();
        ev.type = EasEventType.CLASS;
        ev.name = subjects[s].name;
        ev.subjectId = subjects[s].id;
        ev.timetableId = timetable.id;
        ev.place = sl.place;
        ev.teacher = sl.teacher;
        ev.fromNumber = sl.start;
        ev.lastNumber = sl.last;
        const ts: number[] = timetable.getTimestamps(week, sl.dow, sl.start, sl.start + sl.last - 1);
        ev.from = ts[0];
        ev.to = ts[1];
        ev.color = subjects[s].color;
        events.push(ev);
      }
    }
    // 一条非课程备忘（第5周 周五 中午）
    const memo: EasEventItem = new EasEventItem();
    memo.type = EasEventType.OTHER;
    memo.name = '交课程设计';
    memo.place = '在线';
    memo.timetableId = timetable.id;
    const memoDay: number = timetable.startTime + (5 - 1) * WEEK_MILLIS + (5 - 1) * DAY_MILLIS;
    memo.from = memoDay + new EasTimeInDay(12, 30).toMills();
    memo.to = memoDay + new EasTimeInDay(13, 0).toMills();
    memo.color = 0xFFEF5350;
    events.push(memo);

    bundle.timetable = timetable;
    bundle.subjects = [subA, subB, subC];
    bundle.events = events;
    return bundle;
  }
}
