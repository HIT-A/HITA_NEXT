import { EasEventItem, EasEventType } from '../../../common/model/timetable/TimetableModels';

export const EVENING_START_MINUTES: number = 18 * 60 + 30;

/** Input is the displayed week's events, not today's events or the whole semester. */
export function hasEveningCourse(weekEvents: EasEventItem[]): boolean {
  return weekEvents.some((event: EasEventItem): boolean => {
    if (event.type !== EasEventType.CLASS) return false;
    const start = new Date(event.from);
    return start.getHours() * 60 + start.getMinutes() >= EVENING_START_MINUTES;
  });
}

export function eveningHintVisible(hasCourse: boolean, offset: number, maxOffset: number): boolean {
  return hasCourse && maxOffset > 64 && offset < maxOffset - 64;
}
