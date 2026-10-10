import { TimetableTheme } from '../../../common/theme/TimetableTheme';
import { CourseColorModel } from './CourseColorModel';
import { timetableBlockColor } from './TimetableWeekDraw';

@Component
export struct CourseColorEditor {
  @Prop previewDark: boolean = false;
  @Prop previewWallpaper: boolean = false;
  @Prop textMode: boolean = false;
  @Prop initialColor: number = 0xFF2E86E8;
  @Prop textColor: string = '#FFFFFF';
  @State hue: number = 0;
  @State saturation: number = 0;
  @State colorBrightness: number = 0;
  @State panelWidth: number = 280;
  private readonly panelHeight: number = 170;
  @Prop presets: number[] = [0xFFE57373, 0xFFFFB74D, 0xFF81C784, 0xFF4DB6AC,
    0xFF64B5F6, 0xFF9575CD, 0xFFF06292];
  @State saving: boolean = false;
  @State error: string = '';
  onSave: (color: number) => Promise<void> = async () => {};
  onCancel: () => void = () => {};

  aboutToAppear(): void { this.selectColor(this.initialColor); }

  private selectColor(color: number): void {
    const hsv: CourseColorModel = CourseColorModel.fromColor(color);
    this.hue = hsv.hue;
    this.saturation = hsv.saturation;
    this.colorBrightness = hsv.brightness;
  }

  private pickAt(x: number, y: number): void {
    if (this.saving) { return; }
    this.saturation = Math.max(0, Math.min(1, x / this.panelWidth));
    this.colorBrightness = 1 - Math.max(0, Math.min(1, y / this.panelHeight));
  }

  private dragColor(event: GestureEvent): void {
    if (event.fingerList.length > 0) {
      this.pickAt(event.fingerList[0].localX, event.fingerList[0].localY);
    }
  }

  private color(): number {
    return CourseColorModel.toColor(this.hue, this.saturation, this.colorBrightness);
  }

  private hex(): string {
    return '#' + (this.color() & 0xFFFFFF).toString(16).padStart(6, '0').toUpperCase();
  }

  private async save(): Promise<void> {
    if (this.saving) { return; }
    this.saving = true;
    this.error = '';
    try {
      await this.onSave(this.color());
    } catch (_) {
      this.error = '颜色保存失败，请重试';
    } finally {
      this.saving = false;
    }
  }

  build() {
    Column({ space: 8 }) {
      Text(this.textMode ? '时间表文字颜色' : '课程颜色').fontSize(20).fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.hita_text')).width('100%');
      Text(this.textMode ? '调整标题、日期和时间刻度的颜色。' : '应用到这门课程的所有课块；过亮颜色会自动压暗。')
        .fontSize(13).fontColor($r('app.color.hita_text_secondary')).width('100%');
      Row({ space: 12 }) {
        Text(this.hex()).fontColor($r('app.color.hita_text')).layoutWeight(1);
        Text(this.textMode ? '周一 08:00' : '课块预览')
          .fontColor(this.textMode ? TimetableTheme.resolveText(this.hex(), this.previewDark, this.previewWallpaper) : '#FFFFFF').fontSize(15)
          .padding(16).borderRadius(12)
          .backgroundColor(this.textMode ? $r('app.color.hita_page') : timetableBlockColor(this.color()));
      }.width('100%').margin({ top: 8, bottom: 4 });
      Stack({ alignContent: Alignment.TopStart }) {
        Row().width('100%').height('100%')
          .backgroundColor(CourseColorModel.toColor(this.hue, 1, 1))
          .linearGradient({ direction: GradientDirection.Right,
            colors: [['#FFFFFFFF', 0], ['#00FFFFFF', 1]] });
        Row().width('100%').height('100%')
          .linearGradient({ direction: GradientDirection.Bottom,
            colors: [['#00000000', 0], ['#FF000000', 1]] });
        Stack() {
          Circle().width(18).height(18).fill(Color.Transparent)
            .stroke('#99000000').strokeWidth(4);
          Circle().width(18).height(18).fill(Color.Transparent)
            .stroke(Color.White).strokeWidth(2);
        }.width(20).height(20)
          .position({ x: Math.max(0, Math.min(this.panelWidth - 20,
            this.saturation * this.panelWidth - 10)),
            y: Math.max(0, Math.min(this.panelHeight - 20,
              (1 - this.colorBrightness) * this.panelHeight - 10)) })
          .hitTestBehavior(HitTestMode.None);
      }
      .width('100%').height(this.panelHeight).borderRadius(12).clip(true)
      .accessibilityText('颜色面板：左右调整鲜艳程度，上下调整明暗')
      .onAreaChange((oldArea: Area, area: Area) => { this.panelWidth = Number(area.width); })
      .onTouch((event: TouchEvent) => {
        // Touch bubbling alone does not arbitrate the sheet's vertical pan gesture.
        event.stopPropagation();
        if (event.type === TouchType.Down && event.touches.length > 0) {
          this.pickAt(event.touches[0].x, event.touches[0].y);
        }
      })
      .priorityGesture(
        PanGesture({ direction: PanDirection.All, distance: 0 })
          .onActionStart((event: GestureEvent) => { this.dragColor(event); })
          .onActionUpdate((event: GestureEvent) => { this.dragColor(event); })
          .onActionEnd((event: GestureEvent) => { this.dragColor(event); })
      );
      Stack() {
        Row().width('100%').height(16).borderRadius(8)
          .linearGradient({ direction: GradientDirection.Right,
            colors: [['#FF0000', 0], ['#FFFF00', 1 / 6], ['#00FF00', 2 / 6],
              ['#00FFFF', 3 / 6], ['#0000FF', 4 / 6], ['#FF00FF', 5 / 6], ['#FF0000', 1]] });
        Slider({ value: this.hue, min: 0, max: 360, step: 1 })
          .width('100%').trackColor(Color.Transparent).selectedColor(Color.Transparent)
          .blockColor(Color.White).enabled(!this.saving).accessibilityText('彩虹色相')
          .onChange((value: number) => { this.hue = value; });
      }.width('100%').height(36);
      Row() {
        ForEach(this.presets, (color: number) => {
          Button({ type: ButtonType.Circle }).width(28).height(28)
            .backgroundColor(color).enabled(!this.saving)
            .accessibilityText('预设颜色 ' + (color & 0xFFFFFF).toString(16))
            .onClick(() => { this.selectColor(color); });
        });
      }.width('100%').justifyContent(FlexAlign.SpaceBetween);
      if (this.error.length > 0) {
        Text(this.error).fontColor($r('app.color.hita_error_8a2e42')).fontSize(13);
      }
      Row({ space: 12 }) {
        Button('取消').layoutWeight(1).enabled(!this.saving).onClick(() => this.onCancel());
        Button(this.saving ? '保存中…' : '保存').layoutWeight(1)
          .enabled(!this.saving).onClick(() => this.save());
      }.width('100%').margin({ top: 12 });
    }.width('100%');
  }
}
