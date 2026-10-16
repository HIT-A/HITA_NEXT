/** Notify projections only after a successful local write; failures never fail the write itself. */
export class ScheduleChangeSignal {
  static listener: (() => void) | undefined = undefined;

  static notify(): void {
    try { ScheduleChangeSignal.listener?.(); } catch (_) {}
  }
}
