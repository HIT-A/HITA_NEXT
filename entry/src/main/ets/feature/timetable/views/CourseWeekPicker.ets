import { deviceInfo } from '@kit.BasicServicesKit';
import { CourseDateSelection } from '../CourseDateSelection';
import { COURSE_CONTROL_OVERFLOW, CourseControlHost } from './CourseControlHost';
import { CompatibleMaterialModifier } from '../../../common/theme/CompatibleMaterialModifier';
import { CompatibleSheetMaterial } from '../../../common/theme/CompatibleSheetMaterial';

/** API 26 uses ArkUI's native swipe multi-selection; older devices retain tap selection. */
@Component
export struct CourseWeekPicker {
  @Prop weeks: number[] = [];
  @Link chosen: number[];
  @State editMode: boolean = true;
  @State activeWeek: number = -1;
  onAddWeeks: () => void = () => {};
  onChoosingChanged: (choosing: boolean) => void = (_choosing: boolean) => {};

  aboutToDisappear(): void {
    this.onChoosingChanged(false);
  }

  private select(week: number, selected: boolean): void {
    this.chosen = CourseDateSelection.toggle(this.chosen, week, selected);
  }

  @Builder
  cell(week: number) {
    CourseControlHost({
      barHeight: 44,
      onPressingChanged: (pressing: boolean) => {
        if (pressing) this.activeWeek = week;
        else if (this.activeWeek === week) this.activeWeek = -1;
        this.onChoosingChanged(pressing);
      }
    }) {
      Text(week.toString())
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .height(44)
        .textAlign(TextAlign.Center)
        .borderRadius(12)
        .backgroundColor(this.chosen.includes(week) ? $r('app.color.hita_primary_fill') :
          $r('app.color.hita_surface_soft'))
        .fontColor(this.chosen.includes(week) ?
          (CompatibleSheetMaterial.isEnabled() ? $r('app.color.hita_primary_3390ec') : '#FFFFFF') :
          $r('app.color.hita_text_202b45'))
        .attributeModifier(new CompatibleMaterialModifier(this.chosen.includes(week) ?
          $r('app.color.hita_primary_fill') : $r('app.color.hita_surface_soft'),
          this.chosen.includes(week), CompatibleSheetMaterial.isEnabled(),
          $r('app.color.hita_immersive_segment_selected'), false))
        .accessibilityText('第' + week.toString() + '周')
        .accessibilitySelected(this.chosen.includes(week))
    }
  }

  @Builder
  addWeekCell() {
    CourseControlHost({
      barHeight: 44,
      onPressingChanged: (pressing: boolean) => {
        if (pressing) this.activeWeek = 0;
        else if (this.activeWeek === 0) this.activeWeek = -1;
        this.onChoosingChanged(pressing);
      }
    }) {
      Button('+', { type: ButtonType.Normal })
        .width('100%')
        .height(44)
        .padding(0)
        .borderRadius(12)
        .fontSize(24)
        .fontWeight(FontWeight.Medium)
        .backgroundColor($r('app.color.hita_surface_soft'))
        .fontColor($r('app.color.hita_primary_3390ec'))
        .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_surface_soft'), false,
          CompatibleSheetMaterial.isEnabled()))
        .accessibilityText('增加 5 个教学周')
        .onClick(() => this.onAddWeeks())
    }
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
              .clip(false)
              .zIndex(this.activeWeek === week ? 3 : 1)
              .selectable(true)
              .selected(this.chosen.includes(week))
              .onSelect((selected: boolean) => this.select(week, selected))
              .onClick(() => {
                this.select(week, !this.chosen.includes(week));
              })
          }, (week: number) => week.toString())
          GridItem() { this.addWeekCell() }
            .height(44)
            .clip(false)
            .zIndex(this.activeWeek === 0 ? 3 : 1)
            .selectable(false)
        }
        .columnsTemplate('1fr 1fr 1fr 1fr 1fr')
        .rowsGap(8)
        .columnsGap(8)
        .width(CompatibleSheetMaterial.isEnabled() ?
          'calc(100% + ' + (COURSE_CONTROL_OVERFLOW * 2).toString() + 'vp)' : '100%')
        .padding(CompatibleSheetMaterial.isEnabled() ? COURSE_CONTROL_OVERFLOW : 0)
        .margin(CompatibleSheetMaterial.isEnabled() ? -COURSE_CONTROL_OVERFLOW : 0)
        .height(Math.min(304, Math.ceil((this.weeks.length + 1) / 5) * 52 - 8) +
          (CompatibleSheetMaterial.isEnabled() ? COURSE_CONTROL_OVERFLOW * 2 : 0))
        .clipContent(ContentClipMode.BOUNDARY)
        .zIndex(1)
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
          GridItem() { this.addWeekCell() }
            .height(44)
            .clip(false)
            .zIndex(this.activeWeek === 0 ? 3 : 1)
            .selectable(false)
        }
        .columnsTemplate('1fr 1fr 1fr 1fr 1fr')
        .rowsGap(8)
        .columnsGap(8)
        .height(Math.min(304, Math.ceil((this.weeks.length + 1) / 5) * 52 - 8))
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .clip(false)
  }
}
