import { IMMERSIVE_TAP_ALPHA, IMMERSIVE_TAP_RISE_MS, IMMERSIVE_RELEASE_MS,
  IMMERSIVE_HOLD_RAMP_MS, lightEase } from './ImmersiveLightEffect';

export const DOCK_FLOW_DURATION_MS: number = IMMERSIVE_TAP_RISE_MS + IMMERSIVE_RELEASE_MS;
export const DOCK_TAP_LIGHT_ALPHA: number = IMMERSIVE_TAP_ALPHA;
export const DOCK_HOLD_LIGHT_RAMP_MS: number = IMMERSIVE_HOLD_RAMP_MS;

export function sampleDockHoldLight(elapsedMs: number): number {
  const progress: number = Math.max(0, Math.min(1, elapsedMs / DOCK_HOLD_LIGHT_RAMP_MS));
  const eased: number = progress * progress * (3 - 2 * progress);
  return DOCK_TAP_LIGHT_ALPHA + (1 - DOCK_TAP_LIGHT_ALPHA) * eased;
}

export function dockWhiteLightColor(alpha: number): string {
  return '#' + Math.round(Math.max(0, Math.min(1, alpha)) * 255).toString(16).padStart(2, '0') + 'FFFFFF';
}

export interface DockLightPlayer {
  transfer: (from: number, to: number) => void;
  stop: () => void;
  press: (source: number) => void;
  move: (x: number) => void;
  release: (cancelled: boolean) => void;
}

export class DockLightController {
  private player: DockLightPlayer | undefined = undefined;

  register(player: DockLightPlayer): void {
    this.player = player;
  }

  unregister(player: DockLightPlayer): void {
    if (this.player === player) {
      this.player = undefined;
    }
  }

  transfer(from: number, to: number): void {
    if (from !== to && from >= 0 && from < 3 && to >= 0 && to < 3) {
      this.player?.transfer(from, to);
    }
  }

  stop(): void {
    this.player?.stop();
  }

  press(source: number): void {
    this.player?.press(source);
  }

  move(x: number): void {
    this.player?.move(x);
  }

  release(cancelled: boolean): void {
    this.player?.release(cancelled);
  }
}

/** Stiffness of the flowing light; settles a full-width travel well inside one tap envelope. */
export const DOCK_FLOW_OMEGA: number = 24;

/**
 * Critically damped follower for the flowing light. Retargeting keeps the current position and velocity,
 * so a rapid page change bends the light toward the new tab instead of restarting it at the old one.
 */
export class DockFlowMotion {
  private position: number = 106;
  private velocity: number = 0;
  private target: number = 106;
  private lastMs: number = -1;
  private moving: boolean = false;

  current(): number {
    return this.position;
  }

  isMoving(): boolean {
    return this.moving;
  }

  jump(x: number): void {
    this.position = x;
    this.target = x;
    this.velocity = 0;
    this.moving = false;
    this.lastMs = -1;
  }

  retarget(x: number, nowMs: number): void {
    if (!this.moving) {
      this.velocity = 0;
      this.lastMs = nowMs;
    }
    this.target = x;
    this.moving = true;
  }

  step(nowMs: number): number {
    if (!this.moving) {
      return this.position;
    }
    // Exact critically damped solution, so frame drops cannot destabilise or overshoot it.
    const dt: number = Math.max(0, Math.min(0.05, (nowMs - this.lastMs) / 1000));
    this.lastMs = nowMs;
    const w: number = DOCK_FLOW_OMEGA;
    const x0: number = this.position - this.target;
    const v0: number = this.velocity;
    const decay: number = Math.exp(-w * dt);
    const x: number = (x0 + (v0 + w * x0) * dt) * decay;
    this.velocity = (v0 - (v0 + w * x0) * w * dt) * decay;
    this.position = this.target + x;
    if (Math.abs(x) < 0.5 && Math.abs(this.velocity) < 20) {
      this.jump(this.target);
    }
    return this.position;
  }

  settle(): void {
    this.jump(this.target);
  }
}

export interface DockFlowSample {
  center: number;
  tail: number;
  alpha: number;
}

export function sampleDockFlow(from: number, to: number, elapsedMs: number, width: number): DockFlowSample {
  const progress: number = Math.max(0, Math.min(1, elapsedMs / 360));
  const travel: number = progress * progress * (3 - 2 * progress);
  const start: number = (from + 0.5) * width / 3;
  const end: number = (to + 0.5) * width / 3;
  const envelope: number = elapsedMs <= IMMERSIVE_TAP_RISE_MS ?
    lightEase(elapsedMs / IMMERSIVE_TAP_RISE_MS) :
    1 - lightEase((elapsedMs - IMMERSIVE_TAP_RISE_MS) / IMMERSIVE_RELEASE_MS);
  return {
    center: start + (end - start) * travel,
    tail: start + (end - start) * Math.max(0, travel - 0.16),
    alpha: DOCK_TAP_LIGHT_ALPHA * envelope
  };
}
