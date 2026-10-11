import { image } from '@kit.ImageKit';
import { displaySync } from '@kit.ArkGraphics2D';
import { LengthMetricsUnit } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DeleteEffectController, DeleteEffectPlayer } from '../util/DeleteEffectController';
import { DeleteAnimationClock } from '../util/DeleteAnimationClock';
import { DeleteDissolveRenderer } from '../util/DeleteDissolveRenderer';
import {
  createDeleteDissolve, deleteDissolveGrid,
  DELETE_DISSOLVE_DURATION, DELETE_DISSOLVE_PADDING
} from '../util/DeleteDissolve';

let nextDeleteSnapshotId: number = 0;

@Component
export struct DeleteParticleCard {
  controller: DeleteEffectController = new DeleteEffectController();
  effectId: string = '';
  captureSource: ((density: number) => Promise<image.PixelMap>) | undefined = undefined;
  onSourceHidden: () => void = () => {};
  @BuilderParam content: () => void;
  @State playing: boolean = false;
  @State contentOpacity: number = 1;
  @State cardWidth: number = 0;
  @State cardHeight: number = 0;
  private snapshotId: string = 'delete-snapshot-' + (++nextDeleteSnapshotId).toString();
  private canvas: DrawingRenderingContext = new DrawingRenderingContext(LengthMetricsUnit.PX);
  private snapshot: image.PixelMap | undefined = undefined;
  private renderer: DeleteDissolveRenderer | undefined = undefined;
  private sync: displaySync.DisplaySync | undefined = undefined;
  private clock: DeleteAnimationClock = new DeleteAnimationClock();
  private density: number = 1;
  private frameCount: number = 0;
  private maxDrawMs: number = 0;
  private lastElapsed: number = 0;
  private generation: number = 0;
  private visible: boolean = false;
  private finish: (() => void) | undefined = undefined;
  private ready: (() => void) | undefined = undefined;
  private player: DeleteEffectPlayer = {
    start: (finish: () => void, ready: () => void) => this.start(finish, ready),
    stop: () => this.stop()
  };

  aboutToAppear(): void {
    this.controller.register(this.effectId, this.player);
  }

  aboutToDisappear(): void {
    this.controller.unregister(this.effectId, this.player);
    this.stop();
  }

  private start(finish: () => void, ready: () => void): void {
    if (!this.visible || this.cardWidth <= 0 || this.cardHeight <= 0) {
      finish();
      return;
    }
    this.finish = finish;
    this.ready = ready;
    const generation: number = ++this.generation;
    this.capture(generation).catch(() => {
      if (generation === this.generation) {
        finish();
      }
    });
  }

  private async capture(generation: number): Promise<void> {
    const ui = this.getUIContext();
    this.density = ui.vp2px(1);
    const pixelArea: number = ui.vp2px(this.cardWidth) * ui.vp2px(this.cardHeight);
    const snapshot: image.PixelMap = this.captureSource !== undefined ?
      await this.captureSource(this.density) :
      await ui.getComponentSnapshot().get(this.snapshotId, {
        scale: Math.min(1, Math.sqrt(360000 / pixelArea))
      });
    if (generation !== this.generation) {
      await snapshot.release();
      return;
    }
    this.snapshot = snapshot;
    const grid: number[] = deleteDissolveGrid(this.cardWidth, this.cardHeight);
    const sampler = new OffscreenCanvasRenderingContext2D(grid[0], grid[1],
      new RenderingContextSettings(true), LengthMetricsUnit.PX);
    sampler.drawImage(snapshot, 0, 0, grid[0], grid[1]);
    const sampled: ImageData = sampler.getImageData(0, 0, grid[0], grid[1]);
    this.renderer = new DeleteDissolveRenderer(
      createDeleteDissolve(this.cardWidth, this.cardHeight, sampled.data, grid[0], grid[1]), snapshot);
    this.playing = true;
  }

  private animate(): void {
    if (!this.playing || this.renderer === undefined || this.sync !== undefined) {
      return;
    }
    try {
      this.renderer.draw(this.canvas.canvas, 0, this.density);
      this.canvas.invalidate();
      this.contentOpacity = 0;
      this.onSourceHidden();
      this.clock = new DeleteAnimationClock();
      this.sync = displaySync.create();
      this.sync.setExpectedFrameRateRange({ min: 30, max: 60, expected: 60 });
      this.sync.on('frame', (frame: displaySync.IntervalInfo) => this.drawFrame(frame.timestamp));
      this.ready?.();
      this.sync.start();
    } catch (error) {
      hilog.warn(0x1100, 'DeleteDissolve', 'animation start failed: %{public}s', String(error));
      this.finish?.();
    }
  }

  private drawFrame(timestamp: number): void {
    if (!this.playing || this.renderer === undefined) {
      return;
    }
    try {
      const elapsed: number = this.clock.advance(timestamp);
      if (elapsed < 0) {
        return;
      }
      const began: number = Date.now();
      this.renderer.draw(this.canvas.canvas, elapsed, this.density);
      this.canvas.invalidate();
      this.frameCount++;
      this.lastElapsed = elapsed;
      this.maxDrawMs = Math.max(this.maxDrawMs, Date.now() - began);
      if (elapsed >= DELETE_DISSOLVE_DURATION) {
        this.finish?.();
      }
    } catch (error) {
      hilog.warn(0x1100, 'DeleteDissolve', 'animation frame failed: %{public}s', String(error));
      this.finish?.();
    }
  }

  private stop(): void {
    this.generation++;
    this.finish = undefined;
    this.ready = undefined;
    this.playing = false;
    const sync: displaySync.DisplaySync | undefined = this.sync;
    this.sync = undefined;
    if (sync !== undefined) {
      try {
        sync.stop();
        sync.off('frame');
      } catch (_) {
      }
    }
    this.renderer = undefined;
    const snapshot: image.PixelMap | undefined = this.snapshot;
    this.snapshot = undefined;
    if (snapshot !== undefined) {
      snapshot.release().catch(() => {});
    }
    if (this.frameCount > 0) {
      hilog.info(0x1100, 'DeleteDissolve', 'frames=%{public}d elapsed=%{public}d maxDrawMs=%{public}d',
        this.frameCount, this.lastElapsed, this.maxDrawMs);
      this.frameCount = 0;
      this.maxDrawMs = 0;
      this.lastElapsed = 0;
    }
  }

  @Builder
  private particles() {
    if (this.playing) {
      Canvas(this.canvas)
        .width(this.cardWidth + DELETE_DISSOLVE_PADDING * 2)
        .height(this.cardHeight + DELETE_DISSOLVE_PADDING * 2)
        .hitTestBehavior(HitTestMode.None)
        .accessibilityLevel('no-hide-descendants')
        .onReady(() => this.animate());
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        this.content();
      }
      .width('100%')
      .id(this.snapshotId)
      .opacity(this.contentOpacity)
    }
    .width('100%')
    .onAreaChange((_old: Area, area: Area) => {
      this.cardWidth = Number(area.width);
      this.cardHeight = Number(area.height);
    })
    .onVisibleAreaChange([0, 0.1], (visible: boolean, ratio: number) => {
      this.visible = visible && ratio > 0;
    })
    .overlay(this.particles(), {
      align: Alignment.TopStart,
      offset: { x: -DELETE_DISSOLVE_PADDING, y: -DELETE_DISSOLVE_PADDING }
    });
  }
}
