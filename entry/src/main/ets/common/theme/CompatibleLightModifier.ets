import { deviceInfo } from '@kit.BasicServicesKit';
import lazy { ImmersiveLightFeedback } from './ImmersiveLightFeedback';

/** Drawing never participates in hit testing or replaces click/selection gestures. */
export class CompatibleLightModifier implements AttributeModifier<CommonAttribute> {
  private radius: number;
  private enabled: boolean;
  private panel: boolean;

  constructor(radius: number = 22, enabled: boolean = true, panel: boolean = false) {
    this.radius = radius;
    this.enabled = enabled;
    this.panel = panel;
  }

  applyNormalAttribute(instance: CommonAttribute): void {
    if (this.enabled && deviceInfo.apiAvailable('26.0.0') && !deviceInfo.apiAvailable('27.0.0')) {
      try {
        ImmersiveLightFeedback.apply(instance, this.radius, this.panel);
      } catch (_) {
        // Capability failures must not interfere with the control's action.
      }
    }
  }
}
