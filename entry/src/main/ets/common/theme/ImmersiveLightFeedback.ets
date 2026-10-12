import { DrawContext, uiMaterial } from '@kit.ArkUI';
import { drawing } from '@kit.ArkGraphics2D';
import { Available } from '@kit.BasicServicesKit';
import { ImmersiveLightEnvelope } from '../util/ImmersiveLightEffect';

@Available({ minApiVersion: 'HarmonyOS 26.0.0' })
export class ImmersiveLightFeedback extends DrawModifier {
  private static nodes: WeakMap<CommonAttribute, ImmersiveLightFeedback> = new WeakMap();
  private static handledTimestamp: number = -1;
  private static handledType: TouchType = TouchType.Cancel;
  private static handledEvent: TouchEvent | undefined = undefined;
  private envelope: ImmersiveLightEnvelope = new ImmersiveLightEnvelope();
  private timer: number = -1;
  private pointerId: number = -1;
  private x: number = 0;
  private y: number = 0;
  private alpha: number = 0;
  private radius: number = 22;
  private panel: boolean = false;
  private pressed: boolean = false;
  private detached: boolean = false;

  static apply(instance: CommonAttribute, radius: number = 22, panel: boolean = false): void {
    if (!uiMaterial.isImmersiveMaterialSupported()) {
      return;
    }
    let feedback: ImmersiveLightFeedback | undefined = ImmersiveLightFeedback.nodes.get(instance);
    if (feedback === undefined) {
      feedback = new ImmersiveLightFeedback();
      ImmersiveLightFeedback.nodes.set(instance, feedback);
    }
    const light: ImmersiveLightFeedback = feedback;
    light.radius = radius;
    light.panel = panel;
    light.detached = false;
    instance.drawModifier(light);
    instance.onTouch((event: TouchEvent) => light.observe(event));
    instance.onDetach(() => light.stop());
    instance.onVisibleAreaChange([0], (visible: boolean) => {
      if (!visible) light.stop(false);
    });
  }

  private observe(event: TouchEvent): void {
    // A panel must not add a second glow beneath a material control.
    const childHandled: boolean = this.panel && event.timestamp === ImmersiveLightFeedback.handledTimestamp &&
      event.type === ImmersiveLightFeedback.handledType;
    if (!this.panel) {
      ImmersiveLightFeedback.handledTimestamp = event.timestamp;
      ImmersiveLightFeedback.handledType = event.type;
      ImmersiveLightFeedback.handledEvent = event;
      setTimeout(() => {
        if (ImmersiveLightFeedback.handledEvent === event) {
          ImmersiveLightFeedback.handledTimestamp = -1;
          ImmersiveLightFeedback.handledEvent = undefined;
        }
      }, 0);
    }
    if (event.type === TouchType.Down) {
      if (childHandled || event.touches.length !== 1) {
        if (this.pressed) this.release(true);
        return;
      }
      const point: TouchObject = event.touches[0];
      this.detached = false;
      this.pointerId = point.id;
      this.move(point);
      this.pressed = true;
      this.envelope.press(Date.now());
      this.animate();
    } else if (this.pressed) {
      if (event.type === TouchType.Cancel || event.touches.length > 1) {
        this.release(true);
      } else if (event.type === TouchType.Up) {
        if (!event.touches.some((point: TouchObject): boolean => point.id === this.pointerId)) {
          this.release(false);
        }
      } else {
        const point: TouchObject | undefined = event.touches.find((touch: TouchObject): boolean =>
          touch.id === this.pointerId);
        if (point !== undefined) this.move(point);
      }
    }
  }

  private move(point: TouchObject): void {
    this.x = point.x;
    this.y = point.y;
    this.invalidate();
  }

  private release(cancelled: boolean): void {
    this.pressed = false;
    this.envelope.release(Date.now(), cancelled);
    this.animate();
  }

  private animate(): void {
    if (this.timer >= 0 || this.detached) {
      return;
    }
    const tick: () => void = () => {
      this.timer = -1;
      if (this.detached) return;
      const nowMs: number = Date.now();
      this.alpha = this.envelope.sample(nowMs);
      this.invalidate();
      if (this.envelope.needsFrame(nowMs)) {
        this.timer = setTimeout(tick, 16);
      }
    };
    tick();
  }

  private stop(detached: boolean = true): void {
    this.detached = detached;
    if (this.timer >= 0) clearTimeout(this.timer);
    this.timer = -1;
    this.pressed = false;
    this.pointerId = -1;
    this.envelope.reset();
    this.alpha = 0;
    this.invalidate();
  }

  drawForeground(context: DrawContext): void {
    if (this.alpha <= 0 || context.size.width <= 0 || context.size.height <= 0) return;
    const scale: number = context.sizeInPixel.width / context.size.width;
    const width: number = context.sizeInPixel.width;
    const height: number = context.sizeInPixel.height;
    const radius: number = Math.min(this.radius * scale, width / 2, height / 2);
    const glowRadius: number = Math.max(45 * scale, Math.min(width, height) * 0.8);
    const brush: drawing.Brush = new drawing.Brush();
    brush.setAntiAlias(true);
    brush.setShaderEffect(drawing.ShaderEffect.createRadialGradient({
      x: Math.max(0, Math.min(width, this.x * scale)),
      y: Math.max(0, Math.min(height, this.y * scale))
    }, glowRadius, [ImmersiveLightFeedback.white(this.alpha),
      ImmersiveLightFeedback.white(this.alpha * 0.65), 0x00FFFFFF], drawing.TileMode.CLAMP, [0, 0.35, 1]));
    context.canvas.save();
    context.canvas.clipRoundRect(new drawing.RoundRect({ left: 0, top: 0, right: width, bottom: height },
      radius, radius), drawing.ClipOp.INTERSECT, true);
    context.canvas.attachBrush(brush);
    context.canvas.drawRect(0, 0, width, height);
    context.canvas.detachBrush();
    context.canvas.restore();
  }

  private static white(alpha: number): number {
    return ((Math.round(Math.max(0, Math.min(1, alpha)) * 255) << 24) | 0x00FFFFFF) >>> 0;
  }
}
