/** A Dock drag may never authorize navigation, even after returning to its start. */
export class DockNavigationGuard {
  private sequence: number = 0;
  private dock: boolean = false;
  private pressed: boolean = false;
  private hasTouch: boolean = false;
  private rejected: boolean = false;
  private consumed: boolean = false;
  private pointerId: number = -1;
  private downTimestamp: number = -1;
  private startX: number = 0;
  private startY: number = 0;
  private authorizedIndex: number = -1;

  begin(event: TouchEvent, fromDock: boolean): void {
    if (event.type !== TouchType.Down || event.touches.length === 0) {
      return;
    }
    const touch: TouchObject = event.touches[0];
    if (!this.hasTouch || (event.touches.length === 1 && event.timestamp !== this.downTimestamp)) {
      this.reset();
      this.hasTouch = true;
      this.pressed = true;
      this.downTimestamp = event.timestamp;
      this.pointerId = touch.id;
      this.startX = touch.windowX;
      this.startY = touch.windowY;
    }
    if (event.touches.length !== 1 || touch.id !== this.pointerId) {
      this.rejected = true;
    }
    // Hit testing visits Tabs and then TabBar for the same Down event.
    this.dock = this.dock || fromDock;
  }

  observe(event: TouchEvent): void {
    if (!this.hasTouch) {
      return;
    }
    if (event.type === TouchType.Cancel) {
      this.rejected = true;
      this.pressed = false;
      return;
    }
    if (!this.dock || this.rejected) {
      // Content scrolling and already-cancelled drags need no native history copy.
      if (event.type === TouchType.Up) {
        this.pressed = false;
      }
      return;
    }
    if (event.touches.length > 1) {
      this.rejected = true;
    }
    // A frame may coalesce an out-and-back movement. Inspect its intermediate
    // points as well as the final Move/Up; returning to the start cannot undo it.
    for (const point of event.getHistoricalPoints()) {
      this.checkPoint(point.touchObject);
    }
    for (const touch of event.changedTouches) {
      this.checkPoint(touch);
    }
    for (const touch of event.touches) {
      this.checkPoint(touch);
    }
    if (event.type === TouchType.Up) {
      this.pressed = false;
    }
  }

  private checkPoint(touch: TouchObject): void {
    // 8vp tolerates ordinary tap jitter. Exceeding it CANCELS a click; it never
    // becomes a distance threshold for switching pages.
    const dx: number = touch.windowX - this.startX;
    const dy: number = touch.windowY - this.startY;
    if (touch.id !== this.pointerId || dx * dx + dy * dy > 64) {
      this.rejected = true;
    }
  }

  isDock(): boolean {
    return this.dock;
  }

  requestClick(): number {
    // Also veto the native click's own automatic change. Only the deferred,
    // validated controller call below gets a scoped authorization.
    this.dock = true;
    // API 26's floating TabBar can report index 0 before raw Up, followed by
    // the actual item index in the same dispatch. Supersede the earlier
    // request so it cannot consume the tap before the correct item runs.
    return ++this.sequence;
  }

  commitClick(sequence: number, index: number, changeIndex: (index: number) => void): void {
    if (sequence !== this.sequence || this.pressed || this.rejected || this.consumed) {
      return;
    }
    this.consumed = true;
    this.authorizedIndex = index;
    try {
      changeIndex(index);
    } finally {
      this.authorizedIndex = -1;
    }
  }

  allowsChange(index: number): boolean {
    return !this.dock || this.authorizedIndex === index;
  }

  reset(): void {
    this.sequence++;
    this.dock = false;
    this.pressed = false;
    this.hasTouch = false;
    this.rejected = false;
    this.consumed = false;
    this.authorizedIndex = -1;
  }
}
