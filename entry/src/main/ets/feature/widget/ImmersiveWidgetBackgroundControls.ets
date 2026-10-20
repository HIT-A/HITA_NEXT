import { CompatibleMaterialModifier } from '../../common/theme/CompatibleMaterialModifier';
import { HitaColors } from '../../common/theme/HitaColors';

/**
 * Capsule button following the Button spec: emphasized (brand fill, white text) or normal (soft backplate, brand
 * text) at the NORMAL control size. Place it inside CourseControlHost, as the course editor does: API 26 renders the
 * interactive material only in a native title region, and the material then supplies the finger-following
 * deformation and press light. The emphasized fill doubles as the material colour, so low-power devices keep it.
 */
@Component
export struct ImmersiveFollowButton {
  @Prop label: string = '';
  @Prop isEnabled: boolean = true;
  @Prop primary: boolean = false;
  @Prop fill: boolean = true;
  onPress: () => void = () => {};
  // The material must not follow isEnabled: a modifier that stops applying resets backgroundColor to the Button
  // default (blue) while saving, replacing or removing. Disabling is left to enabled(), which only dims the text.
  private emphasizedMaterial: CompatibleMaterialModifier = new CompatibleMaterialModifier(
    $r('app.color.hita_primary_fill'), true, true, $r('app.color.hita_primary_fill'), false);
  private normalMaterial: CompatibleMaterialModifier = new CompatibleMaterialModifier(
    $r('app.color.hita_surface_soft'), false, true, undefined, false);

  build() {
    Button(this.label, { type: ButtonType.Capsule })
      .buttonStyle(this.primary ? ButtonStyleMode.EMPHASIZED : ButtonStyleMode.NORMAL)
      .controlSize(ControlSize.NORMAL)
      .width(this.fill ? '100%' : undefined)
      .fontColor(this.primary ? $r('sys.color.font_on_primary') : HitaColors.primary)
      .backgroundColor(this.primary ? $r('app.color.hita_primary_fill') : $r('app.color.hita_surface_soft'))
      .attributeModifier(this.primary ? this.emphasizedMaterial : this.normalMaterial)
      .enabled(this.isEnabled)
      .accessibilityText(this.label)
      .onClick(() => this.onPress())
  }
}
