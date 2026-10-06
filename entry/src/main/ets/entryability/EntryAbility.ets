import { AbilityConstant, common, Configuration, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { display, window } from '@kit.ArkUI';
import {
  KEYBOARD_INSET_FALLBACK,
  KEYBOARD_INSET_KEY,
  NAV_BAR_INSET_FALLBACK,
  NAV_BAR_INSET_KEY,
  STATUS_BAR_INSET_FALLBACK,
  STATUS_BAR_INSET_KEY
} from '../common/theme/StatusBarInset';
import { ClassReminderScheduler } from '../feature/timetable/data/ClassReminderScheduler';
import { ClassReminderStore } from '../feature/timetable/data/ClassReminderStore';
import { AppearanceStore } from '../common/theme/AppearanceStore';

const DOMAIN: number = 0x0000;
const TAG: string = 'HitaNEXT';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'Ability onCreate');
    AppStorage.setOrCreate(STATUS_BAR_INSET_KEY, STATUS_BAR_INSET_FALLBACK);
    AppStorage.setOrCreate(NAV_BAR_INSET_KEY, NAV_BAR_INSET_FALLBACK);
    AppStorage.setOrCreate(KEYBOARD_INSET_KEY, KEYBOARD_INSET_FALLBACK);
    AppearanceStore.getInstance().initialize(this.context);
    void this.restoreClassReminders();
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.configureSystemBars(windowStage);
    // 首屏直接进入主界面。教务登录从主界面的会话入口按需打开。
    windowStage.loadContent('pages/Home', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'Succeeded in loading content.');
      AppearanceStore.getInstance().onContentReady();
    });
  }

  private async configureSystemBars(windowStage: window.WindowStage): Promise<void> {
    try {
      const mainWindow: window.Window = await windowStage.getMainWindow();
      await mainWindow.setWindowLayoutFullScreen(true);
      AppearanceStore.getInstance().attachWindow(mainWindow);
      this.captureSystemInsets(mainWindow);
      this.captureKeyboardInset(mainWindow);
      mainWindow.on('avoidAreaChange', (data: window.AvoidAreaOptions) => {
        if (data.type === window.AvoidAreaType.TYPE_SYSTEM ||
          data.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
          this.captureSystemInsets(mainWindow);
        }
        if (data.type === window.AvoidAreaType.TYPE_KEYBOARD) {
          this.captureKeyboardInset(mainWindow);
        }
      });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'Failed to configure system bars: %{public}s', String(e));
    }
  }

  private captureSystemInsets(mainWindow: window.Window): void {
    let topVp: number = STATUS_BAR_INSET_FALLBACK;
    let bottomVp: number = NAV_BAR_INSET_FALLBACK;
    try {
      const density: number = display.getDefaultDisplaySync().densityPixels;
      const systemArea: window.AvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const indicatorArea: window.AvoidArea =
        mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const topPx: number = systemArea.topRect.height;
      const bottomPx: number = Math.max(systemArea.bottomRect.height, indicatorArea.bottomRect.height);
      if (topPx > 0 && density > 0) {
        topVp = topPx / density;
      }
      if (bottomPx > 0 && density > 0) {
        bottomVp = bottomPx / density;
      }
    } catch (e) {
    }
    if (topVp < 24) {
      topVp = STATUS_BAR_INSET_FALLBACK;
    }
    if (bottomVp < 20) {
      bottomVp = NAV_BAR_INSET_FALLBACK;
    }
    AppStorage.setOrCreate(STATUS_BAR_INSET_KEY, topVp);
    AppStorage.setOrCreate(NAV_BAR_INSET_KEY, bottomVp);
  }

  private captureKeyboardInset(mainWindow: window.Window): void {
    let keyboardVp: number = KEYBOARD_INSET_FALLBACK;
    try {
      const density: number = display.getDefaultDisplaySync().densityPixels;
      const keyboardArea: window.AvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_KEYBOARD);
      const keyboardPx: number = keyboardArea.bottomRect.height;
      if (keyboardPx > 0 && density > 0) {
        keyboardVp = keyboardPx / density;
      }
    } catch (_) {
      keyboardVp = KEYBOARD_INSET_FALLBACK;
    }
    AppStorage.setOrCreate(KEYBOARD_INSET_KEY, keyboardVp);
  }

  onWindowStageDestroy(): void {
    AppearanceStore.getInstance().detachWindow();
    hilog.info(DOMAIN, TAG, 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'Ability onForeground');
    void this.restoreClassReminders();
    AppearanceStore.getInstance().onConfigurationUpdate(this.context.config);
  }

  onConfigurationUpdate(config: Configuration): void {
    AppearanceStore.getInstance().onConfigurationUpdate(config);
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'Ability onBackground');
  }

  private async restoreClassReminders(): Promise<void> {
    try {
      await ClassReminderStore.getInstance().init(this.context);
      await ClassReminderScheduler.restore(this.context as common.UIAbilityContext);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'restoreClassReminders %{public}s', String(e));
    }
  }
}
