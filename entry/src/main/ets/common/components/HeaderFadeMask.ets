/**
 * HeaderFadeMask.ets — 抬头渐隐遮罩，透明度随列表滚动偏移淡入，不拦截触摸。
 *
 * headerHeight > 0 时为透明抬头模式（同功能中心）：遮罩覆盖整个抬头并向下延伸渐隐；
 * 否则只在不透明抬头下方画一条渐隐条。
 * fromBottom 时方向反过来，用于输入栏等底部抬头。
 */
import { HeaderFade } from '../theme/HeaderFade';

@Component
export struct HeaderFadeMask {
  @StorageProp('hita_appearance_dark') darkMode: boolean = false;
  @Prop maskOpacity: number = 0;
  /** 与遮罩下方页面底色一致的 RGB 分量。 */
  @Prop rgb: string = '244,247,252';
  @Prop headerHeight: number = 0;
  @Prop fromBottom: boolean = false;

  build() {
    Column()
      .width('100%')
      .height(this.headerHeight + HeaderFade.HEIGHT)
      .linearGradient({
        direction: GradientDirection.Bottom,
        colors: this.stops()
      })
      .opacity(this.maskOpacity)
      .hitTestBehavior(HitTestMode.None)
  }

  private stops(): Array<[ResourceColor, number]> {
    const rgb: string = this.darkMode ? '16,18,20' : this.rgb;
    const offsets: number[] = this.headerHeight > 0 ? HeaderFade.HEADER_OFFSETS : HeaderFade.OFFSETS;
    const alphas: number[] = this.headerHeight > 0 ? HeaderFade.HEADER_ALPHAS : HeaderFade.ALPHAS;
    const stops: Array<[ResourceColor, number]> = [];
    if (this.fromBottom) {
      for (let i: number = offsets.length - 1; i >= 0; i--) {
        stops.push([HeaderFade.rgba(rgb, alphas[i]), 1 - offsets[i]]);
      }
    } else {
      for (let i: number = 0; i < offsets.length; i++) {
        stops.push([HeaderFade.rgba(rgb, alphas[i]), offsets[i]]);
      }
    }
    return stops;
  }
}
