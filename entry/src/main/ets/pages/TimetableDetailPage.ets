/** Android HITA-style timetable detail and course management. */
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
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
import { DOW_FULL, EasTimeTools } from '../common/util/EasTimeTools';
import { EventEditorForm } from './AddEventPage';

const DAY_MS: number = 24 * 60 * 60 * 1000;
const SUBJECT_PALETTE: number[] = [0xFF5C6BC0, 0xFF26A69A, 0xFFEF8E5A, 0xFFD93025,
  0xFF7E57C2, 0xFF42A5F5, 0xFF9CCC65, 0xFF8D6E63];

class TimetableSubjectRow {
  subject: EasTermSubject = new EasTermSubject();
  classCount: number = 0;
  /** 该科目的全部上课记录（按开始时间升序）。 */
  sessions: EasEventItem[] = [];
}

@Entry
@Component
struct TimetableDetailPage {
  @State timetable: EasTimetable | undefined = undefined;
  @State subjectRows: TimetableSubjectRow[] = [];
  @State eventRows: EasEventItem[] = [];
  @State loading: boolean = true;
  /** 0=closed, 1=course detail, 2=course editor. */
  @State eventSheetMode: number = 0;
  /** bindSheet 只看这一个开关；内容状态在收起动画结束前保持不变。 */
  @State sheetVisible: boolean = false;
  @State selectedEvent: EasEventItem | undefined = undefined;
  @State sheetEventId: string = '';
  /** 当前展开课时列表的科目 id（空串 = 全部收起）。 */
  @State expandedSubjectId: string = '';
  /** 展开科目里“学分”输入框的草稿值。 */
  @State creditDraft: string = '';
  // Keep this page on one explicit vertical scroller so rebuilt event rows do
  // not change the gesture/measurement path used by the parent container.
  private detailScroller: Scroller = new Scroller();
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
        const sessions: EasEventItem[] = [];
        for (let j: number = 0; j < subjectEvents.length; j++) {
          if (subjectEvents[j].type !== EasEventType.CLASS) {
            continue;
          }
          subjectEvents[j].color = subjects[i].color;
          sessions.push(subjectEvents[j]);
        }
        const row: TimetableSubjectRow = new TimetableSubjectRow();
        row.subject = subjects[i];
        row.classCount = sessions.length;
        row.sessions = sessions;
        rows.push(row);
      }
      const timetableEvents: EasEventItem[] = await rdb.getEventsOfTimetable(this.timetable.id);
      for (let i: number = 0; i < timetableEvents.length; i++) {
        const event: EasEventItem = timetableEvents[i];
        const subjectColor: number | undefined = colorById.get(event.subjectId);
        event.color = subjectColor === undefined ? TimetableDetailPage.eventColor(event.type) : subjectColor;
        events.push(event);
      }
    }
    this.subjectRows = rows;
    this.eventRows = events;
    this.loading = false;
  }

  private openAddEvent(): void {
    this.sheetEventId = '';
    this.selectedEvent = undefined;
    this.eventSheetMode = 2;
    this.sheetVisible = true;
  }

  private openEditEvent(event: EasEventItem): void {
    this.sheetEventId = event.id;
    this.selectedEvent = event;
    this.eventSheetMode = 2;
    this.sheetVisible = true;
  }

  private openEventDetail(event: EasEventItem): void {
    this.sheetEventId = event.id;
    this.selectedEvent = event;
    this.eventSheetMode = 1;
    this.sheetVisible = true;
  }

  /**
   * 关闭弹层只翻可见性。若在同一帧里清空内容/模式，bindSheet 的显示条件、
   * builder 内容和高度会同时变化，退场动画被打断（真机上残留空白半屏弹层）。
   * 内容状态统一在 onDisappear 里清空。
   */
  private closeSheet(): void {
    this.sheetVisible = false;
  }

  private resetSheetState(): void {
    this.eventSheetMode = 0;
    this.selectedEvent = undefined;
    this.sheetEventId = '';
  }

  private toggleSubject(row: TimetableSubjectRow): void {
    if (this.expandedSubjectId === row.subject.id) {
      this.expandedSubjectId = '';
      return;
    }
    this.expandedSubjectId = row.subject.id;
    this.creditDraft = row.subject.credit > 0 ? TimetableDetailPage.numberText(row.subject.credit) : '';
  }

  /** 手动修正学分（教务属性表缺失或同名多Variant时自动读取会失败）。 */
  private async saveSubjectCredit(row: TimetableSubjectRow): Promise<void> {
    const text: string = this.creditDraft.trim();
    if (text.length === 0) {
      return;
    }
    const value: number = Number(text);
    if (Number.isNaN(value) || value < 0 || value > 100) {
      this.getUIContext().getPromptAction().showToast({ message: '学分应为 0-100 的数字' });
      return;
    }
    if (value === row.subject.credit) {
      return;
    }
    row.subject.credit = value;
    await RdbHelper.getInstance().saveSubject(row.subject);
    await this.load();
    this.creditDraft = value > 0 ? TimetableDetailPage.numberText(value) : '';
    this.getUIContext().getPromptAction().showToast({ message: '学分已更新' });
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
      this.closeSheet();
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

  /** 教务数据未提供考核方式时，允许手动纠正课程类型。 */
  private chooseSubjectType(row: TimetableSubjectRow): void {
    const types: EasSubjectType[] = [EasSubjectType.COM_A, EasSubjectType.COM_B, EasSubjectType.OPT_A,
      EasSubjectType.OPT_B, EasSubjectType.MOOC, EasSubjectType.TAG];
    const button = (type: EasSubjectType): promptAction.Button => {
      const item: promptAction.Button = {
        text: TimetableDetailPage.typeName(type),
        color: type === row.subject.type ? HitaColors.primary : '#303746'
      };
      return item;
    };
    this.getUIContext().getPromptAction().showActionMenu({
      title: '课程类型',
      buttons: [button(types[0]), button(types[1]), button(types[2]), button(types[3]), button(types[4]),
        button(types[5])]
    }).then(async (ret) => {
      const next: EasSubjectType | undefined = types[ret.index];
      if (next === undefined || next === row.subject.type) {
        return;
      }
      const subject: EasTermSubject = row.subject;
      subject.type = next;
      await RdbHelper.getInstance().saveSubject(subject);
      await this.load();
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
        Text(TimetableDetailPage.dateText(timetable.startTime))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#303746')
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
        .rotate({ angle: this.expandedSubjectId === row.subject.id ? 90 : 0 })
    }
    .width('100%')
    .height(76)
    .padding({ left: 14, right: 14 })
    .onClick(() => {
      this.toggleSubject(row);
    })
  }

  /** 一门课程一栏：科目行 + 点击展开后的课时列表。 */
  @Builder
  private courseGroupCard(row: TimetableSubjectRow) {
    Column() {
      this.subjectCard(row)
      if (this.expandedSubjectId === row.subject.id) {
        Divider()
          .color('#EEF1F6')
          .margin({ left: 14, right: 14 })
        Row() {
          Text('课程类型')
            .fontSize(13)
            .fontColor('#7B8498')
          Blank()
          Text(TimetableDetailPage.typeName(row.subject.type))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(HitaColors.primary)
          Text('›')
            .fontSize(20)
            .fontColor('#B2B8C4')
            .margin({ left: 6 })
        }
        .width('100%')
        .height(44)
        .padding({ left: 14, right: 14 })
        .onClick(() => {
          this.chooseSubjectType(row);
        })
        Row() {
          Text('学分')
            .fontSize(13)
            .fontColor('#7B8498')
          Blank()
          TextInput({ text: this.creditDraft, placeholder: '未设置' })
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(HitaColors.primary)
            .textAlign(TextAlign.End)
            .width(84)
            .height(32)
            .padding({ left: 8, right: 8 })
            .backgroundColor('#F4F7FB')
            .borderRadius(8)
            .enterKeyType(EnterKeyType.Done)
            .onChange((value: string) => {
              this.creditDraft = value;
            })
            .onSubmit(() => {
              this.saveSubjectCredit(row);
            })
        }
        .width('100%')
        .height(44)
        .padding({ left: 14, right: 14 })
        if (row.sessions.length === 0) {
          Text('暂无课时记录')
            .fontSize(12)
            .fontColor('#9AA2B1')
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 12, bottom: 14 })
        } else {
          Column({ space: 6 }) {
            ForEach(row.sessions, (session: EasEventItem) => {
              this.sessionRow(session)
            }, (session: EasEventItem) => session.id)
          }
          .width('100%')
          .padding({ left: 10, right: 10, top: 10, bottom: 10 })
        }
      }
    }
    .width('100%')
    .backgroundColor('#FFFFFF')
    .borderRadius(16)
  }

  @Builder
  private sessionRow(session: EasEventItem) {
    Row() {
      Text(TimetableDetailPage.sessionDateText(session.from))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor('#303746')
      Text(TimetableDetailPage.timeRange(session))
        .fontSize(12)
        .fontColor('#7B8498')
        .margin({ left: 10 })
      Blank()
      Text(TimetableDetailPage.sessionPlaceText(session))
        .fontSize(12)
        .fontColor('#8B93A3')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '38%' })
      Text('›')
        .fontSize(20)
        .fontColor('#B2B8C4')
        .margin({ left: 6 })
    }
    .width('100%')
    .height(44)
    .padding({ left: 12, right: 12 })
    .backgroundColor('#F6F8FC')
    .borderRadius(10)
    .onClick(() => {
      this.openEventDetail(session);
    })
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

  @Builder
  private eventSheetContent() {
    if (this.eventSheetMode === 2) {
      EventEditorForm({
        eventId: this.sheetEventId,
        targetTimetableId: this.timetableId,
        initialType: 'CLASS',
        sheetMode: true,
        onCancel: () => {
          this.closeSheet();
        },
        onSaved: () => {
          this.closeSheet();
          this.load();
        }
      })
        .width('100%')
        .height('100%');
    } else if (this.selectedEvent !== undefined) {
      this.courseDetailSheet(this.selectedEvent as EasEventItem);
    }
  }

  @Builder
  private courseDetailSheet(event: EasEventItem) {
    Column() {
      Row() {
        Row()
          .width(7)
          .height(50)
          .borderRadius(4)
          .backgroundColor(TimetableDetailPage.css(event.color === 0 ?
            TimetableDetailPage.eventColor(event.type) : event.color));
        Column() {
          Text(event.name === 'NULL' || event.name.length === 0 ? '未命名课程' : event.name)
            .fontSize(21)
            .fontWeight(FontWeight.Bold)
            .fontColor('#202B45')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
          Text('课程详情')
            .fontSize(13)
            .fontColor('#72809A')
            .margin({ top: 4 });
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 12, right: 8 });

        Text('编辑')
          .fontSize(14)
          .fontColor(HitaColors.primary)
          .fontWeight(FontWeight.Medium)
          .padding({ left: 8, right: 8, top: 8, bottom: 8 })
          .onClick(() => {
            this.openEditEvent(event);
          });
        Button() {
          Text('×')
            .fontSize(25)
            .fontColor('#4C566A');
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .backgroundColor('#E9EEF5')
        .onClick(() => {
          this.closeSheet();
        });
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: 14 });

      this.courseDetailRow($r('sys.symbol.person_crop_circle_fill'), '老师',
        event.teacher.trim().length > 0 ? event.teacher : '无');
      this.courseDetailRow($r('sys.symbol.pin'), '教室',
        event.place.trim().length > 0 ? event.place : '无');
      this.courseDetailRow($r('sys.symbol.clock'), '时间',
        EasTimeTools.printTime(event.from) + ' - ' + EasTimeTools.printTime(event.to));
      this.courseDetailRow($r('sys.symbol.doc_plaintext'), '节次',
        TimetableDetailPage.coursePeriodText(event));
      this.courseDetailRow($r('sys.symbol.calendar'), '日期',
        TimetableDetailPage.courseDateText(event.from));
      this.courseDetailRow($r('sys.symbol.repeat_1'), '课程进度',
        this.courseProgressText(event));

      Row() {
        Blank()
        Text('删除课程')
          .fontSize(14)
          .fontColor(HitaColors.error)
          .fontWeight(FontWeight.Medium)
          .padding({ left: 14, right: 14, top: 9, bottom: 9 })
          .backgroundColor('#FDECEC')
          .borderRadius(18)
          .onClick(() => {
            this.confirmDeleteEvent(event);
          });
      }
      .width('100%')
      .margin({ top: 6 });
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 4, bottom: 20 });
  }

  @Builder
  private courseDetailRow(symbol: Resource, label: string, value: string) {
    Row() {
      Stack() {
        SymbolGlyph(symbol)
          .fontSize(20)
          .fontColor([HitaColors.primary]);
      }
      .width(38)
      .height(38)
      .borderRadius(19)
      .backgroundColor('#E4F0FF')
      .alignContent(Alignment.Center);
      Column() {
        Text(label)
          .fontSize(12)
          .fontColor('#72809A');
        Text(value)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor('#202B45')
          .margin({ top: 2 })
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 });
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center);
  }

  private courseProgressText(event: EasEventItem): string {
    const instances: EasEventItem[] = this.eventRows.filter((item: EasEventItem): boolean =>
      item.type === EasEventType.CLASS && item.subjectId === event.subjectId);
    instances.sort((a: EasEventItem, b: EasEventItem): number => a.from - b.from);
    let index: number = 0;
    for (let i: number = 0; i < instances.length; i++) {
      if (instances[i].id === event.id) {
        index = i + 1;
        break;
      }
    }
    return index > 0 ? '第 ' + index.toString() + ' / ' + instances.length.toString() + ' 次课' :
      '共 ' + instances.length.toString() + ' 次课';
  }

  private static courseDateText(timestamp: number): string {
    const date: Date = new Date(timestamp);
    return date.getFullYear().toString() + '年' + (date.getMonth() + 1).toString() + '月' +
      date.getDate().toString() + '日 · ' + DOW_FULL[EasTimeTools.getDow(timestamp)];
  }

  private static coursePeriodText(event: EasEventItem): string {
    if (event.fromNumber <= 0 || event.lastNumber <= 0) {
      return '未记录节次';
    }
    return event.fromNumber === event.lastNumber ? '第 ' + event.fromNumber.toString() + ' 节' :
      '第 ' + event.fromNumber.toString() + ' - ' + event.lastNumber.toString() + ' 节';
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
        Scroll(this.detailScroller) {
          Column() {
            this.infoCard(this.timetable as EasTimetable)

            Row() {
              Text('我的课程')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor('#202633')
                .layoutWeight(1)
              Text(this.subjectRows.length.toString() + ' 门课程 · 点击展开课时')
                .fontSize(11)
                .fontColor('#9AA2B1')
            }
            .width('100%')
            .margin({ top: 24, bottom: 10 })
            if (this.subjectRows.length === 0) {
              Column() {
                Text('暂无课程')
                  .fontSize(15)
                  .fontColor('#7B8498')
                Text('从教务导入或点击上方“+ 课程”添加后显示在这里')
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
                  this.courseGroupCard(row)
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

            Text('点击课程展开每次上课记录；点击具体课时查看详情、编辑或删除')
              .fontSize(12)
              .fontColor('#9AA2B1')
              .margin({ top: 14, bottom: 36 })
          }
          .width('100%')
          // Keep the final card above the system navigation gesture area.  A
          // plain bottom margin is not included in the Scroll's measured
          // content extent on some HarmonyOS builds, so use real padding.
          .padding({ left: 16, right: 16, bottom: 72 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollable(ScrollDirection.Vertical)
        .enableScrollInteraction(true)
        .edgeEffect(EdgeEffect.None)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .backgroundColor('#F6F7FA')
    .bindSheet(this.sheetVisible, this.eventSheetContent(), {
      height: this.eventSheetMode === 2 ? SheetSize.LARGE : SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      preferType: SheetType.BOTTOM,
      backgroundColor: '#F6F8FC',
      maskColor: 'rgba(20,33,61,0.24)',
      onDisappear: () => {
        this.resetSheetState();
      }
    })
  }

  private static dateText(ms: number): string {
    const d: Date = new Date(ms);
    return d.getFullYear().toString() + '年' + (d.getMonth() + 1).toString() + '月' + d.getDate().toString() + '日';
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

  private static sessionDateText(ms: number): string {
    const d: Date = new Date(ms);
    return (d.getMonth() + 1).toString() + '月' + d.getDate().toString() + '日 · ' +
      DOW_FULL[EasTimeTools.getDow(ms)];
  }

  private static sessionPlaceText(session: EasEventItem): string {
    const place: string = session.place.trim();
    if (place.length > 0) {
      return place;
    }
    const teacher: string = session.teacher.trim();
    return teacher.length > 0 ? teacher : '未填写地点';
  }

  private static timeRange(event: EasEventItem): string {
    const from: Date = new Date(event.from);
    const to: Date = new Date(event.to);
    return TimetableDetailPage.pad2(from.getHours()) + ':' + TimetableDetailPage.pad2(from.getMinutes()) + ' - ' +
      TimetableDetailPage.pad2(to.getHours()) + ':' + TimetableDetailPage.pad2(to.getMinutes());
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
