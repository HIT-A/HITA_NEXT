/**
 * ExamPage.ets — 考试查询。
 *
 * 数据面：聚合本地全部课表中类型为考试（EXAM）的事件，按时间升序展示；
 * 新建考试写入当前课表，编辑和删除始终使用考试原有的事件 ID。
 */
import { common } from '@kit.AbilityKit';
import { HeaderBackButton } from '../common/components/HeaderBackButton';
import { RdbHelper } from '../common/db/RdbHelper';
import { EasEventItem, EasEventType, EasTimetable } from '../common/model/timetable/TimetableModels';
import { DOW_FULL, EasTimeTools } from '../common/util/EasTimeTools';
import { TimetableSelectionStore } from '../feature/timetable/data/TimetableSelectionStore';
import { EventEditorForm } from './AddEventPage';

@Entry
@Component
struct ExamPage {
  @State exams: EasEventItem[] = [];
  @State loading: boolean = true;
  @State loadError: boolean = false;
  @State pendingDeleteId: string = '';
  @State openingEditor: boolean = false;
  /** Keep the editor identity until its dismissal animation finishes. */
  @State sheetVisible: boolean = false;
  /** 0=closed, 1=exam detail, 2=editor, matching the course sheet. */
  @State examSheetMode: number = 0;
  @State selectedExam: EasEventItem | undefined = undefined;
  @State sheetEventId: string = '';
  @State targetTimetableId: string = '';

  async onPageShow(): Promise<void> {
    await this.loadExams();
  }

  private async loadExams(): Promise<void> {
    this.loading = true;
    this.loadError = false;
    try {
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
      this.exams = events;
    } catch (_) {
      this.loadError = true;
    } finally {
      this.loading = false;
    }
  }

  /** 考试事件挂到当前选中的课表；没有可用课表时引导先建课表。 */
  private async openAddExam(): Promise<void> {
    if (this.examSheetMode !== 0 || this.openingEditor || this.pendingDeleteId.length > 0) {
      return;
    }
    this.openingEditor = true;
    try {
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
      this.sheetEventId = '';
      this.targetTimetableId = target;
      this.selectedExam = undefined;
      this.examSheetMode = 2;
      this.sheetVisible = true;
    } catch (_) {
      this.getUIContext().getPromptAction().showToast({ message: '暂时无法打开考试编辑，请重试' });
    } finally {
      this.openingEditor = false;
    }
  }

  private openExamDetail(event: EasEventItem): void {
    if (this.examSheetMode !== 0 || this.openingEditor || this.pendingDeleteId.length > 0) {
      return;
    }
    this.selectedExam = event;
    this.sheetEventId = event.id;
    this.targetTimetableId = event.timetableId;
    this.examSheetMode = 1;
    this.sheetVisible = true;
  }

  private openEditExam(event: EasEventItem): void {
    if (this.pendingDeleteId.length > 0 || this.examSheetMode !== 1 || !this.sheetVisible) {
      return;
    }
    this.sheetEventId = event.id;
    this.targetTimetableId = event.timetableId;
    this.examSheetMode = 2;
  }

  private closeSheet(): void {
    this.sheetVisible = false;
  }

  private resetSheetState(): void {
    this.examSheetMode = 0;
    this.selectedExam = undefined;
    this.sheetEventId = '';
    this.targetTimetableId = '';
  }

  private async confirmDeleteExam(event: EasEventItem): Promise<void> {
    if (this.pendingDeleteId.length > 0 || this.examSheetMode === 2 || this.openingEditor) {
      return;
    }
    this.pendingDeleteId = event.id;
    let confirmed: boolean = false;
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: '删除考试',
        message: '确定删除「' + event.name + '」吗？仅删除这条考试安排，不影响其他课程。',
        buttons: [
          { text: '取消', color: '#7B8498' },
          { text: '删除', color: '#D93025' }
        ]
      });
      confirmed = result.index === 1;
    } catch (_) {
      // Back or tapping outside the confirmation dialog is cancellation.
    }
    if (!confirmed) {
      this.pendingDeleteId = '';
      return;
    }
    try {
      await RdbHelper.getInstance().deleteEvent(event.id);
      this.closeSheet();
      await this.loadExams();
      this.getUIContext().getPromptAction().showToast({ message: '考试已删除' });
    } catch (_) {
      this.getUIContext().getPromptAction().showToast({ message: '删除失败，请重试' });
    } finally {
      this.pendingDeleteId = '';
    }
  }

  static pad(n: number): string {
    return n < 10 ? '0' + n.toString() : n.toString();
  }

  static timeOf(ms: number): string {
    const d: Date = new Date(ms);
    return ExamPage.pad(d.getHours()) + ':' + ExamPage.pad(d.getMinutes());
  }

  static dateOf(ms: number): string {
    const d: Date = new Date(ms);
    return d.getFullYear().toString() + '-' + ExamPage.pad(d.getMonth() + 1) + '-' +
      ExamPage.pad(d.getDate());
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

        Button({ type: ButtonType.Normal }) {
          Row({ space: 5 }) {
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(16)
              .fontColor(['#FFFFFF'])
            Text('添加考试')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
          }
        }
          .fontColor('#FFFFFF')
          .height(40)
          .padding({ left: 12, right: 12 })
          .borderRadius(20)
          .flexShrink(0)
          .backgroundColor('#3390EC')
          .enabled(!this.openingEditor && this.pendingDeleteId.length === 0)
          .onClick(() => {
            this.openAddExam();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .backgroundColor('#FFFFFF')
      .border({ width: { bottom: 1 }, color: '#EAECF0' })
      .alignItems(VerticalAlign.Center)

      if (this.loadError) {
        Row() {
          Text('考试安排加载失败')
            .fontSize(14)
            .fontColor('#D93025')
            .layoutWeight(1)
          Button('重试')
            .onClick(() => this.loadExams())
        }
        .padding(16)
        .width('100%')
      }

      if (this.loading && this.exams.length === 0) {
        LoadingProgress()
          .width(36)
          .height(36)
          .margin({ top: 60 })
      } else if (!this.loadError && this.exams.length === 0) {
        Column() {
          Text('暂无考试安排')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#1A1A1A')
        }
        .width('100%')
        .margin({ top: 60 })
      } else {
        List({ space: 8 }) {
          ForEach(this.exams, (it: EasEventItem) => {
            ListItem() {
              Row() {
                Row()
                  .width(18)
                  .height(54)
                  .borderRadius(9)
                  .backgroundColor('#D93025')
                Column() {
                  Row() {
                    Text(it.name)
                      .fontSize(16)
                      .fontWeight(FontWeight.Medium)
                      .fontColor('#242A36')
                      .layoutWeight(1)
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text('考试')
                      .fontSize(11)
                      .fontColor('#D93025')
                      .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                      .backgroundColor('#FDECEC')
                      .borderRadius(10)
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Center)

                  Text(ExamPage.dateOf(it.from) + ' · ' + ExamPage.timeOf(it.from) + ' - ' +
                    ExamPage.timeOf(it.to))
                    .fontSize(13)
                    .fontColor('#7B8498')
                    .width('100%')
                    .margin({ top: 7 })
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })

                  Text(it.place.length > 0 ? '地点：' + it.place : '地点：待定')
                    .fontSize(13)
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
              .onClick(() => this.openExamDetail(it))
            }
          }, (it: EasEventItem) => it.id)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, top: 12, bottom: 24 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F6F7FA')
    .bindSheet(this.sheetVisible, this.examSheetContent(), {
      height: this.examSheetMode === 2 ? '78%' : SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      preferType: SheetType.BOTTOM,
      backgroundColor: '#F6F8FC',
      maskColor: 'rgba(20,33,61,0.24)',
      onDisappear: () => {
        this.sheetVisible = false;
        this.resetSheetState();
      }
    })
  }

  @Builder
  private examSheetContent() {
    if (this.examSheetMode === 2) {
      EventEditorForm({
        eventId: this.sheetEventId,
        targetTimetableId: this.targetTimetableId,
        initialType: 'EXAM',
        sheetMode: true,
        onCancel: () => {
          this.closeSheet();
        },
        onSaved: () => {
          this.closeSheet();
          this.loadExams();
        }
      })
        .width('100%')
        .height('100%');
    } else if (this.selectedExam !== undefined) {
      this.examDetailSheet(this.selectedExam as EasEventItem);
    }
  }

  @Builder
  private examDetailSheet(event: EasEventItem) {
    Column() {
      Row() {
        HeaderBackButton({
          onBack: () => this.closeSheet()
        })
          .margin({ right: 12 })
        Row()
          .width(7)
          .height(50)
          .borderRadius(4)
          .backgroundColor('#D93025')
        Column() {
          Text(event.name)
            .fontSize(21)
            .fontWeight(FontWeight.Bold)
            .fontColor('#202B45')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('考试详情')
            .fontSize(13)
            .fontColor('#72809A')
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 12, right: 8 })
        Text('编辑')
          .fontSize(14)
          .fontColor('#3390EC')
          .fontWeight(FontWeight.Medium)
          .padding({ left: 8, right: 8, top: 8, bottom: 8 })
          .flexShrink(0)
          .enabled(this.pendingDeleteId.length === 0)
          .onClick(() => this.openEditExam(event))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: 14 })

      this.examDetailRow($r('sys.symbol.person_crop_circle_fill'), '老师',
        event.teacher.trim().length > 0 ? event.teacher : '未填写')
      this.examDetailRow($r('sys.symbol.pin'), '考场',
        event.place.trim().length > 0 ? event.place : '待定')
      this.examDetailRow($r('sys.symbol.clock'), '时间',
        ExamPage.timeOf(event.from) + ' - ' + ExamPage.timeOf(event.to))
      this.examDetailRow($r('sys.symbol.calendar'), '日期',
        ExamPage.dateOf(event.from) + ' · ' + DOW_FULL[EasTimeTools.getDow(event.from)])

      Row() {
        Blank()
        Text('删除考试')
          .fontSize(14)
          .fontColor('#D93025')
          .fontWeight(FontWeight.Medium)
          .padding({ left: 14, right: 14, top: 9, bottom: 9 })
          .backgroundColor('#FDECEC')
          .borderRadius(18)
          .enabled(this.pendingDeleteId.length === 0)
          .onClick(() => this.confirmDeleteExam(event))
      }
      .width('100%')
      .margin({ top: 6 })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 4, bottom: 20 })
  }

  @Builder
  private examDetailRow(symbol: Resource, label: string, value: string) {
    Row() {
      Stack() {
        SymbolGlyph(symbol)
          .fontSize(20)
          .fontColor(['#3390EC'])
      }
      .width(38)
      .height(38)
      .borderRadius(19)
      .backgroundColor('#E4F0FF')
      .alignContent(Alignment.Center)
      Column() {
        Text(label)
          .fontSize(12)
          .fontColor('#72809A')
        Text(value)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor('#202B45')
          .margin({ top: 2 })
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
  }

  navigateBack(): void {
    this.getUIContext().getRouter().back();
  }
}
