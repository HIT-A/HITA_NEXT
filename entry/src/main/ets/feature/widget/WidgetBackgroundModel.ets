/**
 * 服务卡片自定义背景的纯计算部分：编辑器预览、烘焙输出与测试共用同一套几何。
 *
 * scale 以“刚好铺满卡片”为 1；小于 1 时整张图可完整显示，空白处保留卡片底色。
 * x/y 是图片相对卡片的位置比例（0 = 左/上对齐，1 = 右/下对齐），与卡片像素尺寸无关，
 * 因此同一组参数在小预览框与实际输出尺寸上得到同样的取景。
 */

export const WIDGET_BG_MAX_SCALE: number = 4;
/** 实测 2×2 卡片约 1:1，2×4 卡片约 2.15:1。 */
export const WIDGET_BG_COMPACT_ASPECT: number = 1;
export const WIDGET_BG_WIDE_ASPECT: number = 2.15;
export const WIDGET_BG_COMPACT_OUTPUT_W: number = 600;
export const WIDGET_BG_COMPACT_OUTPUT_H: number = 600;
export const WIDGET_BG_WIDE_OUTPUT_W: number = 1290;
export const WIDGET_BG_WIDE_OUTPUT_H: number = 600;
export const WIDGET_BG_DEFAULT_VEIL: number = 30;
export const WIDGET_BG_MAX_VEIL: number = 80;

export class WidgetBackgroundFrame {
  scale: number = 1;
  x: number = 0.5;
  y: number = 0.5;
}

export class WidgetBackgroundPlacement {
  width: number = 0;
  height: number = 0;
  left: number = 0;
  top: number = 0;
}

/** 输出画布上需要绘制的区域，以及对应的源图区域（均为整数像素）。 */
export class WidgetBackgroundBakeRegion {
  empty: boolean = true;
  destX: number = 0;
  destY: number = 0;
  destW: number = 0;
  destH: number = 0;
  srcX: number = 0;
  srcY: number = 0;
  srcW: number = 0;
  srcH: number = 0;
}

export class WidgetBackgroundState {
  revision: number = 0;
  source: string = '';
  sourceWidth: number = 0;
  sourceHeight: number = 0;
  veil: number = WIDGET_BG_DEFAULT_VEIL;
  compact: WidgetBackgroundFrame = new WidgetBackgroundFrame();
  wide: WidgetBackgroundFrame = new WidgetBackgroundFrame();
}

export class WidgetBackgroundModel {
  static frame(scale: number, x: number, y: number): WidgetBackgroundFrame {
    const frame = new WidgetBackgroundFrame();
    frame.scale = scale;
    frame.x = x;
    frame.y = y;
    return frame;
  }

  /** 铺满卡片所需的缩放与完整显示所需缩放之比，即 scale 的下限。 */
  static minScale(imageW: number, imageH: number, frameW: number, frameH: number): number {
    if (!WidgetBackgroundModel.validSize(imageW, imageH) || !WidgetBackgroundModel.validSize(frameW, frameH)) {
      return 1;
    }
    const cover = Math.max(frameW / imageW, frameH / imageH);
    const contain = Math.min(frameW / imageW, frameH / imageH);
    return contain / cover;
  }

  static clamp(frame: WidgetBackgroundFrame, imageW: number, imageH: number,
    frameW: number, frameH: number): WidgetBackgroundFrame {
    const min = WidgetBackgroundModel.minScale(imageW, imageH, frameW, frameH);
    const scale = Number.isFinite(frame.scale) ? frame.scale : 1;
    return WidgetBackgroundModel.frame(Math.min(WIDGET_BG_MAX_SCALE, Math.max(min, scale)),
      WidgetBackgroundModel.unit(frame.x), WidgetBackgroundModel.unit(frame.y));
  }

  /** 保持原始宽高比的绘制矩形；不拉伸，超出卡片的部分由卡片边界裁掉。 */
  static place(frame: WidgetBackgroundFrame, imageW: number, imageH: number,
    frameW: number, frameH: number): WidgetBackgroundPlacement {
    const placement = new WidgetBackgroundPlacement();
    if (!WidgetBackgroundModel.validSize(imageW, imageH) || !WidgetBackgroundModel.validSize(frameW, frameH)) {
      return placement;
    }
    const safe = WidgetBackgroundModel.clamp(frame, imageW, imageH, frameW, frameH);
    const ratio = Math.max(frameW / imageW, frameH / imageH) * safe.scale;
    placement.width = imageW * ratio;
    placement.height = imageH * ratio;
    placement.left = (frameW - placement.width) * safe.x;
    placement.top = (frameH - placement.height) * safe.y;
    return placement;
  }

  static coverFrame(): WidgetBackgroundFrame {
    return WidgetBackgroundModel.frame(1, 0.5, 0.5);
  }

  static containFrame(imageW: number, imageH: number, frameW: number, frameH: number): WidgetBackgroundFrame {
    return WidgetBackgroundModel.frame(WidgetBackgroundModel.minScale(imageW, imageH, frameW, frameH), 0.5, 0.5);
  }

  /** 拖动：dx/dy 为手指位移（与 frameW/frameH 同单位）。 */
  static pan(frame: WidgetBackgroundFrame, dx: number, dy: number, imageW: number, imageH: number,
    frameW: number, frameH: number): WidgetBackgroundFrame {
    const current = WidgetBackgroundModel.place(frame, imageW, imageH, frameW, frameH);
    if (current.width <= 0) {
      return WidgetBackgroundModel.clamp(frame, imageW, imageH, frameW, frameH);
    }
    const safe = WidgetBackgroundModel.clamp(frame, imageW, imageH, frameW, frameH);
    return WidgetBackgroundModel.frame(safe.scale,
      WidgetBackgroundModel.ratioOf(current.left + dx, frameW, current.width, safe.x),
      WidgetBackgroundModel.ratioOf(current.top + dy, frameH, current.height, safe.y));
  }

  /**
   * 双指缩放：以起始帧为基准，起始时位于 (startX, startY) 下方的图片点跟随到 (centerX, centerY)。
   * 同时处理缩放和双指平移，避免与单指拖动叠加。
   */
  static zoom(start: WidgetBackgroundFrame, factor: number, startX: number, startY: number,
    centerX: number, centerY: number, imageW: number, imageH: number,
    frameW: number, frameH: number): WidgetBackgroundFrame {
    const before = WidgetBackgroundModel.place(start, imageW, imageH, frameW, frameH);
    if (before.width <= 0 || !Number.isFinite(factor) || factor <= 0) {
      return WidgetBackgroundModel.clamp(start, imageW, imageH, frameW, frameH);
    }
    const safe = WidgetBackgroundModel.clamp(start, imageW, imageH, frameW, frameH);
    const scaled = WidgetBackgroundModel.clamp(WidgetBackgroundModel.frame(safe.scale * factor, safe.x, safe.y),
      imageW, imageH, frameW, frameH);
    const ratio = scaled.scale / safe.scale;
    const width = before.width * ratio;
    const height = before.height * ratio;
    const left = centerX - (startX - before.left) * ratio;
    const top = centerY - (startY - before.top) * ratio;
    return WidgetBackgroundModel.frame(scaled.scale,
      WidgetBackgroundModel.ratioOf(left, frameW, width, safe.x),
      WidgetBackgroundModel.ratioOf(top, frameH, height, safe.y));
  }

  /** 按滑杆设定缩放值，保持当前位置比例。 */
  static withScale(frame: WidgetBackgroundFrame, scale: number, imageW: number, imageH: number,
    frameW: number, frameH: number): WidgetBackgroundFrame {
    return WidgetBackgroundModel.clamp(WidgetBackgroundModel.frame(scale, frame.x, frame.y),
      imageW, imageH, frameW, frameH);
  }

  /** 烘焙输出时，求可见部分对应的源图区域；完全落在画布外时 empty = true。 */
  static bakeRegion(frame: WidgetBackgroundFrame, imageW: number, imageH: number,
    outW: number, outH: number): WidgetBackgroundBakeRegion {
    const region = new WidgetBackgroundBakeRegion();
    const placed = WidgetBackgroundModel.place(frame, imageW, imageH, outW, outH);
    if (placed.width <= 0 || placed.height <= 0) {
      return region;
    }
    const x0 = Math.max(0, Math.round(placed.left));
    const y0 = Math.max(0, Math.round(placed.top));
    const x1 = Math.min(outW, Math.round(placed.left + placed.width));
    const y1 = Math.min(outH, Math.round(placed.top + placed.height));
    if (x1 - x0 < 1 || y1 - y0 < 1) {
      return region;
    }
    const sx = imageW / placed.width;
    const sy = imageH / placed.height;
    const srcX = Math.min(imageW - 1, Math.max(0, Math.floor((x0 - placed.left) * sx)));
    const srcY = Math.min(imageH - 1, Math.max(0, Math.floor((y0 - placed.top) * sy)));
    const srcRight = Math.min(imageW, Math.max(srcX + 1, Math.ceil((x1 - placed.left) * sx)));
    const srcBottom = Math.min(imageH, Math.max(srcY + 1, Math.ceil((y1 - placed.top) * sy)));
    region.empty = false;
    region.destX = x0;
    region.destY = y0;
    region.destW = x1 - x0;
    region.destH = y1 - y0;
    region.srcX = srcX;
    region.srcY = srcY;
    region.srcW = srcRight - srcX;
    region.srcH = srcBottom - srcY;
    return region;
  }

  /** 白色蒙版叠加后的单通道值，与编辑器预览中的半透明白层一致。 */
  static veilChannel(value: number, veil: number): number {
    const alpha = Math.min(WIDGET_BG_MAX_VEIL, Math.max(0, veil)) / 100;
    return Math.round(value + (255 - value) * alpha);
  }

  /** EXIF Orientation 可能是数字或文本描述（如 "Right-top"），统一为 1–8。 */
  static orientationCode(raw: string): number {
    const text = (raw ?? '').trim().toLowerCase().replace(/[\s_]/g, '-');
    const numeric = Number(text);
    if (Number.isInteger(numeric) && numeric >= 1 && numeric <= 8) {
      return numeric;
    }
    const names: string[] = ['top-left', 'top-right', 'bottom-right', 'bottom-left',
      'left-top', 'right-top', 'right-bottom', 'left-bottom'];
    const index = names.indexOf(text);
    return index >= 0 ? index + 1 : 1;
  }

  static parseState(raw: string): WidgetBackgroundState | undefined {
    try {
      const value = JSON.parse(raw) as WidgetBackgroundState;
      if (value === null || typeof value !== 'object' || typeof value.source !== 'string' ||
        value.source.length === 0 || value.source.includes('/') ||
        !Number.isFinite(value.revision) || value.revision <= 0 ||
        !WidgetBackgroundModel.validSize(value.sourceWidth, value.sourceHeight)) {
        return undefined;
      }
      const state = new WidgetBackgroundState();
      state.revision = value.revision;
      state.source = value.source;
      state.sourceWidth = value.sourceWidth;
      state.sourceHeight = value.sourceHeight;
      state.veil = Number.isFinite(value.veil) ?
        Math.min(WIDGET_BG_MAX_VEIL, Math.max(0, Math.round(value.veil))) : WIDGET_BG_DEFAULT_VEIL;
      state.compact = WidgetBackgroundModel.parseFrame(value.compact);
      state.wide = WidgetBackgroundModel.parseFrame(value.wide);
      return state;
    } catch (_) {
      return undefined;
    }
  }

  static compactName(revision: number): string {
    return 'hita_bg_compact_' + revision.toString();
  }

  static wideName(revision: number): string {
    return 'hita_bg_wide_' + revision.toString();
  }

  private static parseFrame(value: WidgetBackgroundFrame | undefined): WidgetBackgroundFrame {
    if (value === undefined || value === null || typeof value !== 'object') {
      return WidgetBackgroundModel.coverFrame();
    }
    return WidgetBackgroundModel.frame(
      Number.isFinite(value.scale) && value.scale > 0 ? Math.min(WIDGET_BG_MAX_SCALE, value.scale) : 1,
      WidgetBackgroundModel.unit(value.x), WidgetBackgroundModel.unit(value.y));
  }

  /** 由左/上偏移反推位置比例；图片与卡片同宽（高）时该方向不可移动，保留原比例。 */
  private static ratioOf(offset: number, frameSize: number, imageSize: number, fallback: number): number {
    const free = frameSize - imageSize;
    if (Math.abs(free) < 0.5) {
      return WidgetBackgroundModel.unit(fallback);
    }
    return WidgetBackgroundModel.unit(offset / free);
  }

  private static unit(value: number): number {
    return Number.isFinite(value) ? Math.min(1, Math.max(0, value)) : 0.5;
  }

  private static validSize(width: number, height: number): boolean {
    return Number.isFinite(width) && Number.isFinite(height) && width > 0 && height > 0;
  }
}
