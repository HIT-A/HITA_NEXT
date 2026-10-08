import { deviceInfo } from '@kit.BasicServicesKit';
import lazy { DockBarMaterial } from './ImmersiveDockModifier';

/** Keep the API 26 material module unloaded on older systems. */
export class CompatibleDockModifier implements AttributeModifier<TabsAttribute> {
  private bottomMargin: number;
  private hideMask: boolean;
  private darkMode: boolean;

  constructor(bottomMargin: number, hideMask: boolean, darkMode: boolean) {
    this.bottomMargin = bottomMargin;
    this.hideMask = hideMask;
    this.darkMode = darkMode;
  }

  applyNormalAttribute(instance: TabsAttribute): void {
    if (deviceInfo.apiAvailable('26.0.0')) {
      instance.barFloatingStyle(DockBarMaterial.floatingStyle(this.bottomMargin, this.hideMask, this.darkMode));
    } else {
      // The same TabsController still owns click/swipe navigation.
      instance.barHeight(0);
    }
  }
}
