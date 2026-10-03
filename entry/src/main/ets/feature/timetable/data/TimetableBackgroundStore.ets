/**
 * TimetableBackgroundStore.ets — 时间表全屏背景图：从图库选取后拷入应用沙箱并复用。
 */
import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';

const FILE_NAME: string = 'timetable-background.jpg';

export class TimetableBackgroundStore {
  static destPath(context: common.Context): string {
    return context.filesDir + '/' + FILE_NAME;
  }

  static loadPath(context: common.Context): string {
    const dest: string = TimetableBackgroundStore.destPath(context);
    try {
      if (fileIo.accessSync(dest)) {
        return dest;
      }
    } catch (e) {
    }
    return '';
  }

  static toDisplayUri(path: string): string {
    return 'file://' + path + '#' + Date.now().toString();
  }

  /** 拉起图库；用户取消返回空串。 */
  static async pickAndSave(context: common.UIAbilityContext): Promise<string> {
    const options: picker.PhotoSelectOptions = new picker.PhotoSelectOptions();
    options.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = 1;
    const picked: picker.PhotoSelectResult = await new picker.PhotoViewPicker(context).select(options);
    if (picked === undefined || picked.photoUris === undefined || picked.photoUris.length === 0) {
      return '';
    }
    const dest: string = TimetableBackgroundStore.destPath(context);
    const srcFile: fileIo.File = fileIo.openSync(picked.photoUris[0], fileIo.OpenMode.READ_ONLY);
    try {
      const destFile: fileIo.File = fileIo.openSync(dest,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        fileIo.copyFileSync(srcFile.fd, destFile.fd);
      } finally {
        fileIo.closeSync(destFile);
      }
    } finally {
      fileIo.closeSync(srcFile);
    }
    return dest;
  }

  static remove(context: common.Context): void {
    const dest: string = TimetableBackgroundStore.destPath(context);
    try {
      if (fileIo.accessSync(dest)) {
        fileIo.unlinkSync(dest);
      }
    } catch (e) {
    }
  }
}
