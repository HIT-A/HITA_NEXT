export const IMMERSIVE_TAP_ALPHA: number = 0.28;
export const IMMERSIVE_TAP_RISE_MS: number = 180;
export const IMMERSIVE_RELEASE_MS: number = 360;
export const IMMERSIVE_HOLD_DELAY_MS: number = 180;
export const IMMERSIVE_HOLD_RAMP_MS: number = 360;

export function lightEase(progress: number): number {
  const value: number = Math.max(0, Math.min(1, progress));
  return value * value * (3 - 2 * value);
}

/** A quick release completes the gentle tap rise before fading. */
export class ImmersiveLightEnvelope {
  private startedMs: number = 0;
  private releasedMs: number = -1;
  private releaseAlpha: number = 0;
  private startAlpha: number = 0;
  private active: boolean = false;

  press(nowMs: number): void {
    this.startAlpha = this.sample(nowMs);
    this.startedMs = nowMs;
    this.releasedMs = -1;
    this.active = true;
  }

  release(nowMs: number, cancelled: boolean = false): void {
    if (!this.active || this.releasedMs >= 0) {
      return;
    }
    this.releaseAlpha = this.sample(nowMs);
    this.releasedMs = cancelled || nowMs - this.startedMs >= IMMERSIVE_HOLD_DELAY_MS ?
      nowMs : this.startedMs + IMMERSIVE_TAP_RISE_MS;
  }

  sample(nowMs: number): number {
    if (!this.active) {
      return 0;
    }
    const elapsed: number = Math.max(0, nowMs - this.startedMs);
    if (this.releasedMs >= 0 && nowMs >= this.releasedMs) {
      const peak: number = this.releasedMs === this.startedMs + IMMERSIVE_TAP_RISE_MS ?
        Math.max(this.startAlpha, IMMERSIVE_TAP_ALPHA) : this.releaseAlpha;
      return peak * (1 - lightEase((nowMs - this.releasedMs) / IMMERSIVE_RELEASE_MS));
    }
    const tap: number = this.startAlpha + (Math.max(this.startAlpha, IMMERSIVE_TAP_ALPHA) -
      this.startAlpha) * lightEase(elapsed / IMMERSIVE_TAP_RISE_MS);
    if (this.releasedMs >= 0 || elapsed <= IMMERSIVE_HOLD_DELAY_MS) {
      return tap;
    }
    return tap + (1 - tap) * lightEase((elapsed - IMMERSIVE_HOLD_DELAY_MS) / IMMERSIVE_HOLD_RAMP_MS);
  }

  needsFrame(nowMs: number): boolean {
    return this.active && (this.releasedMs >= 0 ?
      nowMs < this.releasedMs + IMMERSIVE_RELEASE_MS :
      nowMs < this.startedMs + IMMERSIVE_HOLD_DELAY_MS + IMMERSIVE_HOLD_RAMP_MS);
  }

  reset(): void {
    this.active = false;
    this.releasedMs = -1;
    this.startAlpha = 0;
    this.releaseAlpha = 0;
  }
}
