/**
 * TimetableWeekDraw.ets — 课表周视图绘制模块（Canvas 纯函数，状态由宿主页面持有）。
 *
 * 语义依据 docs/eas-timetable-view-notes.md（HITA_X TimeTableView 几何还原）：
 *  - 7 等分列；时间轴 08:00–23:00，网格每小时一格；
 *  - 事件块按真实时刻分钟定位：yTop = minutesFromAxisStart/60 * hourH，
 *    高 = durationMinutes/60 * hourH；x=(dow-1)*colW（dow 周一=1）；
 *    fromNumber/lastNumber 只作数据字段，不参与布局（源如此）；
 *  - 今日高亮 = 本周页对今日列整列叠加 ~#10000000 遮罩；
 *  - 源码 NowLine 实为死代码（未实例化），故不绘制；
 *  - 左侧标签画 08:00..23:00 整点；
 *  - 周切换由宿主页面按安卓 ViewPager 手势逻辑处理：跟手平移、阈值切换与回弹动画。
 */
import {
  DAY_MILLIS,
  WEEK_MILLIS,
  EasEventItem,
  EasEventType,
  EasTimetable
} from '../../../common/model/timetable/TimetableModels';

export const DOW_NAMES: string[] = ['一', '二', '三', '四', '五', '六', '日'];
/** 轴起点 08:00（对应源 startTime=800）。 */
export const AXIS_START_HOUR: number = 8;
/** 轴终点 23:00；更晚的课程通过纵向滚动继续查看。 */
export const AXIS_END_HOUR: number = 23;
/** 固定周标题高度；56vp 是 iOS 紧凑课表使用的每小时高度上限。 */
export const TIMETABLE_HEADER_HEIGHT: number = 90;
export const TIMETABLE_HOUR_HEIGHT: number = 56;
/** 安卓端在固定日期栏和首个整点之间保留 24dp。 */
export const TIMETABLE_GRID_TOP_PADDING: number = 24;

export class TimetableDrawStyle {
  static bg: string = '#FBFCFE';
  static gridLine: string = '#D7DEE8';
  static textMain: string = '#111827';
  static textSub: string = '#566276';
  static todayHeadBg: string = '#2E86E8';
  /** 今日列整列遮罩（源 ~#10000000）。 */
  static todayMask: string = 'rgba(46,134,232,0.06)';
  /** 顶栏最低/占比。 */
  static headerMin: number = TIMETABLE_HEADER_HEIGHT;
  static headerRatio: number = 0.12;
  /** 左侧整点标签列最低/占比。 */
  static gutterMin: number = 48;
  static gutterRatio: number = 0.11;
  /** 块外边距（源 1dp 量级，比例化）。 */
  static blockMargin: number = 3;
  /** 安卓端使用高对比度实色课程卡片，标题与地点均使用白色。 */
  static blockOpacity: number = 0.88;

  static compact(value: string, maxChars: number): string {
    if (value.length <= maxChars) {
      return value;
    }
    return value.substring(0, Math.max(1, maxChars - 1)) + '…';
  }

  static wrap(value: string, maxChars: number, maxLines: number): string[] {
    const clean: string = value.trim();
    if (clean.length === 0 || maxChars <= 0 || maxLines <= 0) {
      return [];
    }
    const lines: string[] = [];
    let cursor: number = 0;
    while (cursor < clean.length && lines.length < maxLines) {
      const remaining: number = clean.length - cursor;
      const take: number = Math.min(maxChars, remaining);
      let line: string = clean.substring(cursor, cursor + take);
      cursor += take;
      if (cursor < clean.length && lines.length === maxLines - 1) {
        line = line.substring(0, Math.max(1, line.length - 1)) + '…';
        cursor = clean.length;
      }
      lines.push(line);
    }
    return lines;
  }
}

class TimetableBlockLayout {
  event: EasEventItem;
  lane: number = 0;
  lanes: number = 1;

  constructor(event: EasEventItem) {
    this.event = event;
  }
}

/** ARGB int → css rgba 字符串。 */
export function argbToCss(argb: number, alpha: number): string {
  const r: number = (argb >> 16) & 0xFF;
  const g: number = (argb >> 8) & 0xFF;
  const b: number = argb & 0xFF;
  return 'rgba(' + r.toString() + ',' + g.toString() + ',' + b.toString() + ',' + alpha.toString() + ')';
}

/** 圆角矩形路径（不依赖 roundRect，用 moveTo/lineTo/quadraticCurveTo 拼角）。 */
function roundedRectPath(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number,
  r: number): void {
  const rr: number = Math.max(0, Math.min(r, Math.min(w, h) / 2));
  ctx.beginPath();
  ctx.moveTo(x + rr, y);
  ctx.lineTo(x + w - rr, y);
  ctx.quadraticCurveTo(x + w, y, x + w, y + rr);
  ctx.lineTo(x + w, y + h - rr);
  ctx.quadraticCurveTo(x + w, y + h, x + w - rr, y + h);
  ctx.lineTo(x + rr, y + h);
  ctx.quadraticCurveTo(x, y + h, x, y + h - rr);
  ctx.lineTo(x, y + rr);
  ctx.quadraticCurveTo(x, y, x + rr, y);
  ctx.closePath();
}

/** 取“第 week 周”事件（from 落于本周一..下周一之间，按开始时间升序）。 */
export function eventsOfWeek(timetable: EasTimetable, events: EasEventItem[],
  week: number): EasEventItem[] {
  const day0: number = timetable.startTime + (week - 1) * WEEK_MILLIS;
  const day1: number = day0 + WEEK_MILLIS;
  const out: EasEventItem[] = [];
  for (let i = 0; i < events.length; i++) {
    if (events[i].from >= day0 && events[i].from < day1) {
      out.push(events[i]);
    }
  }
  out.sort((a: EasEventItem, b: EasEventItem): number => {
    return a.from - b.from;
  });
  return out;
}

function drawWeekHeader(ctx: CanvasRenderingContext2D, w: number, headerH: number,
  timetable: EasTimetable, weekNumber: number, isCurrentWeek: boolean): void {
  const gridTop: number = headerH + 2;
  const gridLeft: number = Math.max(TimetableDrawStyle.gutterMin, w * TimetableDrawStyle.gutterRatio);
  const colW: number = (w - gridLeft) / 7;
  const fontUnit: string = 'vp sans-serif';
  const weekMonday: number = timetable.startTime + (weekNumber - 1) * WEEK_MILLIS;
  const todayDow: number = EasTimetable.dowOfMs(Date.now());

  ctx.fillStyle = TimetableDrawStyle.bg;
  ctx.fillRect(0, 0, w, gridTop);
  ctx.textBaseline = 'middle';
  for (let d = 0; d < 7; d++) {
    const x: number = gridLeft + d * colW;
    const isToday: boolean = isCurrentWeek && todayDow === d + 1;
    ctx.fillStyle = isToday ? '#E6F0FC' : '#FFFFFF';
    ctx.fillRect(x, 4, colW, headerH - 2);
    ctx.fillStyle = isToday ? TimetableDrawStyle.todayHeadBg : TimetableDrawStyle.textMain;
    ctx.font = 'bold ' + (isToday ? '11' : '10') + fontUnit;
    ctx.textAlign = 'center';
    ctx.fillText(DOW_NAMES[d], x + colW / 2, headerH / 2 - 11);
    const date: Date = new Date(weekMonday + d * DAY_MILLIS);
    ctx.font = '10' + fontUnit;
    ctx.fillStyle = isToday ? TimetableDrawStyle.todayHeadBg : TimetableDrawStyle.textSub;
    ctx.fillText(date.getDate().toString(), x + colW / 2, headerH / 2 + 16);
  }
  const firstDay: Date = new Date(weekMonday);
  ctx.fillStyle = TimetableDrawStyle.textSub;
  ctx.font = 'bold 11' + fontUnit;
  ctx.textAlign = 'center';
  ctx.fillText((firstDay.getMonth() + 1).toString() + '月', gridLeft / 2, headerH / 2 + 16);
  ctx.textAlign = 'start';
}

/** 绘制固定在纵向滚动区域顶部的周标题。 */
export function drawTimetableWeekHeader(ctx: CanvasRenderingContext2D, w: number, h: number,
  timetable: EasTimetable, weekNumber: number, isCurrentWeek: boolean): void {
  if (w <= 0 || h <= 0) {
    return;
  }
  ctx.clearRect(0, 0, w, h);
  drawWeekHeader(ctx, w, Math.max(2, h - 2), timetable, weekNumber, isCurrentWeek);
}

/**
 * 全量重绘。网格高度可固定为每小时高度，供外层 Scroll 保持安卓端长课卡比例。
 * @param ctx 画布上下文
 * @param w/h 可用尺寸
 * @param timetable 课表（周一起点 startTime）
 * @param events 已按周过滤事件
 * @param weekNumber 展示周
 * @param isCurrentWeek 是否当前周（决定今日遮罩）
 */
export function drawTimetableWeek(ctx: CanvasRenderingContext2D, w: number, h: number,
  timetable: EasTimetable, events: EasEventItem[], weekNumber: number,
  isCurrentWeek: boolean, hourHeightOverride: number = 0,
  headerHeightOverride: number = 0, drawHeader: boolean = true,
  placeScrollOffset: number = 0): boolean {
  if (w <= 0 || h <= 0) {
    return false;
  }
  ctx.clearRect(0, 0, w, h);
  ctx.fillStyle = TimetableDrawStyle.bg;
  ctx.fillRect(0, 0, w, h);

  const headerH: number = drawHeader ? (headerHeightOverride > 0 ? headerHeightOverride :
    Math.max(TimetableDrawStyle.headerMin, h * TimetableDrawStyle.headerRatio)) : 0;
  const gutterW: number = Math.max(TimetableDrawStyle.gutterMin, w * TimetableDrawStyle.gutterRatio);
  const gridLeft: number = gutterW;
  const gridTop: number = drawHeader ? headerH + 2 : TIMETABLE_GRID_TOP_PADDING;
  const gridBottom: number = hourHeightOverride > 0 ?
    Math.min(h - 4, gridTop + (AXIS_END_HOUR - AXIS_START_HOUR) * hourHeightOverride) : h - 4;
  const gridH: number = gridBottom - gridTop;
  const hoursInDay: number = AXIS_END_HOUR - AXIS_START_HOUR;
  const hourH: number = hourHeightOverride > 0 ? hourHeightOverride : gridH / hoursInDay;
  const colW: number = (w - gridLeft) / 7;
  const fontUnit: string = 'vp sans-serif';
  const weekMonday: number = timetable.startTime + (weekNumber - 1) * WEEK_MILLIS;
  const todayDow: number = EasTimetable.dowOfMs(Date.now());
  let hasScrollingPlace: boolean = false;

  if (drawHeader) {
    drawWeekHeader(ctx, w, headerH, timetable, weekNumber, isCurrentWeek);
  }

  // 今日列整列遮罩（仅当前周）
  if (isCurrentWeek) {
    ctx.fillStyle = TimetableDrawStyle.todayMask;
    ctx.fillRect(gridLeft + (todayDow - 1) * colW, gridTop, colW, gridH);
  }

  // 网格（每小时一格）+ 左侧整点标签
  ctx.strokeStyle = TimetableDrawStyle.gridLine;
  ctx.lineWidth = 1;
  for (let i = 0; i <= hoursInDay; i++) {
    const y: number = gridTop + i * hourH;
    ctx.setLineDash([6, 8]);
    ctx.beginPath();
    ctx.moveTo(gridLeft, y);
    ctx.lineTo(w, y);
    ctx.stroke();
  }
  ctx.setLineDash([]);
  ctx.strokeStyle = '#EEF2F6';
  for (let i = 0; i < hoursInDay; i++) {
    const y: number = gridTop + (i + 0.5) * hourH;
    ctx.beginPath();
    ctx.moveTo(gridLeft, y);
    ctx.lineTo(w, y);
    ctx.stroke();
  }
  ctx.font = '10' + fontUnit;
  ctx.fillStyle = TimetableDrawStyle.textSub;
  for (let hour = AXIS_START_HOUR; hour < AXIS_END_HOUR; hour++) {
    const y: number = gridTop + (hour - AXIS_START_HOUR) * hourH;
    const label: string = hour.toString() + ':00';
    ctx.textAlign = 'left';
    ctx.fillText(label, 8, y);
    ctx.textAlign = 'start';
  }
  // 列分隔
  for (let d = 1; d < 7; d++) {
    const x: number = gridLeft + d * colW;
    ctx.beginPath();
    ctx.moveTo(x, gridTop);
    ctx.lineTo(x, gridBottom);
    ctx.stroke();
  }

  // 事件块：真实时刻分钟映射。课程重叠时按 lane 缩窄，避免互相覆盖。
  const axisStartMsOffset: number = AXIS_START_HOUR * 60 * 60 * 1000;
  const m: number = TimetableDrawStyle.blockMargin;
  const layouts: TimetableBlockLayout[] = [];
  const dayLayouts: TimetableBlockLayout[][] = [[], [], [], [], [], [], []];
  for (let i = 0; i < events.length; i++) {
    if (events[i].type !== EasEventType.CLASS) {
      continue;
    }
    const dow: number = events[i].getDow();
    if (dow < 1 || dow > 7) {
      continue;
    }
    const layout: TimetableBlockLayout = new TimetableBlockLayout(events[i]);
    dayLayouts[dow - 1].push(layout);
    layouts.push(layout);
  }
  for (let d = 0; d < 7; d++) {
    dayLayouts[d].sort((a: TimetableBlockLayout, b: TimetableBlockLayout): number => {
      return a.event.from - b.event.from;
    });
    const laneEnds: number[] = [];
    for (let i = 0; i < dayLayouts[d].length; i++) {
      const layout: TimetableBlockLayout = dayLayouts[d][i];
      let lane: number = 0;
      while (lane < laneEnds.length && laneEnds[lane] > layout.event.from) {
        lane++;
      }
      if (lane === laneEnds.length) {
        laneEnds.push(layout.event.to);
      } else {
        laneEnds[lane] = layout.event.to;
      }
      layout.lane = lane;
    }
    for (let i = 0; i < dayLayouts[d].length; i++) {
      const layout: TimetableBlockLayout = dayLayouts[d][i];
      let overlapCount: number = 1;
      for (let j = 0; j < dayLayouts[d].length; j++) {
        if (i === j) {
          continue;
        }
        const other: EasEventItem = dayLayouts[d][j].event;
        if (other.from < layout.event.to && other.to > layout.event.from) {
          overlapCount++;
        }
      }
      layout.lanes = Math.max(1, overlapCount);
    }
  }

  for (let i = 0; i < layouts.length; i++) {
    const layout: TimetableBlockLayout = layouts[i];
    const ev: EasEventItem = layout.event;
    const dow: number = ev.getDow();
    const dayStart: number = weekMonday + (dow - 1) * DAY_MILLIS;
    const topMs: number = ev.from - dayStart - axisStartMsOffset;
    const durMs: number = ev.to - ev.from;
    if (topMs < 0 || durMs <= 0) {
      continue;
    }
    const y: number = gridTop + (topMs / 3600000) * hourH;
    const bh: number = Math.max(4, (durMs / 3600000) * hourH);
    const laneW: number = colW / layout.lanes;
    const x: number = gridLeft + (dow - 1) * colW + layout.lane * laneW + m;
    const bw: number = Math.max(12, laneW - m * 2);
    const radius: number = Math.max(8, Math.min(18, bw * 0.22));
    const eventColor: number = ev.color === 0 ? 0xFF2E86E8 : ev.color;
    const color: string = argbToCss(eventColor, TimetableDrawStyle.blockOpacity);
    ctx.fillStyle = color;
    roundedRectPath(ctx, x, y, bw, bh, radius);
    ctx.fill();
    ctx.strokeStyle = argbToCss(eventColor, 0.98);
    ctx.lineWidth = 1;
    roundedRectPath(ctx, x, y, bw, bh, radius);
    ctx.stroke();
    const cardWidthScreen: number = bw;
    const cardHeightScreen: number = bh;
    const textScale: number = layout.lanes > 1 ? 0.9 : 1;
    const marginScale: number = layout.lanes > 1 ? 0.85 : 1;
    const nameLength: number = ev.name.trim().length;
    // Match the Android card's adaptive title sizing, but keep a larger
    // readable floor on HarmonyOS so long Chinese names still remain legible.
    const lengthScale: number = nameLength <= 4 ? 1.15 :
      (nameLength <= 6 ? 0.92 : (nameLength <= 8 ? 0.75 : 0.62));
    const hasPlace: boolean = ev.place.trim().length > 0;
    const titlePaddingScreen: number = 5 * marginScale;
    const placePaddingScreen: number = hasPlace ? 14 * textScale : 0;
    const titleAvailableScreen: number = Math.max(10,
      cardHeightScreen - titlePaddingScreen * 2 - placePaddingScreen);
    const maxTitleLines: number = cardHeightScreen < 40 ? 1 :
      (cardHeightScreen < 60 ? 2 : 3);
    const maxTitleFromSpace: number = Math.min(16, titleAvailableScreen / 1.2);
    const minTitleSize: number = layout.lanes > 1 ? 5 : 6;
    const titleScreen: number = Math.max(minTitleSize,
      Math.min(maxTitleFromSpace, 13 * textScale * lengthScale));
    const titleFont: number = Math.max(1, Math.round(titleScreen));
    const titleLineHeight: number = Math.max(1, Math.round(titleScreen * 1.2));
    // Chinese glyphs are close to one em wide.  A small allowance lets a
    // three-line card retain the full subject name instead of truncating at
    // only two characters on narrow day columns.
    const titleMaxChars: number = Math.max(2,
      Math.floor((cardWidthScreen - titlePaddingScreen * 2) / titleScreen * 1.18));
    const titleLines: string[] = TimetableDrawStyle.wrap(ev.name === 'NULL' ? '' : ev.name,
      titleMaxChars, maxTitleLines);
    ctx.font = 'bold ' + titleFont.toString() + fontUnit;
    ctx.fillStyle = '#FFFFFF';
    ctx.textAlign = 'center';
    if (titleLines.length > 0) {
      const titleAreaBottom: number = hasPlace && cardHeightScreen >= 38 ?
        y + bh - 17 : y + bh - 8;
      const titleAreaTop: number = y + Math.round(titlePaddingScreen);
      const titleHeight: number = titleLines.length * titleLineHeight;
      let titleY: number = titleAreaTop + Math.max(0, (titleAreaBottom - titleAreaTop - titleHeight) / 2);
      for (let line = 0; line < titleLines.length; line++) {
        if (titleY + titleLineHeight > titleAreaBottom + titleLineHeight) {
          break;
        }
        ctx.fillText(titleLines[line], x + bw / 2, titleY);
        titleY += titleLineHeight;
      }
    }
    if (hasPlace && cardHeightScreen >= 38) {
      ctx.fillStyle = 'rgba(255,255,255,0.78)';
      const placeFont: number = Math.round(10 * textScale);
      ctx.font = placeFont.toString() + fontUnit;
      ctx.textAlign = 'center';
      const placeText: string = ev.place.trim();
      const placeAvailableWidth: number = Math.max(4, cardWidthScreen - titlePaddingScreen * 2);
      const placeTextWidth: number = ctx.measureText(placeText).width;
      const placeY: number = y + bh - 9;
      ctx.save();
      ctx.beginPath();
      ctx.rect(x + titlePaddingScreen, y + bh - 18, placeAvailableWidth, 16);
      ctx.clip();
      if (placeTextWidth <= placeAvailableWidth) {
        ctx.fillText(placeText, x + bw / 2, placeY);
      } else {
        hasScrollingPlace = true;
        const gap: number = 18;
        const cycleWidth: number = placeTextWidth + gap;
        const textX: number = x + titlePaddingScreen - (placeScrollOffset % cycleWidth);
        ctx.textAlign = 'left';
        ctx.fillText(placeText, textX, placeY);
        ctx.fillText(placeText, textX + cycleWidth, placeY);
      }
      ctx.restore();
      ctx.textAlign = 'start';
    }
  }
  return hasScrollingPlace;
}
