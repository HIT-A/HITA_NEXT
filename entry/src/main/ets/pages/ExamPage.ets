/**
 * ExamPage.ets — 考试查询。
 *
 * 数据面：聚合本地全部课表中类型为考试（EXAM）的事件，按时间升序展示；
 * 新建考试写入当前课表，编辑和删除始终使用考试原有的事件 ID。
 * 已登录教务时，可查询深圳校区考试安排并导入当前课表。
 */
import { common } from '@kit.AbilityKit';
import { HeaderBackButton } from '../common/components/HeaderBackButton';
import { HeaderFadeMask } from '../common/components/HeaderFadeMask';
import { HeaderFade } from '../common/theme/HeaderFade';
import { STATUS_BAR_INSET_FALLBACK } from '../common/theme/StatusBarInset';
import { RdbHelper } from '../common/db/RdbHelper';
import { EasEventItem, EasEventType, EasTimetable } from '../common/model/timetable/TimetableModels';
import { DOW_FULL, EasTimeTools } from '../common/util/EasTimeTools';
import { TimetableSelectionStore } from '../feature/timetable/data/TimetableSelectionStore';
import { EasCampus, EasSession } from '../feature/eas/EasSession';
import { EasSessionStore } from '../feature/eas/EasSessionStore';
import { EasDataProvider } from '../feature/eas/EasDataProvider';
import { EasApiClient } from '../feature/eas/EasApiClient';
import { EasExamItem, EasTermItem } from '../feature/eas/model/EasModels';
import { ExamSchedule } from '../feature/eas/ExamSchedule';
import { EventEditorForm } from './AddEventPage';

const HEADER_HEIGHT: number = 60;
const PAGE_BG: string = '#F6F7FA';
const PAGE_BG_RGB: string = '246,247,250';

@Entry
@Component
struct ExamPage {
  @State exams: EasEventItem[] = [];
  @State upcoming: EasEventItem[] = [];
  @State past: EasEventItem[] = [];
  @State remoteExams: EasExamItem[] = [];
  @State loading: boolean = true;
  @State querying: boolean = false;
  @State loadError: boolean = false;
  @State pendingDeleteId: string = '';
  @State openingEditor: boolean = false;
  @State hasSession: boolean = false;
  @State queryMsg: string = '';
  @StorageProp('hita_status_bar_vp') statusBarInset: number = STATUS_BAR_INSET_FALLBACK;
  /** Keep the editor identity until its dismissal animation finishes. */
  @State sheetVisible: boolean = false;
  /** 0=closed, 1=exam detail, 2=editor, 3=remote exam detail. */
  @State examSheetMode: number = 0;
  @State selectedExam: EasEventItem | undefined = undefined;
  @State selectedRemote: EasExamItem | undefined = undefined;
  @State sheetEventId: string = '';
  @State targetTimetableId: string = '';
  @State fadeOpacity: number = 0;
  private pageScroller: Scroller = new Scroller();
  private session: EasSession | undefined = undefined;

  async aboutToAppear(): Promise<void> {
    await this.refreshSession();
  }

  async onPageShow(): Promise<void> {
    await this.refreshSession();
    await this.loadExams();
  }

  private async refreshSession(): Promise<void> {
    try {
      const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
      await EasSessionStore.getInstance().init(ctx);
      const order: EasCampus[] = [EasCampus.SHENZHEN, EasCampus.BENBU, EasCampus.WEIHAI];
      this.session = undefined;
      for (let i = 0; i < order.length; i++) {
        const s: EasSession | undefined = await EasSessionStore.getInstance().load(order[i]);
        if (s !== undefined && s.isLogin()) {
          this.session = s;
          break;
        }
      }
      this.hasSession = this.session !== undefined;
    } catch (_) {
      this.hasSession = false;
    }
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
      const now: number = Date.now();
      this.upcoming = events.filter((event: EasEventItem): boolean => ExamSchedule.isUpcoming(event.to, now));
      this.past = events.filter((event: EasEventItem): boolean => !ExamSchedule.isUpcoming(event.to, now));
      this.remoteExams = this.filterImported(this.remoteExams, events);
    } catch (_) {
      this.loadError = true;
    } finally {
      this.loading = false;
    }
  }

  private filterImported(items: EasExamItem[], events: EasEventItem[]): EasExamItem[] {
    const kept: EasExamItem[] = [];
    for (let i = 0; i < items.length; i++) {
      let exists: boolean = false;
      for (let j = 0; j < events.length; j++) {
        if (ExamSchedule.sameAsEvent(items[i], events[j])) {
          exists = true;
          break;
        }
      }
      if (!exists) {
        kept.push(items[i]);
      }
    }
    return kept;
  }

  private async resolveTargetTimetable(): Promise<string> {
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
    return target;
  }

  /** 考试事件挂到当前选中的课表；没有可用课表时引导先建课表。 */
  private async openAddExam(): Promise<void> {
    if (this.examSheetMode !== 0 || this.openingEditor || this.pendingDeleteId.length > 0) {
      return;
    }
    this.openingEditor = true;
    try {
      const target: string = await this.resolveTargetTimetable();
      if (target.length === 0) {
        this.getUIContext().getPromptAction().showToast({ message: '请先在课表管理中新建课表' });
        return;
      }
      this.sheetEventId = '';
      this.targetTimetableId = target;
      this.selectedExam = undefined;
      this.selectedRemote = undefined;
      this.examSheetMode = 2;
      this.sheetVisible = true;
    } catch (_) {
      this.getUIContext().getPromptAction().showToast({ message: '暂时无法打开考试编辑，请重试' });
    } finally {
      this.openingEditor = false;
    }
  }

  private async queryEasExams(): Promise<void> {
    if (this.querying || this.openingEditor || this.pendingDeleteId.length > 0) {
      return;
    }
    if (this.session === undefined) {
      this.queryMsg = '请先登录教务';
      this.getUIContext().getPromptAction().showToast({ message: '请先登录教务后再查询考试' });
      return;
    }
    this.querying = true;
    this.queryMsg = '正在查询…';
    try {
      const provider: EasDataProvider = new EasDataProvider(new EasApiClient());
      const terms: EasTermItem[] = await provider.getAllTerms(this.session);
      if (terms.length === 0) {
        this.queryMsg = '未获取到学期信息，请稍后重试';
        return;
      }
      const items: EasExamItem[] = await provider.getExamItems(this.session, terms[0]);
      this.remoteExams = this.filterImported(items, this.exams);
      this.queryMsg = this.remoteExams.length > 0 ?
        '教务返回 ' + this.remoteExams.length.toString() + ' 条待导入考试' :
        (items.length > 0 ? '教务考试已全部在本地课表中' : '本学期暂无教务考试安排');
    } catch (e) {
      this.queryMsg = '查询失败：' + (e as Error).message;
    } finally {
      this.querying = false;
    }
  }

  private async importRemoteExam(item: EasExamItem): Promise<void> {
    if (this.openingEditor || this.pendingDeleteId.length > 0) {
      return;
    }
    this.openingEditor = true;
    try {
      const target: string = await this.resolveTargetTimetable();
      if (target.length === 0) {
        this.getUIContext().getPromptAction().showToast({ message: '请先在课表管理中新建课表' });
        return;
      }
      const event: EasEventItem | undefined = ExamSchedule.toEvent(item, target);
      if (event === undefined) {
        this.getUIContext().getPromptAction().showToast({ message: '考试时间无法识别，请手动添加' });
        return;
      }
      await RdbHelper.getInstance().saveEvent(event);
      this.closeSheet();
      await this.loadExams();
      this.getUIContext().getPromptAction().showToast({ message: '已导入到当前课表' });
    } catch (_) {
      this.getUIContext().getPromptAction().showToast({ message: '导入失败，请重试' });
    } finally {
      this.openingEditor = false;
    }
  }

  private openExamDetail(event: EasEventItem): void {
    if (this.examSheetMode !== 0 || this.openingEditor || this.pendingDeleteId.length > 0) {
      return;
    }
    this.selectedExam = event;
    this.selectedRemote = undefined;
    this.sheetEventId = event.id;
    this.targetTimetableId = event.timetableId;
    this.examSheetMode = 1;
    this.sheetVisible = true;
  }

  private openRemoteDetail(item: EasExamItem): void {
    if (this.examSheetMode !== 0 || this.openingEditor || this.pendingDeleteId.length > 0) {
      return;
    }
    this.selectedRemote = item;
    this.selectedExam = undefined;
    this.sheetEventId = '';
    this.examSheetMode = 3;
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
    this.selectedRemote = undefined;
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
    return ExamSchedule.timeOf(ms);
  }

  static dateOf(ms: number): string {
    return ExamSchedule.dateOf(ms);
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.loading && this.exams.length === 0 && this.remoteExams.length === 0) {
        LoadingProgress()
          .width(36)
          .height(36)
          .margin({ top: HEADER_HEIGHT + 60 })
      } else if (this.loadError && this.exams.length === 0) {
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
        .margin({ top: HEADER_HEIGHT })
      } else if (!this.loadError && this.exams.length === 0 && this.remoteExams.length === 0) {
        Column() {
          Text('暂无考试安排')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#1A1A1A')
          Text(this.hasSession ? '点击右上角“查询”从教务同步，或手动添加考试' : '登录教务后可查询考试，也可手动添加')
            .fontSize(13)
            .fontColor('#808080')
            .textAlign(TextAlign.Center)
            .lineHeight(20)
            .margin({ top: 8, bottom: 20 })
          if (this.queryMsg.length > 0) {
            Text(this.queryMsg)
              .fontSize(12)
              .fontColor('#D93025')
              .margin({ bottom: 12 })
          }
          Text('添加考试')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .height(44)
            .padding({ left: 32, right: 32 })
            .backgroundColor('#3390EC')
            .borderRadius(22)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.openAddExam();
            })
        }
        .width('100%')
        .margin({ top: HEADER_HEIGHT + 40 })
        .padding({ left: 32, right: 32 })
        .alignItems(HorizontalAlign.Center)
      } else {
        List({ space: 8, scroller: this.pageScroller }) {
          ListItem() {
            Column()
              .width('100%')
              .height(HEADER_HEIGHT)
          }
          if (this.queryMsg.length > 0) {
            ListItem() {
              Text(this.queryMsg)
                .fontSize(12)
                .fontColor('#2E7D32')
                .width('100%')
            }
          }
          if (this.loadError) {
            ListItem() {
              Row() {
                Text('考试安排加载失败')
                  .fontSize(14)
                  .fontColor('#D93025')
                  .layoutWeight(1)
                Button('重试')
                  .onClick(() => this.loadExams())
              }
              .width('100%')
            }
          }
          if (this.upcoming.length > 0) {
            ListItem() {
              Text('即将到来')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor('#72809A')
            }
          }
          ForEach(this.upcoming, (it: EasEventItem) => {
            ListItem() {
              this.examCard(it)
            }
          }, (it: EasEventItem) => it.id)
          if (this.remoteExams.length > 0) {
            ListItem() {
              Text('教务查询')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor('#72809A')
            }
          }
          ForEach(this.remoteExams, (remote: EasExamItem) => {
            ListItem() {
              this.remoteExamCard(remote)
            }
          }, (remote: EasExamItem) => remote.courseName + '|' + remote.examDate + '|' + remote.examTime +
            '|' + remote.examLocation)
          if (this.past.length > 0) {
            ListItem() {
              Text('已结束')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor('#72809A')
            }
          }
          ForEach(this.past, (it: EasEventItem) => {
            ListItem() {
              this.examCard(it)
            }
          }, (it: EasEventItem) => it.id)
        }
        .width('100%')
        .height('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 24 })
        .scrollBar(BarState.Off)
        .onDidScroll(() => {
          this.fadeOpacity = HeaderFade.opacity(this.pageScroller.currentOffset().yOffset);
        })
      }

      HeaderFadeMask({
        maskOpacity: this.fadeOpacity,
        rgb: PAGE_BG_RGB,
        headerHeight: HEADER_HEIGHT
      })

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

        this.headerAction(this.querying ? '查询中' : '查询',
          !this.querying && this.pendingDeleteId.length === 0, () => {
            this.queryEasExams();
          })
        this.headerAction('添加考试',
          !this.openingEditor && this.pendingDeleteId.length === 0, () => {
            this.openAddExam();
          })
      }
      .width('100%')
      .height(HEADER_HEIGHT)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.statusBarInset })
    .backgroundColor(PAGE_BG)
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
  private examCard(it: EasEventItem) {
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
          Text(ExamSchedule.remainingLabel(it.from, it.to, Date.now()))
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

  @Builder
  private remoteExamCard(remote: EasExamItem) {
    Row() {
      Row()
        .width(18)
        .height(54)
        .borderRadius(9)
        .backgroundColor('#3390EC')
      Column() {
        Row() {
          Text(remote.courseName)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#242A36')
            .layoutWeight(1)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('教务')
            .fontSize(11)
            .fontColor('#3390EC')
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .backgroundColor('#EBF4FC')
            .borderRadius(10)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text((remote.examDate.length > 0 ? remote.examDate : '日期待定') +
          (remote.examTime.length > 0 ? ' · ' + remote.examTime : ''))
          .fontSize(13)
          .fontColor('#7B8498')
          .width('100%')
          .margin({ top: 7 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(remote.examLocation.length > 0 ? '地点：' + remote.examLocation : '地点：待定')
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
    .onClick(() => this.openRemoteDetail(remote))
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
        onSaved: (_event: EasEventItem) => {
          this.closeSheet();
          this.loadExams();
        }
      })
        .width('100%')
        .height('100%');
    } else if (this.examSheetMode === 3 && this.selectedRemote !== undefined) {
      this.remoteDetailSheet(this.selectedRemote as EasExamItem);
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
      this.examDetailRow($r('sys.symbol.checkmark'), '状态',
        ExamSchedule.remainingLabel(event.from, event.to, Date.now()))

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
  private remoteDetailSheet(item: EasExamItem) {
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
          .backgroundColor('#3390EC')
        Column() {
          Text(item.courseName)
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
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: 14 })

      this.examDetailRow($r('sys.symbol.clock'), '时间',
        item.examTime.length > 0 ? item.examTime : '待定')
      this.examDetailRow($r('sys.symbol.calendar'), '日期',
        item.examDate.length > 0 ? item.examDate : '待定')
      this.examDetailRow($r('sys.symbol.pin'), '地点',
        item.examLocation.length > 0 ? item.examLocation : '待定')
      this.examDetailRow($r('sys.symbol.checkmark'), '类型',
        item.examType.length > 0 ? item.examType : '未填写')
      this.examDetailRow($r('sys.symbol.doc_plaintext'), '学期',
        item.termName.length > 0 ? item.termName : '未填写')
      this.examDetailRow($r('sys.symbol.magnifyingglass'), '校区',
        item.campusName.length > 0 ? item.campusName : '未填写')

      Row() {
        Blank()
        Text('导入到课表')
          .fontSize(14)
          .fontColor('#FFFFFF')
          .fontWeight(FontWeight.Medium)
          .padding({ left: 14, right: 14, top: 9, bottom: 9 })
          .backgroundColor('#3390EC')
          .borderRadius(18)
          .enabled(!this.openingEditor)
          .onClick(() => this.importRemoteExam(item))
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

  @Builder
  private headerAction(label: string, enabled: boolean, onAction: () => void) {
    Text(label)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor('#3390EC')
      .height(32)
      .padding({ left: 12, right: 12 })
      .borderRadius(16)
      .backgroundColor('#EBF4FC')
      .textAlign(TextAlign.Center)
      .margin({ left: 8 })
      .flexShrink(0)
      .enabled(enabled)
      .onClick(() => {
        onAction();
      })
  }

  navigateBack(): void {
    this.getUIContext().getRouter().back();
  }
}
