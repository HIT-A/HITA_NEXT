import { common2D, drawing } from '@kit.ArkGraphics2D';
import { image } from '@kit.ImageKit';
import {
  DeleteDissolveMesh, DeleteGrainFrame, writeDeleteGrainFrame, deleteSourceDissolve,
  DELETE_DISSOLVE_DURATION, DELETE_DISSOLVE_PADDING, DELETE_SOURCE_END,
  DELETE_GLOW_SCALE, DELETE_GLOW_ALPHA
} from './DeleteDissolve';

const OPACITY_LEVELS: number = 12;
const MASK_LEVELS: number = 24;
const MAX_PALETTE: number = 8;
const GRAIN_WIDTHS: number[] = [1.0, 1.5, 2.0, 2.7];

class DustBatch {
  points: common2D.Point[] = [];
  glowPoints: common2D.Point[] = [];
  pen: drawing.Pen = new drawing.Pen();
  glowPen: drawing.Pen = new drawing.Pen();

  constructor(color: number, alpha: number, width: number) {
    this.pen.setColor(color);
    this.pen.setAlpha(alpha);
    this.pen.setStrokeWidth(width);
    this.pen.setAntiAlias(true);
    this.pen.setCapStyle(drawing.CapStyle.ROUND_CAP);
    this.glowPen.setColor(color);
    this.glowPen.setAlpha(Math.round(alpha * DELETE_GLOW_ALPHA));
    this.glowPen.setStrokeWidth(width * DELETE_GLOW_SCALE);
    this.glowPen.setAntiAlias(true);
    this.glowPen.setCapStyle(drawing.CapStyle.ROUND_CAP);
  }
}

/** Native point batches replace thousands of Canvas style changes and rectangle commands per frame. */
export class DeleteDissolveRenderer {
  private palette: number[] = [];
  private paletteIndices: number[] = [];
  private points: common2D.Point[] = [];
  private maskPoints: common2D.Point[] = [];
  private batches: DustBatch[] = [];
  private masks: common2D.Point[][] = [];
  private maskPens: drawing.Pen[] = [];
  private imageBrush: drawing.Brush = new drawing.Brush();
  private scratch: DeleteGrainFrame = { x: 0, y: 0, radius: 0, alpha: 0 };
  private bounds: common2D.Rect;
  private maskScaleY: number;
  private mesh: DeleteDissolveMesh;
  private snapshot: image.PixelMap;

  constructor(mesh: DeleteDissolveMesh, snapshot: image.PixelMap) {
    this.mesh = mesh;
    this.snapshot = snapshot;
    const padding: number = DELETE_DISSOLVE_PADDING;
    const width: number = mesh.width / mesh.columns;
    const height: number = mesh.height / mesh.rows;
    this.maskScaleY = height / width;
    this.bounds = { left: padding, top: padding, right: padding + mesh.width, bottom: padding + mesh.height };
    this.imageBrush.setColor(0xffffffff);
    for (const grain of mesh.grains) {
      // Invisible corner pixels must not consume the limited source-color palette.
      this.paletteIndices.push(grain.alpha >= 0.03 ? this.paletteIndex(grain.argb) : 0);
      this.points.push({ x: 0, y: 0 });
      this.maskPoints.push({
        x: padding + grain.x + width / 2,
        y: (padding + grain.y + height / 2) / this.maskScaleY
      });
    }
    for (const color of this.palette) {
      for (let opacity: number = 0; opacity < OPACITY_LEVELS; opacity++) {
        const alpha: number = Math.round((opacity + 0.5) / OPACITY_LEVELS * 255);
        for (const width of GRAIN_WIDTHS) {
          this.batches.push(new DustBatch(color, alpha, width));
        }
      }
    }
    for (let level: number = 0; level < MASK_LEVELS; level++) {
      const pen: drawing.Pen = new drawing.Pen();
      pen.setColor(0xff000000);
      pen.setAlpha(Math.round(level / (MASK_LEVELS - 1) * 255));
      pen.setStrokeWidth(width + 0.25);
      pen.setCapStyle(drawing.CapStyle.SQUARE_CAP);
      pen.setBlendMode(drawing.BlendMode.DST_OUT);
      this.maskPens.push(pen);
      this.masks.push([]);
    }
  }

  private paletteIndex(color: number): number {
    let closest: number = 0;
    let distance: number = Number.MAX_VALUE;
    for (let i: number = 0; i < this.palette.length; i++) {
      const other: number = this.palette[i];
      const red: number = ((color >>> 16) & 255) - ((other >>> 16) & 255);
      const green: number = ((color >>> 8) & 255) - ((other >>> 8) & 255);
      const blue: number = (color & 255) - (other & 255);
      const candidate: number = red * red + green * green + blue * blue;
      if (candidate < distance) {
        distance = candidate;
        closest = i;
      }
    }
    if (distance > 1600 && this.palette.length < MAX_PALETTE) {
      this.palette.push(color);
      return this.palette.length - 1;
    }
    return closest;
  }

  draw(canvas: drawing.Canvas, elapsed: number, density: number): void {
    canvas.clear(0x00000000);
    if (elapsed >= DELETE_DISSOLVE_DURATION) {
      return;
    }
    const padding: number = DELETE_DISSOLVE_PADDING;
    for (const batch of this.batches) {
      batch.points.length = 0;
      batch.glowPoints.length = 0;
    }
    for (const mask of this.masks) {
      mask.length = 0;
    }
    for (let i: number = 0; i < this.mesh.grains.length; i++) {
      const grain = this.mesh.grains[i];
      if (elapsed < DELETE_SOURCE_END && elapsed > grain.birth && grain.alpha > 0) {
        const level: number = Math.round(deleteSourceDissolve(grain, elapsed) * (MASK_LEVELS - 1));
        if (level > 0) {
          this.masks[level].push(this.maskPoints[i]);
        }
      }
      if (grain.alpha < 0.03 || elapsed <= grain.birth || elapsed >= grain.birth + grain.lifetime) {
        continue;
      }
      writeDeleteGrainFrame(grain, elapsed, this.scratch);
      if (this.scratch.alpha < 0.02) {
        continue;
      }
      const point: common2D.Point = this.points[i];
      point.x = padding + this.scratch.x;
      point.y = padding + this.scratch.y;
      const opacity: number = Math.min(OPACITY_LEVELS - 1, Math.floor(this.scratch.alpha * OPACITY_LEVELS));
      const diameter: number = this.scratch.radius * 2;
      const size: number = diameter < 1.25 ? 0 : (diameter < 1.75 ? 1 : (diameter < 2.35 ? 2 : 3));
      const batch: DustBatch =
        this.batches[(this.paletteIndices[i] * OPACITY_LEVELS + opacity) * GRAIN_WIDTHS.length + size];
      batch.points.push(point);
      if (grain.glow) {
        batch.glowPoints.push(point);
      }
    }
    canvas.save();
    try {
      canvas.scale(density, density);
      if (elapsed < DELETE_SOURCE_END) {
        canvas.attachBrush(this.imageBrush);
        canvas.drawImageRect(this.snapshot, this.bounds);
        canvas.detachBrush();
        canvas.save();
        try {
          canvas.scale(1, this.maskScaleY);
          for (let level: number = 0; level < this.masks.length; level++) {
            if (this.masks[level].length > 0) {
              canvas.attachPen(this.maskPens[level]);
              canvas.drawPoints(this.masks[level], drawing.PointMode.POINTS);
            }
          }
        } finally {
          canvas.detachPen();
          canvas.restore();
        }
      }
      for (const batch of this.batches) {
        if (batch.glowPoints.length > 0) {
          canvas.attachPen(batch.glowPen);
          canvas.drawPoints(batch.glowPoints, drawing.PointMode.POINTS);
        }
        if (batch.points.length > 0) {
          canvas.attachPen(batch.pen);
          canvas.drawPoints(batch.points, drawing.PointMode.POINTS);
        }
      }
    } finally {
      canvas.detachPen();
      canvas.detachBrush();
      canvas.restore();
    }
  }
}
