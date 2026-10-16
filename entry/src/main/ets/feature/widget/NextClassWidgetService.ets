import { common } from '@kit.AbilityKit';
import { formBindingData, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { RdbHelper } from '../../common/db/RdbHelper';
import { EasEventItem, EasTimetable } from '../../common/model/timetable/TimetableModels';
import { ScheduleChangeSignal } from '../../common/util/ScheduleChangeSignal';
import { TimetableSelectionStore } from '../timetable/data/TimetableSelectionStore';
import { TimetableResolver } from '../timetable/data/TimetableResolver';
import { NextClassModel, NextClassSnapshot } from './NextClassModel';

export class NextClassWidgetService {
  private static context: common.Context | undefined = undefined;
  private static timer: number = -1;
  private static revision: number = 0;
  private static publishing: boolean = false;
  private static pending: boolean = false;

  static attach(context: common.Context): void {
    NextClassWidgetService.context = context.getApplicationContext();
    ScheduleChangeSignal.listener = (): void => NextClassWidgetService.scheduleRefresh();
    NextClassWidgetService.scheduleRefresh();
  }

  static scheduleRefresh(): void {
    NextClassWidgetService.revision++;
    if (NextClassWidgetService.timer !== -1) clearTimeout(NextClassWidgetService.timer);
    // Imports contain many successful writes; publish only the settled schedule.
    NextClassWidgetService.timer = setTimeout((): void => {
      NextClassWidgetService.timer = -1;
      void NextClassWidgetService.refreshAll();
    }, 300);
  }

  static async load(context: common.Context): Promise<NextClassSnapshot> {
    try {
      const rdb = RdbHelper.getInstance();
      await rdb.init(context);
      const selection = TimetableSelectionStore.getInstance();
      await selection.init(context);
      const selectedId = await selection.load();
      let timetable: EasTimetable | undefined = selectedId.length > 0 ?
        await rdb.getTimetableById(selectedId) : undefined;
      if (timetable === undefined) timetable = await TimetableResolver.getForDisplay(rdb);
      const events: EasEventItem[] = timetable === undefined ? [] : await rdb.getEventsOfTimetable(timetable.id);
      return NextClassModel.snapshot(events, timetable !== undefined);
    } catch (error) {
      hilog.warn(0x0000, 'NextClassWidget', 'load failed: %{public}s', String(error));
      const snapshot = new NextClassSnapshot();
      snapshot.dataState = 'error';
      return snapshot;
    }
  }

  static async refreshForm(context: common.Context, formId: string): Promise<void> {
    let revision: number;
    let snapshot: NextClassSnapshot;
    do {
      revision = NextClassWidgetService.revision;
      snapshot = await NextClassWidgetService.load(context);
    } while (revision !== NextClassWidgetService.revision);
    await NextClassWidgetService.publish(formId, snapshot);
  }

  static async refreshAll(): Promise<void> {
    NextClassWidgetService.pending = true;
    if (NextClassWidgetService.publishing || NextClassWidgetService.context === undefined) return;
    NextClassWidgetService.publishing = true;
    try {
      while (NextClassWidgetService.pending) {
        NextClassWidgetService.pending = false;
        const revision = NextClassWidgetService.revision;
        const forms = (await formProvider.getPublishedRunningFormInfos()).filter((form): boolean =>
          form.moduleName === 'entry' && form.formName === 'NextClassCard');
        if (forms.length === 0) continue;
        const snapshot = await NextClassWidgetService.load(NextClassWidgetService.context);
        if (revision !== NextClassWidgetService.revision) {
          NextClassWidgetService.pending = true;
          continue;
        }
        for (const form of forms) {
          if (revision !== NextClassWidgetService.revision) {
            NextClassWidgetService.pending = true;
            break;
          }
          await NextClassWidgetService.publish(form.formId, snapshot);
        }
      }
    } catch (error) {
      hilog.warn(0x0000, 'NextClassWidget', 'refresh failed: %{public}s', String(error));
    } finally {
      NextClassWidgetService.publishing = false;
    }
  }

  private static async publish(formId: string, snapshot: NextClassSnapshot): Promise<void> {
    try {
      await formProvider.updateForm(formId, formBindingData.createFormBindingData(snapshot));
    } catch (error) {
      // A card may have been removed while the local database was loading.
      hilog.warn(0x0000, 'NextClassWidget', 'publish failed: %{public}s', String(error));
    }
  }
}
