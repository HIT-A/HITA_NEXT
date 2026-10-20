/** Persists the timetable selected for the main timetable/today views. */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { TimetableTheme } from '../../../common/theme/TimetableTheme';
import { ScheduleChangeSignal } from '../../../common/util/ScheduleChangeSignal';

const STORE_NAME: string = 'hitanext_store';
const ACTIVE_TIMETABLE_KEY: string = 'active_timetable_id';
const TEXT_COLOR_KEY: string = 'timetable_text_color';
const CUSTOM_TEXT_COLOR_KEY: string = 'timetable_text_color_custom';

export class TimetableSelectionStore {
  private static instance: TimetableSelectionStore | undefined = undefined;
  private store: preferences.Preferences | undefined = undefined;

  static getInstance(): TimetableSelectionStore {
    if (TimetableSelectionStore.instance === undefined) {
      TimetableSelectionStore.instance = new TimetableSelectionStore();
    }
    return TimetableSelectionStore.instance;
  }

  async init(context: common.Context): Promise<void> {
    try {
      this.store = await preferences.getPreferences(context, { name: STORE_NAME });
    } catch (e) {
      this.store = undefined;
    }
  }

  async load(): Promise<string> {
    if (this.store === undefined) {
      return '';
    }
    try {
      const raw: preferences.ValueType = await this.store.get(ACTIVE_TIMETABLE_KEY, '');
      return raw === undefined || raw === null ? '' : String(raw);
    } catch (e) {
      return '';
    }
  }

  /**
   * Reads the selection from disk for the service card process. Preferences are cached per process, so a
   * cached instance there never sees later selections saved by the app. Do not call this in the app
   * process: it would detach the instance other stores share.
   */
  static async loadLatest(context: common.Context): Promise<string> {
    try {
      preferences.removePreferencesFromCacheSync(context, { name: STORE_NAME });
      const store: preferences.Preferences = await preferences.getPreferences(context, { name: STORE_NAME });
      const raw: preferences.ValueType = await store.get(ACTIVE_TIMETABLE_KEY, '');
      return raw === undefined || raw === null ? '' : String(raw);
    } catch (e) {
      return '';
    }
  }

  async save(id: string): Promise<void> {
    if (this.store === undefined || id.length === 0) {
      return;
    }
    try {
      await this.store.put(ACTIVE_TIMETABLE_KEY, id);
      await this.store.flush();
      ScheduleChangeSignal.notify();
    } catch (e) {
    }
  }

  async clear(): Promise<void> {
    if (this.store === undefined) {
      return;
    }
    try {
      await this.store.delete(ACTIVE_TIMETABLE_KEY);
      await this.store.flush();
      ScheduleChangeSignal.notify();
    } catch (e) {
    }
  }

  async clearIf(id: string): Promise<void> {
    if (id.length === 0) {
      return;
    }
    const current: string = await this.load();
    if (current === id) {
      await this.clear();
    }
  }

  async loadTextColor(fallback: string): Promise<string> {
    if (this.store === undefined) {
      return fallback;
    }
    try {
      const raw: preferences.ValueType = await this.store.get(TEXT_COLOR_KEY, fallback);
      const color: string = raw === undefined || raw === null ? fallback : String(raw);
      const custom = await this.store.get(CUSTOM_TEXT_COLOR_KEY, false);
      // Older versions saved the default theme color as if it were a manual choice.
      if (color.toUpperCase() === TimetableTheme.DEFAULT_TEXT && custom !== true) return TimetableTheme.AUTO_TEXT;
      return color === TimetableTheme.AUTO_TEXT || /^#[0-9A-Fa-f]{6}$/.test(color) ? color : fallback;
    } catch (e) {
      return fallback;
    }
  }

  async saveTextColor(color: string): Promise<void> {
    if (this.store === undefined || (color !== TimetableTheme.AUTO_TEXT && !/^#[0-9A-Fa-f]{6}$/.test(color))) {
      throw new Error('Text color store unavailable or invalid color');
    }
    const previous = await this.store.get(TEXT_COLOR_KEY, TimetableTheme.AUTO_TEXT);
    const wasCustom = await this.store.get(CUSTOM_TEXT_COLOR_KEY, false);
    try {
      await this.store.put(TEXT_COLOR_KEY, color);
      await this.store.put(CUSTOM_TEXT_COLOR_KEY, color !== TimetableTheme.AUTO_TEXT);
      await this.store.flush();
    } catch (_) {
      await this.store.put(TEXT_COLOR_KEY, previous);
      await this.store.put(CUSTOM_TEXT_COLOR_KEY, wasCustom);
      throw new Error('Text color save failed');
    }
  }
}
