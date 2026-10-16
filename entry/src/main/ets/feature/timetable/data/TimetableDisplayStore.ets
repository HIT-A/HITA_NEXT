import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { TimetableDisplayOptions } from './TimetableDisplayOptions';

const DISPLAY_KEY: string = 'timetable_display_options';

export class TimetableDisplayStore {
  private static instance: TimetableDisplayStore | undefined = undefined;
  private store: preferences.Preferences | undefined = undefined;
  private writes: Promise<void> = Promise.resolve();

  static getInstance(): TimetableDisplayStore {
    if (TimetableDisplayStore.instance === undefined) TimetableDisplayStore.instance = new TimetableDisplayStore();
    return TimetableDisplayStore.instance;
  }

  async init(context: common.Context): Promise<void> {
    if (this.store === undefined) {
      this.store = await preferences.getPreferences(context, { name: 'hitanext_store' });
    }
  }

  async load(): Promise<TimetableDisplayOptions> {
    const raw = await this.store?.get(DISPLAY_KEY, '');
    return TimetableDisplayOptions.parse(typeof raw === 'string' ? raw : '');
  }

  save(options: TimetableDisplayOptions): Promise<void> {
    // Snapshot each request before queueing; a slow flush cannot overwrite a newer choice.
    const value = JSON.stringify(TimetableDisplayOptions.parse(JSON.stringify(options)));
    const write = this.writes.then(async () => {
      if (this.store === undefined) throw new Error('Display settings store unavailable');
      const previous = await this.store.get(DISPLAY_KEY, '');
      try {
        await this.store.put(DISPLAY_KEY, value);
        await this.store.flush();
      } catch (_) {
        await this.store.put(DISPLAY_KEY, previous);
        throw new Error('Display settings save failed');
      }
    });
    this.writes = write.catch(() => {});
    return write;
  }
}
