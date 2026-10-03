/**
 * HitaColors.ets — 统一色彩与样式常量，对齐 Android HITA Material3 调色板。
 *
 * 参考用法：import { HitaColors, HitaCardStyle } from './HitaColors';
 * 然后以 HitaColors.primary / HitaCardStyle.cardRadius 等引用。
 */

/**
 * HITA 品牌色系（对应 Android colors.xml / Material3 tokens）。
 * 所有值为 HEX 色串，可直接用于 fontColor / backgroundColor 等属性。
 */
export class HitaColors {
  // ──────────────── Primary ────────────────
  /** 主品牌蓝 */
  static readonly primary: string = '#3390EC';
  /** 主色浅容器背景 */
  static readonly primaryContainer: string = '#EBF4FC';
  /** 主色上的前景（白） */
  static readonly onPrimary: string = '#FFFFFF';
  /** 主色容器上的前景（深蓝） */
  static readonly onPrimaryContainer: string = '#003366';

  // ──────────────── Surface / Background ────────────────
  /** 页面底色 */
  static readonly surface: string = '#F6F7FA';
  /** 卡片/白底容器 */
  static readonly surfaceVariant: string = '#FFFFFF';
  /** 主文本色 */
  static readonly onSurface: string = '#1A1A1A';
  /** 辅助文本色 */
  static readonly onSurfaceVariant: string = '#808080';
  /** 更弱的提示/占位文本色 */
  static readonly muted: string = '#B0B4BA';

  // ──────────────── Semantic ────────────────
  /** 错误 / 删除红 */
  static readonly error: string = '#D93025';
  /** 成功绿 */
  static readonly success: string = '#2E7D32';
  /** 警告黄 */
  static readonly warning: string = '#F9A825';
  /** 信息蓝 */
  static readonly info: string = '#2B6CB0';

  // ──────────────── Component Specific ────────────────
  /** 卡片阴影（8% 黑） */
  static readonly cardShadow: string = '#14000000';
  /** 分割线 */
  static readonly divider: string = '#E8E8E8';
  /** 活跃 Tab */
  static readonly tabActive: string = '#3390EC';
  /** 非活跃 Tab */
  static readonly tabInactive: string = '#999999';

  // ──────────────── Event Type Colors ────────────────
  /** 课程 */
  static readonly eventClass: string = '#3390EC';
  /** 考试 */
  static readonly eventExam: string = '#D93025';
  /** 其他事件 */
  static readonly eventOther: string = '#5C6BC0';
  /** 备忘/标签 */
  static readonly eventTag: string = '#26A69A';
}

/**
 * 卡片 / 排版维度常量（vp 单位，对应 Android 8dp 圆角等规范）。
 */
export class HitaCardStyle {
  /** 卡片圆角 */
  static readonly cardRadius: number = 12;
  /** 卡片阴影扩散半径 */
  static readonly cardShadowRadius: number = 8;
  /** 卡片内边距 */
  static readonly cardPadding: number = 16;
  /** 标题字号 */
  static readonly titleFontSize: number = 20;
  /** 正文字号 */
  static readonly bodyFontSize: number = 14;
  /** 注释/说明字号 */
  static readonly captionFontSize: number = 12;
}
