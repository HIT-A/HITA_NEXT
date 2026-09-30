/** Android HITA-style timetable details and subject management. */
import { common } from '@kit.AbilityKit';
import { RdbHelper } from '../common/db/RdbHelper';
import {
  EasEventItem,
  EasSubjectType,
  EasTermSubject,
  EasTimePeriodInDay,
  EasTimetable
} from '../common/model/timetable/TimetableModels';
import { HitaColors } from '../common/theme/HitaColors';

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
  @State loading: boolean = true;
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

  private async load(): Promise<void> {
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    const rdb: RdbHelper = RdbHelper.getInstance();
    await rdb.init(ctx);
    this.timetable = await rdb.getTimetableById(this.timetableId);
    const rows: TimetableSubjectRow[] = [];
    if (this.timetable !== undefined) {
      const subjects: EasTermSubject[] = await rdb.getSubjectsOfTimetable(this.timetable.id);
      for (let i: number = 0; i < subjects.length; i++) {
        const events: EasEventItem[] = await rdb.getClassesOfSubject(subjects[i].id);
        const row: TimetableSubjectRow = new TimetableSubjectRow();
        row.subject = subjects[i];
        row.classCount = events.length;
        rows.push(row);
      }
    }
    this.subjectRows = rows;
    this.loading = false;
  }

  private async cycleColor(row: TimetableSubjectRow): Promise<void> {
    let next: number = SUBJECT_PALETTE[0];
    for (let i: number = 0; i < SUBJECT_PALETTE.length; i++) {
      if (SUBJECT_PALETTE[i] === row.subject.color) {
        next = SUBJECT_PALETTE[(i + 1) % SUBJECT_PALETTE.length];
        break;
      }
    }
    await RdbHelper.getInstance().changeSubjectColor(row.subject.id, next);
    await this.load();
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
      Text(timetable.name.length > 0 ? timetable.name : '未命名课表')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor('#202633')
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
      .margin({ top: 20 })
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
      Row() {
        Text('课表周数')
          .fontSize(13)
          .fontColor('#7B8498')
        Blank()
        Text(TimetableDetailPage.weekCount(timetable).toString() + ' 周')
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

            Text('点击科目色条可切换颜色，长按科目可删除')
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
    const month: number = d.getMonth() + 1;
    const day: number = d.getDate();
    return d.getFullYear().toString() + '年' + month.toString() + '月' + day.toString() + '日';
  }

  private static weekCount(timetable: EasTimetable): number {
    const weekMs: number = 7 * 24 * 60 * 60 * 1000;
    return Math.max(1, Math.ceil((timetable.endTime - timetable.startTime + 1) / weekMs));
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

  private static css(argb: number): string {
    const r: number = (argb >> 16) & 0xFF;
    const g: number = (argb >> 8) & 0xFF;
    const b: number = argb & 0xFF;
    return 'rgb(' + r.toString() + ',' + g.toString() + ',' + b.toString() + ')';
  }
}
