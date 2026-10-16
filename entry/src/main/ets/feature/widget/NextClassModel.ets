import { EasEventItem, EasEventType } from '../../common/model/timetable/TimetableModels';

/** A small, local-only projection; never send accounts or credentials to the launcher. */
export class WidgetCourse {
  id: string = '';
  name: string = '';
  place: string = '';
  teacher: string = '';
  from: number = 0;
  to: number = 0;
}

export class NextClassSnapshot {
  scheduleJson: string = '[]';
  hasTimetable: boolean = false;
  dataState: string = 'loading';
}

export class NextClassView {
  hasCourse: boolean = false;
  title: string = '还没有课表';
  countdown: string = '—';
  countdownUnit: string = '打开应用添加课表';
  startLabel: string = '下一节课';
  place: string = '地点待定';
  teacher: string = '教师待定';
}

export class NextClassModel {
  static snapshot(events: EasEventItem[], hasTimetable: boolean, now: number = Date.now()): NextClassSnapshot {
    const snapshot = new NextClassSnapshot();
    snapshot.hasTimetable = hasTimetable;
    snapshot.dataState = 'ready';
    const courses: WidgetCourse[] = [];
    const ordered = events.filter((event: EasEventItem): boolean => hasTimetable &&
      event.type === EasEventType.CLASS && Number.isFinite(event.from) &&
      Number.isFinite(event.to) && event.from > now && event.to > event.from)
      .sort((a: EasEventItem, b: EasEventItem): number => a.from - b.from || a.id.localeCompare(b.id));
    // Bounded payload. The extension refills it every 30 minutes, independently of the app.
    for (const event of ordered.slice(0, 64)) {
      const course = new WidgetCourse();
      course.id = event.id;
      course.name = NextClassModel.label(event.name, '未命名课程');
      course.place = NextClassModel.label(event.place, '地点待定');
      course.teacher = NextClassModel.label(event.teacher, '教师待定');
      course.from = event.from;
      course.to = event.to;
      courses.push(course);
    }
    snapshot.scheduleJson = JSON.stringify(courses);
    return snapshot;
  }

  static view(scheduleJson: string, hasTimetable: boolean, dataState: string,
    now: number = Date.now()): NextClassView {
    const view = new NextClassView();
    if (dataState === 'loading') {
      view.title = '正在读取课表';
      view.countdownUnit = '稍候即可查看下一节课';
      return view;
    }
    if (dataState === 'error') {
      view.title = '课表暂不可用';
      view.countdownUnit = '打开应用后重试';
      return view;
    }
    if (!hasTimetable) return view;
    let courses: WidgetCourse[] = [];
    try {
      courses = JSON.parse(scheduleJson) as WidgetCourse[];
      if (!Array.isArray(courses)) throw new Error('Invalid schedule');
    } catch (_) {
      view.title = '课表暂不可用';
      view.countdownUnit = '打开应用后重试';
      return view;
    }
    const today = new Date(now);
    const next = courses.filter((course: WidgetCourse): boolean => {
      if (course === null || !Number.isFinite(course.from) || !Number.isFinite(course.to) ||
        course.from <= now || course.to <= course.from) return false;
      const start = new Date(course.from);
      return start.getFullYear() === today.getFullYear() &&
        start.getMonth() === today.getMonth() && start.getDate() === today.getDate();
    })
      .sort((a: WidgetCourse, b: WidgetCourse): number => a.from - b.from)[0];
    if (next === undefined) {
      view.title = '暂无待上课程';
      view.countdownUnit = '打开应用查看课表';
      return view;
    }
    view.hasCourse = true;
    view.title = NextClassModel.label(next.name, '未命名课程');
    view.place = NextClassModel.label(next.place, '地点待定');
    view.teacher = NextClassModel.label(next.teacher, '教师待定');
    const minutes = Math.ceil((next.from - now) / 60000);
    if (minutes < 60) {
      view.countdown = minutes.toString();
      view.countdownUnit = '分钟后上课';
    } else if (minutes < 1440) {
      view.countdown = Math.floor(minutes / 60).toString() + '小时' +
        (minutes % 60 > 0 ? (minutes % 60).toString() + '分' : '');
      view.countdownUnit = '后上课';
    } else {
      view.countdown = Math.floor(minutes / 1440).toString() + '天' +
        (Math.floor(minutes % 1440 / 60) > 0 ? Math.floor(minutes % 1440 / 60).toString() + '小时' : '');
      view.countdownUnit = '后上课';
    }
    view.startLabel = NextClassModel.startLabel(next.from, now);
    return view;
  }

  private static label(value: string, fallback: string): string {
    if (typeof value !== 'string') return fallback;
    const text = value.trim();
    return text.length === 0 || text.toUpperCase() === 'NULL' ? fallback : text.slice(0, 100);
  }

  private static startLabel(from: number, now: number): string {
    const start = new Date(from);
    const today = new Date(now);
    const tomorrow = new Date(now);
    tomorrow.setDate(tomorrow.getDate() + 1);
    const date = start.toDateString() === today.toDateString() ? '今天' :
      (start.toDateString() === tomorrow.toDateString() ? '明天' :
        (start.getMonth() + 1).toString() + '月' + start.getDate().toString() + '日');
    const hour = start.getHours().toString().padStart(2, '0');
    const minute = start.getMinutes().toString().padStart(2, '0');
    return date + ' ' + hour + ':' + minute;
  }
}
