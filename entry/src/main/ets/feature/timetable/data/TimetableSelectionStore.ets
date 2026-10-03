/** Persists the timetable selected for the main timetable/today views. */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const STORE_NAME: string = 'hitanext_store';
const ACTIVE_TIMETABLE_KEY: string = 'active_timetable_id';
const TEXT_COLOR_KEY: string = 'timetable_text_color';

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

  async save(id: string): Promise<void> {
    if (this.store === undefined || id.length === 0) {
      return;
    }
    try {
      await this.store.put(ACTIVE_TIMETABLE_KEY, id);
      await this.store.flush();
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
      return color.length > 0 ? color : fallback;
    } catch (e) {
      return fallback;
    }
  }

  async saveTextColor(color: string): Promise<void> {
    if (this.store === undefined || color.length === 0) {
      return;
    }
    try {
      await this.store.put(TEXT_COLOR_KEY, color);
      await this.store.flush();
    } catch (e) {
    }
  }
}
