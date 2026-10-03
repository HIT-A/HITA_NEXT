/**
 * ExamPage.ets — 考试查询。
 *
 * 数据面：聚合本地全部课表中类型为考试（EXAM）的事件，按时间升序展示；
 * 右上角「添加考试」可将考试事件录入当前课表。
 */
import { common } from '@kit.AbilityKit';
import { HeaderBackButton } from '../common/components/HeaderBackButton';
import { EasExamItem } from '../feature/eas/model/EasModels';
import { RdbHelper } from '../common/db/RdbHelper';
import { EasEventItem, EasEventType, EasTimetable } from '../common/model/timetable/TimetableModels';
import { TimetableSelectionStore } from '../feature/timetable/data/TimetableSelectionStore';
import { EventEditorForm } from './AddEventPage';

@Entry
@Component
struct ExamPage {
  @State exams: EasExamItem[] = [];
  /** 添加考试弹层只看这一个开关；内容在 onDisappear 里复位。 */
  @State sheetVisible: boolean = false;
  private targetTimetableId: string = '';

  async onPageShow(): Promise<void> {
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    const rdb: RdbHelper = RdbHelper.getInstance();
    await rdb.init(ctx);
    const timetables: EasTimetable[] = await rdb.getTimetables();
    const events: EasEventItem[] = [];
    for (let t = 0; t < timetables.length; t++) {
      const all: EasEventItem[] = await rdb.getEventsOfTimetable(timetables[t].id);
      for (let i = 0; i < all.length; i++) {
        if (all[i].type === EasEventType.EXAM) {
          events.push(all[i]);
        }
      }
    }
    events.sort((a: EasEventItem, b: EasEventItem): number => a.from - b.from);
    const list: EasExamItem[] = [];
    for (let i = 0; i < events.length; i++) {
      const it: EasExamItem = new EasExamItem();
      it.courseName = events[i].name;
      it.examLocation = events[i].place;
      const d: Date = new Date(events[i].from);
      it.examDate = ExamPage.pad(d.getFullYear()) + '-' + ExamPage.pad(d.getMonth() + 1) + '-' +
        ExamPage.pad(d.getDate());
      it.examTime = ExamPage.pad(d.getHours()) + ':' + ExamPage.pad(d.getMinutes()) +
        ' ~ ' + ExamPage.timeOf(events[i].to);
      it.examType = '考试';
      it.termName = '';
      it.campusName = '';
      list.push(it);
    }
    this.exams = list;
  }

  /** 考试事件挂到当前选中的课表；没有可用课表时引导先建课表。 */
  private async openAddExam(): Promise<void> {
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    await TimetableSelectionStore.getInstance().init(ctx);
    const rdb: RdbHelper = RdbHelper.getInstance();
    await rdb.init(ctx);
    let target: string = await TimetableSelectionStore.getInstance().load();
    if (target.length === 0 || await rdb.getTimetableById(target) === undefined) {
      target = '';
      const timetables: EasTimetable[] = await rdb.getTimetables();
      if (timetables.length > 0) {
        target = timetables[0].id;
      }
    }
    if (target.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请先在课表管理中新建课表' });
      return;
    }
    this.targetTimetableId = target;
    this.sheetVisible = true;
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
        HeaderBackButton({
          onBack: () => this.navigateBack()
        })
          .margin({ right: 12 })
        Text('考试查询')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1A1A1A')
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text('+ 添加考试')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .height(32)
          .padding({ left: 12, right: 12 })
          .borderRadius(16)
          .backgroundColor('#3390EC')
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.openAddExam();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .backgroundColor('#FFFFFF')
      .border({ width: { bottom: 1 }, color: '#EAECF0' })
      .alignItems(VerticalAlign.Center)

      if (this.exams.length === 0) {
        Column() {
          Text('暂无考试安排')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#1A1A1A')
          Text('点击右上角“添加考试”录入考试安排')
            .fontSize(13)
            .fontColor('#888888')
            .margin({ top: 8 })
        }
        .width('100%')
        .margin({ top: 60 })
      } else {
        List({ space: 8 }) {
          ForEach(this.exams, (it: EasExamItem) => {
            ListItem() {
              Row() {
                Row()
                  .width(18)
                  .height(54)
                  .borderRadius(9)
                  .backgroundColor('#D93025')
                Column() {
                  Row() {
                    Text(it.courseName)
                      .fontSize(16)
                      .fontWeight(FontWeight.Medium)
                      .fontColor('#242A36')
                      .layoutWeight(1)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(it.examType.length > 0 ? it.examType : '考试')
                      .fontSize(11)
                      .fontColor('#D93025')
                      .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                      .backgroundColor('#FDECEC')
                      .borderRadius(10)
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Center)

                  Text(it.examDate + ' · ' + it.examTime)
                    .fontSize(12)
                    .fontColor('#7B8498')
                    .width('100%')
                    .margin({ top: 7 })
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })

                  Text(it.examLocation.length > 0 ? '地点：' + it.examLocation : '地点：待定')
                    .fontSize(12)
                    .fontColor('#9AA2B1')
                    .width('100%')
                    .margin({ top: 4 })
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                .margin({ left: 12 })
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: 12, bottom: 12 })
              .backgroundColor('#FFFFFF')
              .borderRadius(16)
            }
          }, (it: EasExamItem) => it.courseName + it.examDate + it.examTime)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, top: 4 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F6F7FA')
    .bindSheet(this.sheetVisible, this.examEditorContent(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      preferType: SheetType.BOTTOM,
      backgroundColor: '#F6F8FC',
      maskColor: 'rgba(20,33,61,0.24)',
      onDisappear: () => {
        this.sheetVisible = false;
      }
    })
  }

  @Builder
  private examEditorContent() {
    EventEditorForm({
      eventId: '',
      targetTimetableId: this.targetTimetableId,
      initialType: 'EXAM',
      sheetMode: true,
      onCancel: () => {
        this.sheetVisible = false;
      },
      onSaved: () => {
        this.sheetVisible = false;
        this.onPageShow();
      }
    })
      .width('100%')
      .height('100%');
  }

  navigateBack(): void {
    this.getUIContext().getRouter().back();
  }
}
