/**
 * ExamPage.ets — 考试查询（HITA_X ui/eas/exam 语义 → ArkUI）。
 *
 * 数据面：EasDataProvider.getExamItems（已预留；端点/解析为 M0/M2 抓包项）。
 * 离线预览：内置样例 EasExamItem 列表，字段对齐 HITA_X ExamItem 直迁模型。
 */
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { EasExamItem } from '../feature/eas/model/EasModels';
import { RdbHelper } from '../common/db/RdbHelper';
import { EasEventItem, EasEventType, EasTimetable } from '../common/model/timetable/TimetableModels';
import { TimetableLocalDemo } from '../feature/timetable/data/TimetableLocalDemo';

@Entry
@Component
struct ExamPage {
  @State exams: EasExamItem[] = [];
  @State note: string = '（未加载）';

  async onPageShow(): Promise<void> {
    // 优先：本地 RDB 里的 EXAM 事件 → 渲染为本学期考试卡（离线演示与“真”本地一致）
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    const rdb: RdbHelper = RdbHelper.getInstance();
    await rdb.init(ctx);
    const tt: EasTimetable | undefined = await rdb.getTimetableByEasCode(TimetableLocalDemo.DEMO_CODE);
    if (tt !== undefined) {
      const all: EasEventItem[] = await rdb.getEventsOfTimetable(tt.id);
      const list: EasExamItem[] = [];
      for (let i = 0; i < all.length; i++) {
        if (all[i].type === EasEventType.EXAM) {
          const it: EasExamItem = new EasExamItem();
          it.courseName = all[i].name;
          it.examLocation = all[i].place;
          it.campusName = '演示校区';
          const d: Date = new Date(all[i].from);
          it.examDate = ExamPage.pad(d.getFullYear()) + '-' + ExamPage.pad(d.getMonth() + 1) + '-' +
            ExamPage.pad(d.getDate());
          it.examTime = ExamPage.pad(d.getHours()) + ':' + ExamPage.pad(d.getMinutes()) +
            ' ~ ' + ExamPage.timeOf(all[i].to);
          it.termName = '2023-2024-1（演示）';
          it.examType = '期中/考前';
          list.push(it);
        }
      }
      if (list.length > 0) {
        this.exams = list;
        this.note = '来自本地事件中的考试（' + list.length.toString() + ' 条）';
        return;
      }
    }
    // 无本地考试 → 内置样例
    this.loadSample();
  }

  loadSample(): void {
    const list: EasExamItem[] = [];
    const mk = (course: string, date: string, time: string, loc: string, type: string): void => {
      const it: EasExamItem = new EasExamItem();
      it.courseName = course;
      it.examDate = date;
      it.examTime = time;
      it.examType = type;
      it.examLocation = loc;
      it.termName = '2023-2024-1';
      it.campusName = '深圳校区';
      list.push(it);
    };
    mk('数据结构', '2026-01-08', '09:00 ~ 11:00', 'H-201', '期末考试');
    mk('高等数学A', '2026-01-12', '14:00 ~ 16:00', 'A-305', '期末考试');
    mk('大学英语', '2026-01-16', '09:00 ~ 10:40', 'T-102', '期末考试');
    this.exams = list;
    this.note = '内置样例（真实查询依赖 M0/M2 端点）';
  }

  static pad(n: number): string {
    return n < 10 ? '0' + n.toString() : n.toString();
  }

  static timeOf(ms: number): string {
    const d: Date = new Date(ms);
    return ExamPage.pad(d.getHours()) + ':' + ExamPage.pad(d.getMinutes());
  }

  build() {
    Column() {
      Row() {
        Text('‹')
          .fontSize(30)
          .fontColor('#1A1A1A')
          .fontWeight(FontWeight.Bold)
          .width(44)
          .height(44)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.navigateBack();
          })

        Text('考试查询')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1A1A1A')
          .layoutWeight(1)
          .margin({ left: 4 })

        Text('载入样例')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#667085')
          .height(32)
          .padding({ left: 12, right: 12 })
          .borderRadius(16)
          .backgroundColor('#F2F4F7')
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.loadSample();
          })
      }
      .width('100%')
      .padding({ left: 8, right: 16, top: 8, bottom: 8 })
      .backgroundColor('#FFFFFF')
      .border({ width: { bottom: 1 }, color: '#EAECF0' })
      .alignItems(VerticalAlign.Center)

      Text(this.note)
        .fontSize(12)
        .fontColor('#666666')
        .width('100%')
        .padding({ left: 16, bottom: 8 })

      if (this.exams.length === 0) {
        Text('暂无考试')
          .fontSize(14)
          .fontColor('#888888')
          .margin({ top: 60 })
      } else {
        List({ space: 8 }) {
          ForEach(this.exams, (it: EasExamItem) => {
            ListItem() {
              Column() {
                Row() {
                  Text(it.courseName)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .layoutWeight(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(it.examType.length > 0 ? it.examType : '—')
                    .fontSize(11)
                    .fontColor('#FFFFFF')
                    .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                    .borderRadius(8)
                    .backgroundColor('#D93025')
                }
                .width('100%')

                Text(it.examDate + '  ' + it.examTime)
                  .fontSize(13)
                  .fontColor('#333333')
                  .width('100%')
                  .margin({ top: 8 })

                Text((it.examLocation.length > 0 ? '地点：' + it.examLocation : '地点：待定') +
                  '   ' + (it.campusName.length > 0 ? it.campusName : it.termName))
                  .fontSize(12)
                  .fontColor('#8A8F99')
                  .width('100%')
                  .margin({ top: 6 })
              }
              .width('100%')
              .padding(12)
              .backgroundColor('#FFFFFF')
              .borderRadius(10)
              .shadow({ radius: 8, color: '#14000000', offsetY: 2 })
            }
          }, (it: EasExamItem) => it.courseName + it.examDate + it.examTime)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 12, right: 12 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F6F8')
  }

  navigateBack(): void {
    this.getUIContext().getRouter().back();
  }
}
