import { ImmersiveHeader } from './ImmersiveHeader';
import { CompatibleMaterialModifier } from '../theme/CompatibleMaterialModifier';

@Component
export struct ImmersiveEventCard {
  @BuilderParam content: () => void;
  @State private contentHeight: number = 0;

  private updateHeight(height: number): void {
    if (Number.isFinite(height) && height > 0) {
      const next: number = Math.ceil(height);
      if (next !== this.contentHeight) {
        this.contentHeight = next;
      }
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.contentHeight > 0) {
        // A positioned title host supplies material without constraining the card's content height.
        Column() {
          ImmersiveHeader({ barHeight: this.contentHeight }) {
            Row()
              .width('100%')
              .height(this.contentHeight)
              .backgroundColor($r('app.color.hita_surface'))
              .borderRadius(16)
              .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_surface')));
          }
        }
        .width('100%')
        .height(this.contentHeight)
        .position({ x: 0, y: 0 })
        .accessibilityLevel('no-hide-descendants')
        .hitTestBehavior(HitTestMode.Transparent);
      }
      Column() {
        this.content();
      }
      .width('100%')
      .onAreaChange((oldArea: Area, area: Area) => { this.updateHeight(Number(area.height)); })
      // Let presses reach the lower material layer without blocking list scrolling.
      .hitTestBehavior(HitTestMode.Transparent);
    }
    .width('100%')
    .backgroundColor(this.contentHeight > 0 ? Color.Transparent : $r('app.color.hita_surface'))
    .borderRadius(16)
    .margin({ bottom: 2 });
  }
}
