/**
 * AddEventPage.ets — 新建/编辑事件（HITA_X ui/event/add 语义 → ArkUI 表单）。
 *
 * P1 本地功能：类型(课程/日程/考试/备忘)、名称、地点、日期偏移(今天起 ±370 天)、
 * 开始时刻(整点/半点调节+预设)、时长(30/60/120/180min) → RDB events → 返回时间线自动刷新。
 */
import { promptAction, router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { RdbHelper } from '../common/db/RdbHelper';
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

@Entry
@Component
struct AddEventPage {
  @State typeIdx: number = 0;
  @State name: string = '';
  @State place: string = '';
  @State teacher: string = '';
  @State dayOffset: number = 0;
  @State hour: number = 14;
  @State minute: number = 0;
  @State durationIdx: number = 1; // [30,60,120,180]
  @State hint: string = '';
  @State saved: boolean = false;
  private editId: string = '';
  private timetableId: string = '';
  private subjectId: string = '';

  private durations: number[] = [30, 60, 120, 180];

  async aboutToAppear(): Promise<void> {
    const params: Object | undefined = this.getUIContext().getRouter().getParams();
    if (params === undefined || params === null) {
      return;
    }
    const record = params as Record<string, string>;
    const id: string = record['id'] === undefined ? '' : record['id'] as string;
    this.timetableId = record['timetableId'] === undefined ? '' : record['timetableId'] as string;
    if (id.length === 0 && this.timetableId.length > 0) {
      // 课表详情页的“+课程”默认创建课程，而不是普通日程。
      this.typeIdx = 1;
    }
    if (id.length === 0) {
      // 新建：若从时间线某天进入，沿用该天（offset 参数）
      const offsetRaw: string = record['offset'] === undefined ? '' : record['offset'] as string;
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
      return;
    }
    this.name = ev.name;
    this.place = ev.place;
    this.teacher = ev.teacher;
    this.timetableId = ev.timetableId.length > 0 ? ev.timetableId : this.timetableId;
    this.subjectId = ev.subjectId;
    this.typeIdx = AddEventPage.idxOf(ev.type);
    const d: Date = new Date(ev.from);
    this.hour = d.getHours();
    this.minute = Math.min(55, d.getMinutes());
    const todayMidnight: number = new Date(new Date().setHours(0, 0, 0, 0)).getTime();
    const fromMidnight: number = new Date(new Date(ev.from).setHours(0, 0, 0, 0)).getTime();
    let off: number = Math.round((fromMidnight - todayMidnight) / DAY_MS);
    if (off < -MAX_DAY_OFFSET) {
      off = -MAX_DAY_OFFSET;
    }
    if (off > MAX_DAY_OFFSET) {
      off = MAX_DAY_OFFSET;
    }
    this.dayOffset = off;
    const durMin: number = Math.round((ev.to - ev.from) / 60000);
    let best: number = 1;
    for (let i = 0; i < this.durations.length; i++) {
      if (Math.abs(this.durations[i] - durMin) < Math.abs(this.durations[best] - durMin)) {
        best = i;
      }
    }
    this.durationIdx = best;
  }

  private static pad2(n: number): string {
    return n < 10 ? '0' + n.toString() : n.toString();
  }

  private dateText(): string {
    const d: Date = new Date(Date.now() + this.dayOffset * DAY_MS);
    return d.getFullYear().toString() + '-' + AddEventPage.pad2(d.getMonth() + 1) + '-' +
      AddEventPage.pad2(d.getDate());
  }

  private startLabel(): string {
    return AddEventPage.pad2(this.hour) + ':' + AddEventPage.pad2(this.minute);
  }

  private endLabel(): string {
    const total: number = this.hour * 60 + this.minute + this.durations[this.durationIdx];
    const h: number = Math.floor(total / 60) % 24;
    const m: number = total % 60;
    return AddEventPage.pad2(h) + ':' + AddEventPage.pad2(m);
  }

  private shiftDay(delta: number): void {
    let d: number = this.dayOffset + delta;
    if (d < -MAX_DAY_OFFSET) {
      d = -MAX_DAY_OFFSET;
    }
    if (d > MAX_DAY_OFFSET) {
      d = MAX_DAY_OFFSET;
    }
    this.dayOffset = d;
  }

  private shiftHour(delta: number): void {
    let h: number = this.hour + delta;
    if (h < 0) {
      h = 0;
    }
    if (h > 23) {
      h = 23;
    }
    this.hour = h;
  }

  private shiftMinute(delta: number): void {
    let m: number = this.minute + delta;
    if (m < 0) {
      m = 0;
    }
    if (m > 55) {
      m = 55;
    }
    this.minute = m;
  }

  private async save(): Promise<void> {
    if (this.name.trim().length === 0) {
      this.hint = '请填写名称';
      return;
    }
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    await RdbHelper.getInstance().init(ctx);
    const base: number = new Date(new Date().setHours(0, 0, 0, 0)).getTime() + this.dayOffset * DAY_MS;
    const ev: EasEventItem = new EasEventItem();
    if (this.editId.length > 0) {
      ev.id = this.editId;
    }
    ev.type = AddEventPage.typeOf(this.typeIdx);
    ev.name = this.name.trim();
    ev.place = this.place.trim();
    ev.teacher = this.teacher.trim();
    ev.subjectId = this.subjectId;
    // 从课表详情页新建的课程必须挂到目标课表，不能回退到演示课表。
    ev.timetableId = this.timetableId;
    if (this.typeIdx === 1 && this.editId.length === 0) {
      if (ev.timetableId.length === 0) {
        const tt: EasTimetable | undefined = await RdbHelper.getInstance().getTimetableByEasCode('LOCAL_DEMO_001');
        if (tt !== undefined) {
          ev.timetableId = tt.id;
        }
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
    ev.to = ev.from + this.durations[this.durationIdx] * 60 * 1000;
    ev.color = AddEventPage.typeColor(ev.type);
    ev.createdAt = Date.now();
    await RdbHelper.getInstance().saveEvent(ev);
    this.saved = true;
    this.hint = this.editId.length > 0 ? '已更新' : '已保存';
    this.getUIContext().getPromptAction().showToast({ message: this.editId.length > 0 ? '事件已更新' : '事件已保存' });
    setTimeout(() => {
      this.getUIContext().getRouter().back();
    }, 500);
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

  build() {
    Column() {
      Row() {
        Text('<')
          .fontSize(22)
          .fontColor('#FFFFFF')
          .fontWeight(FontWeight.Bold)
          .width(40)
          .height(40)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.getUIContext().getRouter().back();
          })

        Text(this.editId.length > 0 ? '编辑事件' : '新建事件')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .layoutWeight(1)
          .margin({ left: 4 })
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 16 })
      .backgroundColor('#3390EC')
      .alignItems(VerticalAlign.Center)

      List({ space: 10 }) {
        ListItem() {
          this.typeRow()
        }
        ListItem() {
          Column() {
            Text('名称')
              .fontSize(12)
              .fontColor('#666666')
            TextInput({ placeholder: '事件名称', text: this.name })
              .onChange((value: string) => {
                this.name = value;
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        ListItem() {
          Column() {
            Text('地点（可空）')
              .fontSize(12)
              .fontColor('#666666')
            TextInput({ placeholder: '地点 / 教室 / 在线', text: this.place })
              .onChange((value: string) => {
                this.place = value;
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        ListItem() {
          Column() {
            Text('教师 / 组织者（可空）')
              .fontSize(12)
              .fontColor('#666666')
            TextInput({ placeholder: '教师 / 联系人', text: this.teacher })
              .onChange((value: string) => {
                this.teacher = value;
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        ListItem() {
          this.dateRow()
        }
        ListItem() {
          this.timeRow()
        }
        ListItem() {
          this.durationRow()
        }
        if (this.hint.length > 0) {
          ListItem() {
            Text(this.hint)
              .fontSize(13)
              .fontColor(this.saved ? '#2E7D32' : '#D93025')
              .width('100%')
          }
        }
        ListItem() {
          Button('保存')
            .width('100%')
            .height(44)
            .backgroundColor('#3390EC')
            .borderRadius(22)
            .onClick(() => {
              this.save();
            })
        }
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 12, right: 12 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F6F8')
  }

  @Builder
  typeRow() {
    Row({ space: 8 }) {
      ForEach(TYPE_ITEMS, (item: string, index: number) => {
        Button(item)
          .fontSize(14)
          .backgroundColor(this.typeIdx === index ? '#3390EC' : '#FFFFFF')
          .fontColor(this.typeIdx === index ? '#FFFFFF' : '#333333')
          .border({ width: 1, color: this.typeIdx === index ? '#3390EC' : '#E0E0E0' })
          .onClick(() => {
            this.typeIdx = index;
          })
      }, (item: string) => item)
    }
    .width('100%')
  }

  @Builder
  dateRow() {
    Column() {
      Text('日期')
        .fontSize(12)
        .fontColor('#666666')
      Row() {
        Button('今天')
          .fontSize(13)
          .height(32)
          .backgroundColor(this.dayOffset === 0 ? '#3390EC' : '#EDF1F7')
          .fontColor(this.dayOffset === 0 ? '#FFFFFF' : '#333333')
          .onClick(() => {
            this.dayOffset = 0;
          })
        Button('明天')
          .fontSize(13)
          .height(32)
          .backgroundColor(this.dayOffset === 1 ? '#3390EC' : '#EDF1F7')
          .fontColor(this.dayOffset === 1 ? '#FFFFFF' : '#333333')
          .onClick(() => {
            this.dayOffset = 1;
          })
        Blank()
        Row() {
          Button('‹')
            .width(34)
            .height(32)
            .fontSize(16)
            .onClick(() => {
              this.shiftDay(-1);
            })
          Text(this.dateText())
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .width(110)
            .textAlign(TextAlign.Center)
          Button('›')
            .width(34)
            .height(32)
            .fontSize(16)
            .onClick(() => {
              this.shiftDay(1);
            })
        }
      }
      .width('100%')
      .margin({ top: 4 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  timeRow() {
    Column() {
      Text('开始时间')
        .fontSize(12)
        .fontColor('#666666')
      Row() {
        Button('-')
          .width(40)
          .height(32)
          .onClick(() => {
            this.shiftHour(-1);
          })
        Text(this.startLabel())
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .width(90)
          .textAlign(TextAlign.Center)
        Button('+')
          .width(40)
          .height(32)
          .onClick(() => {
            this.shiftHour(1);
          })
        Blank()
        Button('-5分')
          .fontSize(12)
          .height(32)
          .backgroundColor('#EDF1F7')
          .onClick(() => {
            this.shiftMinute(-5);
          })
        Text(AddEventPage.pad2(this.minute) + '分')
          .fontSize(14)
          .width(46)
          .textAlign(TextAlign.Center)
        Button('+5分')
          .fontSize(12)
          .height(32)
          .backgroundColor('#EDF1F7')
          .onClick(() => {
            this.shiftMinute(5);
          })
      }
      .width('100%')
      .margin({ top: 4 })
      Row({ space: 6 }) {
        Text('预设：')
          .fontSize(12)
          .fontColor('#999999')
        Button('09:00')
          .fontSize(12)
          .height(30)
          .backgroundColor('#EDF1F7')
          .onClick(() => {
            this.hour = 9;
            this.minute = 0;
          })
        Button('12:30')
          .fontSize(12)
          .height(30)
          .backgroundColor('#EDF1F7')
          .onClick(() => {
            this.hour = 12;
            this.minute = 30;
          })
        Button('14:00')
          .fontSize(12)
          .height(30)
          .backgroundColor('#EDF1F7')
          .onClick(() => {
            this.hour = 14;
            this.minute = 0;
          })
        Button('19:00')
          .fontSize(12)
          .height(30)
          .backgroundColor('#EDF1F7')
          .onClick(() => {
            this.hour = 19;
            this.minute = 0;
          })
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  durationRow() {
    Column() {
      Text('时长（至 ' + this.endLabel() + '）')
        .fontSize(12)
        .fontColor('#666666')
      Row({ space: 6 }) {
        ForEach(this.durations, (min: number, index: number) => {
          Button(min.toString() + ' 分钟')
            .fontSize(13)
            .height(32)
            .backgroundColor(this.durationIdx === index ? '#3390EC' : '#EDF1F7')
            .fontColor(this.durationIdx === index ? '#FFFFFF' : '#333333')
            .onClick(() => {
              this.durationIdx = index;
            })
        }, (min: number) => min.toString())
      }
      .width('100%')
      .margin({ top: 4 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
