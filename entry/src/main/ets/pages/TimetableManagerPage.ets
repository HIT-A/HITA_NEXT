/** Android HITA-style timetable library. */
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { RdbHelper } from '../common/db/RdbHelper';
import { EasTimetable } from '../common/model/timetable/TimetableModels';
import { HitaColors } from '../common/theme/HitaColors';
import { IcsExporter } from '../common/util/ICSExport';
import { TimetableSelectionStore } from '../feature/timetable/data/TimetableSelectionStore';

const WEEK_MS: number = 7 * 24 * 60 * 60 * 1000;

@Entry
@Component
struct TimetableManagerPage {
  @State timetables: EasTimetable[] = [];
  @State selectedIds: string[] = [];
  @State selectionMode: boolean = false;
  @State loading: boolean = true;
  @State exporting: boolean = false;
  @State activeTimetableId: string = '';

  async onPageShow(): Promise<void> {
    await this.load();
  }

  private async load(): Promise<void> {
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    await TimetableSelectionStore.getInstance().init(ctx);
    const rdb: RdbHelper = RdbHelper.getInstance();
    await rdb.init(ctx);
    this.timetables = await rdb.getTimetables();
    this.activeTimetableId = await TimetableSelectionStore.getInstance().load();
    this.loading = false;
  }

  private selected(id: string): boolean {
    return this.selectedIds.indexOf(id) >= 0;
  }

  private toggleSelection(id: string): void {
    const next: string[] = [];
    let found: boolean = false;
    for (let i: number = 0; i < this.selectedIds.length; i++) {
      if (this.selectedIds[i] === id) {
        found = true;
      } else {
        next.push(this.selectedIds[i]);
      }
    }
    if (!found) {
      next.push(id);
    }
    this.selectedIds = next;
    this.selectionMode = next.length > 0;
  }

  private async openTimetable(timetable: EasTimetable): Promise<void> {
    if (this.selectionMode) {
      this.toggleSelection(timetable.id);
      return;
    }
    await TimetableSelectionStore.getInstance().save(timetable.id);
    this.activeTimetableId = timetable.id;
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/TimetableDetailPage',
      params: { 'timetableId': timetable.id }
    });
  }

  private openAddMenu(): void {
    this.getUIContext().getPromptAction().showActionMenu({
      title: '添加课表',
      buttons: [
        { text: '新建空课表', color: HitaColors.primary },
        { text: '从教务导入', color: HitaColors.primary }
      ]
    }).then((ret) => {
      if (ret.index === 0) {
        this.createEmptyTimetable();
      } else if (ret.index === 1) {
        this.openImportPage();
      }
    }).catch(() => {
    });
  }

  private openImportPage(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/ImportTimetablePage' });
  }

  private async createEmptyTimetable(): Promise<void> {
    const now: number = Date.now();
    const timetable: EasTimetable = new EasTimetable();
    timetable.name = TimetableManagerPage.defaultName(now);
    timetable.code = 'LOCAL:' + timetable.id;
    timetable.startTime = EasTimetable.mondayMsOf(now);
    timetable.endTime = timetable.startTime + 20 * WEEK_MS - 1;
    timetable.createdAt = now;
    await RdbHelper.getInstance().saveTimetable(timetable);
    await TimetableSelectionStore.getInstance().save(timetable.id);
    this.activeTimetableId = timetable.id;
    await this.load();
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/TimetableDetailPage',
      params: { 'timetableId': timetable.id }
    });
  }

  /** Export the selected/current timetable into the app sandbox as an ICS file. */
  private async exportTimetable(timetable: EasTimetable): Promise<void> {
    if (this.exporting) {
      return;
    }
    this.exporting = true;
    try {
      const events = await RdbHelper.getInstance().getEventsOfTimetable(timetable.id);
      if (events.length === 0) {
        this.getUIContext().getPromptAction().showToast({ message: '当前课表没有可导出的课程' });
        return;
      }
      const ics: string = IcsExporter.fromEvents(events, timetable.name);
      const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const path: string = ctx.filesDir + '/hita-' + timetable.id + '.ics';
      const file = fileIo.openSync(path,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        fileIo.writeSync(file.fd, ics);
      } finally {
        fileIo.closeSync(file);
      }
      this.getUIContext().getPromptAction().showToast({
        message: '已导出 ICS（' + ics.length.toString() + 'B）'
      });
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '导出 ICS 失败' });
    } finally {
      this.exporting = false;
    }
  }

  private showExportMenu(): void {
    if (this.timetables.length === 0 || this.exporting) {
      this.getUIContext().getPromptAction().showToast({ message: '暂无可导出的课表' });
      return;
    }
    // Android exports the currently active timetable from this toolbar. The
    // manager opens with the newest timetable first, so keep the same single
    // action here and avoid a platform-specific dynamic action-menu tuple.
    this.exportTimetable(this.timetables[0]);
  }

  private confirmDelete(): void {
    const count: number = this.selectedIds.length;
    if (count === 0) {
      return;
    }
    this.getUIContext().getPromptAction().showDialog({
      title: '删除课表',
      message: '确定删除选中的 ' + count.toString() + ' 张课表及其全部课程吗？',
      buttons: [
        { text: '取消', color: '#7B8190' },
        { text: '删除', color: HitaColors.error }
      ]
    }).then(async (ret) => {
      if (ret.index !== 1) {
        return;
      }
      await RdbHelper.getInstance().deleteTimetablesCascade(this.selectedIds);
      for (let i: number = 0; i < this.selectedIds.length; i++) {
        await TimetableSelectionStore.getInstance().clearIf(this.selectedIds[i]);
      }
      this.selectedIds = [];
      this.selectionMode = false;
      await this.load();
      this.getUIContext().getPromptAction().showToast({ message: '课表已删除' });
    }).catch(() => {
    });
  }

  @Builder
  private timetableCard(timetable: EasTimetable) {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column() {
        Stack() {
          Circle()
            .width(120)
            .height(120)
            .fill(TimetableManagerPage.seasonLight(timetable.startTime))
            .translate({ x: 48, y: -20 })
          Circle()
            .width(84)
            .height(84)
            .fill(TimetableManagerPage.seasonMain(timetable.startTime))
            .translate({ x: 6, y: 28 })
          Circle()
            .width(28)
            .height(28)
            .fill('#66FFFFFF')
            .translate({ x: 50, y: 13 })
        }
        .width('100%')
        .height(150)

        Column() {
          Text(timetable.name.length > 0 ? timetable.name : '未命名课表')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#202633')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(TimetableManagerPage.dateRange(timetable))
            .fontSize(12)
            .fontColor('#788196')
            .margin({ top: 8 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 18, right: 18 })
      }
      .width('100%')
      .height(260)
      .backgroundColor('#FFFFFF')
      .borderRadius(24)
      .shadow({ radius: 12, color: '#10000000', offsetY: 4 })
      .onClick(() => {
        this.openTimetable(timetable);
      })
      .gesture(
        LongPressGesture({ repeat: false })
          .onAction(() => {
            this.toggleSelection(timetable.id);
          })
      )

      if (!this.selectionMode && this.activeTimetableId === timetable.id) {
        Row() {
          Text('当前')
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
        }
        .height(26)
        .padding({ left: 10, right: 10 })
        .justifyContent(FlexAlign.Center)
        .backgroundColor(HitaColors.primary)
        .borderRadius(13)
        .margin({ top: 12, right: 12 })
      }

      if (this.selectionMode) {
        Row() {
          Text(this.selected(timetable.id) ? '✓' : '')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
        }
        .width(30)
        .height(30)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.selected(timetable.id) ? HitaColors.primary : '#D7DCE5')
        .borderRadius(15)
        .margin({ top: 12, right: 12 })
      }
    }
    .width('100%')
    .height(260)
  }

  @Builder
  private addCard() {
    Column() {
      this.addActionGlyph($r('sys.symbol.plus'), () => {
        this.createEmptyTimetable();
      });
      this.addActionGlyph($r('sys.symbol.repeat_1'), () => {
        this.openImportPage();
      });
      this.addActionGlyph($r('sys.symbol.doc_plaintext'), () => {
        this.getUIContext().getPromptAction().showToast({ message: 'ICS 导入暂未适配' });
      });
    }
    .width('100%')
    .height(260)
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#FFFFFF')
    .borderRadius(24)
    .border({ width: 1, color: '#DDE4EE', style: BorderStyle.Dashed })
  }

  @Builder
  private addActionGlyph(symbol: Resource, action: () => void) {
    Stack() {
      SymbolGlyph(symbol)
        .fontSize(24)
        .fontColor([HitaColors.primary]);
    }
    .width(64)
    .height(64)
    .alignContent(Alignment.Center)
    .backgroundColor('#E8F3FD')
    .borderRadius(32)
    .onClick(action);
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
            if (this.selectionMode) {
              this.selectedIds = [];
              this.selectionMode = false;
            } else {
              this.getUIContext().getRouter().back();
            }
          })
        Text(this.selectionMode ? '已选择 ' + this.selectedIds.length.toString() + ' 项' : '课表管理')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#202633')
          .layoutWeight(1)
          .margin({ left: 4 })
        if (this.selectionMode) {
          Text('删除')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(HitaColors.error)
            .padding({ left: 14, right: 14, top: 10, bottom: 10 })
            .onClick(() => {
              this.confirmDelete();
            })
        } else {
          SymbolGlyph($r('sys.symbol.doc_plaintext'))
            .fontSize(20)
            .fontColor([HitaColors.primary])
            .width(44)
            .height(44)
            .onClick(() => {
              this.showExportMenu();
            });
        }
      }
      .width('100%')
      .height(64)
      .padding({ left: 6, right: 12 })
      .alignItems(VerticalAlign.Center)

      if (this.loading) {
        LoadingProgress()
          .width(32)
          .height(32)
          .color(HitaColors.primary)
          .margin({ top: 80 })
      } else {
        Grid() {
          ForEach(this.timetables, (timetable: EasTimetable) => {
            GridItem() {
              this.timetableCard(timetable)
            }
          }, (timetable: EasTimetable) => timetable.id)
          if (!this.selectionMode) {
            GridItem() {
              this.addCard()
            }
          }
        }
        .columnsTemplate('1fr 1fr')
        .columnsGap(12)
        .rowsGap(14)
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, top: 8, bottom: 28 })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F6F7FA')
  }

  private static defaultName(now: number): string {
    const d: Date = new Date(now);
    const season: string = d.getMonth() < 6 ? '春季学期' : '秋季学期';
    return d.getFullYear().toString() + ' ' + season;
  }

  private static dateRange(timetable: EasTimetable): string {
    return TimetableManagerPage.dateText(timetable.startTime) + ' - ' +
      TimetableManagerPage.dateText(timetable.endTime);
  }

  private static dateText(ms: number): string {
    const d: Date = new Date(ms);
    const m: number = d.getMonth() + 1;
    const day: number = d.getDate();
    return d.getFullYear().toString() + '.' + (m < 10 ? '0' : '') + m.toString() + '.' +
      (day < 10 ? '0' : '') + day.toString();
  }

  private static seasonMain(ms: number): string {
    const month: number = new Date(ms).getMonth() + 1;
    if (month >= 3 && month <= 5) {
      return '#78C99A';
    }
    if (month >= 6 && month <= 8) {
      return '#F4B75B';
    }
    if (month >= 9 && month <= 11) {
      return '#E9876A';
    }
    return '#78A9DE';
  }

  private static seasonLight(ms: number): string {
    const month: number = new Date(ms).getMonth() + 1;
    if (month >= 3 && month <= 5) {
      return '#DDF3E5';
    }
    if (month >= 6 && month <= 8) {
      return '#FBEAC8';
    }
    if (month >= 9 && month <= 11) {
      return '#F8DCD4';
    }
    return '#DCEAF8';
  }
}
