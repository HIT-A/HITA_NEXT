/**
 * ImmersiveDockModifier.ets — 底部 dock 的单层背景模糊与半透明白底。
 *
 * 只使用 backdropBlur，不再叠系统 BlurStyle / ImmersiveMaterial，避免两层模糊。
 * HDS 点光源（6.0.0(20) 起）仍给按压页签照亮描边；旧系统探测失败时静默关掉光效。
 */
import { hdsEffect } from '@kit.UIDesignKit';

export class ImmersiveDockModifier implements AttributeModifier<StackAttribute> {
  applyNormalAttribute(instance: StackAttribute): void {
    // 磨砂指数 30：仅一层模糊半径 14 + 栏底色 0.30。
    instance.backdropBlur(14);
    instance.backgroundColor('rgba(255,255,255,0.30)');
    instance.clip(true);
    instance.shadow({ radius: 24, color: 'rgba(20,33,61,0.16)', offsetX: 0, offsetY: 8 });
  }
}

/**
 * 页签按下时成为强光点光源照亮 dock 描边，松手熄灭。点光源一旦设置就常亮，
 * 常亮会在页签图标和文字上泛光，所以只在按压态点亮。
 */
export class DockLightSourceModifier implements AttributeModifier<ColumnAttribute> {
  applyNormalAttribute(instance: ColumnAttribute): void {
    DockPointLight.apply(instance, DockPointLight.build(true, false));
  }

  applyPressedAttribute(instance: ColumnAttribute): void {
    DockPointLight.apply(instance, DockPointLight.build(true, true));
  }
}

/** dock 高光描边作为被照亮的边框（羽化描边）。 */
export class DockRimLightModifier implements AttributeModifier<ColumnAttribute> {
  applyNormalAttribute(instance: ColumnAttribute): void {
    DockPointLight.apply(instance, DockPointLight.build(false));
  }
}

class DockPointLight {
  private static available: boolean = true;

  static apply(instance: ColumnAttribute, effect: VisualEffect | undefined): void {
    if (effect !== undefined) {
      instance.visualEffect(effect);
    }
  }

  static build(asSource: boolean, lit: boolean = false): VisualEffect | undefined {
    if (!DockPointLight.available) {
      return undefined;
    }
    try {
      const light: hdsEffect.PointLightEffect = {};
      if (asSource) {
        light.sourceType = lit ? hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE;
      } else {
        light.illuminatedType = hdsEffect.PointLightIlluminatedType.DEFAULT_FEATHERING_BORDER;
      }
      return new hdsEffect.HdsEffectBuilder().pointLight(light).buildEffect();
    } catch (e) {
      DockPointLight.available = false;
      return undefined;
    }
  }
}
