/**
 * ImmersiveDockModifier.ets — 底部 dock 沉浸光感（组件适配）。
 *
 * HarmonyOS 7 / API 26 的 systemMaterial 支持标题栏和底部 TabBar 区域。
 * 因此材质挂在 Tabs.barFloatingStyle.systemMaterial，而不是自定义 Stack。
 *
 * @see https://developer.huawei.com/consumer/cn/doc/doccenter-advanced-features/bpta-spatiality-immersive
 * @see https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/arkts-apis-uimaterial
 */
import { uiMaterial } from '@kit.ArkUI';
import { Available } from '@kit.BasicServicesKit';

const DOCK_BAR_WIDTH: number = 212;

@Available({ minApiVersion: 'HarmonyOS 26.0.0' })
export class DockBarMaterial {
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
      if (uiMaterial.isImmersiveMaterialSupported()) {
        style.systemMaterial = new uiMaterial.ImmersiveMaterial({
          style: DockBarMaterial.styleForDevice(),
          applyShadow: true,
          // 按背景亮度反色，避免深色课表上图标发灰；具体色值走系统文本色，避免纯黑超对比度上限。
          colorInvert: true,
          // 原生按压形变与触点光感反馈由同一个 TabBar 材质处理。
          interactive: true,
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
