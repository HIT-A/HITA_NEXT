/**
 * ImmersiveDockModifier.ets — 底部 dock 沉浸光感（组件适配）。
 *
 * HarmonyOS 7 / targetSdk 26 起，普通组件上的 systemMaterial 只在底部 TabBar 生效。
 * 因此材质挂在 Tabs.barFloatingStyle.systemMaterial，而不是自定义 Stack。
 *
 * @see https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/arkts-immersive-light-sense-component-adaptation
 */
import { deviceInfo } from '@kit.BasicServicesKit';
// Do not load the API 26 native module on HarmonyOS 6.1.
import lazy { uiMaterial } from '@kit.ArkUI';

const DOCK_BAR_WIDTH: number = 212;

export class DockBarMaterial {
  static supportsFloatingBar(): boolean {
    return deviceInfo.sdkApiVersion >= 26;
  }

  static floatingStyle(bottomMargin: number, hideMask: boolean = false,
    darkMode: boolean = false): FloatingTabBarStyle {
    const style: FloatingTabBarStyle = {
      barWidth: {
        smallBarWidth: DOCK_BAR_WIDTH,
        mediumBarWidth: DOCK_BAR_WIDTH,
        largeBarWidth: DOCK_BAR_WIDTH
      },
      barBottomMargin: bottomMargin,
      maskColor: hideMask ? Color.Transparent : (darkMode ? '#99101214' : '#66F1F3F5'),
      maskHeight: hideMask ? 0 : 92
    };
    try {
      if (DockBarMaterial.supportsFloatingBar() && uiMaterial.isImmersiveMaterialSupported()) {
        style.systemMaterial = new uiMaterial.ImmersiveMaterial({
          style: DockBarMaterial.styleForDevice(),
          applyShadow: true,
          // 按背景亮度反色，避免深色课表上图标发灰；具体色值走系统文本色，避免纯黑超对比度上限。
          colorInvert: true,
          interactive: false,
          lightEffect: { color: Color.White }
        });
      }
    } catch (e) {
      // 设备或 API 不支持时，悬浮栏仍保留圆角与蒙层。
    }
    return style;
  }

  private static styleForDevice(): uiMaterial.ImmersiveStyle {
    try {
      const level: uiMaterial.MaterialLevel = uiMaterial.getGlobalMaterialLevel();
      if (level === uiMaterial.MaterialLevel.EXQUISITE) {
        return uiMaterial.ImmersiveStyle.ULTRA_THIN;
      }
      if (level === uiMaterial.MaterialLevel.GENTLE) {
        return uiMaterial.ImmersiveStyle.THIN;
      }
    } catch (e) {
      // 回落到薄材质。
    }
    return uiMaterial.ImmersiveStyle.THIN;
  }
}

export class DockBarModifier implements AttributeModifier<TabsAttribute> {
  private bottomMargin: number;
  private hideMask: boolean;
  private darkMode: boolean;

  constructor(bottomMargin: number, hideMask: boolean, darkMode: boolean) {
    this.bottomMargin = bottomMargin;
    this.hideMask = hideMask;
    this.darkMode = darkMode;
  }

  applyNormalAttribute(instance: TabsAttribute): void {
    if (DockBarMaterial.supportsFloatingBar()) {
      instance.barFloatingStyle(DockBarMaterial.floatingStyle(this.bottomMargin, this.hideMask, this.darkMode));
    }
  }
}
