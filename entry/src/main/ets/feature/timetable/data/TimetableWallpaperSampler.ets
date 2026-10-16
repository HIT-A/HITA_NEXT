import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { TimetableBackdropPixels } from '../../../common/theme/TimetableBackdrop';

export class TimetableWallpaperSampler {
  static async read(path: string): Promise<TimetableBackdropPixels | undefined> {
    if (path.length === 0) return undefined;
    let file: fileIo.File | undefined = undefined;
    let source: image.ImageSource | undefined = undefined;
    let pixels: image.PixelMap | undefined = undefined;
    try {
      file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      source = image.createImageSource(file.fd);
      const original = await source.getImageInfo();
      const scale = Math.min(1, 96 / Math.max(original.size.width, original.size.height));
      pixels = await source.createPixelMap({
        desiredSize: {
          width: Math.max(1, Math.round(original.size.width * scale)),
          height: Math.max(1, Math.round(original.size.height * scale))
        },
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
        desiredDynamicRange: image.DecodingDynamicRange.SDR
      });
      const info = await pixels.getImageInfo();
      const buffer = new ArrayBuffer(pixels.getPixelBytesNumber());
      await pixels.readPixelsToBuffer(buffer);
      return new TimetableBackdropPixels(info.size.width, info.size.height, pixels.getBytesNumberPerRow(),
        new Uint8Array(buffer), info.alphaType === image.AlphaType.PREMUL);
    } catch (_) {
      return undefined;
    } finally {
      try { if (pixels !== undefined) await pixels.release(); } catch (_) {}
      try { if (source !== undefined) await source.release(); } catch (_) {}
      try { if (file !== undefined) fileIo.closeSync(file); } catch (_) {}
    }
  }
}
