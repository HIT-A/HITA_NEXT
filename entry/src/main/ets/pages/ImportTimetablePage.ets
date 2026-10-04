/** Android-style timetable import configuration page. */
import { common } from '@kit.AbilityKit';
import { HeaderBackButton } from '../common/components/HeaderBackButton';
import { HeaderFadeMask } from '../common/components/HeaderFadeMask';
import { HeaderFade } from '../common/theme/HeaderFade';
import { STATUS_BAR_INSET_FALLBACK } from '../common/theme/StatusBarInset';
import { EasApiClient } from '../feature/eas/EasApiClient';
import { EasCampus, EasSession } from '../feature/eas/EasSession';
import { EasSessionStore } from '../feature/eas/EasSessionStore';
import { EasDataProvider } from '../feature/eas/EasDataProvider';
import { EasImportResult, EasTimetableImporter } from '../feature/eas/EasTimetableImporter';
import { EasTermItem } from '../feature/eas/model/EasModels';
import { EasTimeInDay, EasTimePeriodInDay, EasTimetable } from '../common/model/timetable/TimetableModels';
import { TimetableSelectionStore } from '../feature/timetable/data/TimetableSelectionStore';
import { HitaColors } from '../common/theme/HitaColors';

const HEADER_HEIGHT: number = 64;
const PAGE_BG: string = '#F4F7FC';
const PAGE_BG_RGB: string = '244,247,252';
const CARD_BG: string = '#FFFFFF';
const TEXT_PRIMARY: string = '#14213D';
const TEXT_SECONDARY: string = '#4E5C72';

@Entry
@Component
struct ImportTimetablePage {
  @State terms: EasTermItem[] = [];
  @State selectedTermIndex: number = -1;
  @State startTime: number = Date.now();
  @State schedule: EasTimePeriodInDay[] = [];
  @State loading: boolean = true;
  @State importing: boolean = false;
  @State message: string = '';
  @State error: string = '';
  @State fadeOpacity: number = 0;
  @StorageProp('hita_status_bar_vp') statusBarInset: number = STATUS_BAR_INSET_FALLBACK;
  private session: EasSession | undefined = undefined;
  private pageScroller: Scroller = new Scroller();

  async aboutToAppear(): Promise<void> {
    await this.load();
  }

  private async load(): Promise<void> {
    this.loading = true;
    this.error = '';
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    await EasSessionStore.getInstance().init(ctx);
    const campus: EasCampus | undefined = await EasSessionStore.getInstance().loadLastCampus();
    if (campus === undefined) {
      this.loading = false;
      this.error = '请先登录教务系统';
      return;
    }
    this.session = await EasSessionStore.getInstance().load(campus);
    if (this.session === undefined || !this.session.isLogin()) {
      this.loading = false;
      this.error = '请先登录教务系统';
      return;
    }
    try {
      const provider: EasDataProvider = new EasDataProvider(new EasApiClient());
      this.terms = await provider.getAllTerms(this.session as EasSession);
      this.selectedTermIndex = 0;
      for (let i: number = 0; i < this.terms.length; i++) {
        if (this.terms[i].isCurrent) {
          this.selectedTermIndex = i;
          break;
        }
      }
      const term: EasTermItem | undefined = this.selectedTerm();
      this.startTime = term === undefined ? Date.now() : ImportTimetablePage.startOfTerm(term);
      this.schedule = ImportTimetablePage.defaultSchedule(this.session.campus);
      if (this.session.campus === EasCampus.SHENZHEN && term !== undefined) {
        try {
          const remote: EasTimePeriodInDay[] = await provider.getShenzhenScheduleStructure(
            this.session as EasSession, term);
          if (remote.length > 0) {
            this.schedule = remote;
          }
        } catch (e) {
          // Keep the local fallback if the optional schedule endpoint is unavailable.
        }
      }
    } catch (e) {
      this.error = e instanceof Error ? e.message : String(e);
    } finally {
      this.loading = false;
    }
  }

  private selectedTerm(): EasTermItem | undefined {
    if (this.selectedTermIndex < 0 || this.selectedTermIndex >= this.terms.length) {
      return undefined;
    }
    return this.terms[this.selectedTermIndex];
  }

  private chooseTerm(): void {
    if (this.terms.length === 0) {
      return;
    }
    const range: string[] = [];
    for (let i: number = 0; i < this.terms.length; i++) {
      range.push(this.terms[i].name);
    }
    this.getUIContext().showTextPickerDialog({
      range: range,
      selected: this.selectedTermIndex,
      canLoop: false,
      onAccept: async (result: TextPickerResult) => {
        const index: number = typeof result.index === 'number' ? result.index : 0;
        if (index < 0 || index >= this.terms.length) {
          return;
        }
        this.selectedTermIndex = index;
        const term: EasTermItem | undefined = this.selectedTerm();
        if (term !== undefined) {
          this.startTime = ImportTimetablePage.startOfTerm(term);
          if (this.session !== undefined && this.session.campus === EasCampus.SHENZHEN) {
            try {
              const remote: EasTimePeriodInDay[] = await new EasDataProvider(new EasApiClient())
                .getShenzhenScheduleStructure(this.session as EasSession, term);
              if (remote.length > 0) {
                this.schedule = remote;
              }
            } catch (e) {
            }
          }
        }
      }
    });
  }

  private chooseStartDate(): void {
    this.getUIContext().showDatePickerDialog({
      selected: new Date(this.startTime),
      onDateAccept: (date: Date) => {
        const selected: Date = new Date(date.getFullYear(), date.getMonth(), date.getDate(), 0, 0, 0, 0);
        this.startTime = selected.getTime();
      }
    });
  }

  private editPeriod(index: number): void {
    if (index < 0 || index >= this.schedule.length) {
      return;
    }
    const period: EasTimePeriodInDay = this.schedule[index];
    this.getUIContext().getPromptAction().showActionMenu({
      title: '第 ' + (index + 1).toString() + ' 节',
      buttons: [
        { text: '调整开始时间', color: HitaColors.primary },
        { text: '调整结束时间', color: HitaColors.primary },
        { text: '恢复默认时间', color: HitaColors.primary }
      ]
    }).then((result) => {
      if (result.index === 0) {
        this.pickPeriodTime(index, true);
      } else if (result.index === 1) {
        this.pickPeriodTime(index, false);
      } else if (result.index === 2) {
        const defaults: EasTimePeriodInDay[] = this.session === undefined ?
          EasTimetable.getDefaultTimeStructure() : ImportTimetablePage.defaultSchedule(this.session.campus);
        if (index < defaults.length) {
          const next: EasTimePeriodInDay[] = this.schedule.slice();
          next[index] = defaults[index].clone();
          this.schedule = next;
        }
      }
    }).catch(() => {
    });
  }

  private pickPeriodTime(index: number, from: boolean): void {
    const current: EasTimeInDay = from ? this.schedule[index].from : this.schedule[index].to;
    const selected: Date = new Date(2000, 0, 1, current.hour, current.minute, 0, 0);
    this.getUIContext().showTimePickerDialog({
      selected: selected,
      useMilitaryTime: true,
      onAccept: (value: TimePickerResult) => {
        const existing: EasTimePeriodInDay = this.schedule[index];
        const nextFrom: EasTimeInDay = from ? new EasTimeInDay(value.hour, value.minute) : existing.from;
        const nextTo: EasTimeInDay = from ? existing.to : new EasTimeInDay(value.hour, value.minute);
        if (nextTo.compareTo(nextFrom) <= 0) {
          this.getUIContext().getPromptAction().showToast({ message: '结束时间必须晚于开始时间' });
          return;
        }
        const next: EasTimePeriodInDay[] = this.schedule.slice();
        next[index] = new EasTimePeriodInDay(nextFrom, nextTo);
        this.schedule = next;
      }
    });
  }

  private async import(): Promise<void> {
    if (this.importing || this.selectedTerm() === undefined || this.session === undefined) {
      return;
    }
    this.importing = true;
    this.message = '';
    this.error = '';
    try {
      const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
      const result: EasImportResult = await EasTimetableImporter.importCurrent(ctx,
        this.selectedTerm() as EasTermItem, this.startTime, this.schedule);
      if (result.success && result.timetable !== undefined) {
        await TimetableSelectionStore.getInstance().init(ctx);
        await TimetableSelectionStore.getInstance().save(result.timetable.id);
        this.message = result.message;
        this.getUIContext().getPromptAction().showToast({ message: result.message });
        setTimeout(() => {
          this.getUIContext().getRouter().back();
        }, 500);
      } else {
        this.error = result.message.length > 0 ? result.message : '导入课表失败';
      }
    } catch (e) {
      this.error = e instanceof Error ? e.message : String(e);
    } finally {
      this.importing = false;
    }
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.loading) {
        LoadingProgress()
          .width(32)
          .height(32)
          .color(HitaColors.primary)
          .margin({ top: HEADER_HEIGHT + 80 });
      } else if (this.error.length > 0 && this.terms.length === 0) {
        Column() {
          Text(this.error)
            .fontSize(16)
            .fontColor(TEXT_PRIMARY);
          Button('返回')
            .margin({ top: 18 })
            .onClick(() => this.getUIContext().getRouter().back());
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center);
      } else {
        Scroll(this.pageScroller) {
          Column({ space: 12 }) {
            Blank().height(HEADER_HEIGHT);
            this.termCard();
            this.dateCard();
            this.scheduleCard();
            if (this.error.length > 0) {
              Text(this.error)
                .fontSize(13)
                .fontColor('#C23B4A')
                .width('100%');
            }
            if (this.message.length > 0) {
              Text(this.message)
                .fontSize(13)
                .fontColor('#248A5A')
                .width('100%');
            }
            Blank().height(36);
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 20 });
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .onDidScroll(() => {
          this.fadeOpacity = HeaderFade.opacity(this.pageScroller.currentOffset().yOffset);
        });
      }

      HeaderFadeMask({
        maskOpacity: this.fadeOpacity,
        rgb: PAGE_BG_RGB,
        headerHeight: HEADER_HEIGHT
      })

      Row() {
        HeaderBackButton({
          onBack: () => this.getUIContext().getRouter().back()
        })
          .margin({ right: 12 });
        Text('导入课表')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_PRIMARY)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
        Button(this.importing ? '导入中' : '导入')
          .fontSize(14)
          .fontColor('#FFFFFF')
          .backgroundColor(this.importing ? '#AFC8E8' : HitaColors.primary)
          .borderRadius(18)
          .height(36)
          .padding({ left: 16, right: 16 })
          .enabled(!this.importing && this.selectedTerm() !== undefined)
          .onClick(() => this.import());
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
    .backgroundColor(PAGE_BG);
  }

  @Builder
  private termCard() {
    Column() {
      Text('导入学期')
        .fontSize(13)
        .fontColor(TEXT_SECONDARY)
        .width('100%');
      Row() {
        Column() {
          Text(this.selectedTerm() === undefined ? '未选择学期' : (this.selectedTerm() as EasTermItem).name)
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor(TEXT_PRIMARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
          Text(this.selectedTerm() === undefined ? '点击选择教务学期' :
            (this.selectedTerm() as EasTermItem).getCode())
            .fontSize(12)
            .fontColor(TEXT_SECONDARY)
            .margin({ top: 4 });
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);
        Text('›')
          .fontSize(24)
          .fontColor(TEXT_SECONDARY);
      }
      .width('100%')
      .margin({ top: 10 })
      .onClick(() => this.chooseTerm());
    }
    .width('100%')
    .padding(18)
    .backgroundColor(CARD_BG)
    .borderRadius(18);
  }

  @Builder
  private dateCard() {
    Row() {
      Column() {
        Text('开学日期')
          .fontSize(13)
          .fontColor(TEXT_SECONDARY);
        Text(ImportTimetablePage.dateText(this.startTime))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(TEXT_PRIMARY)
          .margin({ top: 6 });
        Text('点击调整，课程日期会同步平移')
          .fontSize(12)
          .fontColor(TEXT_SECONDARY)
          .margin({ top: 4 });
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start);
      SymbolGlyph($r('sys.symbol.calendar'))
        .fontSize(24)
        .fontColor([HitaColors.primary]);
    }
    .width('100%')
    .padding(18)
    .backgroundColor(CARD_BG)
    .borderRadius(18)
    .onClick(() => this.chooseStartDate());
  }

  @Builder
  private scheduleCard() {
    Column() {
      Row() {
        Text('每日节次')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_PRIMARY)
          .layoutWeight(1);
        Text(this.schedule.length.toString() + ' 节')
          .fontSize(13)
          .fontColor(TEXT_SECONDARY);
      }
      .width('100%');
      Text('点击任意一节可修改开始或结束时间')
        .fontSize(12)
        .fontColor(TEXT_SECONDARY)
        .width('100%')
        .margin({ top: 5, bottom: 10 });
      Column() {
        ForEach(this.schedule, (period: EasTimePeriodInDay, index: number) => {
          Row() {
            Stack() {
              Text((index + 1).toString())
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(HitaColors.primary);
            }
            .width(34)
            .height(34)
            .borderRadius(17)
            .backgroundColor('#E8F3FD')
            .alignContent(Alignment.Center);
            Column() {
              Text('第 ' + (index + 1).toString() + ' 节')
                .fontSize(15)
                .fontColor(TEXT_PRIMARY);
              Text(period.from.toString() + ' - ' + period.to.toString())
                .fontSize(13)
                .fontColor(TEXT_SECONDARY)
                .margin({ top: 3 });
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            .margin({ left: 12 });
            Text('›')
              .fontSize(22)
              .fontColor('#A3ADBB');
          }
          .width('100%')
          .height(58)
          .alignItems(VerticalAlign.Center)
          .onClick(() => this.editPeriod(index));
          if (index < this.schedule.length - 1) {
            Divider()
              .strokeWidth(1)
              .color('#EEF1F5')
              .margin({ left: 46 });
          }
        }, (period: EasTimePeriodInDay, index: number) => index.toString() + period.toString());
      }
      .width('100%');
    }
    .width('100%')
    .padding(18)
    .backgroundColor(CARD_BG)
    .borderRadius(18);
  }

  private static dateText(timestamp: number): string {
    const d: Date = new Date(timestamp);
    return d.getFullYear().toString() + '年' + (d.getMonth() + 1).toString() + '月' + d.getDate().toString() + '日';
  }

  private static startOfTerm(term: EasTermItem): number {
    return EasTimetableImporter.startOfTerm(term);
  }

  private static defaultSchedule(campus: EasCampus): EasTimePeriodInDay[] {
    return EasTimetableImporter.scheduleStructure(campus);
  }
}
