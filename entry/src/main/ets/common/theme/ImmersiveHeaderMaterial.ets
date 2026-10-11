import { uiMaterial } from '@kit.ArkUI';
import { Available } from '@kit.BasicServicesKit';

@Available({ minApiVersion: 'HarmonyOS 26.0.0' })
export class HeaderMaterial {
  static apply(instance: CommonAttribute, fallbackColor: ResourceColor, blueSurface: boolean): void {
    try {
      const material: uiMaterial.ImmersiveMaterial | undefined = HeaderMaterial.create(blueSurface);
      if (material === undefined) {
        return;
      }
      // An opaque legacy fill would hide the material's blur and refraction.
      instance.backgroundColor(Color.Transparent);
      instance.systemMaterial(material);
    } catch (e) {
      instance.backgroundColor(fallbackColor);
    }
  }

  static create(blueSurface: boolean = false): uiMaterial.ImmersiveMaterial | undefined {
    try {
      if (!uiMaterial.isImmersiveMaterialSupported()) {
        return undefined;
      }
      return new uiMaterial.ImmersiveMaterial({
        style: blueSurface ? uiMaterial.ImmersiveStyle.REGULAR : HeaderMaterial.controlStyle(),
        materialColor: blueSurface ? $r('app.color.hita_immersive_hero_tint') : Color.Transparent,
        colorInvert: !blueSurface,
        applyShadow: blueSurface,
        interactive: true,
        lightEffect: { color: Color.White }
      });
    } catch (e) {
      return undefined;
    }
  }

  private static controlStyle(): uiMaterial.ImmersiveStyle {
    try {
      if (uiMaterial.getGlobalMaterialLevel() === uiMaterial.MaterialLevel.EXQUISITE) {
        return uiMaterial.ImmersiveStyle.ULTRA_THIN;
      }
    } catch (e) {
      // Let the system retain its balanced or low-power rendering policy.
    }
    return uiMaterial.ImmersiveStyle.THIN;
  }
}
