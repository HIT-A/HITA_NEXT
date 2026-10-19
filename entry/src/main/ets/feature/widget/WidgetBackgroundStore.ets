/**
 * WidgetBackgroundStore.ets — 服务卡片自定义背景的本地存储与烘焙。
 *
 * 选图后先按 EXIF 方向转正并限制长边，保存为草稿；用户确定取景后，按 2×2 / 2×4
 * 卡片比例各烘焙一张图片，卡片只需按 Cover 居中显示，不再做二次拉伸或裁切。
 * 状态写在 filesDir 下的 JSON 文件中，服务卡片扩展进程每次读取都是最新内容。
 */
import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  WIDGET_BG_COMPACT_OUTPUT_H,
  WIDGET_BG_COMPACT_OUTPUT_W,
  WIDGET_BG_WIDE_OUTPUT_H,
  WIDGET_BG_WIDE_OUTPUT_W,
  WidgetBackgroundBakeRegion,
  WidgetBackgroundFrame,
  WidgetBackgroundModel,
  WidgetBackgroundState
} from './WidgetBackgroundModel';

const DIR_NAME: string = 'widget-background';
const STATE_FILE: string = 'state.json';
const DRAFT_PREFIX: string = 'widget-background-draft-';
const MAX_SOURCE_EDGE: number = 2560;
// API 19 及更早版本单张卡片图片上限为 2 MB。
const MAX_CARD_IMAGE_BYTES: number = 1800 * 1024;
const TAG: string = 'WidgetBackground';

export class WidgetBackgroundSource {
  path: string = '';
  width: number = 0;
  height: number = 0;
}

export class WidgetBackgroundFiles {
  compactName: string = '';
  compactPath: string = '';
  wideName: string = '';
  widePath: string = '';
}

export class WidgetBackgroundStore {
  static dir(context: common.Context): string {
    return context.getApplicationContext().filesDir + '/' + DIR_NAME;
  }

  static load(context: common.Context): WidgetBackgroundState | undefined {
    try {
      const path = WidgetBackgroundStore.dir(context) + '/' + STATE_FILE;
      if (!fileIo.accessSync(path)) {
        return undefined;
      }
      const state = WidgetBackgroundModel.parseState(fileIo.readTextSync(path));
      if (state === undefined || !fileIo.accessSync(WidgetBackgroundStore.sourcePath(context, state))) {
        return undefined;
      }
      return state;
    } catch (_) {
      return undefined;
    }
  }

  static hasBackground(context: common.Context): boolean {
    return WidgetBackgroundStore.load(context) !== undefined;
  }

  static sourcePath(context: common.Context, state: WidgetBackgroundState): string {
    return WidgetBackgroundStore.dir(context) + '/' + state.source;
  }

  static displayUri(path: string): string {
    return 'file://' + path;
  }

  /** 发布到卡片的两张烘焙图；文件缺失时返回 undefined，卡片显示默认白底。 */
  static filesForPublish(context: common.Context): WidgetBackgroundFiles | undefined {
    const state = WidgetBackgroundStore.load(context);
    if (state === undefined) {
      return undefined;
    }
    const dir = WidgetBackgroundStore.dir(context);
    const files = new WidgetBackgroundFiles();
    files.compactName = WidgetBackgroundModel.compactName(state.revision);
    files.compactPath = dir + '/' + WidgetBackgroundStore.bakedFile('compact', state.revision);
    files.wideName = WidgetBackgroundModel.wideName(state.revision);
    files.widePath = dir + '/' + WidgetBackgroundStore.bakedFile('wide', state.revision);
    try {
      return fileIo.accessSync(files.compactPath) && fileIo.accessSync(files.widePath) ? files : undefined;
    } catch (_) {
      return undefined;
    }
  }

  /** 拉起图库，转正方向并缩小到可编辑尺寸；用户取消返回 undefined。 */
  static async pickDraft(context: common.UIAbilityContext): Promise<WidgetBackgroundSource | undefined> {
    const options = new picker.PhotoSelectOptions();
    options.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = 1;
    const picked = await new picker.PhotoViewPicker(context).select(options);
    if (picked === undefined || picked.photoUris === undefined || picked.photoUris.length === 0) {
      return undefined;
    }
    return await WidgetBackgroundStore.importDraft(context, picked.photoUris[0]);
  }

  static clearDrafts(context: common.Context, keep: string = ''): void {
    const cache = context.getApplicationContext().cacheDir;
    try {
      for (const name of fileIo.listFileSync(cache)) {
        if (name.startsWith(DRAFT_PREFIX) && cache + '/' + name !== keep) {
          WidgetBackgroundStore.unlink(cache + '/' + name);
        }
      }
    } catch (_) {
    }
  }

  /**
   * 保存取景并烘焙两种尺寸。sourcePath 可以是新草稿，也可以是已保存的源图。
   * 新文件全部写好后才替换状态文件，失败时保留原背景。
   */
  static async save(context: common.Context, sourcePath: string, sourceWidth: number, sourceHeight: number,
    compact: WidgetBackgroundFrame, wide: WidgetBackgroundFrame, veil: number): Promise<WidgetBackgroundState> {
    const dir = WidgetBackgroundStore.dir(context);
    WidgetBackgroundStore.ensureDir(dir);
    const previous = WidgetBackgroundStore.load(context);
    const state = new WidgetBackgroundState();
    state.revision = Math.max(Date.now(), previous === undefined ? 0 : previous.revision + 1);
    state.veil = veil;
    state.compact = WidgetBackgroundModel.clamp(compact, sourceWidth, sourceHeight,
      WIDGET_BG_COMPACT_OUTPUT_W, WIDGET_BG_COMPACT_OUTPUT_H);
    state.wide = WidgetBackgroundModel.clamp(wide, sourceWidth, sourceHeight,
      WIDGET_BG_WIDE_OUTPUT_W, WIDGET_BG_WIDE_OUTPUT_H);
    const created: string[] = [];
    try {
      if (previous !== undefined && sourcePath === WidgetBackgroundStore.sourcePath(context, previous)) {
        state.source = previous.source;
      } else {
        const extension = sourcePath.toLowerCase().endsWith('.png') ? '.png' : '.jpg';
        state.source = 'source-' + state.revision.toString() + extension;
        fileIo.copyFileSync(sourcePath, dir + '/' + state.source);
        created.push(dir + '/' + state.source);
      }
      const source = dir + '/' + state.source;
      const compactPath = dir + '/' + WidgetBackgroundStore.bakedFile('compact', state.revision);
      created.push(compactPath);
      const size = await WidgetBackgroundStore.bake(source, state.compact,
        WIDGET_BG_COMPACT_OUTPUT_W, WIDGET_BG_COMPACT_OUTPUT_H, veil, compactPath);
      state.sourceWidth = size.width;
      state.sourceHeight = size.height;
      const widePath = dir + '/' + WidgetBackgroundStore.bakedFile('wide', state.revision);
      created.push(widePath);
      await WidgetBackgroundStore.bake(source, state.wide,
        WIDGET_BG_WIDE_OUTPUT_W, WIDGET_BG_WIDE_OUTPUT_H, veil, widePath);
      WidgetBackgroundStore.writeState(dir, state);
    } catch (error) {
      for (const path of created) {
        WidgetBackgroundStore.unlink(path);
      }
      throw error as Error;
    }
    const keep: string[] = [STATE_FILE, state.source, WidgetBackgroundStore.bakedFile('compact', state.revision),
      WidgetBackgroundStore.bakedFile('wide', state.revision)];
    WidgetBackgroundStore.prune(dir, keep);
    WidgetBackgroundStore.clearDrafts(context);
    return state;
  }

  static remove(context: common.Context): void {
    const dir = WidgetBackgroundStore.dir(context);
    // 先删状态文件，正在刷新的卡片随即回到默认白底。
    WidgetBackgroundStore.unlink(dir + '/' + STATE_FILE);
    WidgetBackgroundStore.prune(dir, []);
    WidgetBackgroundStore.clearDrafts(context);
  }

  private static async importDraft(context: common.Context, uri: string): Promise<WidgetBackgroundSource> {
    const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    let imageSource: image.ImageSource | undefined = undefined;
    let pixels: image.PixelMap | undefined = undefined;
    try {
      imageSource = image.createImageSource(file.fd);
      const info = await imageSource.getImageInfo();
      const orientation = await WidgetBackgroundStore.orientation(imageSource);
      const ratio = Math.min(1, MAX_SOURCE_EDGE / Math.max(info.size.width, info.size.height));
      const desired: image.Size = {
        width: Math.max(1, Math.round(info.size.width * ratio)),
        height: Math.max(1, Math.round(info.size.height * ratio))
      };
      pixels = await imageSource.createPixelMap({
        editable: true,
        desiredSize: desired,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      });
      await WidgetBackgroundStore.applyOrientation(pixels, orientation);
      const decoded = pixels.getImageInfoSync();
      const alpha = decoded.alphaType !== image.AlphaType.OPAQUE;
      const result = new WidgetBackgroundSource();
      result.path = context.getApplicationContext().cacheDir + '/' + DRAFT_PREFIX + Date.now().toString() +
        (alpha ? '.png' : '.jpg');
      result.width = decoded.size.width;
      result.height = decoded.size.height;
      await WidgetBackgroundStore.pack(pixels, result.path, alpha ? 'image/png' : 'image/jpeg', 92);
      // Keep the previous draft until the new one is complete; the editor may still show it.
      WidgetBackgroundStore.clearDrafts(context, result.path);
      hilog.info(0x0000, TAG, 'draft %{public}dx%{public}d orientation=%{public}d alpha=%{public}d',
        result.width, result.height, orientation, decoded.alphaType);
      return result;
    } finally {
      if (pixels !== undefined) {
        await pixels.release();
      }
      if (imageSource !== undefined) {
        await imageSource.release();
      }
      fileIo.closeSync(file);
    }
  }

  private static async orientation(source: image.ImageSource): Promise<number> {
    try {
      return WidgetBackgroundModel.orientationCode(await source.getImageProperty(image.PropertyKey.ORIENTATION));
    } catch (_) {
      // PNG、WebP 或没有 EXIF 的图片按原方向处理。
      return 1;
    }
  }

  /** 解码结果保持原始像素方向，这里按 EXIF 转正，保证预览、草稿和卡片一致。 */
  private static async applyOrientation(pixels: image.PixelMap, code: number): Promise<void> {
    if (code === 2) {
      await pixels.flip(true, false);
    } else if (code === 3) {
      await pixels.rotate(180);
    } else if (code === 4) {
      await pixels.flip(false, true);
    } else if (code === 5) {
      await pixels.rotate(90);
      await pixels.flip(true, false);
    } else if (code === 6) {
      await pixels.rotate(90);
    } else if (code === 7) {
      await pixels.rotate(270);
      await pixels.flip(true, false);
    } else if (code === 8) {
      await pixels.rotate(270);
    }
  }

  /** 白底合成 → 白色蒙版 → JPEG；返回源图实际解码尺寸。 */
  private static async bake(sourcePath: string, frame: WidgetBackgroundFrame, outW: number, outH: number,
    veil: number, destPath: string): Promise<image.Size> {
    const file = fileIo.openSync(sourcePath, fileIo.OpenMode.READ_ONLY);
    let imageSource: image.ImageSource | undefined = undefined;
    let piece: image.PixelMap | undefined = undefined;
    let output: image.PixelMap | undefined = undefined;
    try {
      imageSource = image.createImageSource(file.fd);
      const info = await imageSource.getImageInfo();
      const region: WidgetBackgroundBakeRegion = WidgetBackgroundModel.bakeRegion(frame,
        info.size.width, info.size.height, outW, outH);
      const outBuffer = new ArrayBuffer(outW * outH * 4);
      const canvas = new Uint8Array(outBuffer);
      canvas.fill(255);
      let format: image.PixelMapFormat = image.PixelMapFormat.RGBA_8888;
      if (!region.empty) {
        piece = await imageSource.createPixelMap({
          desiredRegion: { x: region.srcX, y: region.srcY, size: { width: region.srcW, height: region.srcH } },
          desiredSize: { width: region.destW, height: region.destH },
          cropAndScaleStrategy: image.CropAndScaleStrategy.CROP_FIRST,
          desiredPixelFormat: image.PixelMapFormat.RGBA_8888
        });
        const pieceInfo = piece.getImageInfoSync();
        if (pieceInfo.pixelFormat !== image.PixelMapFormat.RGBA_8888 &&
          pieceInfo.pixelFormat !== image.PixelMapFormat.BGRA_8888) {
          throw new Error('Unsupported pixel format ' + pieceInfo.pixelFormat.toString());
        }
        format = pieceInfo.pixelFormat;
        const buffer = new ArrayBuffer(piece.getPixelBytesNumber());
        await piece.readPixelsToBuffer(buffer);
        WidgetBackgroundStore.composite(new Uint8Array(buffer), pieceInfo, region, canvas, outW, outH);
      }
      WidgetBackgroundStore.applyVeil(canvas, veil);
      output = await image.createPixelMap(outBuffer, {
        size: { width: outW, height: outH },
        srcPixelFormat: format,
        pixelFormat: format,
        alphaType: image.AlphaType.OPAQUE
      });
      await WidgetBackgroundStore.pack(output, destPath, 'image/jpeg', 90);
      if (fileIo.statSync(destPath).size > MAX_CARD_IMAGE_BYTES) {
        await WidgetBackgroundStore.pack(output, destPath, 'image/jpeg', 75);
      }
      return info.size;
    } finally {
      if (output !== undefined) {
        await output.release();
      }
      if (piece !== undefined) {
        await piece.release();
      }
      if (imageSource !== undefined) {
        await imageSource.release();
      }
      fileIo.closeSync(file);
    }
  }

  /** 把解码后的可见区域按白底合成到输出画布；RGBA/BGRA 的颜色通道对白底合成是对称的。 */
  private static composite(src: Uint8Array, info: image.ImageInfo, region: WidgetBackgroundBakeRegion,
    canvas: Uint8Array, outW: number, outH: number): void {
    const width = Math.min(info.size.width, outW - region.destX);
    const height = Math.min(info.size.height, outH - region.destY);
    const stride = info.stride > 0 ? info.stride : info.size.width * 4;
    const opaque = info.alphaType === image.AlphaType.OPAQUE;
    const premultiplied = info.alphaType === image.AlphaType.PREMUL;
    for (let y = 0; y < height; y++) {
      let s = y * stride;
      let d = ((region.destY + y) * outW + region.destX) * 4;
      for (let x = 0; x < width; x++) {
        const a = opaque ? 255 : src[s + 3];
        for (let c = 0; c < 3; c++) {
          const value = src[s + c];
          canvas[d + c] = a === 255 ? value : (premultiplied ?
            Math.min(255, value + 255 - a) : Math.round((value * a + 255 * (255 - a)) / 255));
        }
        canvas[d + 3] = 255;
        s += 4;
        d += 4;
      }
    }
  }

  private static applyVeil(canvas: Uint8Array, veil: number): void {
    if (veil <= 0) {
      return;
    }
    const table = new Uint8Array(256);
    for (let value = 0; value < 256; value++) {
      table[value] = WidgetBackgroundModel.veilChannel(value, veil);
    }
    for (let i = 0; i < canvas.length; i += 4) {
      canvas[i] = table[canvas[i]];
      canvas[i + 1] = table[canvas[i + 1]];
      canvas[i + 2] = table[canvas[i + 2]];
    }
  }

  private static async pack(pixels: image.PixelMap, path: string, format: string, quality: number): Promise<void> {
    const packer = image.createImagePacker();
    const file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      await packer.packToFile(pixels, file.fd, { format: format, quality: quality });
    } finally {
      fileIo.closeSync(file);
      await packer.release();
    }
  }

  private static writeState(dir: string, state: WidgetBackgroundState): void {
    const temp = dir + '/' + STATE_FILE + '.tmp';
    const file = fileIo.openSync(temp, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, JSON.stringify(state));
    } finally {
      fileIo.closeSync(file);
    }
    fileIo.renameSync(temp, dir + '/' + STATE_FILE);
  }

  private static bakedFile(kind: string, revision: number): string {
    return kind + '-' + revision.toString() + '.jpg';
  }

  private static ensureDir(dir: string): void {
    if (!fileIo.accessSync(dir)) {
      fileIo.mkdirSync(dir, true);
    }
  }

  private static prune(dir: string, keep: string[]): void {
    try {
      if (!fileIo.accessSync(dir)) {
        return;
      }
      for (const name of fileIo.listFileSync(dir)) {
        if (!keep.includes(name)) {
          WidgetBackgroundStore.unlink(dir + '/' + name);
        }
      }
    } catch (_) {
    }
  }

  private static unlink(path: string): void {
    try {
      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path);
      }
    } catch (_) {
    }
  }
}
