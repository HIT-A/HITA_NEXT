import { deviceInfo } from '@kit.BasicServicesKit';
import { CourseDateSelection } from '../CourseDateSelection';

/** API 26 uses ArkUI's native swipe multi-selection; older devices retain tap selection. */
@Component
export struct CourseWeekPicker {
  @Prop weeks: number[] = [];
  @Link chosen: number[];
  @State editMode: boolean = true;
  onChoosingChanged: (choosing: boolean) => void = (_choosing: boolean) => {};

  aboutToDisappear(): void {
    this.onChoosingChanged(false);
  }

  private select(week: number, selected: boolean): void {
    this.chosen = CourseDateSelection.toggle(this.chosen, week, selected);
  }

  @Builder
  cell(week: number) {
    Text(week.toString())
      .fontSize(16)
      .fontWeight(FontWeight.Medium)
      .width('100%')
      .height('100%')
      .textAlign(TextAlign.Center)
      .borderRadius(12)
      .backgroundColor(this.chosen.includes(week) ? $r('app.color.hita_primary_fill') :
        $r('app.color.hita_surface_soft'))
      .fontColor(this.chosen.includes(week) ? '#FFFFFF' : $r('app.color.hita_text_202b45'))
      .accessibilityText('第' + week.toString() + '周')
      .accessibilitySelected(this.chosen.includes(week))
  }

  build() {
    Column({ space: 8 }) {
      if (deviceInfo.apiAvailable('26.0.0')) {
        Row() {
          Text(this.editMode ? '滑过周数可连续选择或取消' : '点击周数选择，或开启滑动选择')
            .fontSize(12)
            .fontColor($r('app.color.hita_text_secondary_72809a'))
            .layoutWeight(1)
          if (!this.editMode) {
            Button('滑动选择')
              .fontSize(12)
              .height(32)
              .onClick(() => { this.editMode = true; })
          }
        }
        .width('100%')
        Grid() {
          ForEach(this.weeks, (week: number) => {
            GridItem() { this.cell(week) }
              .height(44)
              .selectable(true)
              .selected(this.chosen.includes(week))
              .onSelect((selected: boolean) => this.select(week, selected))
              .onClick(() => {
                this.select(week, !this.chosen.includes(week));
              })
          }, (week: number) => week.toString())
        }
        .columnsTemplate('1fr 1fr 1fr 1fr 1fr')
        .rowsGap(8)
        .columnsGap(8)
        .height(Math.min(304, Math.ceil(this.weeks.length / 5) * 52 - 8))
        .editModeOptions({ useDefaultMultiSelectStyle: false, enableTwoFingerMultiSelect: true })
        .enableEditMode(this.editMode)
        .onEditModeChange((enabled: boolean) => { this.editMode = enabled; })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) this.onChoosingChanged(this.editMode);
          if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.onChoosingChanged(false);
        })
      } else {
        Text('点击周数可多选，也可使用全部、单周、双周')
          .fontSize(12)
          .fontColor($r('app.color.hita_text_secondary_72809a'))
        Grid() {
          ForEach(this.weeks, (week: number) => {
            GridItem() { this.cell(week) }
              .height(44)
              .onClick(() => this.select(week, !this.chosen.includes(week)))
          }, (week: number) => week.toString())
        }
        .columnsTemplate('1fr 1fr 1fr 1fr 1fr')
        .rowsGap(8)
        .columnsGap(8)
        .height(Math.min(304, Math.ceil(this.weeks.length / 5) * 52 - 8))
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
