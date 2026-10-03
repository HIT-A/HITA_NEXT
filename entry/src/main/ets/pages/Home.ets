/**
 * HITA NEXT main shell.
 *
 * The Android client uses a compact toolbar and a floating pill navigation bar.
 * This page keeps the same information hierarchy while reusing the HarmonyOS
 * timetable/session data layer already used by the app.
 */
import { common } from '@kit.AbilityKit';
import { FrameCallback } from '@kit.ArkUI';
import { HeaderBackButton } from '../common/components/HeaderBackButton';
import { RdbHelper } from '../common/db/RdbHelper';
import { EasEventItem, EasEventType, EasTermSubject, EasTimetable } from '../common/model/timetable/TimetableModels';
import { DOW_FULL, EasTimeTools } from '../common/util/EasTimeTools';
import { EasCampus, EasSession } from '../feature/eas/EasSession';
import { EasSessionStore } from '../feature/eas/EasSessionStore';
import { EasImportResult, EasTimetableImporter } from '../feature/eas/EasTimetableImporter';
import { EasLoginPage } from '../feature/eas/webLogin/EasLoginPage';
import { TimetableResolver } from '../feature/timetable/data/TimetableResolver';
import { TimetableSelectionStore } from '../feature/timetable/data/TimetableSelectionStore';
import { IcsImportResult, TimetableIcsImporter } from '../feature/timetable/data/TimetableIcsImporter';
import {
  AXIS_END_HOUR,
  AXIS_START_HOUR,
  TIMETABLE_GRID_TOP_PADDING,
  TIMETABLE_HEADER_HEIGHT,
  TIMETABLE_HOUR_HEIGHT,
  TimetablePlaceLabel,
  drawTimetablePlaces,
  drawTimetableWeek,
  drawTimetableWeekHeader,
  eventsOfWeek,
  timetableEventSpan
} from '../feature/timetable/views/TimetableWeekDraw';

const DAY_MS: number = 24 * 60 * 60 * 1000;
const COLOR_PRIMARY: string = '#2E86E8';
const COLOR_SURFACE: string = '#F4F7FC';
const COLOR_CARD: string = '#FFFFFF';
const COLOR_TEXT_PRIMARY: string = '#14213D';
const COLOR_TEXT_SECONDARY: string = '#6B7A90';
const COLOR_TEXT_HINT: string = '#8A96A8';
const COLOR_NAV_ACTIVE: string = '#E3EEFC';
const COLOR_NAV_ACTIVE_TEXT: string = '#1B6FD1';
const COLOR_CLASS: string = '#2E86E8';
const COLOR_EXAM: string = '#8A2E42';
const COLOR_OTHER: string = '#1B4F9C';
const COLOR_TAG: string = '#0F6E56';
const TIMETABLE_BOTTOM_SAFE_EXTENSION: number = 56;

class TimetableMarqueeCallback extends FrameCallback {
  private callback: (timeMs: number) => void;

  constructor(callback: (timeMs: number) => void) {
    super();
    this.callback = callback;
  }

  onFrame(frameTimeInNano: number): void {
    this.callback(frameTimeInNano / 1000000);
  }
}

@Entry
@Component
struct Home {
  @State todayItems: EasEventItem[] = [];
  @State timelineText: string = '暂无今日日程';
  @State sessionText: string = '未登录';
  @State currentTab: number = 0;
  @State hasTimetable: boolean = false;
  @State timetableCount: number = 0;
  @State currentTimetable: EasTimetable | undefined = undefined;
  @State recentTimetable: EasTimetable | undefined = undefined;
  @State importing: boolean = false;
  @State importMessage: string = '';
  @State importError: string = '';
  @State activeClass: EasEventItem | undefined = undefined;
  @State nextClass: EasEventItem | undefined = undefined;
  @State nowTick: number = Date.now();
  @State sessionInfo: EasSession | undefined = undefined;
  @State activeSheetVisible: boolean = false;
  @State sessionSheetOpen: boolean = false;
  @State sessionSheetCampus: string = 'WEIHAI';
  @State sessionSheetInfo: EasSession | undefined = undefined;
  @State loginSheetOpen: boolean = false;
  @State loginCampusCode: string = 'WEIHAI';
  @State courseSheetOpen: boolean = false;
  @State selectedCourse: EasEventItem | undefined = undefined;
  @State timetableEvents: EasEventItem[] = [];
  @State timetableWeek: number = 1;
  // Week paging follows the Android timetable: drag the page with the finger,
  // then slide it out/in around the week data swap.
  @State timetableDragOffset: number = 0;
  @State timetableAnimationDuration: number = 0;
  @State timetableAnimating: boolean = false;
  private importRequested: boolean = false;
  private clockTimer: number = -1;
  private pageVisible: boolean = false;
  private timetablePlaceLabels: TimetablePlaceLabel[] = [];
  private timetableMarqueeCallback: TimetableMarqueeCallback | undefined = undefined;
  private timetableMarqueeGeneration: number = 0;
  private timetableMarqueeElapsedMs: number = 0;
  private timetableMarqueeLastFrameMs: number = -1;
  private timetableAnimationTimer: number = -1;
  private dayKey: string = EasTimeTools.printDate(Date.now());
  private timetableCanvas: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private timetableHeaderCanvas: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private timetablePlaceCanvas: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private timetableAreaW: number = 0;
  private timetableAreaH: number = 0;
  @State private timetableCanvasHeight: number = 0;

  async aboutToAppear(): Promise<void> {
    this.pageVisible = true;
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    await EasSessionStore.getInstance().init(ctx);
    await TimetableSelectionStore.getInstance().init(ctx);
    const params: Object | undefined = this.getUIContext().getRouter().getParams();
    if (params !== undefined && params !== null) {
      const record: Record<string, string> = params as Record<string, string>;
      // ScorePage 等页面的“去登录”直达会话弹层（原开发入口页已移除）。
      if (record['openSession'] === '1') {
        this.openSessionSheet();
      }
    }
    await this.refreshSummaries();
    this.startClock();
  }

  async onPageShow(): Promise<void> {
    this.pageVisible = true;
    this.startClock();
    await this.refreshSummaries();
    this.drawTimetableNow();
  }

  onPageHide(): void {
    this.pageVisible = false;
    this.stopTimetableMarquee();
  }

  aboutToDisappear(): void {
    this.pageVisible = false;
    this.stopTimetableMarquee();
    if (this.clockTimer >= 0) {
      clearInterval(this.clockTimer);
      this.clockTimer = -1;
    }
    if (this.timetableAnimationTimer >= 0) {
      clearTimeout(this.timetableAnimationTimer);
      this.timetableAnimationTimer = -1;
    }
  }

  private startClock(): void {
    if (this.clockTimer < 0) {
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
  }

  private stopTimetableMarquee(): void {
    // Queued frame callbacks cannot be cancelled; invalidate their generation.
    this.timetableMarqueeGeneration++;
    this.timetableMarqueeCallback = undefined;
    this.timetableMarqueeLastFrameMs = -1;
  }

  private startTimetableMarquee(): void {
    if (this.timetableMarqueeCallback !== undefined || !this.pageVisible ||
      this.currentTab !== 1 || this.timetablePlaceLabels.length === 0) {
      return;
    }
    const generation: number = this.timetableMarqueeGeneration;
    const callback: TimetableMarqueeCallback = new TimetableMarqueeCallback((timeMs: number) => {
      if (generation !== this.timetableMarqueeGeneration || !this.pageVisible || this.currentTab !== 1) {
        return;
      }
      if (this.timetableMarqueeLastFrameMs >= 0) {
        this.timetableMarqueeElapsedMs += Math.max(0, timeMs - this.timetableMarqueeLastFrameMs);
      }
      this.timetableMarqueeLastFrameMs = timeMs;
      const nextDelay: number = drawTimetablePlaces(this.timetablePlaceCanvas,
        this.timetableAreaW, this.timetableCanvasHeight, this.timetablePlaceLabels,
        this.timetableMarqueeElapsedMs);
      if (nextDelay < 0) {
        this.stopTimetableMarquee();
      } else if (nextDelay > 0) {
        this.getUIContext().postDelayedFrameCallback(callback, Math.ceil(nextDelay));
      } else {
        this.getUIContext().postFrameCallback(callback);
      }
    });
    this.timetableMarqueeCallback = callback;
    this.getUIContext().postFrameCallback(callback);
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

    const allTimetables: EasTimetable[] = await rdb.getTimetables();
    this.timetableCount = allTimetables.length;
    this.recentTimetable = await TimetableResolver.getRecent(rdb, this.nowTick);
    const selectedId: string = await TimetableSelectionStore.getInstance().load();
    let selected: EasTimetable | undefined = undefined;
    if (selectedId.length > 0) {
      selected = await rdb.getTimetableById(selectedId);
      if (selected === undefined) {
        await TimetableSelectionStore.getInstance().clearIf(selectedId);
      }
    }
    const real: EasTimetable | undefined = await TimetableResolver.getReal(rdb);
    if (found !== undefined && real === undefined && selected === undefined &&
      !this.importing && !this.importRequested) {
      await this.importTimetable(false);
      return;
    }

    const display: EasTimetable | undefined = selected !== undefined ? selected :
      (real !== undefined ? real : await TimetableResolver.getForDisplay(rdb));
    this.hasTimetable = display !== undefined;
    this.currentTimetable = display;

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
      this.stopTimetableMarquee();
      return;
    }
    const weekEvents: EasEventItem[] = eventsOfWeek(this.currentTimetable,
      this.timetableEvents, this.timetableWeek);
    const current: number = this.currentTimetable.getWeekNumber(this.nowTick);
    const hourHeight: number = this.timetableHourHeight();
    const bodyViewportHeight: number = Math.max(1,
      this.timetableAreaH - TIMETABLE_HEADER_HEIGHT + TIMETABLE_BOTTOM_SAFE_EXTENSION);
    const contentHeight: number = TIMETABLE_GRID_TOP_PADDING +
      (AXIS_END_HOUR - AXIS_START_HOUR) * hourHeight + 8;
    const canvasHeight: number = Math.max(bodyViewportHeight, contentHeight);
    if (this.timetableCanvasHeight !== canvasHeight) {
      this.timetableCanvasHeight = canvasHeight;
    }
    const labels: TimetablePlaceLabel[] = drawTimetableWeek(this.timetableCanvas,
      this.timetableAreaW, canvasHeight,
      this.currentTimetable, weekEvents, this.timetableWeek, current === this.timetableWeek,
      hourHeight, 0, false);
    if (labels.length !== this.timetablePlaceLabels.length ||
      labels.some((label: TimetablePlaceLabel, index: number): boolean =>
        !label.matches(this.timetablePlaceLabels[index]))) {
      this.stopTimetableMarquee();
      this.timetableMarqueeElapsedMs = 0;
    }
    this.timetablePlaceLabels = labels;
    drawTimetablePlaces(this.timetablePlaceCanvas, this.timetableAreaW, canvasHeight,
      labels, this.timetableMarqueeElapsedMs);
    this.startTimetableMarquee();
    drawTimetableWeekHeader(this.timetableHeaderCanvas, this.timetableAreaW,
      TIMETABLE_HEADER_HEIGHT, this.currentTimetable, this.timetableWeek,
      current === this.timetableWeek);
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
    this.stopTimetableMarquee();
    this.timetableMarqueeElapsedMs = 0;
    this.drawTimetableNow();
  }

  private timetableDragLimit(): number {
    return Math.max(1, this.timetableAreaW);
  }

  private timetableHourHeight(): number {
    if (this.timetableAreaH <= TIMETABLE_HEADER_HEIGHT) {
      return TIMETABLE_HOUR_HEIGHT;
    }
    // Keep 08:00–19:00 visible in the initial viewport, while preserving
    // the iOS compact layout's 56vp/hour as the upper bound.
    const visibleHours: number = 19 - AXIS_START_HOUR;
    const availableGridHeight: number = this.timetableAreaH - TIMETABLE_HEADER_HEIGHT -
      TIMETABLE_GRID_TOP_PADDING - 8 + TIMETABLE_BOTTOM_SAFE_EXTENSION;
    return Math.max(42, Math.min(TIMETABLE_HOUR_HEIGHT, availableGridHeight / visibleHours));
  }

  private openCourseAt(x: number, y: number): void {
    if (this.currentTimetable === undefined || x <= 0 || y < TIMETABLE_GRID_TOP_PADDING) {
      return;
    }
    const gutterWidth: number = Math.max(48, this.timetableAreaW * 0.11);
    if (x < gutterWidth || x > this.timetableAreaW) {
      return;
    }
    const columnWidth: number = (this.timetableAreaW - gutterWidth) / 7;
    const day: number = Math.max(1, Math.min(7, Math.floor((x - gutterWidth) / columnWidth) + 1));
    const minuteOfDay: number = AXIS_START_HOUR * 60 +
      (y - TIMETABLE_GRID_TOP_PADDING) / this.timetableHourHeight() * 60;
    if (minuteOfDay < AXIS_START_HOUR * 60 || minuteOfDay > AXIS_END_HOUR * 60) {
      return;
    }
    const weekMonday: number = this.currentTimetable.startTime +
      (this.timetableWeek - 1) * 7 * DAY_MS;
    const tappedTime: number = weekMonday + (day - 1) * DAY_MS + minuteOfDay * 60000;
    const weekEvents: EasEventItem[] = eventsOfWeek(this.currentTimetable,
      this.timetableEvents, this.timetableWeek);
    for (let i: number = weekEvents.length - 1; i >= 0; i--) {
      const event: EasEventItem = weekEvents[i];
      const span = timetableEventSpan(this.currentTimetable, event, this.timetableWeek);
      const isCourseOrExam: boolean = event.type === EasEventType.CLASS || event.type === EasEventType.EXAM;
      if (isCourseOrExam && event.getDow() === day && span !== undefined &&
        span.from <= tappedTime && span.to >= tappedTime) {
        this.selectedCourse = event;
        this.courseSheetOpen = true;
        this.activeSheetVisible = true;
        return;
      }
    }
  }

  private eventDetailEndTime(event: EasEventItem): number {
    if (event.to > event.from) {
      return event.to;
    }
    if (this.currentTimetable !== undefined) {
      const span = timetableEventSpan(this.currentTimetable, event, this.timetableWeek);
      if (span !== undefined && span.to > span.from) {
        return span.to;
      }
    }
    return event.from + 60 * 60 * 1000;
  }

  private courseProgressText(event: EasEventItem): string {
    const instances: EasEventItem[] = this.timetableEvents.filter((item: EasEventItem): boolean =>
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

  private timetableOpacity(): number {
    const ratio: number = Math.abs(this.timetableDragOffset) / this.timetableDragLimit();
    // Android uses alpha = 1 - abs(offset) / pageWidth while paging.
    return 1 - Math.min(1, ratio);
  }

  private resetTimetableAnimationState(): void {
    this.timetableAnimationDuration = 0;
    this.timetableDragOffset = 0;
    this.timetableAnimating = false;
    this.timetableAnimationTimer = -1;
  }

  private animateTimetableSnapBack(): void {
    this.timetableAnimating = true;
    this.timetableAnimationDuration = 150;
    this.timetableDragOffset = 0;
    this.timetableAnimationTimer = setTimeout(() => {
      this.resetTimetableAnimationState();
    }, 170);
  }

  private animateTimetableWeek(delta: number): void {
    if (this.timetableAnimating) {
      return;
    }
    const width: number = this.timetableDragLimit();
    const exitOffset: number = delta > 0 ? -width : width;
    const entryOffset: number = -exitOffset;
    this.timetableAnimating = true;
    this.timetableAnimationDuration = 150;
    this.timetableDragOffset = exitOffset;

    // Swap the week after the outgoing page has left, then bring the new page
    // in from the opposite edge. A zero-duration reposition prevents a reverse
    // animation through the center between the two 150ms legs.
    this.timetableAnimationTimer = setTimeout(() => {
      this.timetableAnimationDuration = 0;
      this.shiftTimetableWeek(delta);
      this.timetableDragOffset = entryOffset;
      this.timetableAnimationTimer = setTimeout(() => {
        this.timetableAnimationDuration = 150;
        this.timetableDragOffset = 0;
        this.timetableAnimationTimer = setTimeout(() => {
          this.resetTimetableAnimationState();
        }, 170);
      }, 20);
    }, 160);
  }

  private handleTimetablePanUpdate(event: GestureEvent): void {
    if (this.timetableAnimating) {
      return;
    }
    const width: number = this.timetableDragLimit();
    this.timetableAnimationDuration = 0;
    this.timetableDragOffset = Math.max(-width, Math.min(width, event.offsetX));
  }

  private handleTimetablePanEnd(event: GestureEvent): void {
    if (this.timetableAnimating) {
      return;
    }
    const width: number = this.timetableDragLimit();
    const threshold: number = width * 0.15;
    const offset: number = event.offsetX;
    if (offset < -threshold && this.timetableWeek < this.maxTimetableWeek()) {
      this.animateTimetableWeek(1);
    } else if (offset > threshold && this.timetableWeek > 1) {
      this.animateTimetableWeek(-1);
    } else if (Math.abs(offset) > 0) {
      this.animateTimetableSnapBack();
    } else {
      this.resetTimetableAnimationState();
    }
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
    const hourHeight: number = this.timetableHourHeight();
    const bodyViewportHeight: number = Math.max(1,
      h - TIMETABLE_HEADER_HEIGHT + TIMETABLE_BOTTOM_SAFE_EXTENSION);
    const contentHeight: number = TIMETABLE_GRID_TOP_PADDING +
      (AXIS_END_HOUR - AXIS_START_HOUR) * hourHeight + 8;
    this.timetableCanvasHeight = Math.max(bodyViewportHeight, contentHeight);
    this.drawTimetableNow();
  }

  private async importIcsTimetable(): Promise<void> {
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      const result: IcsImportResult | undefined = await TimetableIcsImporter.pickAndImport(ctx);
      if (result === undefined) {
        return;
      }
      this.getUIContext().getPromptAction().showToast({ message: result.message });
      if (result.success) {
        await this.refreshSummaries();
        this.getUIContext().getRouter().pushUrl({
          url: 'pages/TimetableDetailPage',
          params: { 'timetableId': result.timetableId }
        });
      }
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '导入 ICS 失败' });
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
        if (result.timetable !== undefined) {
          await TimetableSelectionStore.getInstance().save(result.timetable.id);
        }
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

  private static campusFromCode(code: string): EasCampus {
    if (code === 'SHENZHEN') {
      return EasCampus.SHENZHEN;
    }
    if (code === 'BENBU') {
      return EasCampus.BENBU;
    }
    return EasCampus.WEIHAI;
  }

  private async openSessionSheet(): Promise<void> {
    const storedCampus: EasCampus | undefined = await EasSessionStore.getInstance().loadLastCampus();
    const campus: EasCampus = this.sessionInfo === undefined ?
      (storedCampus === undefined ? EasCampus.WEIHAI : storedCampus) : this.sessionInfo.campus;
    this.sessionSheetCampus = campus.toString();
    this.sessionSheetInfo = await EasSessionStore.getInstance().load(campus);
    this.sessionSheetOpen = true;
    this.activeSheetVisible = true;
  }

  private async selectSessionCampus(code: string): Promise<void> {
    this.sessionSheetCampus = code;
    this.sessionSheetInfo = await EasSessionStore.getInstance().load(Home.campusFromCode(code));
  }

  private beginSessionLogin(): void {
    this.loginCampusCode = this.sessionSheetCampus;
    this.sessionSheetOpen = false;
    this.loginSheetOpen = true;
    this.activeSheetVisible = true;
  }

  private async logoutSession(): Promise<void> {
    const campus: EasCampus = Home.campusFromCode(this.sessionSheetCampus);
    await EasSessionStore.getInstance().clear(campus);
    this.sessionSheetInfo = undefined;
    this.activeSheetVisible = false;
    await this.refreshSummaries();
    this.getUIContext().getPromptAction().showToast({ message: '已退出' + Home.campusName(campus) + '教务会话' });
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
      // 时间表/更多页：内容延伸进底部安全区，导航胶囊悬浮在内容之上（与时间表一致）。
      .padding({ bottom: this.currentTab === 0 ? 64 : 0 })
      .backgroundColor(this.currentTab === 1 ? 'transparent' : COLOR_SURFACE)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])

      this.pillNavigation();

    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.currentTab === 1 ? 'transparent' : COLOR_SURFACE)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .bindSheet(this.activeSheetVisible, this.activeSheet(), {
      height: this.loginSheetOpen ? SheetSize.LARGE : SheetSize.FIT_CONTENT,
      dragBar: true,
      // Every sheet owns its header control; the system close bubble overlaps
      // the web login toolbar's trailing actions.
      showClose: false,
      preferType: SheetType.BOTTOM,
      backgroundColor: COLOR_SURFACE,
      maskColor: 'rgba(20,33,61,0.24)',
      onDisappear: () => {
        // Keep content and height stable until the dismissal animation finishes.
        this.activeSheetVisible = false;
        this.sessionSheetOpen = false;
        this.loginSheetOpen = false;
        this.courseSheetOpen = false;
        this.selectedCourse = undefined;
      }
    });
  }

  @Builder
  activeSheet() {
    if (this.loginSheetOpen) {
      EasLoginPage({
        campusCode: this.loginCampusCode,
        studentType: '1',
        onCancel: () => {
          this.activeSheetVisible = false;
        },
        onLoggedIn: (session: EasSession) => {
          this.activeSheetVisible = false;
          this.sessionSheetInfo = session;
          this.refreshSummaries();
        }
      })
        .width('100%')
        .height('100%');
    } else if (this.courseSheetOpen && this.selectedCourse !== undefined) {
      this.courseDetailSheet(this.selectedCourse as EasEventItem);
    } else {
      this.sessionSheet();
    }
  }

  @Builder
  pillNavigation() {
    Stack() {
      Stack() {
        Row()
          .width(68)
          .height(44)
          // Keep the Android-style selected capsule visible. Only the area
          // around the navigation pill is transparent over the timetable.
          .backgroundColor(COLOR_NAV_ACTIVE)
          .borderRadius(22)
          .offset({ x: 68 * this.currentTab })
          .animation({ duration: 260, curve: Curve.EaseInOut });

        Row() {
          this.navItem($r('sys.symbol.calendar'), '今日', 0);
          this.navItem($r('sys.symbol.doc_plaintext'), '时间表', 1);
          this.navItem($r('sys.symbol.more'), '更多', 2);
        }
        .width(204)
        .height(44);
      }
      .width(204)
      .height(44)
      .alignContent(Alignment.Start);
    }
    .width(212)
    .height(52)
    .padding(4)
    .backgroundColor(COLOR_CARD)
    .borderRadius(28)
    .border({ width: 1, color: '#E7EDF5' })
    .shadow({ radius: 14, color: '#18000000', offsetX: 0, offsetY: 4 })
    .margin({ bottom: 0 })
    .translate({ y: 10 });
  }

  @Builder
  navItem(symbol: Resource, label: string, index: number) {
    Column() {
      SymbolGlyph(symbol)
        .fontSize(18)
        .fontColor([index === this.currentTab ? COLOR_NAV_ACTIVE_TEXT : COLOR_TEXT_SECONDARY])
      Text(label)
        .fontSize(11)
        .fontColor(index === this.currentTab ? COLOR_NAV_ACTIVE_TEXT : COLOR_TEXT_SECONDARY)
        .margin({ top: 3 })
    }
    .width(68)
    .height(44)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('transparent')
    .borderRadius(22)
    .opacity(1)
    .onClick(() => {
      if (this.currentTab !== index) {
        this.stopTimetableMarquee();
        this.timetableMarqueeElapsedMs = 0;
      }
      this.currentTab = index;
    })
  }

  @Builder
  tabToday() {
    Column() {
      this.todayHeader();

      Row() {
        this.todayHeroCard();
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
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
    .margin({ top: 12 });
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
      Text(this.hasTimetable ? '本周其余课程见时间表' : '暂无已导入或手动创建的课表')
        .fontSize(13)
        .fontColor(COLOR_TEXT_HINT)
        .margin({ top: 8, bottom: 20 })
      if (!this.hasTimetable) {
        this.emptyTimetableActions();
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
  emptyTimetableActions() {
    Row({ space: 10 }) {
      Button(this.sessionInfo === undefined ? '登录教务' : '导入课表')
        .fontSize(14)
        .height(40)
        .fontColor('#FFFFFF')
        .backgroundColor(COLOR_PRIMARY)
        .borderRadius(20)
        .onClick(() => {
          if (this.sessionInfo === undefined) {
            this.openSessionSheet();
          } else {
            this.getUIContext().getRouter().pushUrl({ url: 'pages/ImportTimetablePage' });
          }
        });
      Button('课表管理')
        .fontSize(14)
        .height(40)
        .fontColor(COLOR_PRIMARY)
        .backgroundColor(COLOR_NAV_ACTIVE)
        .borderRadius(20)
        .onClick(() => {
          this.getUIContext().getRouter().pushUrl({ url: 'pages/TimetableManagerPage' });
        });
    }
  }

  @Builder
  tabTimetable() {
    Column() {
      Row() {
        Column() {
          Text(this.currentTimetable === undefined ? '时间表' :
            '第' + this.timetableWeek.toString() + '周')
            .fontSize(34)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.timetableCampusTerm())
            .fontSize(15)
            .fontColor(COLOR_TEXT_SECONDARY)
            .backgroundColor(COLOR_CARD)
            .borderRadius(12)
            .padding({ left: 11, right: 11, top: 5, bottom: 5 })
            .margin({ top: 7 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ left: 20, right: 18, top: 16, bottom: 10 })
      .alignItems(VerticalAlign.Center)

      if (this.currentTimetable === undefined) {
        Column() {
          Text('还没有课表数据')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLOR_TEXT_PRIMARY)
          Text('暂无已导入或手动创建的课表')
            .fontSize(13)
            .fontColor(COLOR_TEXT_SECONDARY)
            .margin({ top: 8, bottom: 16 })
          this.emptyTimetableActions();
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding(24);
      } else {
        Column() {
          Canvas(this.timetableHeaderCanvas)
            .width('100%')
            .height(TIMETABLE_HEADER_HEIGHT)
            .onReady(() => {
              this.drawTimetableNow();
            })

          Scroll() {
            Stack({ alignContent: Alignment.TopStart }) {
              Canvas(this.timetableCanvas)
                .width('100%')
                .height('100%')
                .onReady(() => {
                  this.drawTimetableNow();
                })
                .onClick((event: ClickEvent) => {
                  this.openCourseAt(event.x, event.y);
                })
              Canvas(this.timetablePlaceCanvas)
                .width('100%')
                .height('100%')
                .hitTestBehavior(HitTestMode.None)
                .onReady(() => {
                  this.drawTimetableNow();
                })
            }
            .width('100%')
            .height(this.timetableCanvasHeight)
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
            .onDisAppear(() => {
              this.stopTimetableMarquee();
            })
          }
          .width('100%')
          .layoutWeight(1)
          .scrollable(ScrollDirection.Vertical)
          .scrollBar(BarState.Off)
          // The navigation pill is drawn into the bottom system inset. Extend
          // the timetable viewport there as well so the grid remains visible
          // beneath the translucent lower half of the pill.
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        }
        .width('100%')
        .layoutWeight(1)
        // Keep the body canvas flush with the fixed date header.  Its own
        // 24vp grid top padding is painted by the today-column mask, so a
        // separate layout gap would visibly break that column.
        .padding({ top: 0 })
        .backgroundColor('transparent')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        .clip(false)
        .onAreaChange((oldValue: Area, newValue: Area) => {
          this.onTimetableArea(newValue.width as number, newValue.height as number);
        })
        .translate({ x: this.timetableDragOffset, y: 0 })
        .opacity(this.timetableOpacity())
        .animation({ duration: this.timetableAnimationDuration, curve: Curve.EaseOut })
        .gesture(
          PanGesture({ direction: PanDirection.Horizontal, distance: 10 })
            .onActionUpdate((event: GestureEvent) => {
              this.handleTimetablePanUpdate(event);
            })
            .onActionEnd((event: GestureEvent) => {
              this.handleTimetablePanEnd(event);
            })
        );
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('transparent')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
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
  tabMine() {
    Column() {
      Row() {
        Text('功能中心')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center);

      Scroll() {
        Column() {
          this.userCard();

          Row() {
            this.moreShortcut($r('sys.symbol.calendar'), '最近课表',
              this.recentTimetable === undefined ? '暂无课表' : this.recentTimetable.name,
              () => {
                if (this.recentTimetable !== undefined) {
                  this.getUIContext().getRouter().pushUrl({
                    url: 'pages/TimetableDetailPage',
                    params: { 'timetableId': this.recentTimetable.id }
                  });
                }
              });
            Blank().width(8);
            this.moreShortcut($r('sys.symbol.doc_plaintext'), '课表管理',
              this.timetableCount === 0 ? '暂无课表' : '共 ' + this.timetableCount.toString() + ' 张课表',
              () => {
                this.getUIContext().getRouter().pushUrl({ url: 'pages/TimetableManagerPage' });
              });
          }
          .width('100%')
          .padding({ top: 8 });

          this.moreSectionTitle('课表工具');
          Column() {
            this.moreNavigationRow($r('sys.symbol.repeat_1'), '导入课表',
              this.importing ? '正在从教务系统同步' : '从教务系统同步当前学期', () => {
                this.getUIContext().getRouter().pushUrl({ url: 'pages/ImportTimetablePage' });
              });
            this.moreNavigationRow($r('sys.symbol.doc_plaintext'), '导入 ICS 课表',
              '从日历文件导入课程', () => {
                this.importIcsTimetable();
              });
          }
          .width('100%')
          .padding({ top: 4, bottom: 4 })
          .backgroundColor(COLOR_CARD)
          .borderRadius(16);

          this.moreSectionTitle('教务功能');
          Column() {
            this.moreNavigationRow($r('sys.symbol.calendar'), '考试',
              '查看考试时间与地点', () => {
                this.getUIContext().getRouter().pushUrl({ url: 'pages/ExamPage' });
              });
            this.moreNavigationRow($r('sys.symbol.doc_plaintext'), '成绩管理',
              '查看学期成绩与绩点', () => {
                this.getUIContext().getRouter().pushUrl({ url: 'pages/ScorePage' });
              });
            this.moreNavigationRow($r('sys.symbol.magnifyingglass'), '空教室',
              '查询可用教室与空闲时段', () => {
                this.getUIContext().getPromptAction().showToast({ message: '空教室查询将在教务会话完善后开放' });
              });
          }
          .width('100%')
          .padding({ top: 4, bottom: 4 })
          .backgroundColor(COLOR_CARD)
          .borderRadius(16);

          this.moreSectionTitle('课程资源');
          Column() {
            this.moreNavigationRow($r('sys.symbol.magnifyingglass'), '本地搜索',
              '搜索课程、教师与教室', () => {
                this.getUIContext().getRouter().pushUrl({ url: 'pages/SearchPage' });
              });
          }
          .width('100%')
          .padding({ top: 4, bottom: 4 })
          .backgroundColor(COLOR_CARD)
          .borderRadius(16);

          this.moreSectionTitle('设置');
          Column() {
            this.moreNavigationRow($r('sys.symbol.doc_plaintext'), '公告',
              '版本更新 · 服务与故障通知', () => {
                this.getUIContext().getRouter().pushUrl({ url: 'pages/NoticesPage' });
              });
          }
          .width('100%')
          .padding({ top: 4, bottom: 4 })
          .backgroundColor(COLOR_CARD)
          .borderRadius(16);

          Blank().height(110);
        }
        .width('100%')
        // Single source of truth for the tab's horizontal inset: every card,
        // title and shortcut row below spans this padded content area.
        .padding({ left: 16, right: 16, bottom: 16 });
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM]);
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
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF');
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor(this.sessionInfo === undefined ? '#AAB4C1' : COLOR_PRIMARY)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center);
      Column() {
        Text(this.sessionInfo === undefined ? '未登录教务' :
          (this.sessionInfo.name.length > 0 ? this.sessionInfo.name :
            (this.sessionInfo.username.length > 0 ? this.sessionInfo.username :
              (this.sessionInfo.stuId.length > 0 ? this.sessionInfo.stuId : '已登录教务'))))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_TEXT_PRIMARY);
        Text(this.sessionInfo === undefined ? '点击进行教务登录' :
          ((this.sessionInfo.stuId.length > 0 ? this.sessionInfo.stuId + '\n' : '') +
            Home.campusName(this.sessionInfo.campus) +
            (this.sessionInfo.school.length > 0 ? ' · ' + this.sessionInfo.school : '') +
            (this.sessionInfo.major.length > 0 ? ' · ' + this.sessionInfo.major : '')))
          .fontSize(12)
          .fontColor(COLOR_TEXT_SECONDARY)
          .margin({ top: 4 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 });
      Text('›')
        .fontSize(24)
        .fontColor(COLOR_TEXT_SECONDARY);
    }
    .width('100%')
    .padding(16)
    .backgroundColor(COLOR_CARD)
    .borderRadius(16)
    .margin({ top: 8, bottom: 8 })
    .onClick(() => {
      this.openSessionSheet();
    });
  }

  @Builder
  courseDetailSheet(event: EasEventItem) {
    Column() {
      Row() {
        HeaderBackButton({
          onBack: () => {
            this.activeSheetVisible = false;
          }
        })
          .margin({ right: 12 });
        Row()
          .width(7)
          .height(50)
          .borderRadius(4)
          .backgroundColor(Home.canvasColorCss(event.color === 0 ?
            Home.defaultCanvasColor(event.type) : event.color));
        Column() {
          Text(event.name === 'NULL' || event.name.length === 0 ? '未命名课程' : event.name)
            .fontSize(21)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
          Text(event.type === EasEventType.EXAM ? '考试详情' : '课程详情')
            .fontSize(13)
            .fontColor(COLOR_TEXT_SECONDARY)
            .margin({ top: 4 });
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 12, right: 10 });

      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: 14 });

      this.courseDetailRow($r('sys.symbol.person_crop_circle_fill'), '老师',
        event.teacher.trim().length > 0 ? event.teacher : '无');
      this.courseDetailRow($r('sys.symbol.pin'), event.type === EasEventType.EXAM ? '考场' : '教室',
        event.place.trim().length > 0 ? event.place : '无');
      this.courseDetailRow($r('sys.symbol.clock'), '时间',
        EasTimeTools.printTime(event.from) + ' - ' + EasTimeTools.printTime(this.eventDetailEndTime(event)));
      if (event.type !== EasEventType.EXAM) {
        this.courseDetailRow($r('sys.symbol.doc_plaintext'), '节次', Home.coursePeriodText(event));
      }
      this.courseDetailRow($r('sys.symbol.calendar'), '日期', Home.courseDateText(event.from));
      if (event.type === EasEventType.EXAM) {
        this.courseDetailRow($r('sys.symbol.checkmark'), '类型', '考试');
      } else {
        this.courseDetailRow($r('sys.symbol.repeat_1'), '课程进度', this.courseProgressText(event));
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 4, bottom: 20 });
  }

  @Builder
  courseDetailRow(symbol: Resource, label: string, value: string) {
    Row() {
      Stack() {
        SymbolGlyph(symbol)
          .fontSize(20)
          .fontColor([COLOR_PRIMARY]);
      }
      .width(38)
      .height(38)
      .borderRadius(19)
      .backgroundColor(COLOR_NAV_ACTIVE)
      .alignContent(Alignment.Center);
      Column() {
        Text(label)
          .fontSize(12)
          .fontColor(COLOR_TEXT_SECONDARY);
        Text(value)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY)
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

  private static canvasColorCss(argb: number): string {
    const r: number = (argb >> 16) & 0xFF;
    const g: number = (argb >> 8) & 0xFF;
    const b: number = argb & 0xFF;
    return 'rgb(' + r.toString() + ',' + g.toString() + ',' + b.toString() + ')';
  }

  @Builder
  sessionSheet() {
    Column() {
      Row() {
        HeaderBackButton({
          onBack: () => {
            this.activeSheetVisible = false;
          }
        })
          .margin({ right: 12 });
        Column() {
          Text('教务认证')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_TEXT_PRIMARY);
          Text(this.sessionSheetInfo === undefined ? '请登录教务账号以继续' : '当前教务会话')
            .fontSize(13)
            .fontColor(COLOR_TEXT_SECONDARY)
            .margin({ top: 4 });
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);

      }
      .width('100%')
      .alignItems(VerticalAlign.Center);

      Column() {
        Text('认证校区')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_SECONDARY)
          .width('100%');

        Row({ space: 4 }) {
          this.sessionCampusButton('SHENZHEN', '深圳');
          this.sessionCampusButton('BENBU', '本部');
          this.sessionCampusButton('WEIHAI', '威海');
        }
        .width('100%')
        .padding(4)
        .backgroundColor('#EAF0F7')
        .borderRadius(16)
        .margin({ top: 7 });
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ top: 18 });

      if (this.sessionSheetInfo !== undefined) {
        Row() {
          Stack() {
            Text(this.sessionSheetInfo.name.length > 0 ?
              this.sessionSheetInfo.name.substring(0, 1) : 'U')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF');
          }
          .width(48)
          .height(48)
          .borderRadius(24)
          .backgroundColor(COLOR_PRIMARY)
          .alignContent(Alignment.Center);
          Column() {
            Text(this.sessionSheetInfo.name.length > 0 ? this.sessionSheetInfo.name :
              (this.sessionSheetInfo.stuId.length > 0 ? this.sessionSheetInfo.stuId : '已登录教务'))
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLOR_TEXT_PRIMARY)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
            Text(Home.campusName(this.sessionSheetInfo.campus) +
              (this.sessionSheetInfo.stuId.length > 0 ? ' · ' + this.sessionSheetInfo.stuId : ''))
              .fontSize(13)
              .fontColor(COLOR_TEXT_SECONDARY)
              .margin({ top: 4 });
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 12 });

          Text('已连接')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor('#248A5A')
            .padding({ left: 9, right: 9, top: 5, bottom: 5 })
            .backgroundColor('#E6F5ED')
            .borderRadius(12);
        }
        .width('100%')
        .padding(15)
        .backgroundColor('#F8FAFD')
        .border({ width: 1, color: '#E3EAF2' })
        .borderRadius(18)
        .margin({ top: 16 });

        Row({ space: 8 }) {
          Button('重新登录')
            .layoutWeight(1)
            .height(46)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLOR_PRIMARY)
            .backgroundColor(COLOR_NAV_ACTIVE)
            .borderRadius(17)
            .onClick(() => {
              this.beginSessionLogin();
            });
          Button('退出登录')
            .layoutWeight(1)
            .height(46)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#D93025')
            .backgroundColor('#FCE8E6')
            .borderRadius(17)
            .onClick(() => {
              this.logoutSession();
            });
        }
        .width('100%')
        .margin({ top: 12 });
      } else {
        Column() {
          Row() {
            Stack() {
              SymbolGlyph($r('sys.symbol.lock_shield'))
                .fontSize(22)
                .fontColor([COLOR_PRIMARY]);
            }
            .width(42)
            .height(42)
            .borderRadius(21)
            .backgroundColor(COLOR_NAV_ACTIVE)
            .alignContent(Alignment.Center);
            Column() {
              Text('登录教务系统')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(COLOR_TEXT_PRIMARY);
              Text('将打开对应校区的官方认证页')
                .fontSize(12)
                .fontColor(COLOR_TEXT_SECONDARY)
                .margin({ top: 3 });
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            .margin({ left: 12 });
          }
          .width('100%');

          Button('网页登录')
            .width('100%')
            .height(46)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .backgroundColor(COLOR_PRIMARY)
            .borderRadius(17)
            .margin({ top: 14 })
            .onClick(() => {
              this.beginSessionLogin();
            });

          Row() {
            SymbolGlyph($r('sys.symbol.lock_shield'))
              .fontSize(14)
              .fontColor([COLOR_TEXT_HINT]);
            Text('HITA 不保存您的教务密码')
              .fontSize(12)
              .fontColor(COLOR_TEXT_HINT)
              .margin({ left: 6 });
          }
          .margin({ top: 12 });
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#F8FAFD')
        .border({ width: 1, color: '#E3EAF2' })
        .borderRadius(18)
        .margin({ top: 16 });
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 4, bottom: 22 });
  }

  @Builder
  sessionCampusButton(code: string, label: string) {
    Row() {
      Circle()
        .width(9)
        .height(9)
        .fill(this.sessionSheetCampus === code ? COLOR_PRIMARY : 'transparent')
        .stroke(this.sessionSheetCampus === code ? COLOR_PRIMARY : '#A9B4C2')
        .strokeWidth(1.5);
      Text(label)
        .fontSize(15)
        .fontWeight(this.sessionSheetCampus === code ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.sessionSheetCampus === code ? COLOR_TEXT_PRIMARY : COLOR_TEXT_SECONDARY)
        .margin({ left: 7 });
    }
    .layoutWeight(1)
    .height(42)
    .justifyContent(FlexAlign.Center)
    .borderRadius(13)
    .backgroundColor(this.sessionSheetCampus === code ? COLOR_CARD : 'transparent')
    .onClick(() => {
      this.selectSessionCampus(code);
    });
  }

  @Builder
  moreShortcut(symbol: Resource, title: string, subtitle: string, action: () => void) {
    Row() {
      Stack() {
        SymbolGlyph(symbol)
          .fontSize(22)
          .fontColor([COLOR_PRIMARY]);
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .alignContent(Alignment.Center)
      .backgroundColor(COLOR_NAV_ACTIVE);
      Column() {
        Text(title)
          .fontSize(12)
          .fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(subtitle)
          .fontSize(14)
          .fontColor(COLOR_TEXT_PRIMARY)
          .margin({ top: 4 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 });
    }
    // Give each shortcut a zero base width so the two weighted cards remain
    // exactly equal on narrow devices.
    .width(0)
    .layoutWeight(1)
    .height(80)
    .padding({ left: 12, right: 12 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(COLOR_CARD)
    .borderRadius(16)
    .onClick(action);
  }

  @Builder
  moreSectionTitle(title: string) {
    Text(title)
      .fontSize(18)
      .fontWeight(FontWeight.Bold)
      .fontColor(COLOR_TEXT_PRIMARY)
      .margin({ top: 16, bottom: 4 })
      .alignSelf(ItemAlign.Start);
  }

  @Builder
  moreNavigationRow(symbol: Resource, title: string, subtitle: string, action: () => void) {
    Row() {
      Stack() {
        SymbolGlyph(symbol)
          .fontSize(22)
          .fontColor([COLOR_PRIMARY]);
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .alignContent(Alignment.Center)
      .backgroundColor(COLOR_NAV_ACTIVE);
      Column() {
        Text(title)
          .fontSize(14)
          .fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
        if (subtitle.length > 0) {
          Text(subtitle)
            .fontSize(12)
            .fontColor(COLOR_TEXT_SECONDARY)
            .margin({ top: 2 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 });
      Text('›')
        .fontSize(23)
        .fontColor(COLOR_TEXT_SECONDARY);
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .onClick(action);
  }
}
