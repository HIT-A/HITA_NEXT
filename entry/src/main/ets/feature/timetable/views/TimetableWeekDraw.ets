/**
 * TimetableWeekDraw.ets — 课表周视图绘制模块（Canvas 纯函数，状态由宿主页面持有）。
 *
 * 语义依据 docs/eas-timetable-view-notes.md（HITA_X TimeTableView 几何还原）：
 *  - 7 等分列；时间轴 08:00–24:00（16h），网格每小时一格；
 *  - 事件块按真实时刻分钟定位：yTop = minutesFromAxisStart/60 * hourH，
 *    高 = durationMinutes/60 * hourH；x=(dow-1)*colW（dow 周一=1）；
 *    fromNumber/lastNumber 只作数据字段，不参与布局（源如此）；
 *  - 今日高亮 = 本周页对今日列整列叠加 ~#10000000 遮罩；
 *  - 源码 NowLine 实为死代码（未实例化），故不绘制；
 *  - 左侧标签画 08:00..23:00 整点；
 *  - 周切换在源为 ViewPager 环形窗口（WINDOW_SIZE=5）→ ArkTS 先用按钮切周，手势后续。
 */
import {
  DAY_MILLIS,
  WEEK_MILLIS,
  EasEventItem,
  EasEventType,
  EasTimetable
} from '../../../common/model/timetable/TimetableModels';

export const DOW_NAMES: string[] = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
/** 轴起点 08:00（对应源 startTime=800）。 */
export const AXIS_START_HOUR: number = 8;
/** 轴终点 24:00。 */
export const AXIS_END_HOUR: number = 24;

export class TimetableDrawStyle {
  static bg: string = '#F6F7FA';
  static gridLine: string = '#E7EBF0';
  static textMain: string = '#1A1A1A';
  static textSub: string = '#7E8998';
  static todayHeadBg: string = '#3390EC';
  /** 今日列整列遮罩（源 ~#10000000）。 */
  static todayMask: string = 'rgba(0,0,0,0.06)';
  /** 顶栏最低/占比。 */
  static headerMin: number = 28;
  static headerRatio: number = 0.055;
  /** 左侧整点标签列最低/占比。 */
  static gutterMin: number = 40;
  static gutterRatio: number = 0.075;
  /** 块外边距（源 1dp 量级，比例化）。 */
  static blockMargin: number = 2;
  /** 块填充不透明度（源 ~95%）。 */
  static blockOpacity: number = 0.94;

  static compact(value: string, maxChars: number): string {
    if (value.length <= maxChars) {
      return value;
    }
    return value.substring(0, Math.max(1, maxChars - 1)) + '…';
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

/**
 * 全量重绘。
 * @param ctx 画布上下文
 * @param w/h 可用尺寸
 * @param timetable 课表（周一起点 startTime）
 * @param events 已按周过滤事件
 * @param weekNumber 展示周
 * @param isCurrentWeek 是否当前周（决定今日遮罩）
 */
export function drawTimetableWeek(ctx: CanvasRenderingContext2D, w: number, h: number,
  timetable: EasTimetable, events: EasEventItem[], weekNumber: number,
  isCurrentWeek: boolean): void {
  if (w <= 0 || h <= 0) {
    return;
  }
  ctx.clearRect(0, 0, w, h);
  ctx.fillStyle = TimetableDrawStyle.bg;
  ctx.fillRect(0, 0, w, h);

  const headerH: number = Math.max(TimetableDrawStyle.headerMin, h * TimetableDrawStyle.headerRatio);
  const gutterW: number = Math.max(TimetableDrawStyle.gutterMin, w * TimetableDrawStyle.gutterRatio);
  const gridLeft: number = gutterW;
  const gridTop: number = headerH + 2;
  const gridBottom: number = h - 4;
  const gridH: number = gridBottom - gridTop;
  const hoursInDay: number = AXIS_END_HOUR - AXIS_START_HOUR;
  const hourH: number = gridH / hoursInDay;
  const colW: number = (w - gridLeft) / 7;
  const weekMonday: number = timetable.startTime + (weekNumber - 1) * WEEK_MILLIS;
  const todayDow: number = EasTimetable.dowOfMs(Date.now());

  // 星期头
  ctx.textBaseline = 'middle';
  for (let d = 0; d < 7; d++) {
    const x: number = gridLeft + d * colW;
    const isToday: boolean = isCurrentWeek && todayDow === d + 1;
    ctx.fillStyle = isToday ? '#EAF4FD' : '#FFFFFF';
    ctx.fillRect(x, gridTop - headerH + 4, colW, headerH - 4);
    ctx.fillStyle = isToday ? TimetableDrawStyle.todayHeadBg : TimetableDrawStyle.textMain;
    ctx.font = isToday ? 'bold 12px sans-serif' : '12px sans-serif';
    ctx.textAlign = 'center';
    ctx.fillText(DOW_NAMES[d], x + colW / 2, gridTop - headerH / 2 - 3);
    const date: Date = new Date(weekMonday + d * DAY_MILLIS);
    ctx.font = '10px sans-serif';
    ctx.fillStyle = isToday ? TimetableDrawStyle.todayHeadBg : TimetableDrawStyle.textSub;
    ctx.fillText(date.getDate().toString(), x + colW / 2, gridTop - headerH / 2 + 10);
    ctx.textAlign = 'start';
  }
  // 周标题（左侧 gutter 上）
  ctx.fillStyle = TimetableDrawStyle.textSub;
  ctx.font = '10px sans-serif';
  ctx.textAlign = 'center';
  ctx.fillText('第' + weekNumber.toString() + '周', gutterW / 2, gridTop - headerH / 2 + 2);
  ctx.textAlign = 'start';

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
    ctx.beginPath();
    ctx.moveTo(gridLeft, y);
    ctx.lineTo(w, y);
    ctx.stroke();
  }
  ctx.font = '9px sans-serif';
  ctx.fillStyle = TimetableDrawStyle.textSub;
  for (let hour = AXIS_START_HOUR; hour < AXIS_END_HOUR; hour++) {
    const y: number = gridTop + (hour - AXIS_START_HOUR) * hourH;
    const label: string = hour.toString() + ':00';
    ctx.textAlign = 'right';
    ctx.fillText(label, gridLeft - 3, y);
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
    const radius: number = Math.max(4, Math.min(10, bw * 0.12));
    const color: string = argbToCss(ev.color, TimetableDrawStyle.blockOpacity);
    ctx.fillStyle = color;
    roundedRectPath(ctx, x, y, bw, bh, radius);
    ctx.fill();
    ctx.strokeStyle = argbToCss(ev.color, 0.82);
    ctx.lineWidth = 1;
    roundedRectPath(ctx, x, y, bw, bh, radius);
    ctx.stroke();
    ctx.fillStyle = '#FFFFFF';
    ctx.beginPath();
    ctx.arc(x + 9, y + 9, 3, 0, Math.PI * 2);
    ctx.fill();
    ctx.font = Math.max(9, Math.min(12, Math.floor(laneW / 4))) + 'px sans-serif';
    ctx.textAlign = 'start';
    if (ev.name.length > 0 && ev.name !== 'NULL') {
      ctx.fillText(TimetableDrawStyle.compact(ev.name, bw < 52 ? 5 : 9), x + 5, y + 20);
    }
    if (ev.place.length > 0 && bh >= 38) {
      ctx.fillStyle = 'rgba(255,255,255,0.78)';
      ctx.font = '9px sans-serif';
      ctx.fillText(TimetableDrawStyle.compact(ev.place, bw < 52 ? 5 : 10), x + 5, y + 33);
    }
  }

  // 当前时间线：安卓端样式为细红线，只有当前周显示。
  if (isCurrentWeek) {
    const now: Date = new Date();
    const minute: number = now.getHours() * 60 + now.getMinutes();
    const axisStart: number = AXIS_START_HOUR * 60;
    const axisEnd: number = AXIS_END_HOUR * 60;
    if (minute >= axisStart && minute <= axisEnd) {
      const nowY: number = gridTop + ((minute - axisStart) / (axisEnd - axisStart)) * gridH;
      ctx.strokeStyle = '#D93025';
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      ctx.moveTo(gridLeft, nowY);
      ctx.lineTo(w, nowY);
      ctx.stroke();
      ctx.fillStyle = '#D93025';
      ctx.beginPath();
      ctx.arc(gridLeft, nowY, 3.5, 0, Math.PI * 2);
      ctx.fill();
    }
  }
}
