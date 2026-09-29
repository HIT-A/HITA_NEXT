/**
 * HITA NEXT main shell.
 *
 * The Android client uses a compact toolbar and a floating pill navigation bar.
 * This page keeps the same information hierarchy while reusing the HarmonyOS
 * timetable/session data layer already used by the app.
 */
import { common } from '@kit.AbilityKit';
import { RdbHelper } from '../common/db/RdbHelper';
import { EasEventItem, EasEventType, EasTermSubject, EasTimetable } from '../common/model/timetable/TimetableModels';
import { DOW_FULL, EasTimeTools } from '../common/util/EasTimeTools';
import { TimetableLocalDemo } from '../feature/timetable/data/TimetableLocalDemo';
import { EasCampus, EasSession } from '../feature/eas/EasSession';
import { EasSessionStore } from '../feature/eas/EasSessionStore';
import { EasImportResult, EasTimetableImporter } from '../feature/eas/EasTimetableImporter';
import { TimetableResolver } from '../feature/timetable/data/TimetableResolver';
import { drawTimetableWeek, eventsOfWeek } from '../feature/timetable/views/TimetableWeekDraw';

const DAY_MS: number = 24 * 60 * 60 * 1000;
const COLOR_PRIMARY: string = '#2E86E8';
const COLOR_SURFACE: string = '#F4F7FC';
const COLOR_CARD: string = '#FFFFFF';
const COLOR_TEXT_PRIMARY: string = '#14213D';
const COLOR_TEXT_SECONDARY: string = '#6B7A90';
const COLOR_TEXT_HINT: string = '#8A96A8';
const COLOR_DIVIDER: string = '#DCE4F0';
const COLOR_NAV: string = '#FFFFFF';
const COLOR_NAV_ACTIVE: string = '#E3EEFC';
const COLOR_NAV_ACTIVE_TEXT: string = '#1B6FD1';
const COLOR_CLASS: string = '#2E86E8';
const COLOR_EXAM: string = '#8A2E42';
const COLOR_OTHER: string = '#1B4F9C';
const COLOR_TAG: string = '#0F6E56';

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
  @State timetableEvents: EasEventItem[] = [];
  @State timetableWeek: number = 1;
  private importRequested: boolean = false;
  private clockTimer: number = -1;
  private dayKey: string = EasTimeTools.printDate(Date.now());
  private timetableCanvas: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private timetableAreaW: number = 0;
  private timetableAreaH: number = 0;

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
      this.drawTimetableNow();
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
    this.sessionText = found === undefined ? '未登录：从导航页登录统一认证' : '已登录';

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
    let allEvents: EasEventItem[] = [];
    if (display !== undefined) {
      allEvents = await rdb.getEventsOfTimetable(display.id);
      const subjects: EasTermSubject[] = await rdb.getSubjectsOfTimetable(display.id);
      const colorById: Map<string, number> = new Map<string, number>();
      for (let i: number = 0; i < subjects.length; i++) {
        colorById.set(subjects[i].id, subjects[i].color);
      }
      for (let i: number = 0; i < allEvents.length; i++) {
        const color: number | undefined = colorById.get(allEvents[i].subjectId);
        allEvents[i].color = color === undefined ? Home.defaultCanvasColor(allEvents[i].type) : color;
      }
      this.timetableEvents = allEvents;
      const currentWeek: number = display.getWeekNumber(this.nowTick);
      this.timetableWeek = currentWeek > 0 ? currentWeek : 1;
    } else {
      this.timetableEvents = [];
      this.timetableWeek = 1;
    }
    const today: EasEventItem[] = allEvents.filter((event: EasEventItem): boolean =>
      event.from >= now0 && event.from < now0 + DAY_MS);
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

  private drawTimetableNow(): void {
    if (this.timetableAreaW <= 0 || this.timetableAreaH <= 0 || this.currentTimetable === undefined) {
      return;
    }
    const weekEvents: EasEventItem[] = eventsOfWeek(this.currentTimetable,
      this.timetableEvents, this.timetableWeek);
    const current: number = this.currentTimetable.getWeekNumber(this.nowTick);
    drawTimetableWeek(this.timetableCanvas, this.timetableAreaW, this.timetableAreaH,
      this.currentTimetable, weekEvents, this.timetableWeek, current === this.timetableWeek);
  }

  private maxTimetableWeek(): number {
    if (this.currentTimetable === undefined) {
      return 1;
    }
    const max: number = this.currentTimetable.getWeekNumber(this.currentTimetable.endTime - 1);
    return max > 0 ? max : 1;
  }

  private shiftTimetableWeek(delta: number): void {
    const next: number = this.timetableWeek + delta;
    if (next < 1 || next > this.maxTimetableWeek()) {
      return;
    }
    this.timetableWeek = next;
    this.drawTimetableNow();
  }

  private gotoCurrentTimetableWeek(): void {
    if (this.currentTimetable === undefined) {
      return;
    }
    const current: number = this.currentTimetable.getWeekNumber(this.nowTick);
    if (current > 0) {
      this.timetableWeek = current;
      this.drawTimetableNow();
    }
  }

  private timetableCampusTerm(): string {
    const campus: string = this.sessionInfo === undefined ? '' : Home.campusName(this.sessionInfo.campus);
    if (this.currentTimetable === undefined) {
      return campus.length > 0 ? campus : '当前学期';
    }
    return (campus.length > 0 ? campus + ' · ' : '') + this.currentTimetable.name;
  }

  private onTimetableArea(w: number, h: number): void {
    this.timetableAreaW = w;
    this.timetableAreaH = h;
    this.drawTimetableNow();
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
      return COLOR_PRIMARY;
    }
    if (status === '即将开始') {
      return COLOR_PRIMARY;
    }
    return COLOR_TEXT_HINT;
  }

  private static statusBgColor(status: string): string {
    if (status === '进行中') {
      return '#E3EEFC';
    }
    if (status === '即将开始') {
      return '#EAF3FD';
    }
    return '#F1F4F8';
  }

  private static defaultCanvasColor(type: EasEventType): number {
    if (type === EasEventType.EXAM) {
      return 0xFFB24B63;
    }
    if (type === EasEventType.OTHER) {
      return 0xFF4D7CC7;
    }
    if (type === EasEventType.TAG) {
      return 0xFF2F8F72;
    }
    return 0xFF2E86E8;
  }

  private todayClassCount(): number {
    let count: number = 0;
    for (let i: number = 0; i < this.todayItems.length; i++) {
      if (this.todayItems[i].type === EasEventType.CLASS) {
        count++;
      }
    }
    return count;
  }

  private completedClassCount(): number {
    let count: number = 0;
    for (let i: number = 0; i < this.todayItems.length; i++) {
      if (this.todayItems[i].type === EasEventType.CLASS && this.todayItems[i].to <= this.nowTick) {
        count++;
      }
    }
    return count;
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
      Row()
        .width(88)
        .height(52)
        .backgroundColor(COLOR_NAV_ACTIVE)
        .borderRadius(25)
        .offset({ x: 88 * this.currentTab })
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
    .borderRadius(27)
    .border({ width: 1, color: COLOR_DIVIDER })
    .shadow({ radius: 16, color: '#1A6B7A90', offsetX: 0, offsetY: 5 })
    .margin({ bottom: 12 });
  }

  @Builder
  navItem(symbol: Resource, label: string, index: number) {
    Column() {
      SymbolGlyph(symbol)
        .fontSize(20)
        .fontColor([index === this.currentTab ? COLOR_NAV_ACTIVE_TEXT : COLOR_TEXT_SECONDARY])
      Text(label)
        .fontSize(11)
        .fontColor(index === this.currentTab ? COLOR_NAV_ACTIVE_TEXT : COLOR_TEXT_SECONDARY)
        .margin({ top: 3 })
    }
    .width(88)
    .height(52)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('transparent')
    .borderRadius(25)
    .opacity(1)
    .onClick(() => {
      this.currentTab = index;
    })
  }

  @Builder
  topBar(title: string, subtitle: string, actionSymbol: string, action: () => void) {
    Row() {
      Column() {
        Text(title)
          .fontSize(22)
          .fontWeight(FontWeight.Medium)
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
        .backgroundColor(COLOR_NAV_ACTIVE)
        .alignContent(Alignment.Center)
        .onClick(action)
      }
    }
    .width('100%')
    .padding({ left: 20, right: 16, top: 14, bottom: 10 })
    .backgroundColor(COLOR_SURFACE)
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
      this.todayHeader();

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
  todayHeader() {
    Row() {
      Text((new Date(this.nowTick).getMonth() + 1).toString() + '月' +
        new Date(this.nowTick).getDate().toString() + '日')
        .fontSize(24)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLOR_TEXT_PRIMARY);
      Text(DOW_FULL[EasTimeTools.getDow(this.nowTick)] +
        (this.currentTimetable !== undefined && this.currentTimetable.getWeekNumber(this.nowTick) > 0
          ? ' · 第' + this.currentTimetable.getWeekNumber(this.nowTick).toString() + '周' : ''))
        .fontSize(13)
        .fontColor(COLOR_TEXT_SECONDARY)
        .margin({ left: 8, top: 7 });
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 14, bottom: 2 })
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  todayHeroCard() {
    Column() {
      Row() {
        Column() {
          if (this.activeClass !== undefined) {
            Text('正在进行')
              .fontSize(12)
              .fontColor('#DCEEFF')
              .fontWeight(FontWeight.Medium);
            Text(this.activeClass.name)
              .fontSize(20)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 5 });
          } else if (this.nextClass !== undefined) {
            Text('下一节课 · ' + Home.countdownText(this.nextClass, this.nowTick))
              .fontSize(12)
              .fontColor('#DCEEFF')
              .fontWeight(FontWeight.Medium);
            Text(this.nextClass.name)
              .fontSize(20)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 5 });
          } else {
            Text('今日空闲')
              .fontSize(20)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF');
            Text('享受当下，按自己的节奏安排今天')
              .fontSize(12)
              .fontColor('#DCEEFF')
              .margin({ top: 6 });
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);
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
            .backgroundColor('#5AA2EE')
            .borderRadius(12)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
        }
        .width('100%')
        .margin({ top: 16 });

        Progress({ value: this.activeClass.getProgress(this.nowTick) * 100, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(5)
          .color('#FFFFFF')
          .backgroundColor('#5AA2EE')
          .margin({ top: 12 });
        Text('今日已上 ' + this.completedClassCount().toString() + ' 节，共 ' +
          this.todayClassCount().toString() + ' 节')
          .fontSize(11)
          .fontColor('#DCEBFF')
          .margin({ top: 6 });
      } else if (this.nextClass !== undefined) {
        Row() {
          SymbolGlyph($r('sys.symbol.clock'))
            .fontSize(15)
            .fontColor(['#DCEEFF']);
          Text(EasTimeTools.printTime(this.nextClass.from) + ' - ' + EasTimeTools.printTime(this.nextClass.to))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .margin({ left: 6 });
          Blank();
          Text(this.nextClass.place.length > 0 ? this.nextClass.place : '待开始')
            .fontSize(12)
            .fontColor('#FFFFFF')
            .backgroundColor('#5AA2EE')
            .borderRadius(12)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
        }
        .width('100%')
        .margin({ top: 16 });

      } else {
        Text('今天没有待开始的课程')
          .fontSize(13)
          .fontColor('#DCEEFF')
          .margin({ top: 16 });
      }
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 16, bottom: 16 })
    .backgroundColor(COLOR_PRIMARY)
    .borderRadius(24)
    .shadow({ radius: 14, color: '#262E86E8', offsetY: 6 })
    .margin({ left: 14, right: 14, top: 12 });
  }

  @Builder
  todaySectionHeader() {
    Row() {
      Column() {
        Text('今日安排')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_SECONDARY);
        if (this.timelineText.length > 0) {
          Text(this.timelineText)
            .fontSize(11)
            .fontColor(COLOR_TEXT_HINT)
            .margin({ top: 3 });
        }
      }
      .alignItems(HorizontalAlign.Start);
      Blank();
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: 7 });
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
            .backgroundColor('#DCE4F0');
          Stack() {
            if (event.containsTimestamp(this.nowTick)) {
              Circle()
                .width(22)
                .height(22)
                .fill('#CFE3FA');
              Circle()
                .width(14)
                .height(14)
                .fill(COLOR_PRIMARY);
            } else {
              Circle()
                .width(event.to <= this.nowTick ? 18 : 12)
                .height(event.to <= this.nowTick ? 18 : 12)
                .fill(event.to <= this.nowTick ? '#C9D1DD' : Home.eventColor(event.type));
            }
            if (event.to <= this.nowTick && !event.containsTimestamp(this.nowTick)) {
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
            if (event.type !== EasEventType.CLASS) {
              Text(Home.typeTag(event.type))
                .fontSize(11)
                .fontColor(Home.eventColor(event.type))
                .width(24)
                .height(24)
                .textAlign(TextAlign.Center)
                .borderRadius(12)
                .backgroundColor(Home.statusBgColor(Home.eventStatus(event, this.nowTick)));
            }
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
                  .fontColor([COLOR_TEXT_SECONDARY]);
                Text(event.place)
                  .fontSize(12)
                  .fontColor(COLOR_TEXT_SECONDARY)
                  .margin({ left: 5 })
                  .backgroundColor('#E3EEFC')
                  .borderRadius(11)
                  .padding({ left: 7, right: 7, top: 3, bottom: 3 })
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
    .backgroundColor(COLOR_CARD)
    .borderRadius(16)
    .border({ width: event.containsTimestamp(this.nowTick) ? 1.5 : 1,
      color: event.containsTimestamp(this.nowTick) ? '#9CC5F5' : '#EDF1F7' })
    .clip(true)
    .margin({ bottom: 2 });
  }

  @Builder
  tabTimetable() {
    Column() {
      Row() {
        Column() {
          Text(this.currentTimetable === undefined ? '时间表' :
            '第' + this.timetableWeek.toString() + '周')
            .fontSize(22)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLOR_TEXT_PRIMARY)
          Text(this.timetableCampusTerm())
            .fontSize(12)
            .fontColor(COLOR_TEXT_SECONDARY)
            .backgroundColor(COLOR_CARD)
            .borderRadius(12)
            .padding({ left: 9, right: 9, top: 4, bottom: 4 })
            .margin({ top: 6 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Stack() {
          SymbolGlyph($r('sys.symbol.repeat_1'))
            .fontSize(19)
            .fontColor([COLOR_PRIMARY]);
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor(COLOR_NAV_ACTIVE)
        .alignContent(Alignment.Center)
        .onClick(() => {
          this.importTimetable(true);
        });
      }
      .width('100%')
      .padding({ left: 16, right: 14, top: 14, bottom: 8 })
      .alignItems(VerticalAlign.Center)

      if (this.currentTimetable === undefined) {
        Column() {
          Text('还没有课表数据')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLOR_TEXT_PRIMARY)
          Text('登录后导入课表，或先生成一份演示课表。')
            .fontSize(13)
            .fontColor(COLOR_TEXT_SECONDARY)
            .margin({ top: 8, bottom: 16 })
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
                .backgroundColor(COLOR_NAV_ACTIVE)
                .borderRadius(20)
                .margin({ left: 8 })
                .onClick(() => {
                  this.importTimetable(true);
                });
            }
          }
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding(24);
      } else {
        Row() {
          Text('‹')
            .fontSize(23)
            .fontColor(COLOR_TEXT_SECONDARY)
            .width(34)
            .height(30)
            .textAlign(TextAlign.Center)
            .borderRadius(15)
            .backgroundColor(COLOR_CARD)
            .border({ width: 1, color: COLOR_DIVIDER })
            .onClick(() => {
              this.shiftTimetableWeek(-1);
            });
          Text(this.timetableWeek === this.currentTimetable.getWeekNumber(this.nowTick)
            ? '本周' : '第' + this.timetableWeek.toString() + '周')
            .fontSize(12)
            .fontColor(COLOR_PRIMARY)
            .height(30)
            .padding({ left: 13, right: 13 })
            .backgroundColor(COLOR_NAV_ACTIVE)
            .borderRadius(15)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.gotoCurrentTimetableWeek();
            });
          Text('›')
            .fontSize(23)
            .fontColor(COLOR_TEXT_SECONDARY)
            .width(34)
            .height(30)
            .textAlign(TextAlign.Center)
            .borderRadius(15)
            .backgroundColor(COLOR_CARD)
            .border({ width: 1, color: COLOR_DIVIDER })
            .onClick(() => {
              this.shiftTimetableWeek(1);
            });
          Blank();
          Text(this.importing ? '正在同步…' : '左右滑动切换周')
            .fontSize(11)
            .fontColor(COLOR_TEXT_HINT)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 4, bottom: 7 })
        .alignItems(VerticalAlign.Center)

        Column() {
          Canvas(this.timetableCanvas)
            .width('100%')
            .height('100%')
            .onReady(() => {
              this.drawTimetableNow();
            })
            .onAreaChange((oldValue: Area, newValue: Area) => {
              this.onTimetableArea(newValue.width as number, newValue.height as number);
            })
            .gesture(
              SwipeGesture({ direction: SwipeDirection.Horizontal, speed: 120 })
                .onAction((event: GestureEvent) => {
                  if (event.offsetX < -60) {
                    this.shiftTimetableWeek(1);
                  } else if (event.offsetX > 60) {
                    this.shiftTimetableWeek(-1);
                  }
                })
            )
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 8, right: 8, top: 2, bottom: 4 })
        .backgroundColor(COLOR_SURFACE);
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLOR_SURFACE)
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
        .width(32)
        .height(32)
        .borderRadius(10)
        .alignContent(Alignment.Center)
        .backgroundColor(COLOR_NAV_ACTIVE)
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
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor(COLOR_CARD)
    .borderRadius(18)
    .border({ width: 1, color: '#EDF1F7' })
    .margin({ left: 14, right: 14, top: 9 })
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
          .padding({ left: 14, right: 14, top: 12 });

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
      .padding(16)
      .backgroundColor(COLOR_CARD)
      .borderRadius(20)
      .border({ width: 1, color: '#EDF1F7' })
      .margin({ left: 14, right: 14, top: 12 })
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
        .width(32)
        .height(32)
        .borderRadius(10)
        .alignContent(Alignment.Center)
        .backgroundColor(COLOR_NAV_ACTIVE);
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
    .borderRadius(18)
    .border({ width: 1, color: '#EDF1F7' })
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
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(COLOR_TEXT_SECONDARY)
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
              .width(32)
              .height(32)
              .textAlign(TextAlign.Center)
              .borderRadius(10)
              .backgroundColor(COLOR_NAV_ACTIVE);
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
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
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
    .borderRadius(18)
    .border({ width: 1, color: '#EDF1F7' })
    .margin({ left: 14, right: 14 })
    .clip(true);
  }
}
