/** API 23 dock: backdrop blur and background-aware foreground inversion. */
@Component
export struct FrostedDock {
  @Prop selectedIndex: number = 0;
  @Prop bottomInset: number = 24;
  @Prop darkMode: boolean = false;
  @Prop hideMask: boolean = false;
  onSelect: (index: number) => void = () => {};

  @Builder
  item(icon: Resource, label: string, index: number) {
    Column({ space: 3 }) {
      SymbolGlyph(icon)
        .fontSize(20)
        .fontColor([Color.White])
        .invert({ low: 0.1, high: 0.9, threshold: 0.5, thresholdRange: 0.15 })
      Text(label)
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .invert({ low: 0.1, high: 0.9, threshold: 0.5, thresholdRange: 0.15 })
    }
    .layoutWeight(1)
    .height(48)
    .justifyContent(FlexAlign.Center)
    .opacity(this.selectedIndex === index ? 1 : 0.65)
    .borderRadius(24)
    .backgroundColor(this.selectedIndex === index ? (this.darkMode ? '#18FFFFFF' : '#10000000') : Color.Transparent)
    .accessibilityText(label)
    .accessibilitySelected(this.selectedIndex === index)
    .onClick(() => this.onSelect(index))
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (!this.hideMask) {
        Column()
          .width('100%')
          .height(92 + this.bottomInset)
          .linearGradient({
            angle: 0,
            colors: [[this.darkMode ? '#99101214' : '#66F1F3F5', 0], [Color.Transparent, 1]]
          })
          .hitTestBehavior(HitTestMode.None)
      }
      Row() {
        this.item($r('sys.symbol.calendar'), '今日', 0)
        this.item($r('sys.symbol.doc_plaintext'), '时间表', 1)
        this.item($r('sys.symbol.more'), '更多', 2)
      }
      .width(212)
      .height(56)
      .padding(4)
      .borderRadius(28)
      .backgroundEffect({
        radius: 24, saturation: 1.1, brightness: 1,
        color: this.darkMode ? '#66101214' : '#44F1F3F5'
      })
      .border({ width: 0.5, color: this.darkMode ? '#33FFFFFF' : '#88FFFFFF' })
      .shadow({ radius: 12, color: '#20000000', offsetY: 4 })
      .margin({ bottom: 12 + this.bottomInset })
    }
    .width('100%')
    .height(92 + this.bottomInset)
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
