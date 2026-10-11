import { Available } from '@kit.BasicServicesKit';
import { ImmersiveHeader } from './ImmersiveHeader';

@Available({ minApiVersion: 'HarmonyOS 26.0.0' })
@Component
export struct ImmersiveNewsLayout {
  @Prop titleHeight: number = 60;
  @BuilderParam header: () => void;
  @BuilderParam dock: () => void;
  @BuilderParam content: () => void;
  @State contentHeight: number = 800;

  private blurStops(): FractionStop[] {
    const height: number = Math.max(this.contentHeight, this.titleHeight + 1);
    const start: number = Math.max(0, this.titleHeight - 52);
    const span: number = this.titleHeight - start;
    // Sample a smoothstep falloff so both ends ease into their neighboring regions.
    return [[1, 0], [1, start / height],
      [0.84375, (start + span * 0.25) / height],
      [0.5, (start + span * 0.5) / height],
      [0.15625, (start + span * 0.75) / height],
      [0, this.titleHeight / height], [0, 1]];
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      // Blur only the scrolling content; keep the title and dock in sharp sibling layers.
      Column() {
        this.content();
      }
      .width('100%')
      .height('100%')
      .linearGradientBlur(20, {
        direction: GradientDirection.Bottom,
        fractionStops: this.blurStops()
      })
      .onAreaChange((oldArea: Area, newArea: Area) => {
        this.contentHeight = Number(newArea.height);
      });

      ImmersiveHeader({ barHeight: this.titleHeight }) {
        this.header();
      }
      Column() {
        ImmersiveHeader({ barHeight: 52 }) {
          this.dock();
        }
      }
      .width('100%')
      .height(52)
      .hitTestBehavior(HitTestMode.Transparent)
      .margin({ top: this.titleHeight });
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM]);
  }
}
