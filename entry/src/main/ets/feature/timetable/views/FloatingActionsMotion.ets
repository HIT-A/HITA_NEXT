// 18vp inset + 48vp control + 16vp material overflow + 2vp clearance.
export const FLOATING_ACTION_EXIT: number = 84;
export const FLOATING_ACTION_GAP: number = 60;
export const FLOATING_ACTION_EXIT_DURATION: number = 180;
export const FLOATING_ACTION_RELEASE_DELAY: number = 16;

/** Keep the visible part of the 170/17 spring, without its invisible settling tail. */
export function floatingActionExitProgress(fraction: number): number {
  const elapsed = Math.max(0, Math.min(1, fraction)) * FLOATING_ACTION_EXIT_DURATION / 1000;
  const damping = 17 / 2;
  const frequency = Math.sqrt(170 - damping * damping);
  const end = FLOATING_ACTION_EXIT_DURATION / 1000;
  const progress = 1 - Math.exp(-damping * elapsed) *
    (Math.cos(frequency * elapsed) + damping / frequency * Math.sin(frequency * elapsed));
  const endProgress = 1 - Math.exp(-damping * end) *
    (Math.cos(frequency * end) + damping / frequency * Math.sin(frequency * end));
  return progress / endProgress;
}

export class FloatingActionsFrame {
  side: number = 1;
  eveningMounted: boolean = false;
  returnMounted: boolean = false;
  eveningX: number = FLOATING_ACTION_EXIT;
  returnX: number = FLOATING_ACTION_EXIT;
  returnLift: number = 0;

  copy(): FloatingActionsFrame {
    const frame = new FloatingActionsFrame();
    frame.side = this.side;
    frame.eveningMounted = this.eveningMounted;
    frame.returnMounted = this.returnMounted;
    frame.eveningX = this.eveningX;
    frame.returnX = this.returnX;
    frame.returnLift = this.returnLift;
    return frame;
  }
}

/** Interrupt ordinary motion immediately; only an edge handoff must finish leaving first. */
export class FloatingActionsMotion {
  private frame: FloatingActionsFrame = new FloatingActionsFrame();
  private active: boolean = false;
  private evening: boolean = false;
  private returnWeek: boolean = false;
  private side: number = 1;
  private blocked: boolean = false;
  private pressed: number = 0;
  private releaseTimer: number = -1;
  private running: boolean = false;
  private handingOff: boolean = false;
  private generation: number = 0;
  private render: (frame: FloatingActionsFrame) => void;
  private animate: (frame: FloatingActionsFrame, stiffness: number, exiting: boolean, generation: number,
    finish: () => void) => void;

  constructor(render: (frame: FloatingActionsFrame) => void,
    animate: (frame: FloatingActionsFrame, stiffness: number, exiting: boolean, generation: number,
      finish: () => void) => void) {
    this.render = render;
    this.animate = animate;
  }

  update(active: boolean, evening: boolean, returnWeek: boolean, blocked: boolean): void {
    this.evening = evening;
    this.returnWeek = returnWeek;
    this.blocked = blocked;
    if (!active) {
      this.stop();
      return;
    }
    this.active = true;
    this.reconcile();
  }

  setSide(left: boolean): void {
    this.side = left ? -1 : 1;
    this.reconcile();
  }

  setPressed(control: number, pressed: boolean): void {
    this.pressed = pressed ? this.pressed | control : this.pressed & ~control;
    if (this.releaseTimer >= 0) clearTimeout(this.releaseTimer);
    this.releaseTimer = -1;
    if (this.pressed === 0 && this.active) {
      // Let onClick and its parent state updates complete before moving the target.
      this.releaseTimer = setTimeout(() => {
        this.releaseTimer = -1;
        this.reconcile();
      }, FLOATING_ACTION_RELEASE_DELAY);
    }
  }

  isCurrent(generation: number): boolean {
    return this.active && generation === this.generation;
  }

  stop(): void {
    this.active = false;
    this.generation++;
    this.running = false;
    this.handingOff = false;
    this.pressed = 0;
    if (this.releaseTimer >= 0) clearTimeout(this.releaseTimer);
    this.releaseTimer = -1;
    this.frame = new FloatingActionsFrame();
    this.frame.side = this.side;
    this.frame.eveningX = this.side * FLOATING_ACTION_EXIT;
    this.frame.returnX = this.side * FLOATING_ACTION_EXIT;
    this.render(this.frame.copy());
  }

  private commit(target: FloatingActionsFrame, stiffness: number, exiting: boolean): void {
    this.running = true;
    const generation = ++this.generation;
    this.frame = target;
    this.animate(target.copy(), stiffness, exiting, generation, () => {
      if (!this.isCurrent(generation)) return;
      this.running = false;
      this.reconcile();
    });
  }

  private reconcile(): void {
    if (!this.active || this.blocked || this.pressed !== 0 || this.releaseTimer >= 0) return;
    let target = this.frame.copy();
    const switching = this.side !== target.side;
    const exit = target.side * FLOATING_ACTION_EXIT;
    if (switching && (target.eveningMounted || target.returnMounted)) {
      if (this.handingOff && this.running) return;
      const outside = (!target.eveningMounted || target.eveningX === exit) &&
        (!target.returnMounted || target.returnX === exit);
      if (this.running || !outside) {
        this.handingOff = true;
        // Reuse an in-flight departure instead of restarting its 180ms clock.
        if (outside && this.running) return;
        if (target.eveningMounted) target.eveningX = exit;
        if (target.returnMounted) target.returnX = exit;
        this.commit(target, 170, true);
        return;
      }
    }
    this.handingOff = false;

    let changed = false;
    // Target offsets do not mean a running departure is already outside the viewport.
    if (!this.running) {
      if (!this.evening && target.eveningMounted && target.eveningX === exit) {
        target.eveningMounted = false; changed = true;
      }
      if (!this.returnWeek && target.returnMounted && target.returnX === exit) {
        target.returnMounted = false; changed = true;
      }
    }
    if (switching) {
      // Switch anchors only once every mounted control is outside the viewport.
      target.side = this.side;
      target.eveningX = this.side * FLOATING_ACTION_EXIT;
      target.returnX = this.side * FLOATING_ACTION_EXIT;
      changed = true;
    }
    if ((this.evening && !target.eveningMounted) || (this.returnWeek && !target.returnMounted)) {
      if (this.evening && !target.eveningMounted) {
        target.eveningMounted = true;
        target.eveningX = target.side * FLOATING_ACTION_EXIT;
      }
      if (this.returnWeek && !target.returnMounted) {
        target.returnMounted = true;
        target.returnX = target.side * FLOATING_ACTION_EXIT;
        target.returnLift = this.evening ? FLOATING_ACTION_GAP : 0;
      }
      changed = true;
    }
    if (changed) {
      this.frame = target;
      this.render(target.copy());
    }
    const eveningX = this.evening ? 0 : target.side * FLOATING_ACTION_EXIT;
    const returnX = this.returnWeek ? 0 : target.side * FLOATING_ACTION_EXIT;
    const lift = this.evening ? FLOATING_ACTION_GAP : 0;
    const moveEvening = target.eveningMounted && target.eveningX !== eveningX;
    const moveReturn = target.returnMounted && target.returnX !== returnX;
    if (moveEvening || moveReturn || target.returnLift !== lift) {
      const exiting = (moveEvening && !this.evening) || (moveReturn && !this.returnWeek);
      target = target.copy();
      target.eveningX = eveningX;
      target.returnX = returnX;
      target.returnLift = lift;
      // Replacing the native target reverses from its current presentation position.
      // Move into/out of the lower slot diagonally, without a serialized slot wait.
      this.commit(target, moveEvening || moveReturn ? 170 : 200, exiting);
    }
  }
}
