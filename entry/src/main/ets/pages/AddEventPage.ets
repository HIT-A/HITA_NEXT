/**
 * AddEventPage.ets — 新建/编辑事件（HITA_X ui/event/add 语义 → ArkUI 表单）。
 *
 * Both timetable entry points share single-date/calendar and weekly course creation.
 * Weekly occurrences are committed atomically; editing still changes one occurrence only.
 */
import { common } from '@kit.AbilityKit';
import { CourseDateSelection } from '../feature/timetable/CourseDateSelection';
import { CourseWeekPicker } from '../feature/timetable/views/CourseWeekPicker';
import { HeaderBackButton } from '../common/components/HeaderBackButton';
import { ImmersiveHeader } from '../common/components/ImmersiveHeader';
import { CompatibleMaterialModifier } from '../common/theme/CompatibleMaterialModifier';
import { STATUS_BAR_INSET_FALLBACK } from '../common/theme/StatusBarInset';
import { RdbHelper } from '../common/db/RdbHelper';
import { TimetableResolver } from '../feature/timetable/data/TimetableResolver';
import { TimetableSelectionStore } from '../feature/timetable/data/TimetableSelectionStore';
import {
  EasEventItem,
  EasEventType,
  EasSubjectType,
  EasTermSubject,
  EasTimetable,
  newId
} from '../common/model/timetable/TimetableModels';

const DAY_MS: number = 24 * 60 * 60 * 1000;
const MAX_DAY_OFFSET: number = 370;
const TYPE_ITEMS: string[] = ['日程', '课程', '考试', '备忘'];

@Component
export struct EventEditorForm {
  /**
   * The editor is also used as a bottom sheet from TimetableDetailPage.
   * Route parameters remain supported for the standalone timeline flow.
   */
  @Prop eventId: string = '';
  @Prop targetTimetableId: string = '';
  @Prop initialType: string = '';
  @Prop sheetMode: boolean = false;
  onCancel: () => void = () => {};
  onSaved: (event: EasEventItem, occurrences: EasEventItem[]) => void =
    (_event: EasEventItem, _occurrences: EasEventItem[]) => {};

  @State courseEntry: boolean = false;
  @State timeMode: number = 0;
  @State fromPeriod: number = 0;
  @State toPeriod: number = 0;
  @State selectedSubjectId: string = '';
  @State pickingExisting: boolean = false;
  @State typeIdx: number = 0;
  @State name: string = '';
  @State place: string = '';
  @State teacher: string = '';
  @State dayOffset: number = 0;
  @State dateMode: number = 0;
  @State selectedWeeks: number[] = [];
  @State selectedWeekdays: number[] = [];
  @State weekChoices: number[] = [];
  @State choosingWeeks: boolean = false;
  @State courseTimetable: EasTimetable | undefined = undefined;
  private initialWeek: number = 0;
  private todayBase: number = new Date(new Date().setHours(0, 0, 0, 0)).getTime();
  @State hour: number = 14;
  @State minute: number = 0;
  @State endHour: number = 15;
  @State endMinute: number = 0;
  @State hint: string = '';
  @State saved: boolean = false;
  @State loading: boolean = true;
  @State loadFailed: boolean = false;
  @State saving: boolean = false;
  private editId: string = '';
  private timetableId: string = '';
  private subjectId: string = '';
  private editorActive: boolean = false;

  async aboutToAppear(): Promise<void> {
    this.editorActive = true;
    try {
      await this.loadEvent();
    } catch (_) {
      this.loadFailed = true;
      this.hint = '读取失败，请关闭后重试';
    } finally {
      this.loading = false;
    }
  }

  aboutToDisappear(): void {
    this.editorActive = false;
  }

  private async loadEvent(): Promise<void> {
    const params: Object | undefined = this.getUIContext().getRouter().getParams();
    let id: string = this.eventId;
    this.timetableId = this.targetTimetableId;
    let routeType: string = this.initialType;
    let offsetRaw: string = '';
    if (!this.sheetMode && params !== undefined && params !== null) {
      const record = params as Record<string, string>;
      if (id.length === 0) {
        id = record['id'] === undefined ? '' : record['id'] as string;
      }
      if (this.timetableId.length === 0) {
        this.timetableId = record['timetableId'] === undefined ? '' : record['timetableId'] as string;
      }
      if (routeType.length === 0) {
        routeType = record['type'] === undefined ? '' : record['type'] as string;
      }
      offsetRaw = record['offset'] === undefined ? '' : record['offset'] as string;
      this.initialWeek = Number(record['week'] || '0');
    }
    this.courseEntry = routeType === 'CLASS';
    if (id.length === 0 && routeType.length > 0) {
      // 新建时按调用方指定类型初始化（CLASS=课程 / EXAM=考试；缺省为日程）。
      this.typeIdx = EventEditorForm.idxOf(EventEditorForm.typeFromName(routeType));
    }
    if (id.length === 0) {
      // 新建：若从时间线某天进入，沿用该天（offset 参数）
      if (offsetRaw.length > 0) {
        const n: number = Number(offsetRaw);
        if (!Number.isNaN(n)) {
          let off: number = n;
          if (off < -MAX_DAY_OFFSET) {
            off = -MAX_DAY_OFFSET;
          }
          if (off > MAX_DAY_OFFSET) {
            off = MAX_DAY_OFFSET;
          }
          this.dayOffset = off;
        }
      }
      if (this.typeIdx === 1) {
        this.timeMode = 1;
        await this.loadCourseTimetable();
      }
      return;
    }
    this.editId = id;
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    await RdbHelper.getInstance().init(ctx);
    const ev: EasEventItem | undefined = await RdbHelper.getInstance().getEventById(id);
    if (ev === undefined) {
      this.loadFailed = true;
      this.hint = '这条记录已不存在，请关闭后刷新列表';
      return;
    }
    this.name = ev.name;
    this.place = ev.place;
    this.teacher = ev.teacher;
    this.timetableId = ev.timetableId.length > 0 ? ev.timetableId : this.timetableId;
    this.subjectId = ev.subjectId;
    this.typeIdx = EventEditorForm.idxOf(ev.type);
    const d: Date = new Date(ev.from);
    this.hour = d.getHours();
    this.minute = d.getMinutes();
    const end: Date = new Date(ev.to);
    this.endHour = end.getHours();
    this.endMinute = end.getMinutes();
    const todayMidnight: number = new Date(new Date().setHours(0, 0, 0, 0)).getTime();
    const fromMidnight: number = new Date(new Date(ev.from).setHours(0, 0, 0, 0)).getTime();
    // Editing an older record must not silently move its original date.
    this.dayOffset = Math.round((fromMidnight - todayMidnight) / DAY_MS);
  }

  private static pad2(n: number): string {
    return n < 10 ? '0' + n.toString() : n.toString();
  }

  private dateText(): string {
    const d: Date = new Date(this.todayBase + this.dayOffset * DAY_MS);
    return d.getFullYear().toString() + '-' + EventEditorForm.pad2(d.getMonth() + 1) + '-' +
      EventEditorForm.pad2(d.getDate());
  }

  /** Native month calendar instead of the rolling year/month/day selector. */
  private chooseDate(): void {
    CalendarPickerDialog.show({
      selected: new Date(this.todayBase + this.dayOffset * DAY_MS),
      onAccept: (date: Date) => {
        const selected: Date = new Date(date.getFullYear(), date.getMonth(), date.getDate());
        this.dayOffset = Math.round((selected.getTime() - this.todayBase) / DAY_MS);
      }
    });
  }

  private async loadCourseTimetable(initializeSelection: boolean = true): Promise<void> {
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    const rdb: RdbHelper = RdbHelper.getInstance();
    await rdb.init(ctx);
    let timetable: EasTimetable | undefined;
    if (this.timetableId.length > 0) {
      timetable = await rdb.getTimetableById(this.timetableId);
    } else {
      const selection: TimetableSelectionStore = TimetableSelectionStore.getInstance();
      await selection.init(ctx);
      const selectedId: string = await selection.load();
      timetable = selectedId.length > 0 ? await rdb.getTimetableById(selectedId) : undefined;
      if (timetable === undefined) timetable = await TimetableResolver.getForDisplay(rdb);
    }
    this.courseTimetable = timetable;
    if (timetable === undefined) {
      this.hint = '请先新建或导入课表，再添加课程';
      return;
    }
    this.timetableId = timetable.id;
    this.weekChoices = CourseDateSelection.numbers(Math.max(CourseDateSelection.weekCount(timetable),
      initializeSelection ? 0 : this.weekChoices.length));
    if (initializeSelection && this.selectedWeeks.length === 0 && this.weekChoices.length > 0) {
      const week: number = this.initialWeek > 0 ? this.initialWeek : timetable.getWeekNumber(Date.now());
      this.selectedWeeks = [Math.max(1, Math.min(this.weekChoices.length, week))];
    }
    if (initializeSelection && this.selectedWeekdays.length === 0) {
      const day: number = new Date(this.todayBase + this.dayOffset * DAY_MS).getDay();
      this.selectedWeekdays = [day === 0 ? 7 : day];
    }
  }

  private selectWeekPreset(mode: number): void {
    this.selectedWeeks = this.weekChoices.filter((week: number): boolean =>
      mode === 0 || (mode === 1 && week % 2 === 1) || (mode === 2 && week % 2 === 0));
  }

  private usesPeriods(): boolean { return this.typeIdx === 1 && this.editId.length === 0 && this.timeMode === 1; }

  private selectedTime(): number[] {
    if (!this.usesPeriods()) return [this.hour * 60 + this.minute, this.endHour * 60 + this.endMinute];
    const periods = this.courseTimetable?.scheduleStructure;
    if (periods === undefined || this.fromPeriod < 1 || this.toPeriod < this.fromPeriod ||
      this.toPeriod > periods.length) return [-1, -1];
    const start = periods[this.fromPeriod - 1].from;
    const end = periods[this.toPeriod - 1].to;
    return [start.hour * 60 + start.minute, end.hour * 60 + end.minute];
  }

  private static minuteLabel(value: number): string {
    return value < 0 ? '未选择' : EventEditorForm.pad2(Math.floor(value / 60)) + ':' + EventEditorForm.pad2(value % 60);
  }

  private startLabel(): string { return EventEditorForm.minuteLabel(this.selectedTime()[0]); }
  private endLabel(): string { return EventEditorForm.minuteLabel(this.selectedTime()[1]); }

  private choosePeriod(start: boolean): void {
    const timetable = this.courseTimetable;
    if (timetable === undefined || timetable.scheduleStructure.length === 0) return;
    this.getUIContext().showTextPickerDialog({
      range: timetable.scheduleStructure.map((period, index: number): string =>
        '第 ' + (index + 1).toString() + ' 节  ' + EventEditorForm.minuteLabel(period.from.hour * 60 + period.from.minute) +
        '–' + EventEditorForm.minuteLabel(period.to.hour * 60 + period.to.minute)),
      selected: Math.max(0, (start ? this.fromPeriod : this.toPeriod) - 1),
      canLoop: false,
      onAccept: (result: TextPickerResult) => {
        if (typeof result.index !== 'number' || result.index < 0 || result.index >= timetable.scheduleStructure.length) return;
        if (start) {
          this.fromPeriod = result.index + 1;
          if (this.toPeriod < this.fromPeriod) this.toPeriod = this.fromPeriod;
        } else {
          this.toPeriod = result.index + 1;
          if (this.fromPeriod === 0 || this.fromPeriod > this.toPeriod) this.fromPeriod = this.toPeriod;
        }
        this.hint = '';
      }
    });
  }

  private selectExistingCourse(event: EasEventItem): void {
    this.selectedSubjectId = event.subjectId;
    this.name = event.name;
    this.place = event.place;
    this.teacher = event.teacher;
    this.hint = '';
  }

  private async chooseExistingCourse(): Promise<void> {
    if (this.pickingExisting || this.loading || this.saving) return;
    this.pickingExisting = true;
    try {
      const rdb = RdbHelper.getInstance();
      const subjects = await rdb.getSubjectsOfTimetable(this.timetableId);
      const events = await rdb.getEventsOfTimetable(this.timetableId);
      const choices: EasEventItem[] = [];
      const seen: Set<string> = new Set<string>();
      for (const event of events) {
        if (event.type !== EasEventType.CLASS || !subjects.some((subject: EasTermSubject): boolean => subject.id === event.subjectId)) continue;
        const key: string = JSON.stringify([event.subjectId, event.name, event.place, event.teacher]);
        if (seen.has(key)) continue;
        seen.add(key);
        choices.push(event);
      }
      for (const subject of subjects) {
        if (choices.some((event: EasEventItem): boolean => event.subjectId === subject.id)) continue;
        const event = new EasEventItem();
        event.subjectId = subject.id;
        event.name = subject.name;
        choices.push(event);
      }
      choices.sort((a: EasEventItem, b: EasEventItem): number => a.name.localeCompare(b.name));
      if (!this.editorActive) return;
      if (choices.length === 0) { this.hint = '当前课表还没有课程，请手动填写'; return; }
      this.getUIContext().showTextPickerDialog({
        range: choices.map((event: EasEventItem): string => [event.name, event.place, event.teacher]
          .filter((value: string): boolean => value.length > 0).join(' · ')),
        selected: Math.max(0, choices.findIndex((event: EasEventItem): boolean => event.subjectId === this.selectedSubjectId)),
        canLoop: false,
        onAccept: (result: TextPickerResult) => {
          if (typeof result.index === 'number' && choices[result.index] !== undefined) this.selectExistingCourse(choices[result.index]);
        }
      });
    } catch (_) { this.hint = '读取已有课程失败，请重试'; }
    finally { this.pickingExisting = false; }
  }

  private validationHint(): string {
    if (this.name.trim().length === 0) return this.typeIdx === 1 ? '请填写课程名称' : '请填写名称';
    if (this.typeIdx === 1 && this.editId.length === 0) {
      const timetable = this.courseTimetable;
      if (timetable === undefined) return '请先新建或导入课表';
      if (this.dateMode === 1) {
        try { CourseDateSelection.weeklyDates(timetable, this.selectedWeeks, this.selectedWeekdays, this.weekChoices.length); }
        catch (error) { return error instanceof Error ? error.message : '请检查日期选择'; }
      } else if (this.todayBase + this.dayOffset * DAY_MS < EasTimetable.mondayMsOf(timetable.startTime)) {
        return '日期早于开学日期，请选择本学期内或之后的日期';
      }
    }
    const time = this.selectedTime();
    if (time[0] < 0 || time[1] < 0) return '请选择上课节次';
    if (time[1] <= time[0]) return '结束时间必须晚于开始时间';
    return '';
  }

  private canSave(): boolean {
    return !this.loading && !this.loadFailed && !this.saving && !this.saved && !this.pickingExisting &&
      this.validationHint().length === 0;
  }

  private extensionHint(): string {
    const timetable = this.courseTimetable;
    if (timetable === undefined || this.editId.length > 0) return '';
    const lastDate: number = this.dateMode === 0 ? this.todayBase + this.dayOffset * DAY_MS :
      EasTimetable.mondayMsOf(timetable.startTime) +
      (Math.max(1, ...this.selectedWeeks) - 1) * 7 * DAY_MS + (Math.max(1, ...this.selectedWeekdays) - 1) * DAY_MS;
    const end: number = lastDate + this.selectedTime()[1] * 60000;
    if (end <= timetable.endTime) return '';
    const date: Date = new Date(CourseDateSelection.weekEnd(end));
    return '保存后课表将延长至 ' + date.getFullYear().toString() + '-' +
      EventEditorForm.pad2(date.getMonth() + 1) + '-' + EventEditorForm.pad2(date.getDate());
  }

  /** 与导入课表页一致：点击弹出系统时间选择器。 */
  private pickStartTime(): void {
    this.getUIContext().showTimePickerDialog({
      selected: new Date(2000, 0, 1, this.hour, this.minute, 0, 0),
      useMilitaryTime: true,
      onAccept: (value: TimePickerResult) => {
        const selectedMinutes: number = value.hour * 60 + value.minute;
        const endMinutes: number = this.endHour * 60 + this.endMinute;
        if (selectedMinutes >= endMinutes) {
          this.getUIContext().getPromptAction().showToast({ message: '开始时间必须早于结束时间' });
          return;
        }
        this.hour = value.hour;
        this.minute = value.minute;
      }
    });
  }

  private pickEndTime(): void {
    this.getUIContext().showTimePickerDialog({
      selected: new Date(2000, 0, 1, this.endHour, this.endMinute, 0, 0),
      useMilitaryTime: true,
      onAccept: (value: TimePickerResult) => {
        const selectedMinutes: number = value.hour * 60 + value.minute;
        const startMinutes: number = this.hour * 60 + this.minute;
        if (selectedMinutes <= startMinutes) {
          this.getUIContext().getPromptAction().showToast({ message: '结束时间必须晚于开始时间' });
          return;
        }
        this.endHour = value.hour;
        this.endMinute = value.minute;
      }
    });
  }

  private async save(): Promise<void> {
    if (this.loading || this.loadFailed || this.saving || this.saved) {
      return;
    }
    const invalid: string = this.validationHint();
    if (invalid.length > 0) { this.hint = invalid; return; }
    this.saving = true;
    try {
      await this.persistEvent();
    } catch (_) {
      this.hint = '保存失败，请重试';
    } finally {
      this.saving = false;
    }
  }

  private async persistEvent(): Promise<void> {
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    const rdb: RdbHelper = RdbHelper.getInstance();
    await rdb.init(ctx);
    const base: number = this.todayBase + this.dayOffset * DAY_MS;
    let ev: EasEventItem = new EasEventItem();
    if (this.editId.length > 0) {
      const existing: EasEventItem | undefined = await rdb.getEventById(this.editId);
      if (existing === undefined) {
        this.loadFailed = true;
        this.hint = '这条记录已不存在，请关闭后刷新列表';
        return;
      }
      ev = existing;
    }
    ev.type = EventEditorForm.typeOf(this.typeIdx);
    ev.name = this.name.trim();
    ev.place = this.place.trim();
    ev.teacher = this.teacher.trim();
    ev.subjectId = this.subjectId;
    // Prefer the explicit target, then the user's current timetable.
    ev.timetableId = this.timetableId;
    let occurrences: EasEventItem[] = [ev];
    if (this.typeIdx === 1 && this.editId.length === 0) {
      // Resolve the explicit target again before writing; never fall back to another timetable if it was deleted.
      await this.loadCourseTimetable(false);
      const timetable: EasTimetable | undefined = this.courseTimetable;
      if (timetable === undefined) return;
      const invalid: string = this.validationHint();
      if (invalid.length > 0) { this.hint = invalid; return; }
      ev.timetableId = timetable.id;
      let dates: number[] = [base];
      if (this.dateMode === 1) {
        try {
          dates = CourseDateSelection.weeklyDates(timetable, this.selectedWeeks, this.selectedWeekdays, this.weekChoices.length);
        } catch (error) {
          this.hint = error instanceof Error ? error.message : '日期选择无效';
          return;
        }
      }
      const subjects: EasTermSubject[] = await rdb.getSubjectsOfTimetable(timetable.id);
      let matched: EasTermSubject | undefined = subjects.find((subject: EasTermSubject): boolean =>
        this.selectedSubjectId.length > 0 ? subject.id === this.selectedSubjectId : subject.name === ev.name);
      if (this.selectedSubjectId.length > 0 && matched === undefined) {
        this.hint = '所选课程已不存在，请重新选择或手动填写';
        return;
      }
      const newSubject: boolean = matched === undefined;
      if (matched === undefined) {
        matched = new EasTermSubject();
        matched.name = ev.name;
        matched.timetableId = timetable.id;
        matched.type = EasSubjectType.COM_B;
        matched.field = 'manual';
        matched.countInSPA = false;
      }
      occurrences = [];
      const selectedTime: number[] = this.selectedTime();
      for (const date of dates) {
        const occurrence: EasEventItem = new EasEventItem();
        occurrence.type = EasEventType.CLASS;
        occurrence.name = ev.name;
        occurrence.place = ev.place;
        occurrence.teacher = ev.teacher;
        occurrence.timetableId = timetable.id;
        occurrence.subjectId = matched.id;
        occurrence.color = matched.color;
        const from: Date = new Date(date);
        const to: Date = new Date(date);
        from.setHours(Math.floor(selectedTime[0] / 60), selectedTime[0] % 60, 0, 0);
        to.setHours(Math.floor(selectedTime[1] / 60), selectedTime[1] % 60, 0, 0);
        occurrence.fromNumber = this.usesPeriods() ? this.fromPeriod : 0;
        occurrence.lastNumber = this.usesPeriods() ? this.toPeriod : 0;
        occurrence.from = from.getTime();
        occurrence.to = to.getTime();
        occurrences.push(occurrence);
      }
      await rdb.saveCourseOccurrences(matched, occurrences, newSubject);
      ev = occurrences[0];
    } else {
      // Clock edits must not retain now-inaccurate period metadata from a period-based course.
      if (this.editId.length > 0 && ev.type === EasEventType.CLASS &&
        (new Date(ev.from).getHours() !== this.hour || new Date(ev.from).getMinutes() !== this.minute ||
         new Date(ev.to).getHours() !== this.endHour || new Date(ev.to).getMinutes() !== this.endMinute)) {
        ev.fromNumber = 0;
        ev.lastNumber = 0;
      }
      ev.from = base + this.hour * 60 * 60 * 1000 + this.minute * 60 * 1000;
      ev.to = base + this.endHour * 60 * 60 * 1000 + this.endMinute * 60 * 1000;
      if (this.editId.length === 0 || ev.color === 0) ev.color = EventEditorForm.typeColor(ev.type);
      if (this.editId.length > 0) {
        await rdb.updateEvent(ev);
      } else {
        await rdb.saveEvent(ev);
      }
    }
    // A pending write may finish after the user has closed this editor.
    if (!this.editorActive) {
      return;
    }
    this.saved = true;
    this.hint = this.editId.length > 0 ? '已更新' :
      (this.typeIdx === 1 ? '已添加 ' + occurrences.length.toString() + ' 个课次' : '已保存');
    this.getUIContext().getPromptAction().showToast({ message: this.hint });
    if (this.sheetMode) {
      this.onSaved(ev, occurrences);
    } else {
      this.getUIContext().getRouter().back();
    }
  }

  static idxOf(t: EasEventType): number {
    if (t === EasEventType.CLASS) {
      return 1;
    }
    if (t === EasEventType.EXAM) {
      return 2;
    }
    if (t === EasEventType.TAG) {
      return 3;
    }
    return 0;
  }

  static typeFromName(name: string): EasEventType {
    if (name === 'CLASS') {
      return EasEventType.CLASS;
    }
    if (name === 'EXAM') {
      return EasEventType.EXAM;
    }
    if (name === 'TAG') {
      return EasEventType.TAG;
    }
    return EasEventType.OTHER;
  }

  static typeOf(idx: number): EasEventType {
    if (idx === 1) {
      return EasEventType.CLASS;
    }
    if (idx === 2) {
      return EasEventType.EXAM;
    }
    if (idx === 3) {
      return EasEventType.TAG;
    }
    return EasEventType.OTHER;
  }

  static typeColor(t: EasEventType): number {
    if (t === EasEventType.EXAM) {
      return 0xFFD93025;
    }
    if (t === EasEventType.OTHER) {
      return 0xFF5C6BC0;
    }
    if (t === EasEventType.TAG) {
      return 0xFF26A69A;
    }
    return 0xFF3390EC;
  }

  private sheetTitle(): string {
    if (this.editId.length > 0) {
      return this.typeIdx === 2 ? '编辑考试' : '编辑课程';
    }
    return this.typeIdx === 2 ? '添加考试' : '添加课程';
  }

  private sheetSubtitle(): string {
    if (this.editId.length > 0) {
      return '修改信息';
    }
    return this.typeIdx === 2 ? '考试将添加到当前课表' : '将课程添加到当前课表';
  }

  private teachingWeekHint(): string {
    const timetable = this.courseTimetable;
    if (timetable === undefined) return '教学周从课表开学日期计算，可增加后续周数';
    const start = new Date(timetable.startTime);
    return '教学周从 ' + start.getFullYear().toString() + '-' + EventEditorForm.pad2(start.getMonth() + 1) +
      '-' + EventEditorForm.pad2(start.getDate()) + ' 起算，当前课表共 ' +
      CourseDateSelection.weekCount(timetable).toString() + ' 周；需要时可增加周数';
  }

  private courseSaveSummary(): string {
    const invalid: string = this.validationHint();
    if (invalid.length > 0) return invalid;
    if (this.editId.length > 0) return '仅修改当前课次';
    if (this.dateMode === 0) return this.dateText() + ' · ' + this.startLabel() + '–' + this.endLabel();
    if (this.selectedWeekdays.length === 0) return '请选择上课的星期';
    if (this.selectedWeeks.length === 0) return '请选择教学周';
    return '将添加 ' + (this.selectedWeeks.length * this.selectedWeekdays.length).toString() +
      ' 个课次 · ' + this.startLabel() + '–' + this.endLabel();
  }

  build() {
    Column() {
      if (this.sheetMode) {
        ImmersiveHeader({ barHeight: 58 }) {
          Row() {
            HeaderBackButton({
              onBack: () => this.onCancel()
            })
              .margin({ right: 12 })
            Column() {
              Text(this.sheetTitle())
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.hita_text_1d2b45'))
              Text(this.sheetSubtitle())
                .fontSize(12)
                .fontColor($r('app.color.hita_text_secondary_72809a'))
                .margin({ top: 3 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .height(58)
          .padding({ left: 20, right: 16 })
          .alignItems(VerticalAlign.Center)
        }
      } else {
        ImmersiveHeader({ barHeight: 56 }) {
          Row() {
            HeaderBackButton({
              onBack: () => this.getUIContext().getRouter().back()
            })
              .margin({ right: 12 })
            Text(this.typeIdx === 1 ? this.sheetTitle() : (this.editId.length > 0 ? '编辑事件' : '新建事件'))
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.typeIdx === 1 ? $r('app.color.hita_text_1d2b45') : '#FFFFFF')
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .height(56)
          .padding({ left: 16, right: 16 })
          .backgroundColor(this.typeIdx === 1 ? Color.Transparent : $r('app.color.hita_primary_fill'))
          .alignItems(VerticalAlign.Center)
        }
      }

      List({ space: 12 }) {
        if (!this.sheetMode && !this.courseEntry) {
          ListItem() {
            this.typeRow()
          }
        }
        if (this.typeIdx === 1) {
          ListItem() { this.courseInfoCard() }
          ListItem() { this.timeRow() }
        } else {
        ListItem() {
          Column() {
            Text('名称')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.hita_text_202b45'))
            TextInput({ placeholder: '事件名称', text: this.name })
              .fontSize(16)
              .height(46)
              .padding({ left: 12, right: 12 })
              .backgroundColor($r('app.color.hita_surface'))
              .border({ width: 1, color: $r('app.color.hita_divider_d7e0ec') })
              .borderRadius(13)
              .margin({ top: 6 })
              .onChange((value: string) => {
                this.name = value;
              })
          }
          .width('100%')
          .padding(12)
          .backgroundColor($r('app.color.hita_surface'))
          .borderRadius(14)
          .alignItems(HorizontalAlign.Start)
        }
        ListItem() {
          Column() {
            Text('地点（可空）')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.hita_text_202b45'))
            TextInput({ placeholder: '地点 / 教室 / 在线', text: this.place })
              .fontSize(16)
              .height(46)
              .padding({ left: 12, right: 12 })
              .backgroundColor($r('app.color.hita_surface'))
              .border({ width: 1, color: $r('app.color.hita_divider_d7e0ec') })
              .borderRadius(13)
              .margin({ top: 6 })
              .onChange((value: string) => {
                this.place = value;
              })
          }
          .width('100%')
          .padding(12)
          .backgroundColor($r('app.color.hita_surface'))
          .borderRadius(14)
          .alignItems(HorizontalAlign.Start)
        }
        ListItem() {
          Column() {
            Text('教师 / 组织者（可空）')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.hita_text_202b45'))
            TextInput({ placeholder: '教师 / 联系人', text: this.teacher })
              .fontSize(16)
              .height(46)
              .padding({ left: 12, right: 12 })
              .backgroundColor($r('app.color.hita_surface'))
              .border({ width: 1, color: $r('app.color.hita_divider_d7e0ec') })
              .borderRadius(13)
              .margin({ top: 6 })
              .onChange((value: string) => {
                this.teacher = value;
              })
          }
          .width('100%')
          .padding(12)
          .backgroundColor($r('app.color.hita_surface'))
          .borderRadius(14)
          .alignItems(HorizontalAlign.Start)
        }
        }
        ListItem() {
          if (this.typeIdx === 1 && this.editId.length === 0) {
            this.courseDateRow()
          } else {
            this.dateRow()
          }
        }
        if (this.typeIdx !== 1) {
          ListItem() { this.timeRow() }
        }
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: this.sheetMode ? 20 : 16, right: this.sheetMode ? 20 : 16, top: 8, bottom: 16 })
      .scrollBar(BarState.Off)
      .enableScrollInteraction(!this.choosingWeeks)
      .enabled(!this.loading && !this.loadFailed && !this.saving && !this.saved)

      Column() {
        if (this.typeIdx === 1 && !this.loading && this.hint.length === 0) {
          Text(this.courseSaveSummary())
            .fontSize(12)
            .fontColor($r('app.color.hita_text_secondary_72809a'))
            .width('100%')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ bottom: 8 })
        }
        if (this.hint.length > 0) {
          Text(this.hint)
            .fontSize(12)
            .fontColor(this.saved ? $r('app.color.hita_success_2e7d32') : $r('app.color.hita_error'))
            .width('100%')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ bottom: 6 })
        }
        ImmersiveHeader({ barHeight: 44 }) {
          Button(this.loading ? '正在读取' : (this.saving ? '正在保存' :
            (this.typeIdx === 1 ? (this.editId.length > 0 ? '保存修改' : '添加课程') : '保存')), { type: ButtonType.Capsule })
            .width('100%')
            .height(44)
            .fontWeight(FontWeight.Medium)
            .fontColor(CompatibleMaterialModifier.foreground('#FFFFFF'))
            .backgroundColor($r('app.color.hita_primary_fill'))
            .borderRadius(22)
            .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_primary_fill')))
            .enabled(this.canSave())
            .onClick(() => {
              this.save();
            })
        }
      }
      .width('100%')
      .padding({
        left: this.sheetMode ? 20 : 12,
        right: this.sheetMode ? 20 : 12,
        top: 8,
        bottom: 10
      })
      .backgroundColor(this.sheetMode ? $r('app.color.hita_surface_soft') : $r('app.color.hita_page_f5f6f8'))
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.sheetMode ? $r('app.color.hita_surface_soft') : $r('app.color.hita_page_f5f6f8'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  courseInfoCard() {
    Column({ space: 12 }) {
      Row() {
        Text('课程信息')
          .fontSize(15).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.hita_text_202b45'))
        Blank()
        Text('名称必填')
          .fontSize(12).fontColor($r('app.color.hita_text_secondary_72809a'))
      }.width('100%')
      if (this.courseTimetable !== undefined) {
        Text('添加至 ' + this.courseTimetable.name)
          .fontSize(12).fontColor($r('app.color.hita_text_secondary_72809a'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      if (this.editId.length === 0) {
        Row({ space: 8 }) {
          Button(this.pickingExisting ? '正在读取…' : '选择已有课程')
            .layoutWeight(1).height(36).fontSize(13)
            .backgroundColor($r('app.color.hita_surface_soft'))
            .fontColor($r('app.color.hita_primary_3390ec'))
            .enabled(!this.pickingExisting)
            .onClick(() => { void this.chooseExistingCourse(); })
          if (this.selectedSubjectId.length > 0) {
            Button('手动填写').height(36).fontSize(13)
              .backgroundColor($r('app.color.hita_surface_soft'))
              .fontColor($r('app.color.hita_text_secondary_72809a'))
              .onClick(() => {
                this.selectedSubjectId = ''; this.name = ''; this.place = ''; this.teacher = ''; this.hint = '';
              })
          }
        }.width('100%')
      }
      TextInput({ placeholder: '课程名称，如高等数学', text: this.name })
        .enabled(this.selectedSubjectId.length === 0)
        .fontSize(17).fontWeight(FontWeight.Medium).height(48)
        .padding({ left: 12, right: 12 }).borderRadius(12)
        .backgroundColor($r('app.color.hita_surface_soft'))
        .onChange((value: string) => { this.name = value; this.hint = ''; })
      Row({ space: 12 }) {
        Text('教室').fontSize(14).fontColor($r('app.color.hita_text_secondary_72809a'))
        TextInput({ placeholder: '选填，如 T3101', text: this.place })
          .fontSize(15).height(44).layoutWeight(1)
          .padding({ left: 12, right: 12 }).borderRadius(12)
          .backgroundColor($r('app.color.hita_surface_soft'))
          .onChange((value: string) => { this.place = value; })
      }.width('100%')
      Row({ space: 12 }) {
        Text('教师').fontSize(14).fontColor($r('app.color.hita_text_secondary_72809a'))
        TextInput({ placeholder: '选填，授课教师', text: this.teacher })
          .fontSize(15).height(44).layoutWeight(1)
          .padding({ left: 12, right: 12 }).borderRadius(12)
          .backgroundColor($r('app.color.hita_surface_soft'))
          .onChange((value: string) => { this.teacher = value; })
      }.width('100%')
    }
    .width('100%').padding(16).borderRadius(20)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor($r('app.color.hita_surface'))
  }

  @Builder
  typeRow() {
    Row() {
      ForEach(TYPE_ITEMS, (item: string, index: number) => {
        Button(item)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
          .height(38)
          .margin({ left: index === 0 ? 0 : 3, right: index === TYPE_ITEMS.length - 1 ? 0 : 3 })
          .backgroundColor(this.typeIdx === index ? $r('app.color.hita_primary_fill') : $r('app.color.hita_surface'))
          .fontColor(this.typeIdx === index ? '#FFFFFF' : $r('app.color.hita_text_333333'))
          .borderRadius(10)
          .onClick(() => {
            this.typeIdx = index;
            if (index === 1 && this.editId.length === 0) {
              this.loadCourseTimetable().catch(() => { this.hint = '读取课表失败，请重试'; });
            }
          })
      }, (item: string) => item)
    }
    .width('100%')
    .height(48)
    .padding(5)
    .backgroundColor($r('app.color.hita_control_e8edf4'))
    .borderRadius(14)
  }

  @Builder
  courseDateRow() {
    Column({ space: 12 }) {
      Text('上课日期').fontSize(15).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.hita_text_202b45'))
      Row({ space: 8 }) {
        ForEach(['单日', '每周'], (label: string, index: number) => {
          Button(label)
            .layoutWeight(1)
            .height(36)
            .backgroundColor(this.dateMode === index ? $r('app.color.hita_primary_fill') :
              $r('app.color.hita_surface_soft'))
            .fontColor(this.dateMode === index ? '#FFFFFF' : $r('app.color.hita_text_202b45'))
            .accessibilitySelected(this.dateMode === index)
            .onClick(() => { this.dateMode = index; this.hint = ''; })
        }, (label: string) => label)
      }
      if (this.dateMode === 0) {
        this.dateRow()
      } else if (this.weekChoices.length === 0) {
        Text('请先设置课表的起止日期')
          .fontColor($r('app.color.hita_text_secondary_72809a'))
      } else {
        Text('星期（可多选）').fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.hita_text_202b45'))
        Row({ space: 4 }) {
          ForEach(['一', '二', '三', '四', '五', '六', '日'], (label: string, index: number) => {
            Button(label)
              .layoutWeight(1)
              .height(38)
              .padding(0)
              .borderRadius(10)
              .fontSize(14)
              .backgroundColor(this.selectedWeekdays.includes(index + 1) ? $r('app.color.hita_primary_fill') :
                $r('app.color.hita_surface_soft'))
              .fontColor(this.selectedWeekdays.includes(index + 1) ? '#FFFFFF' : $r('app.color.hita_text_202b45'))
              .accessibilityText('星期' + label)
              .accessibilitySelected(this.selectedWeekdays.includes(index + 1))
              .onClick(() => {
                this.selectedWeekdays = CourseDateSelection.toggle(this.selectedWeekdays, index + 1,
                  !this.selectedWeekdays.includes(index + 1));
              })
          }, (label: string) => label)
        }
        Text('教学周（可多选）').fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.hita_text_202b45'))
        Text(this.teachingWeekHint()).fontSize(12)
          .fontColor($r('app.color.hita_text_secondary_72809a'))
        Row({ space: 6 }) {
          ForEach(['全部', '单周', '双周', '清空'], (label: string, index: number) => {
            Button(label)
              .layoutWeight(1)
              .height(32)
              .fontSize(13)
              .backgroundColor($r('app.color.hita_surface_soft'))
              .fontColor($r('app.color.hita_primary_3390ec'))
              .onClick(() => this.selectWeekPreset(index))
          }, (label: string) => label)
        }
        Button('增加 5 周')
          .height(32).fontSize(13)
          .backgroundColor($r('app.color.hita_surface_soft'))
          .fontColor($r('app.color.hita_primary_3390ec'))
          .onClick(() => {
            this.weekChoices = CourseDateSelection.numbers(this.weekChoices.length + 5);
            this.hint = '';
          })
        CourseWeekPicker({ weeks: this.weekChoices, chosen: $selectedWeeks,
          onChoosingChanged: (choosing: boolean) => { this.choosingWeeks = choosing; } })
        Text('已选 ' + this.selectedWeeks.length.toString() + ' 周 · ' +
          this.selectedWeekdays.length.toString() + ' 天/周，共 ' +
          (this.selectedWeeks.length * this.selectedWeekdays.length).toString() + ' 个课次')
          .fontSize(12)
          .fontColor($r('app.color.hita_text_secondary_72809a'))
      }
      if (this.extensionHint().length > 0) {
        Text(this.extensionHint()).fontSize(12)
          .fontColor($r('app.color.hita_primary_3390ec'))
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .backgroundColor($r('app.color.hita_surface'))
    .borderRadius(16)
  }

  @Builder
  dateRow() {
    Row() {
      Column() {
        Text('日期')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.hita_text_202b45'))
        Text(this.dateText())
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.hita_text_1d2b45'))
          .margin({ top: 6 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.calendar'))
        .fontSize(24)
        .fontColor([$r('app.color.hita_primary_3390ec')])
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding(14)
    .backgroundColor($r('app.color.hita_surface'))
    .borderRadius(16)
    .onClick(() => {
      this.chooseDate();
    })
  }

  @Builder
  timeRow() {
    Column() {
      Text(this.typeIdx === 1 ? '上课时间' : '时间')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.hita_text_202b45'))
      if (this.typeIdx === 1 && this.editId.length === 0) {
        Row({ space: 8 }) {
          ForEach(['具体时间', '按节次'], (label: string, index: number) => {
            Button(label).layoutWeight(1).height(36).fontSize(14)
              .backgroundColor(this.timeMode === index ? $r('app.color.hita_primary_fill') : $r('app.color.hita_surface_soft'))
              .fontColor(this.timeMode === index ? '#FFFFFF' : $r('app.color.hita_text_202b45'))
              .accessibilitySelected(this.timeMode === index)
              .onClick(() => { this.timeMode = index; this.hint = ''; })
          }, (label: string) => label)
        }.width('100%').margin({ top: 10 })
      }
      Row({ space: 10 }) {
        Row() {
          Column() {
            Text(this.usesPeriods() ? '开始节次' : '开始时间')
              .fontSize(12)
              .fontColor($r('app.color.hita_text_secondary_72809a'))
            Text(this.usesPeriods() ? (this.fromPeriod > 0 ? '第 ' + this.fromPeriod.toString() + ' 节' : '请选择') : this.startLabel())
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.hita_text_1d2b45'))
              .margin({ top: 6 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          SymbolGlyph($r('sys.symbol.clock'))
            .fontSize(20)
            .fontColor([$r('app.color.hita_primary_3390ec')])
        }
        .layoutWeight(1)
        .alignItems(VerticalAlign.Center)
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .backgroundColor($r('app.color.hita_surface_soft'))
        .borderRadius(12)
        .onClick(() => {
          if (this.usesPeriods()) this.choosePeriod(true); else this.pickStartTime();
        })
        Row() {
          Column() {
            Text(this.usesPeriods() ? '结束节次' : '结束时间')
              .fontSize(12)
              .fontColor($r('app.color.hita_text_secondary_72809a'))
            Text(this.usesPeriods() ? (this.toPeriod > 0 ? '第 ' + this.toPeriod.toString() + ' 节' : '请选择') : this.endLabel())
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.hita_text_1d2b45'))
              .margin({ top: 6 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          SymbolGlyph($r('sys.symbol.clock'))
            .fontSize(20)
            .fontColor([$r('app.color.hita_primary_3390ec')])
        }
        .layoutWeight(1)
        .alignItems(VerticalAlign.Center)
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .backgroundColor($r('app.color.hita_surface_soft'))
        .borderRadius(12)
        .onClick(() => {
          if (this.usesPeriods()) this.choosePeriod(false); else this.pickEndTime();
        })
      }
      .width('100%')
      .margin({ top: 8 })
      if (this.usesPeriods()) {
        Text(this.selectedTime()[0] < 0 ? '按当前课表作息选择上课节次' : this.startLabel() + '–' + this.endLabel())
          .fontSize(12).fontColor($r('app.color.hita_text_secondary_72809a')).margin({ top: 8 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .backgroundColor($r('app.color.hita_surface'))
    .borderRadius(16)
  }

}

/** Route wrapper kept for the standalone timeline editor. */
@Entry
@Component
struct AddEventPage {
  @StorageProp('hita_status_bar_vp') statusBarInset: number = STATUS_BAR_INSET_FALLBACK;
  build() {
    Column() {
      EventEditorForm()
        .width('100%')
        .height('100%');
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.statusBarInset })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM]);
  }
}
