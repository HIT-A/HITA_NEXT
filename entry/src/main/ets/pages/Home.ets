/**
 * HITA NEXT main shell.
 *
 * The Android client uses a compact toolbar and a floating pill navigation bar.
 * This page keeps the same information hierarchy while reusing the HarmonyOS
 * timetable/session data layer already used by the app.
 */
import { common } from '@kit.AbilityKit';
import { RdbHelper } from '../common/db/RdbHelper';
import { EasEventItem, EasEventType, EasTimetable } from '../common/model/timetable/TimetableModels';
import { DOW_FULL, EasTimeTools } from '../common/util/EasTimeTools';
import { TimetableLocalDemo } from '../feature/timetable/data/TimetableLocalDemo';
import { EasCampus, EasSession } from '../feature/eas/EasSession';
import { EasSessionStore } from '../feature/eas/EasSessionStore';
import { EasImportResult, EasTimetableImporter } from '../feature/eas/EasTimetableImporter';
import { TimetableResolver } from '../feature/timetable/data/TimetableResolver';

const DAY_MS: number = 24 * 60 * 60 * 1000;
const COLOR_PRIMARY: string = '#3390EC';
const COLOR_SURFACE: string = '#F6F7FA';
const COLOR_CARD: string = '#FFFFFF';
const COLOR_TEXT_PRIMARY: string = '#1A1A1A';
const COLOR_TEXT_SECONDARY: string = '#667085';
const COLOR_TEXT_HINT: string = '#98A2B3';
const COLOR_DIVIDER: string = '#EAECF0';
const COLOR_NAV: string = '#1E1E32';
const COLOR_CLASS: string = '#3390EC';
const COLOR_EXAM: string = '#D93025';
const COLOR_OTHER: string = '#5C6BC0';
const COLOR_TAG: string = '#26A69A';

class HitaMenuItem {
  symbol: string;
  title: string;
  subtitle: string;
  destination: string;

  constructor(symbol: string, title: string, subtitle: string, destination: string) {
    this.symbol = symbol;
    this.title = title;
    this.subtitle = subtitle;
    this.destination = destination;
  }
}

@Entry
@Component
struct Home {
  @State todayItems: EasEventItem[] = [];
  @State timelineText: string = '暂无今日日程';
  @State tableText: string = '课表尚未导入';
  @State sessionText: string = '未登录';
  @State hasDemo: boolean = false;
  @State currentTab: number = 0;
  @State hasTimetable: boolean = false;
  @State hasRealTimetable: boolean = false;
  @State currentTimetable: EasTimetable | undefined = undefined;
  @State importing: boolean = false;
  @State importMessage: string = '';
  @State importError: string = '';
  @State activeClass: EasEventItem | undefined = undefined;
  @State nextClass: EasEventItem | undefined = undefined;
  @State nowTick: number = Date.now();
  @State sessionInfo: EasSession | undefined = undefined;
  private importRequested: boolean = false;
  private clockTimer: number = -1;
  private dayKey: string = EasTimeTools.printDate(Date.now());

  async aboutToAppear(): Promise<void> {
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    await EasSessionStore.getInstance().init(ctx);
    await this.refreshSummaries();
    this.startClock();
  }

  async onPageShow(): Promise<void> {
    this.startClock();
    await this.refreshSummaries();
  }

  aboutToDisappear(): void {
    if (this.clockTimer >= 0) {
      clearInterval(this.clockTimer);
      this.clockTimer = -1;
    }
  }

  private startClock(): void {
    if (this.clockTimer >= 0) {
      return;
    }
    this.clockTimer = setInterval(() => {
      this.nowTick = Date.now();
      this.updateTodayHighlights();
      const nextDayKey: string = EasTimeTools.printDate(this.nowTick);
      if (nextDayKey !== this.dayKey) {
        this.dayKey = nextDayKey;
        this.refreshSummaries();
      }
    }, 60000);
  }

  async refreshSummaries(): Promise<void> {
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    const rdb: RdbHelper = RdbHelper.getInstance();
    await rdb.init(ctx);

    const preferred: EasCampus | undefined = await EasSessionStore.getInstance().loadLastCampus();
    const order: EasCampus[] = [EasCampus.BENBU, EasCampus.WEIHAI, EasCampus.SHENZHEN];
    if (preferred !== undefined) {
      const index: number = order.indexOf(preferred);
      if (index > 0) {
        order.splice(index, 1);
        order.unshift(preferred);
      }
    }
    let found: EasSession | undefined = undefined;
    for (let i = 0; i < order.length && found === undefined; i++) {
      const session: EasSession | undefined = await EasSessionStore.getInstance().load(order[i]);
      if (session !== undefined && session.isLogin()) {
        found = session;
      }
    }
    this.sessionInfo = found;
    this.sessionText = found === undefined ? '未登录：从导航页登录统一认证' :
      '已登录 · ' + Home.campusName(found.campus);

    const real: EasTimetable | undefined = await TimetableResolver.getReal(rdb);
    if (found !== undefined && real === undefined && !this.importing && !this.importRequested) {
      await this.importTimetable(false);
      return;
    }

    const demo: EasTimetable | undefined = await rdb.getTimetableByEasCode(TimetableLocalDemo.DEMO_CODE);
    const display: EasTimetable | undefined = real !== undefined ? real : demo;
    this.hasDemo = demo !== undefined;
    this.hasRealTimetable = real !== undefined;
    this.hasTimetable = display !== undefined;
    this.currentTimetable = display;
    if (display === undefined) {
      this.tableText = found === undefined ? '课表：请先登录并导入' : '课表：暂无数据，可点击导入';
    } else {
      const week: number = display.getWeekNumber(Date.now());
      this.tableText = display.name + (real !== undefined ? ' · 已导入' : ' · 演示课表') +
        (week > 0 ? ' · 第 ' + week.toString() + ' 周' : '');
    }

    const now0: number = new Date(new Date().setHours(0, 0, 0, 0)).getTime();
    let today: EasEventItem[] = [];
    if (display !== undefined) {
      const events: EasEventItem[] = await rdb.getEventsOfTimetable(display.id);
      today = events.filter((event: EasEventItem): boolean => event.from >= now0 && event.from < now0 + DAY_MS);
    }
    today.sort((a: EasEventItem, b: EasEventItem): number => a.from - b.from);
    this.todayItems = today;
    this.nowTick = Date.now();
    this.updateTodayHighlights();
    this.timelineText = today.length === 0 ? (display === undefined ? '暂无课表' : '今日暂无安排') :
      '今日 ' + today.length.toString() + ' 项安排';
  }

  private updateTodayHighlights(): void {
    const now: number = this.nowTick;
    this.activeClass = undefined;
    this.nextClass = undefined;
    for (let i = 0; i < this.todayItems.length; i++) {
      const event: EasEventItem = this.todayItems[i];
      if (event.type !== EasEventType.CLASS) {
        continue;
      }
      if (event.from <= now && event.to > now) {
        this.activeClass = event;
        continue;
      }
      if (event.from > now && this.nextClass === undefined) {
        this.nextClass = event;
      }
    }
  }

  async importTimetable(showToast: boolean = true): Promise<void> {
    if (this.importing) {
      return;
    }
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    this.importing = true;
    this.importRequested = true;
    this.importMessage = '正在从教务系统读取课表…';
    this.importError = '';
    try {
      const result: EasImportResult = await EasTimetableImporter.importCurrent(ctx);
      if (result.success) {
        this.importMessage = result.message;
        if (showToast) {
          this.getUIContext().getPromptAction().showToast({ message: result.message });
        }
      } else {
        this.importMessage = '';
        this.importError = result.message.length > 0 ? result.message : '导入课表失败';
        if (showToast) {
          this.getUIContext().getPromptAction().showToast({ message: this.importError });
        }
      }
    } catch (error) {
      const message: string = error instanceof Error ? error.message : String(error);
      this.importMessage = '';
      this.importError = message.length > 0 ? message : '导入课表失败';
      if (showToast) {
        this.getUIContext().getPromptAction().showToast({ message: this.importError });
      }
    } finally {
      this.importing = false;
      await this.refreshSummaries();
    }
  }

  async seed(): Promise<void> {
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    this.getUIContext().getPromptAction().showDialog({
      title: '生成本地演示数据',
      message: '用于体验课表、今日时间线和科目页面。已有演示数据会被重建。',
      buttons: [
        { text: '取消', color: COLOR_TEXT_HINT },
        { text: '生成', color: COLOR_PRIMARY }
      ]
    }).then(async (result) => {
      if (result.index === 1) {
        await TimetableLocalDemo.runSelfCheck(ctx);
        this.getUIContext().getPromptAction().showToast({ message: '演示数据已生成' });
        await this.refreshSummaries();
      }
    }).catch(() => {
    });
  }

  private static typeTag(type: EasEventType): string {
    if (type === EasEventType.EXAM) {
      return '考';
    }
    if (type === EasEventType.TAG) {
      return '备';
    }
    return '课';
  }

  private static eventColor(type: EasEventType): string {
    if (type === EasEventType.CLASS) {
      return COLOR_CLASS;
    }
    if (type === EasEventType.EXAM) {
      return COLOR_EXAM;
    }
    if (type === EasEventType.TAG) {
      return COLOR_TAG;
    }
    return COLOR_OTHER;
  }

  private static eventStatus(event: EasEventItem, now: number = Date.now()): string {
    if (now >= event.from && now <= event.to) {
      return '进行中';
    }
    if (event.from > now && event.from - now <= 30 * 60 * 1000) {
      return '即将开始';
    }
    if (now > event.to) {
      return '已结束';
    }
    return '';
  }

  private static statusColor(status: string): string {
    if (status === '进行中') {
      return COLOR_EXAM;
    }
    if (status === '即将开始') {
      return COLOR_PRIMARY;
    }
    return COLOR_TEXT_HINT;
  }

  private static statusBgColor(status: string): string {
    if (status === '进行中') {
      return '#FFF1F0';
    }
    if (status === '即将开始') {
      return '#EBF4FC';
    }
    return '#F2F4F7';
  }

  private static formatHeaderDate(): string {
    const date: Date = new Date();
    const dow: number = EasTimeTools.getDow(Date.now());
    return (date.getMonth() + 1).toString() + '月' + date.getDate().toString() + '日  ' + DOW_FULL[dow];
  }

  private static countdownText(event: EasEventItem, now: number): string {
    const minutes: number = Math.max(1, Math.ceil((event.from - now) / 60000));
    if (minutes >= 60) {
      const hours: number = Math.floor(minutes / 60);
      const remainder: number = minutes % 60;
      return remainder === 0 ? hours.toString() + '小时后开始' :
        hours.toString() + '小时' + remainder.toString() + '分钟后开始';
    }
    return minutes.toString() + '分钟后开始';
  }

  private static campusName(campus: EasCampus): string {
    if (campus === EasCampus.SHENZHEN) {
      return '深圳校区';
    }
    if (campus === EasCampus.BENBU) {
      return '本部校区';
    }
    return '威海校区';
  }

  private static sessionText(session: EasSession | undefined): string {
    return session === undefined ? '未登录' : Home.campusName(session.campus);
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        if (this.currentTab === 0) {
          this.tabToday();
        } else if (this.currentTab === 1) {
          this.tabTimetable();
        } else {
          this.tabMine();
        }
      }
      .width('100%')
      .height('100%')
      .padding({ bottom: 92 })
      .backgroundColor(COLOR_SURFACE)

      this.pillNavigation();
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLOR_SURFACE);
  }

  @Builder
  pillNavigation() {
    Stack() {
      Row() {
        Blank()
          .width(88 * this.currentTab);
        Row()
          .width(88)
          .height(52)
          .backgroundColor('#2AABEE')
          .borderRadius(25);
        Blank()
          .layoutWeight(1);
      }
      .width('100%')
      .height(52)
      .animation({ duration: 260, curve: Curve.EaseInOut });

      Row() {
        this.navItem($r('sys.symbol.calendar'), '今日', 0);
        this.navItem($r('sys.symbol.doc_plaintext'), '时间表', 1);
        this.navItem($r('sys.symbol.more'), '更多', 2);
      }
    }
    .width(286)
    .height(64)
    .padding({ left: 6, right: 6, top: 6, bottom: 6 })
    .backgroundColor(COLOR_NAV)
    .borderRadius(32)
    .shadow({ radius: 18, color: '#33000000', offsetX: 0, offsetY: 7 })
    .margin({ bottom: 18 })
  }

  @Builder
  navItem(symbol: Resource, label: string, index: number) {
    Column() {
      SymbolGlyph(symbol)
        .fontSize(20)
        .fontColor(['#FFFFFF'])
      Text(label)
        .fontSize(10)
        .fontColor('#FFFFFF')
        .margin({ top: 3 })
    }
    .width(88)
    .height(52)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('transparent')
    .borderRadius(25)
    .opacity(index === this.currentTab ? 1 : 0.62)
    .onClick(() => {
      animateTo({ duration: 260, curve: Curve.EaseInOut }, () => {
        this.currentTab = index;
      });
    })
  }

  @Builder
  topBar(title: string, subtitle: string, actionSymbol: string, action: () => void) {
    Row() {
      Column() {
        Text(title)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_TEXT_PRIMARY)
        if (subtitle.length > 0) {
          Text(subtitle)
            .fontSize(12)
            .fontColor(COLOR_TEXT_SECONDARY)
            .margin({ top: 4 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (actionSymbol.length > 0) {
        Stack() {
          if (actionSymbol === '＋') {
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(22)
              .fontColor([COLOR_PRIMARY]);
          } else if (actionSymbol === '↻') {
            SymbolGlyph($r('sys.symbol.repeat_1'))
              .fontSize(21)
              .fontColor([COLOR_PRIMARY]);
          } else {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(21)
              .fontColor([COLOR_PRIMARY]);
          }
        }
        .width(46)
        .height(46)
        .borderRadius(23)
        .backgroundColor('#EBF4FC')
        .alignContent(Alignment.Center)
        .onClick(action)
      }
    }
    .width('100%')
    .padding({ left: 20, right: 16, top: 14, bottom: 14 })
    .backgroundColor(COLOR_CARD)
    .border({ width: { bottom: 1 }, color: COLOR_DIVIDER })
  }

  @Builder
  featureGlyph(symbol: string) {
    if (symbol === '▦') {
      SymbolGlyph($r('sys.symbol.calendar'))
        .fontSize(22)
        .fontColor([COLOR_PRIMARY]);
    } else if (symbol === '◫') {
      SymbolGlyph($r('sys.symbol.doc_plaintext'))
        .fontSize(22)
        .fontColor([COLOR_PRIMARY]);
    } else if (symbol === '◉') {
      SymbolGlyph($r('sys.symbol.checkmark_circle'))
        .fontSize(22)
        .fontColor([COLOR_PRIMARY]);
    } else if (symbol === '＋') {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(22)
        .fontColor(['#FFFFFF']);
    } else {
      SymbolGlyph($r('sys.symbol.person_crop_circle_fill'))
        .fontSize(22)
        .fontColor([COLOR_PRIMARY]);
    }
  }

  @Builder
  tabToday() {
    Column() {
      this.topBar(Home.formatHeaderDate(), '', '', () => {});

      this.todayHeroCard();
      this.todaySectionHeader();

      if (this.todayItems.length === 0) {
        this.emptyToday();
      } else {
        List({ space: 10 }) {
          ForEach(this.todayItems, (event: EasEventItem) => {
            ListItem() {
              this.eventRow(event);
            }
          }, (event: EasEventItem) => event.id);
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, top: 8, bottom: 16 })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  todayHeroCard() {
    Column() {
      Row() {
        Column() {
          if (this.activeClass !== undefined) {
            Text('正在进行')
              .fontSize(14)
              .fontColor('#DCEEFF')
              .fontWeight(FontWeight.Medium);
            Text(this.activeClass.name)
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 5 });
          } else if (this.nextClass !== undefined) {
            Text('下一节课')
              .fontSize(14)
              .fontColor('#DCEEFF')
              .fontWeight(FontWeight.Medium);
            Text(this.nextClass.name)
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 5 });
          } else {
            Text('今日空闲')
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF');
            Text('享受当下，按自己的节奏安排今天')
              .fontSize(14)
              .fontColor('#DCEEFF')
              .margin({ top: 6 });
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);

        Stack() {
          SymbolGlyph(this.activeClass !== undefined ? $r('sys.symbol.timer') : $r('sys.symbol.alarm'))
            .fontSize(34)
            .fontColor(['#FFFFFF']);
        }
        .width(64)
        .height(64)
        .borderRadius(32)
        .alignContent(Alignment.Center)
        .backgroundColor('#2B80D8');
      }
      .width('100%');

      if (this.activeClass !== undefined) {
        Row() {
          SymbolGlyph($r('sys.symbol.clock'))
            .fontSize(15)
            .fontColor(['#DCEEFF']);
          Text(EasTimeTools.printTime(this.activeClass.from) + ' - ' + EasTimeTools.printTime(this.activeClass.to))
            .fontSize(13)
            .fontColor('#FFFFFF')
            .margin({ left: 6 });
          Blank();
          Text(this.activeClass.place.length > 0 ? this.activeClass.place : '上课中')
            .fontSize(13)
            .fontColor('#FFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
        }
        .width('100%')
        .margin({ top: 16 });

        Progress({ value: this.activeClass.getProgress(this.nowTick) * 100, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(4)
          .color('#FFFFFF')
          .backgroundColor('#6AA9E7')
          .margin({ top: 12 });
      } else if (this.nextClass !== undefined) {
        Row() {
          SymbolGlyph($r('sys.symbol.clock'))
            .fontSize(15)
            .fontColor(['#DCEEFF']);
          Text(Home.countdownText(this.nextClass, this.nowTick))
            .fontSize(13)
            .fontColor('#FFFFFF')
            .margin({ left: 6 });
          Blank();
          Text(EasTimeTools.printTime(this.nextClass.from))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF');
        }
        .width('100%')
        .margin({ top: 16 });

        if (this.nextClass.place.length > 0) {
          Row() {
            SymbolGlyph($r('sys.symbol.pin'))
              .fontSize(14)
              .fontColor(['#DCEEFF']);
            Text(this.nextClass.place)
              .fontSize(12)
              .fontColor('#DCEEFF')
              .margin({ left: 6 })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
          }
          .margin({ top: 8 });
        }
      } else {
        Text('今天没有待开始的课程')
          .fontSize(13)
          .fontColor('#DCEEFF')
          .margin({ top: 16 });
      }
    }
    .width('100%')
    .padding(18)
    .backgroundColor(COLOR_PRIMARY)
    .borderRadius(18)
    .shadow({ radius: 14, color: '#263390EC', offsetY: 6 })
    .margin({ left: 16, right: 16, top: 14 });
  }

  @Builder
  todaySectionHeader() {
    Row() {
      Column() {
        Text('今日课表')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_TEXT_PRIMARY);
        Text(this.timelineText)
          .fontSize(12)
          .fontColor(COLOR_TEXT_SECONDARY)
          .margin({ top: 4 });
      }
      .alignItems(HorizontalAlign.Start);
      Blank();
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 18, bottom: 8 });
  }

  @Builder
  emptyToday() {
    Column() {
      Blank()
      Text('—')
        .fontSize(48)
        .fontColor('#C9D2DE')
        .margin({ bottom: 14 })
      Text(this.hasTimetable ? '今日暂无日程' : '还没有可展示的课表')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLOR_TEXT_SECONDARY)
      Text(this.hasTimetable ? '切换到课表查看整周安排' : '登录后导入课表，或生成一份演示数据')
        .fontSize(13)
        .fontColor(COLOR_TEXT_HINT)
        .margin({ top: 8, bottom: 20 })
      if (!this.hasTimetable) {
        Row() {
          Button('生成演示数据')
            .fontSize(14)
            .height(40)
            .fontColor('#FFFFFF')
            .backgroundColor(COLOR_PRIMARY)
            .borderRadius(20)
            .onClick(() => {
              this.seed();
            })
          if (this.sessionInfo !== undefined) {
            Button('导入课表')
              .fontSize(14)
              .height(40)
              .fontColor(COLOR_PRIMARY)
              .backgroundColor('#EBF4FC')
              .borderRadius(20)
              .margin({ left: 10 })
              .onClick(() => {
                this.importTimetable(true);
              })
          }
        }
      }
      Blank()
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  eventRow(event: EasEventItem) {
    Row() {
      Column() {
        Text(EasTimeTools.printTime(event.from))
          .fontSize(11)
          .fontColor(COLOR_TEXT_HINT)
          .width('100%')
          .textAlign(TextAlign.Center);
        Stack() {
          Row()
            .width(2)
            .height(28)
            .backgroundColor('#D8E0EA');
          Stack() {
            Circle()
              .width(event.to <= this.nowTick ? 18 : 12)
              .height(event.to <= this.nowTick ? 18 : 12)
              .fill(event.to <= this.nowTick ? '#AAB4C1' : Home.eventColor(event.type));
            if (event.to <= this.nowTick) {
              SymbolGlyph($r('sys.symbol.checkmark'))
                .fontSize(10)
                .fontColor(['#FFFFFF']);
            }
          }
          .width(20)
          .height(20)
          .alignContent(Alignment.Center);
        }
        .width('100%')
        .height(30)
        .alignContent(Alignment.Center);
      }
      .width(48)
      .alignItems(HorizontalAlign.Center)
      Column() {
        if (event.to <= this.nowTick) {
          Row() {
            Text(event.name)
              .fontSize(14)
              .fontColor(COLOR_TEXT_SECONDARY)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
            Text('已结束')
              .fontSize(11)
              .fontColor(COLOR_TEXT_HINT)
              .backgroundColor('#F2F4F7')
              .borderRadius(9)
              .padding({ left: 7, right: 7, top: 3, bottom: 3 });
          }
          .width('100%');
        } else {
          Row() {
            Text(event.name)
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor(event.type === EasEventType.EXAM ? COLOR_EXAM : COLOR_TEXT_PRIMARY)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
            Text(Home.typeTag(event.type))
              .fontSize(11)
              .fontColor(Home.eventColor(event.type))
              .width(24)
              .height(24)
              .textAlign(TextAlign.Center)
              .borderRadius(12)
              .backgroundColor(Home.statusBgColor(Home.eventStatus(event, this.nowTick)));
          }
          .width('100%')
          .alignItems(VerticalAlign.Center);

          Row() {
            SymbolGlyph($r('sys.symbol.clock'))
              .fontSize(14)
              .fontColor([COLOR_TEXT_SECONDARY]);
            Text(EasTimeTools.printTime(event.from) + ' - ' + EasTimeTools.printTime(event.to))
              .fontSize(12)
              .fontColor(COLOR_TEXT_SECONDARY)
              .margin({ left: 5 });
            Blank();
            if (Home.eventStatus(event, this.nowTick).length > 0) {
              Text(Home.eventStatus(event, this.nowTick))
                .fontSize(11)
                .fontColor(Home.statusColor(Home.eventStatus(event, this.nowTick)))
                .backgroundColor(Home.statusBgColor(Home.eventStatus(event, this.nowTick)))
                .borderRadius(9)
                .padding({ left: 7, right: 7, top: 3, bottom: 3 });
            }
          }
          .width('100%')
          .margin({ top: 9 });

          if (event.place.length > 0 || event.teacher.length > 0) {
            Row() {
              if (event.place.length > 0) {
                SymbolGlyph($r('sys.symbol.pin'))
                  .fontSize(13)
                  .fontColor([COLOR_PRIMARY]);
                Text(event.place)
                  .fontSize(12)
                  .fontColor(COLOR_TEXT_SECONDARY)
                  .margin({ left: 5 })
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis });
              }
              if (event.teacher.length > 0) {
                Text((event.place.length > 0 ? '  ·  ' : '') + event.teacher)
                  .fontSize(12)
                  .fontColor(COLOR_TEXT_SECONDARY)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ left: event.place.length > 0 ? 5 : 0 });
              }
            }
            .width('100%')
            .margin({ top: 8 });
          }

          if (event.containsTimestamp(this.nowTick)) {
            Progress({ value: event.getProgress(this.nowTick) * 100, total: 100, type: ProgressType.Linear })
              .width('100%')
              .height(3)
              .color(COLOR_PRIMARY)
              .backgroundColor('#E8F1FB')
              .margin({ top: 10 });
          }
        }
      }
      .layoutWeight(1)
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .backgroundColor(event.to <= this.nowTick ? '#F9FAFB' : COLOR_CARD)
    .borderRadius(14)
    .border({ width: 1, color: event.to <= this.nowTick ? '#EEF0F3' : COLOR_DIVIDER })
    .clip(true)
    .margin({ bottom: 2 })
  }

  @Builder
  tabTimetable() {
    Column() {
      this.topBar('时间表', this.currentTimetable === undefined ? '当前学期' : this.currentTimetable.name, '↻', () => {
        this.importTimetable(true);
      });

      Scroll() {
        Column() {
          Row() {
            Column() {
              Text(this.hasRealTimetable ? '已连接教务课表' : (this.hasDemo ? '演示课表' : '尚未设置'))
                .fontSize(13)
                .fontColor(this.hasRealTimetable ? '#2E7D32' : COLOR_TEXT_SECONDARY)
              Text(this.tableText)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(COLOR_TEXT_PRIMARY)
                .margin({ top: 6 })
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Text(this.hasRealTimetable ? '✓' : '·')
              .fontSize(24)
              .fontColor(this.hasRealTimetable ? '#2E7D32' : COLOR_TEXT_HINT)
          }
          .width('100%')
          .padding(16)
          .backgroundColor(COLOR_CARD)
          .borderRadius(8)
          .border({ width: 1, color: COLOR_DIVIDER })
          .margin({ left: 16, right: 16, top: 16 })

          if (this.importMessage.length > 0) {
            this.statusBanner(this.importMessage, '#EBF4FC', COLOR_PRIMARY);
          }
          if (this.importError.length > 0) {
            this.statusBanner(this.importError, '#FFF1F0', COLOR_EXAM);
          }

          this.actionRow('▦', '周课表', '查看分钟轴课表与整周安排', 'pages/TimetablePreview');
          this.actionRow('◫', '科目管理', '查看科目颜色与已导入课程', 'pages/SubjectsPage');

          Row() {
            Text('＋')
              .fontSize(22)
              .fontColor('#FFFFFF')
              .width(40)
              .height(40)
              .textAlign(TextAlign.Center)
              .borderRadius(20)
              .backgroundColor(COLOR_PRIMARY)
            Column() {
              Text('导入教务课表')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(COLOR_TEXT_PRIMARY)
              Text(this.importing ? '正在同步，请稍候…' : '从当前登录会话更新本学期课表')
                .fontSize(12)
                .fontColor(COLOR_TEXT_SECONDARY)
                .margin({ top: 4 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            .margin({ left: 12 })
            Text('›')
              .fontSize(24)
              .fontColor(COLOR_TEXT_HINT)
          }
          .width('100%')
          .padding(14)
          .backgroundColor(COLOR_CARD)
          .borderRadius(8)
          .border({ width: 1, color: COLOR_DIVIDER })
          .margin({ left: 16, right: 16, top: 10 })
          .onClick(() => {
            this.importTimetable(true);
          })

          if (!this.hasTimetable) {
            Column() {
              Text('还没有课表数据')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(COLOR_TEXT_PRIMARY)
              Text('可以先生成演示数据，确认页面和周视图正常工作。')
                .fontSize(13)
                .fontColor(COLOR_TEXT_SECONDARY)
                .margin({ top: 8, bottom: 16 })
              Button('生成演示数据')
                .fontSize(14)
                .height(40)
                .fontColor('#FFFFFF')
                .backgroundColor(COLOR_PRIMARY)
                .borderRadius(20)
                .onClick(() => {
                  this.seed();
                })
            }
            .width('100%')
            .padding(24)
            .alignItems(HorizontalAlign.Center)
            .backgroundColor(COLOR_CARD)
            .borderRadius(8)
            .border({ width: 1, color: COLOR_DIVIDER })
            .margin({ left: 16, right: 16, top: 10 })
          }
        }
        .width('100%')
        .padding({ bottom: 24 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  statusBanner(message: string, background: string, foreground: string) {
    Row() {
      Text('•')
        .fontSize(18)
        .fontColor(foreground)
      Text(message)
        .fontSize(12)
        .fontColor(foreground)
        .layoutWeight(1)
        .margin({ left: 8 })
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor(background)
    .borderRadius(8)
    .margin({ left: 16, right: 16, top: 10 })
  }

  @Builder
  actionRow(symbol: string, title: string, subtitle: string, destination: string) {
    Row() {
      Stack() {
        this.featureGlyph(symbol)
      }
        .width(42)
        .height(42)
        .borderRadius(21)
        .alignContent(Alignment.Center)
        .backgroundColor('#EBF4FC')
      Column() {
        Text(title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY)
        Text(subtitle)
          .fontSize(12)
          .fontColor(COLOR_TEXT_SECONDARY)
          .margin({ top: 4 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
      Text('›')
        .fontSize(24)
        .fontColor(COLOR_TEXT_HINT)
    }
    .width('100%')
    .padding(14)
    .backgroundColor(COLOR_CARD)
    .borderRadius(8)
    .border({ width: 1, color: COLOR_DIVIDER })
    .margin({ left: 16, right: 16, top: 10 })
    .onClick(() => {
      this.getUIContext().getRouter().pushUrl({ url: destination });
    })
  }

  @Builder
  tabMine() {
    Column() {
      this.topBar('更多', '常用功能与教务工具', '⌕', () => {
        this.getUIContext().getRouter().pushUrl({ url: 'pages/SearchPage' });
      });
      Scroll() {
        Column() {
          this.userCard();
          Row() {
            this.shortcut('▦', '时间表', '周视图', 1);
            this.shortcut('◉', '成绩', '成绩查询', 0);
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14 });

          this.sectionTitle('教务');
          this.menuGroup([
            new HitaMenuItem('◉', '成绩查询', '查看学期成绩与绩点', 'pages/ScorePage'),
            new HitaMenuItem('□', '考试查询', '查看考试时间与地点', 'pages/ExamPage'),
            new HitaMenuItem('⌕', '本地搜索', '搜索课程、事件和记录', 'pages/SearchPage')
          ]);
          this.sectionTitle('设置');
          this.menuGroup([
            new HitaMenuItem('◎', '会话管理', '登录校区与同步状态', 'pages/ProfilePage'),
            new HitaMenuItem('◇', '开发者自检', '检查本地数据库和网络链路', 'pages/Index'),
            new HitaMenuItem('i', '关于 HITA NEXT', '版本与开源信息', 'pages/AboutPage')
          ]);
          Text('HITA NEXT · HarmonyOS')
            .fontSize(12)
            .fontColor(COLOR_TEXT_HINT)
            .margin({ top: 22, bottom: 24 });
        }
        .width('100%')
        .padding({ bottom: 18 });
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off);
    }
    .width('100%')
    .height('100%');
  }

  @Builder
  userCard() {
    Row() {
      Column() {
        Text(this.sessionInfo === undefined ? '?' :
          (this.sessionInfo.name.length > 0 ? this.sessionInfo.name.substring(0, 1) : 'U'))
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF');
      }
      .width(54)
      .height(54)
      .borderRadius(27)
      .backgroundColor(this.sessionInfo === undefined ? '#AAB4C1' : COLOR_PRIMARY)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center);
      Column() {
        Text(this.sessionInfo === undefined ? '未登录' :
          (this.sessionInfo.name.length > 0 ? this.sessionInfo.name : this.sessionInfo.username))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_TEXT_PRIMARY);
        Text(this.sessionInfo === undefined ? '登录统一认证以使用完整功能' :
          Home.campusName(this.sessionInfo.campus) + '  ·  ' + this.sessionText)
          .fontSize(12)
          .fontColor(COLOR_TEXT_SECONDARY)
          .margin({ top: 5 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
        if (this.sessionInfo !== undefined && this.sessionInfo.stuId.length > 0) {
          Text('学号  ' + this.sessionInfo.stuId)
            .fontSize(11)
            .fontColor(COLOR_TEXT_HINT)
            .margin({ top: 3 });
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 14 });
      Text('›')
        .fontSize(24)
        .fontColor(COLOR_TEXT_HINT);
    }
    .width('100%')
    .padding(18)
    .backgroundColor(COLOR_CARD)
    .borderRadius(8)
    .border({ width: 1, color: COLOR_DIVIDER })
    .margin({ left: 16, right: 16, top: 16 })
    .onClick(() => {
      this.getUIContext().getRouter().pushUrl({
        url: this.sessionInfo === undefined ? 'pages/WelcomePage' : 'pages/ProfilePage'
      });
    });
  }

  @Builder
  shortcut(symbol: string, title: string, subtitle: string, destinationIndex: number) {
    Column() {
      Stack() {
        this.featureGlyph(symbol)
      }
        .width(42)
        .height(42)
        .borderRadius(21)
        .alignContent(Alignment.Center)
        .backgroundColor('#EBF4FC');
      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLOR_TEXT_PRIMARY)
        .margin({ top: 10 });
      Text(subtitle)
        .fontSize(11)
        .fontColor(COLOR_TEXT_SECONDARY)
        .margin({ top: 3 });
    }
    .layoutWeight(1)
    .height(116)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(COLOR_CARD)
    .borderRadius(8)
    .border({ width: 1, color: COLOR_DIVIDER })
    .margin({ right: destinationIndex === 1 ? 6 : 0, left: destinationIndex === 0 ? 6 : 0 })
    .onClick(() => {
      if (destinationIndex === 1) {
        this.currentTab = 1;
      } else {
        this.getUIContext().getRouter().pushUrl({ url: 'pages/ScorePage' });
      }
    });
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor(COLOR_TEXT_HINT)
      .margin({ left: 20, right: 20, top: 20, bottom: 8 })
      .alignSelf(ItemAlign.Start);
  }

  @Builder
  menuGroup(items: HitaMenuItem[]) {
    Column() {
      ForEach(items, (item: HitaMenuItem, index: number) => {
        Column() {
          Row() {
            Text(item.symbol)
              .fontSize(20)
              .fontColor(COLOR_PRIMARY)
              .width(34)
              .height(34)
              .textAlign(TextAlign.Center)
              .borderRadius(17)
              .backgroundColor('#EBF4FC');
            Column() {
              Text(item.title)
                .fontSize(15)
                .fontColor(COLOR_TEXT_PRIMARY);
              Text(item.subtitle)
                .fontSize(11)
                .fontColor(COLOR_TEXT_SECONDARY)
                .margin({ top: 3 });
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            .margin({ left: 12 });
            Text('›')
              .fontSize(23)
              .fontColor(COLOR_TEXT_HINT);
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .onClick(() => {
            this.getUIContext().getRouter().pushUrl({ url: item.destination });
          });
          if (index < items.length - 1) {
            Row()
              .width('100%')
              .height(1)
              .backgroundColor(COLOR_DIVIDER)
              .margin({ left: 62 });
          }
        }
      }, (item: HitaMenuItem) => item.destination);
    }
    .width('100%')
    .backgroundColor(COLOR_CARD)
    .borderRadius(8)
    .border({ width: 1, color: COLOR_DIVIDER })
    .margin({ left: 16, right: 16 })
    .clip(true);
  }
}
