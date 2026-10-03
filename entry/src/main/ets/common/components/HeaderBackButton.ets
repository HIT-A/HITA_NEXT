import { HitaColors } from '../theme/HitaColors';

@Component
export struct HeaderBackButton {
  @Prop accessibilityLabel: string = '返回';
  onBack: () => void = () => {};

  build() {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph($r('sys.symbol.chevron_left'))
        .fontSize(20)
        .fontWeight(FontWeight.Regular)
        .fontColor([HitaColors.onSurface]);
    }
    .width(44)
    .height(44)
    .padding(0)
    .flexShrink(0)
    .backgroundColor('#F2F4F7')
    .accessibilityText(this.accessibilityLabel)
    .onClick(() => {
      this.onBack();
    });
  }
}
