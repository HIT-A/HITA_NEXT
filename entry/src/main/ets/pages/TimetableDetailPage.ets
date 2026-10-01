/** Android HITA-style timetable detail and course management. */
import { common } from '@kit.AbilityKit';
import { RdbHelper } from '../common/db/RdbHelper';
import {
  EasEventItem,
  EasEventType,
  EasSubjectType,
  EasTermSubject,
  EasTimePeriodInDay,
  EasTimetable
} from '../common/model/timetable/TimetableModels';
import { HitaColors } from '../common/theme/HitaColors';

const DAY_MS: number = 24 * 60 * 60 * 1000;
const SUBJECT_PALETTE: number[] = [0xFF5C6BC0, 0xFF26A69A, 0xFFEF8E5A, 0xFFD93025,
  0xFF7E57C2, 0xFF42A5F5, 0xFF9CCC65, 0xFF8D6E63];

class TimetableSubjectRow {
  subject: EasTermSubject = new EasTermSubject();
  classCount: number = 0;
}

@Entry
@Component
struct TimetableDetailPage {
  @State timetable: EasTimetable | undefined = undefined;
  @State subjectRows: TimetableSubjectRow[] = [];
  @State eventRows: EasEventItem[] = [];
  @State startDateDraft: string = '';
  @State loading: boolean = true;
  @State savingStart: boolean = false;
  private timetableId: string = '';

  async aboutToAppear(): Promise<void> {
    const params: Object | undefined = this.getUIContext().getRouter().getParams();
    if (params !== undefined && params !== null) {
      const record: Record<string, string> = params as Record<string, string>;
      const timetableParam: string = record['timetableId'] === undefined ? '' : record['timetableId'];
      const legacyParam: string = record['id'] === undefined ? '' : record['id'];
      this.timetableId = timetableParam.length > 0 ? timetableParam : legacyParam;
    }
    await this.load();
  }

  async onPageShow(): Promise<void> {
    if (!this.loading) {
      await this.load();
    }
  }

  private async load(): Promise<void> {
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    const rdb: RdbHelper = RdbHelper.getInstance();
    await rdb.init(ctx);
    this.timetable = await rdb.getTimetableById(this.timetableId);
    const rows: TimetableSubjectRow[] = [];
    const events: EasEventItem[] = [];
    if (this.timetable !== undefined) {
      const subjects: EasTermSubject[] = await rdb.getSubjectsOfTimetable(this.timetable.id);
      const colorById: Map<string, number> = new Map<string, number>();
      for (let i: number = 0; i < subjects.length; i++) {
        colorById.set(subjects[i].id, subjects[i].color);
        const subjectEvents: EasEventItem[] = await rdb.getClassesOfSubject(subjects[i].id);
        const row: TimetableSubjectRow = new TimetableSubjectRow();
        row.subject = subjects[i];
        row.classCount = subjectEvents.length;
        rows.push(row);
      }
      const timetableEvents: EasEventItem[] = await rdb.getEventsOfTimetable(this.timetable.id);
      for (let i: number = 0; i < timetableEvents.length; i++) {
        const event: EasEventItem = timetableEvents[i];
        const subjectColor: number | undefined = colorById.get(event.subjectId);
        event.color = subjectColor === undefined ? TimetableDetailPage.eventColor(event.type) : subjectColor;
        events.push(event);
      }
      this.startDateDraft = TimetableDetailPage.dateInput(this.timetable.startTime);
    }
    this.subjectRows = rows;
    this.eventRows = events;
    this.loading = false;
  }

  private async saveStartDate(): Promise<void> {
    if (this.timetable === undefined || this.savingStart) {
      return;
    }
    const parsedStart: number = TimetableDetailPage.parseDate(this.startDateDraft);
    const nextStart: number = parsedStart <= 0 ? 0 : EasTimetable.mondayMsOf(parsedStart);
    if (nextStart <= 0) {
      this.getUIContext().getPromptAction().showToast({ message: '日期格式应为 YYYY-MM-DD' });
      return;
    }
    const delta: number = nextStart - this.timetable.startTime;
    if (delta === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '开学日期未变化' });
      return;
    }
    this.savingStart = true;
    try {
      const rdb: RdbHelper = RdbHelper.getInstance();
      const events: EasEventItem[] = await rdb.getEventsOfTimetable(this.timetable.id);
      const changed: EasTimetable = this.timetable;
      changed.startTime = nextStart;
      changed.endTime += delta;
      await rdb.saveTimetable(changed);
      for (let i: number = 0; i < events.length; i++) {
        // Android 端只平移课表中的课程实例，考试/标签等独立事件保留原时间。
        if (events[i].type !== EasEventType.CLASS) {
          continue;
        }
        events[i].from += delta;
        events[i].to += delta;
        await rdb.saveEvent(events[i]);
      }
      this.getUIContext().getPromptAction().showToast({ message: '开学日期已更新，课程已同步平移' });
      await this.load();
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '更新开学日期失败' });
    } finally {
      this.savingStart = false;
    }
  }

  private openAddEvent(): void {
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/AddEventPage',
      params: { 'timetableId': this.timetableId, 'type': 'CLASS' }
    });
  }

  private openEditEvent(event: EasEventItem): void {
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/AddEventPage',
      params: { 'id': event.id, 'timetableId': this.timetableId }
    });
  }

  private confirmDeleteEvent(event: EasEventItem): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '删除课程',
      message: '确定删除「' + event.name + '」吗？',
      buttons: [
        { text: '取消', color: '#7B8190' },
        { text: '删除', color: HitaColors.error }
      ]
    }).then(async (ret) => {
      if (ret.index !== 1) {
        return;
      }
      await RdbHelper.getInstance().deleteEvent(event.id);
      await this.load();
      this.getUIContext().getPromptAction().showToast({ message: '课程已删除' });
    }).catch(() => {
    });
  }

  private cycleColor(row: TimetableSubjectRow): void {
    let next: number = SUBJECT_PALETTE[0];
    for (let i: number = 0; i < SUBJECT_PALETTE.length; i++) {
      if (SUBJECT_PALETTE[i] === row.subject.color) {
        next = SUBJECT_PALETTE[(i + 1) % SUBJECT_PALETTE.length];
        break;
      }
    }
    RdbHelper.getInstance().changeSubjectColor(row.subject.id, next).then(() => {
      this.load();
    }).catch(() => {
    });
  }

  private confirmDeleteSubject(row: TimetableSubjectRow): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '删除科目',
      message: '确定删除「' + row.subject.name + '」及其全部课程吗？',
      buttons: [
        { text: '取消', color: '#7B8190' },
        { text: '删除', color: HitaColors.error }
      ]
    }).then(async (ret) => {
      if (ret.index !== 1) {
        return;
      }
      const rdb: RdbHelper = RdbHelper.getInstance();
      await rdb.deleteEventsOfSubject(row.subject.id);
      await rdb.deleteSubject(row.subject.id);
      await this.load();
    }).catch(() => {
    });
  }

  @Builder
  private infoCard(timetable: EasTimetable) {
    Column() {
      Row() {
        Column() {
          Text(timetable.name.length > 0 ? timetable.name : '未命名课表')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor('#202633')
          Text(TimetableDetailPage.weekCount(timetable).toString() + ' 周课表')
            .fontSize(12)
            .fontColor('#7B8498')
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Button('+ 课程')
          .fontSize(13)
          .fontColor('#FFFFFF')
          .height(34)
          .backgroundColor(HitaColors.primary)
          .borderRadius(17)
          .onClick(() => {
            this.openAddEvent();
          })
      }
      .width('100%')
      Row() {
        Text('开学日期')
          .fontSize(13)
          .fontColor('#7B8498')
        Blank()
        TextInput({ text: this.startDateDraft, placeholder: 'YYYY-MM-DD' })
          .fontSize(14)
          .fontColor('#303746')
          .width(126)
          .height(34)
          .textAlign(TextAlign.End)
          .backgroundColor('#F4F7FB')
          .borderRadius(8)
          .padding({ left: 8, right: 8 })
          .onChange((value: string) => {
            this.startDateDraft = value;
          })
        Button(this.savingStart ? '保存中' : '保存')
          .fontSize(12)
          .fontColor(HitaColors.primary)
          .height(30)
          .backgroundColor('#E8F3FD')
          .margin({ left: 8 })
          .onClick(() => {
            this.saveStartDate();
          })
      }
      .width('100%')
      .margin({ top: 18 })
      Row() {
        Text('结束日期')
          .fontSize(13)
          .fontColor('#7B8498')
        Blank()
        Text(TimetableDetailPage.dateText(timetable.endTime))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#303746')
      }
      .width('100%')
      .margin({ top: 12 })
    }
    .width('100%')
    .padding(18)
    .backgroundColor('#FFFFFF')
    .borderRadius(20)
  }

  @Builder
  private subjectCard(row: TimetableSubjectRow) {
    Row() {
      Row()
        .width(18)
        .height(54)
        .borderRadius(9)
        .backgroundColor(TimetableDetailPage.css(row.subject.color))
        .onClick(() => {
          this.cycleColor(row);
        })
      Column() {
        Text(row.subject.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#242A36')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(TimetableDetailPage.typeName(row.subject.type) + ' · ' +
          TimetableDetailPage.numberText(row.subject.credit) + ' 学分 · ' +
          row.classCount.toString() + ' 次课')
          .fontSize(12)
          .fontColor('#7B8498')
          .margin({ top: 6 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
      Text('›')
        .fontSize(24)
        .fontColor('#B2B8C4')
    }
    .width('100%')
    .height(76)
    .padding({ left: 14, right: 14 })
    .backgroundColor('#FFFFFF')
    .borderRadius(16)
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction(() => {
          this.confirmDeleteSubject(row);
        })
    )
  }

  @Builder
  private eventCard(event: EasEventItem) {
    Row() {
      Row()
        .width(8)
        .height(62)
        .borderRadius(4)
        .backgroundColor(TimetableDetailPage.css(event.color))
      Column() {
        Text(event.name.length > 0 ? event.name : '未命名课程')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#242A36')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(TimetableDetailPage.eventDateText(event.from) + ' · ' +
          TimetableDetailPage.timeRange(event))
          .fontSize(12)
          .fontColor('#7B8498')
          .margin({ top: 6 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(TimetableDetailPage.eventMeta(event))
          .fontSize(12)
          .fontColor('#9AA2B1')
          .margin({ top: 4 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
      Text('›')
        .fontSize(24)
        .fontColor('#B2B8C4')
    }
    .width('100%')
    .height(82)
    .padding({ left: 14, right: 14 })
    .backgroundColor('#FFFFFF')
    .borderRadius(16)
    .onClick(() => {
      this.openEditEvent(event);
    })
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction(() => {
          this.confirmDeleteEvent(event);
        })
    )
  }

  @Builder
  private scheduleRow(period: EasTimePeriodInDay, index: number) {
    Row() {
      Row() {
        Text((index + 1).toString())
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(HitaColors.primary)
      }
      .width(32)
      .height(32)
      .justifyContent(FlexAlign.Center)
      .backgroundColor('#E8F3FD')
      .borderRadius(16)
      Text(period.from.toString())
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#303746')
        .margin({ left: 12 })
      Text('-')
        .fontSize(12)
        .fontColor('#A0A7B5')
        .margin({ left: 7, right: 7 })
      Text(period.to.toString())
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#303746')
      Blank()
      Text(period.getLengthInMinutes().toString() + ' 分钟')
        .fontSize(12)
        .fontColor('#8B93A3')
    }
    .width('100%')
    .height(52)
    .padding({ left: 12, right: 12 })
    .backgroundColor('#FFFFFF')
  }

  build() {
    Column() {
      Row() {
        Text('<')
          .fontSize(24)
          .fontWeight(FontWeight.Medium)
          .width(44)
          .height(44)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.getUIContext().getRouter().back();
          })
        Text('课表详情')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#202633')
          .layoutWeight(1)
          .margin({ left: 4 })
      }
      .width('100%')
      .height(64)
      .padding({ left: 6, right: 16 })
      .alignItems(VerticalAlign.Center)

      if (this.loading) {
        LoadingProgress()
          .width(32)
          .height(32)
          .color(HitaColors.primary)
          .margin({ top: 80 })
      } else if (this.timetable === undefined) {
        Text('课表不存在或已删除')
          .fontSize(15)
          .fontColor('#7B8498')
          .margin({ top: 80 })
      } else {
        Scroll() {
          Column() {
            this.infoCard(this.timetable as EasTimetable)

            Row() {
              Text('课程实例')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor('#202633')
                .layoutWeight(1)
              Text('长按删除 · 点击编辑')
                .fontSize(11)
                .fontColor('#9AA2B1')
            }
            .width('100%')
            .margin({ top: 24, bottom: 10 })
            if (this.eventRows.length === 0) {
              Column() {
                Text('暂无课程实例')
                  .fontSize(15)
                  .fontColor('#7B8498')
                Text('点击上方“+ 课程”手动添加课程')
                  .fontSize(12)
                  .fontColor('#A0A7B5')
                  .margin({ top: 6 })
              }
              .width('100%')
              .padding({ top: 26, bottom: 26 })
              .backgroundColor('#FFFFFF')
              .borderRadius(16)
            } else {
              Column({ space: 8 }) {
                ForEach(this.eventRows, (event: EasEventItem) => {
                  this.eventCard(event)
                }, (event: EasEventItem) => event.id)
              }
              .width('100%')
            }

            Text('科目')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#202633')
              .width('100%')
              .margin({ top: 24, bottom: 10 })
            if (this.subjectRows.length === 0) {
              Column() {
                Text('暂无科目')
                  .fontSize(15)
                  .fontColor('#7B8498')
                Text('从教务导入或在课表中添加课程后会显示在这里')
                  .fontSize(12)
                  .fontColor('#A0A7B5')
                  .margin({ top: 6 })
              }
              .width('100%')
              .padding({ top: 26, bottom: 26 })
              .backgroundColor('#FFFFFF')
              .borderRadius(16)
            } else {
              Column({ space: 8 }) {
                ForEach(this.subjectRows, (row: TimetableSubjectRow) => {
                  this.subjectCard(row)
                }, (row: TimetableSubjectRow) => row.subject.id)
              }
              .width('100%')
            }

            Text('课表结构')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#202633')
              .width('100%')
              .margin({ top: 24, bottom: 10 })
            Column() {
              ForEach((this.timetable as EasTimetable).scheduleStructure,
                (period: EasTimePeriodInDay, index: number) => {
                  this.scheduleRow(period, index)
                }, (period: EasTimePeriodInDay, index: number) => index.toString() + period.toString())
            }
            .width('100%')
            .borderRadius(18)
            .clip(true)

            Text('课程可点击编辑，长按可删除；科目色条可切换颜色，长按科目可删除')
              .fontSize(12)
              .fontColor('#9AA2B1')
              .margin({ top: 14, bottom: 36 })
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F6F7FA')
  }

  private static dateText(ms: number): string {
    const d: Date = new Date(ms);
    return d.getFullYear().toString() + '年' + (d.getMonth() + 1).toString() + '月' + d.getDate().toString() + '日';
  }

  private static dateInput(ms: number): string {
    const d: Date = new Date(ms);
    return d.getFullYear().toString() + '-' + TimetableDetailPage.pad2(d.getMonth() + 1) + '-' +
      TimetableDetailPage.pad2(d.getDate());
  }

  private static parseDate(raw: string): number {
    const parts: string[] = raw.trim().split('-');
    if (parts.length !== 3) {
      return 0;
    }
    const year: number = Number(parts[0]);
    const month: number = Number(parts[1]);
    const day: number = Number(parts[2]);
    if (Number.isNaN(year) || Number.isNaN(month) || Number.isNaN(day) || year < 1970 || month < 1 || month > 12 ||
      day < 1 || day > 31) {
      return 0;
    }
    const d: Date = new Date(year, month - 1, day, 0, 0, 0, 0);
    if (d.getFullYear() !== year || d.getMonth() !== month - 1 || d.getDate() !== day) {
      return 0;
    }
    return d.getTime();
  }

  private static pad2(value: number): string {
    return value < 10 ? '0' + value.toString() : value.toString();
  }

  private static weekCount(timetable: EasTimetable): number {
    return Math.max(1, Math.ceil((timetable.endTime - timetable.startTime + 1) / (7 * DAY_MS)));
  }

  private static numberText(value: number): string {
    const text: string = value.toString();
    return text.indexOf('.') >= 0 ? text : text + '.0';
  }

  private static typeName(type: EasSubjectType): string {
    if (type === EasSubjectType.COM_A) {
      return '必修·考试';
    }
    if (type === EasSubjectType.COM_B) {
      return '必修·考查';
    }
    if (type === EasSubjectType.OPT_A) {
      return '选修·专选';
    }
    if (type === EasSubjectType.OPT_B) {
      return '选修·任选';
    }
    if (type === EasSubjectType.MOOC) {
      return '慕课';
    }
    return '其他';
  }

  private static eventDateText(ms: number): string {
    const d: Date = new Date(ms);
    return (d.getMonth() + 1).toString() + '月' + d.getDate().toString() + '日';
  }

  private static timeRange(event: EasEventItem): string {
    const from: Date = new Date(event.from);
    const to: Date = new Date(event.to);
    return TimetableDetailPage.pad2(from.getHours()) + ':' + TimetableDetailPage.pad2(from.getMinutes()) + ' - ' +
      TimetableDetailPage.pad2(to.getHours()) + ':' + TimetableDetailPage.pad2(to.getMinutes());
  }

  private static eventMeta(event: EasEventItem): string {
    const teacher: string = event.teacher.trim();
    const place: string = event.place.trim();
    if (teacher.length > 0 && place.length > 0) {
      return teacher + ' · ' + place;
    }
    if (teacher.length > 0) {
      return teacher;
    }
    if (place.length > 0) {
      return place;
    }
    return TimetableDetailPage.eventTypeName(event.type);
  }

  private static eventTypeName(type: EasEventType): string {
    if (type === EasEventType.CLASS) {
      return '课程';
    }
    if (type === EasEventType.EXAM) {
      return '考试';
    }
    if (type === EasEventType.TAG) {
      return '标签';
    }
    return '其他';
  }

  private static eventColor(type: EasEventType): number {
    if (type === EasEventType.EXAM) {
      return 0xFFD93025;
    }
    if (type === EasEventType.TAG) {
      return 0xFF26A69A;
    }
    if (type === EasEventType.OTHER) {
      return 0xFF5C6BC0;
    }
    return 0xFF3390EC;
  }

  private static css(argb: number): string {
    const r: number = (argb >> 16) & 0xFF;
    const g: number = (argb >> 8) & 0xFF;
    const b: number = argb & 0xFF;
    return 'rgb(' + r.toString() + ',' + g.toString() + ',' + b.toString() + ')';
  }
}
