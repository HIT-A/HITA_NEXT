/**
 * AddEventPage.ets — 新建/编辑事件（HITA_X ui/event/add 语义 → ArkUI 表单）。
 *
 * P1 本地功能：类型(课程/日程/考试/备忘)、名称、地点、日期偏移(今天起 ±370 天)、
 * 起止时间（系统滚轮选择器）→ RDB events → 返回时间线自动刷新。
 */
import { common } from '@kit.AbilityKit';
import { HeaderBackButton } from '../common/components/HeaderBackButton';
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
  onSaved: (event: EasEventItem) => void = (_event: EasEventItem) => {};

  @State typeIdx: number = 0;
  @State name: string = '';
  @State place: string = '';
  @State teacher: string = '';
  @State dayOffset: number = 0;
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
    }
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
    const d: Date = new Date(Date.now() + this.dayOffset * DAY_MS);
    return d.getFullYear().toString() + '-' + EventEditorForm.pad2(d.getMonth() + 1) + '-' +
      EventEditorForm.pad2(d.getDate());
  }

  /** 与导入课表页一致：点击弹出系统日期选择器。 */
  private chooseDate(): void {
    this.getUIContext().showDatePickerDialog({
      selected: new Date(Date.now() + this.dayOffset * DAY_MS),
      onDateAccept: (date: Date) => {
        const selected: Date = new Date(date.getFullYear(), date.getMonth(), date.getDate(), 0, 0, 0, 0);
        const todayMidnight: number = new Date(new Date().setHours(0, 0, 0, 0)).getTime();
        let off: number = Math.round((selected.getTime() - todayMidnight) / DAY_MS);
        if (off < -MAX_DAY_OFFSET) {
          off = -MAX_DAY_OFFSET;
        }
        if (off > MAX_DAY_OFFSET) {
          off = MAX_DAY_OFFSET;
        }
        this.dayOffset = off;
      }
    });
  }

  private startLabel(): string {
    return EventEditorForm.pad2(this.hour) + ':' + EventEditorForm.pad2(this.minute);
  }

  private endLabel(): string {
    return EventEditorForm.pad2(this.endHour) + ':' + EventEditorForm.pad2(this.endMinute);
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
    if (this.name.trim().length === 0) {
      this.hint = '请填写名称';
      return;
    }
    if (this.endHour * 60 + this.endMinute <= this.hour * 60 + this.minute) {
      this.hint = '结束时间必须晚于开始时间';
      return;
    }
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
    const base: number = new Date(new Date().setHours(0, 0, 0, 0)).getTime() + this.dayOffset * DAY_MS;
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
    if (this.typeIdx === 1 && this.editId.length === 0) {
      if (ev.timetableId.length === 0) {
        const selection: TimetableSelectionStore = TimetableSelectionStore.getInstance();
        await selection.init(ctx);
        const selectedId: string = await selection.load();
        let tt: EasTimetable | undefined = selectedId.length > 0 ?
          await rdb.getTimetableById(selectedId) : undefined;
        if (tt === undefined) {
          tt = await TimetableResolver.getForDisplay(rdb);
        }
        if (tt !== undefined) {
          ev.timetableId = tt.id;
        }
      }
      if (ev.timetableId.length === 0 || await rdb.getTimetableById(ev.timetableId) === undefined) {
        this.hint = '请先新建或导入课表，再添加课程';
        return;
      }
      if (ev.timetableId.length > 0) {
        // 为手动课程建立一个可管理的科目记录，避免课程只存在于事件表中。
        const subjects: EasTermSubject[] = await RdbHelper.getInstance().getSubjectsOfTimetable(ev.timetableId);
        let matched: EasTermSubject | undefined = undefined;
        for (let i: number = 0; i < subjects.length; i++) {
          if (subjects[i].name === ev.name) {
            matched = subjects[i];
            break;
          }
        }
        if (matched === undefined) {
          const subject: EasTermSubject = new EasTermSubject();
          subject.id = newId();
          subject.timetableId = ev.timetableId;
          subject.name = ev.name;
          subject.type = EasSubjectType.COM_B;
          subject.credit = 0;
          subject.field = 'manual';
          subject.code = '';
          subject.key = '';
          subject.school = '';
          subject.countInSPA = false;
          subject.createdAt = Date.now();
          await RdbHelper.getInstance().saveSubject(subject);
          matched = subject;
        }
        ev.subjectId = matched.id;
      }
    }
    ev.from = base + this.hour * 60 * 60 * 1000 + this.minute * 60 * 1000;
    ev.to = base + this.endHour * 60 * 60 * 1000 + this.endMinute * 60 * 1000;
    ev.color = EventEditorForm.typeColor(ev.type);
    if (this.editId.length > 0) {
      await rdb.updateEvent(ev);
    } else {
      await rdb.saveEvent(ev);
    }
    // A pending write may finish after the user has closed this editor.
    if (!this.editorActive) {
      return;
    }
    this.saved = true;
    this.hint = this.editId.length > 0 ? '已更新' : '已保存';
    this.getUIContext().getPromptAction().showToast({ message: this.editId.length > 0 ? '事件已更新' : '事件已保存' });
    if (this.sheetMode) {
      this.onSaved(ev);
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

  build() {
    Column() {
      if (this.sheetMode) {
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
      } else {
        Row() {
          HeaderBackButton({
            onBack: () => this.getUIContext().getRouter().back()
          })
            .margin({ right: 12 })
          Text(this.editId.length > 0 ? '编辑事件' : '新建事件')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        .backgroundColor($r('app.color.hita_primary_fill'))
        .alignItems(VerticalAlign.Center)
      }

      List({ space: 8 }) {
        if (!this.sheetMode) {
          ListItem() {
            this.typeRow()
          }
        }
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
        ListItem() {
          this.dateRow()
        }
        ListItem() {
          this.timeRow()
        }
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: this.sheetMode ? 20 : 12, right: this.sheetMode ? 20 : 12, bottom: 10 })

      Column() {
        if (this.hint.length > 0) {
          Text(this.hint)
            .fontSize(12)
            .fontColor(this.saved ? $r('app.color.hita_success_2e7d32') : $r('app.color.hita_error'))
            .width('100%')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ bottom: 6 })
        }
        Button(this.loading ? '正在读取' : (this.saving ? '正在保存' : '保存'))
          .width('100%')
          .height(44)
          .backgroundColor($r('app.color.hita_primary_fill'))
          .borderRadius(22)
          .enabled(!this.loading && !this.loadFailed && !this.saving && !this.saved)
          .onClick(() => {
            this.save();
          })
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
      Text('时间')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.hita_text_202b45'))
      Row({ space: 10 }) {
        Row() {
          Column() {
            Text('开始时间')
              .fontSize(12)
              .fontColor($r('app.color.hita_text_secondary_72809a'))
            Text(this.startLabel())
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
          this.pickStartTime();
        })
        Row() {
          Column() {
            Text('结束时间')
              .fontSize(12)
              .fontColor($r('app.color.hita_text_secondary_72809a'))
            Text(this.endLabel())
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
          this.pickEndTime();
        })
      }
      .width('100%')
      .margin({ top: 8 })
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
