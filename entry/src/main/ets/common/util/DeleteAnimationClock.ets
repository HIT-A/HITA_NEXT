/** Skip stale callbacks and avoid jumping to the last frame after a transient UI stall. */
export class DeleteAnimationClock {
  private previous: number = -1;
  private elapsed: number = 0;

  advance(timestamp: number): number {
    if (this.previous < 0) {
      this.previous = timestamp;
      return this.elapsed;
    }
    const delta: number = (timestamp - this.previous) / 1000000;
    if (delta < 12) {
      return -1;
    }
    this.previous = timestamp;
    this.elapsed += Math.min(delta, 50);
    return this.elapsed;
  }
}
