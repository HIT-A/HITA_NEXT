/** Shared time-based class selection for the home page and service card. */
export interface ClassTimeCandidate {
  id: string;
  from: number;
  to: number;
}

export interface CurrentClassSelectionResult<T extends ClassTimeCandidate> {
  current: T | undefined;
  next: T | undefined;
}

export class CurrentClassSelection {
  /** Prefer the latest-starting ongoing class; otherwise the first class starting today. */
  static find<T extends ClassTimeCandidate>(courses: T[], now: number): CurrentClassSelectionResult<T> {
    let current: T | undefined = undefined;
    let next: T | undefined = undefined;
    if (!Number.isFinite(now)) return { current, next };

    const dayEnd: Date = new Date(now);
    dayEnd.setHours(0, 0, 0, 0);
    dayEnd.setDate(dayEnd.getDate() + 1);
    const endOfToday: number = dayEnd.getTime();

    for (let i: number = 0; i < courses.length; i++) {
      const course: T = courses[i];
      if (course === undefined || course === null || !Number.isFinite(course.from) ||
        !Number.isFinite(course.to) || course.to <= course.from) {
        continue;
      }
      if (course.from <= now && course.to > now) {
        if (current === undefined || course.from > current.from ||
          (course.from === current.from && course.id < current.id)) {
          current = course;
        }
        continue;
      }
      if (course.from > now && course.from < endOfToday &&
        (next === undefined || course.from < next.from ||
          (course.from === next.from && course.id < next.id))) {
        next = course;
      }
    }
    return { current, next };
  }
}
