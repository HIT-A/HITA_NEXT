/**
 * DockGlass.ets — dock 液态玻璃的高光参数。
 *
 * 所有反光与高光按同一增益放大（不透明度上限 1），整体调节光感强弱只需改 LIGHT_GAIN。
 */
export class DockGlass {
  /** 各处反光不透明度 = 基准值 × LIGHT_GAIN。 */
  static readonly LIGHT_GAIN: number = 1.6;
  /** 高光描边宽度（vp）。描边要细而亮，加粗后像一圈白色塑料边。 */
  static readonly RIM_WIDTH: number = 1;
  /** 磨砂白：指数 30，后景色隐约可见，栏体不是透明玻璃。 */
  static readonly FROST: string = 'rgba(255,255,255,0.30)';

  static glow(alpha: number): string {
    return DockGlass.light('255,255,255', alpha);
  }

  /** 光线穿过玻璃后在底缘汇聚的辉光。浅色界面上白光看不出来，所以带一点天蓝色相。 */
  static caustic(alpha: number): string {
    return DockGlass.light('120,196,255', alpha);
  }

  private static light(rgb: string, alpha: number): string {
    return 'rgba(' + rgb + ',' + Math.min(1, alpha * DockGlass.LIGHT_GAIN).toFixed(3) + ')';
  }
}
