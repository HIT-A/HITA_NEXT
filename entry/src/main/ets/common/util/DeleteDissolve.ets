export const DELETE_DISSOLVE_DURATION: number = 1400;
// Scale every phase together so a longer duration slows the motion, not just its cleanup.
const DELETE_TIME_SCALE: number = DELETE_DISSOLVE_DURATION / 940;
export const DELETE_SOURCE_FADE_DURATION: number = 105 * DELETE_TIME_SCALE;
export const DELETE_SOURCE_END: number = 450 * DELETE_TIME_SCALE;
export const DELETE_DISSOLVE_PADDING: number = 128;
export const DELETE_DISSOLVE_MAX_GRAINS: number = 1500;
export const DELETE_GLOW_SCALE: number = 1.8;
export const DELETE_GLOW_ALPHA: number = 0.07;

export interface DeleteGrain {
  x: number;
  y: number;
  width: number;
  height: number;
  birth: number;
  lifetime: number;
  radius: number;
  phase: number;
  drift: number;
  color: string;
  argb: number;
  alpha: number;
  glow: boolean;
  originX: number;
  originY: number;
  phaseX: number;
  phaseY: number;
  sinPhaseX: number;
  cosPhaseY: number;
  sinPhase: number;
}

export interface DeleteGrainFrame {
  x: number;
  y: number;
  radius: number;
  alpha: number;
}

export interface DeleteDissolveMesh {
  width: number;
  height: number;
  columns: number;
  rows: number;
  grains: DeleteGrain[];
}

function noise(x: number, y: number): number {
  const value: number = Math.sin(x * 127.1 + y * 311.7) * 43758.5453;
  return value - Math.floor(value);
}

export function deleteDissolveGrid(width: number, height: number): number[] {
  const pitch: number = Math.max(3, Math.sqrt(width * height / DELETE_DISSOLVE_MAX_GRAINS));
  const columns: number = Math.min(DELETE_DISSOLVE_MAX_GRAINS, Math.max(1, Math.floor(width / pitch)));
  return [columns, Math.min(Math.floor(DELETE_DISSOLVE_MAX_GRAINS / columns),
    Math.max(1, Math.floor(height / pitch)))];
}

/** The source pixels seed the dust; rounded corners and transparent areas emit nothing. */
export function createDeleteDissolve(width: number, height: number,
  pixels: Uint8ClampedArray, columns: number, rows: number): DeleteDissolveMesh {
  const mesh: DeleteDissolveMesh = { width, height, columns, rows, grains: [] };
  const cellWidth: number = width / columns;
  const cellHeight: number = height / rows;
  for (let row: number = 0; row < rows; row++) {
    for (let column: number = 0; column < columns; column++) {
      const index: number = (row * columns + column) * 4;
      const alpha: number = pixels[index + 3] / 255;
      const random: number = noise(column, row);
      const red: number = pixels[index];
      const green: number = pixels[index + 1];
      const blue: number = pixels[index + 2];
      // Keep the sampled card and text colors; motion only changes opacity.
      const color: string = 'rgb(' + red + ',' + green + ',' + blue + ')';
      const x: number = column * cellWidth;
      const y: number = row * cellHeight;
      const phase: number = noise(column + 5, row + 11) * Math.PI * 2;
      const drift: number = noise(row + 2, column + 7);
      const phaseX: number = x * 0.032 + y * 0.019;
      const phaseY: number = y * 0.045 - x * 0.012;
      const front: number = (1 - column / columns) * 0.65 + (1 - row / rows) * 0.35;
      const wave: number = 0.5 + Math.sin(x * 0.045 + y * 0.04) * 0.3 +
        Math.sin(y * 0.09 - x * 0.022) * 0.2;
      mesh.grains.push({
        x,
        y,
        width: cellWidth,
        height: cellHeight,
        birth: (30 + front * 190 + wave * 75 + random * 30) * DELETE_TIME_SCALE,
        lifetime: (485 + noise(row + 9, column + 3) * 120) * DELETE_TIME_SCALE,
        radius: 0.8 + Math.pow(random, 1.6) * 0.75,
        phase,
        drift,
        color,
        argb: (0xff000000 | (red << 16) | (green << 8) | blue) >>> 0,
        alpha,
        glow: random > 0.86,
        originX: x + cellWidth * (0.5 + Math.sin(phase) * 0.38),
        originY: y + cellHeight * (0.1 + drift * 0.8),
        phaseX,
        phaseY,
        sinPhaseX: Math.sin(phaseX),
        cosPhaseY: Math.cos(phaseY),
        sinPhase: Math.sin(phase)
      });
    }
  }
  return mesh;
}

/** Neighbouring grains share eddies so the trail flows instead of spraying in straight lines. */
export function deleteGrainFrame(grain: DeleteGrain, elapsed: number): DeleteGrainFrame {
  const frame: DeleteGrainFrame = { x: 0, y: 0, radius: 0, alpha: 0 };
  writeDeleteGrainFrame(grain, elapsed, frame);
  return frame;
}

/** Transfer opacity from each source patch to its grains with one continuous curve. */
export function deleteSourceDissolve(grain: DeleteGrain, elapsed: number): number {
  const progress: number = Math.max(0, Math.min(1, (elapsed - grain.birth) / DELETE_SOURCE_FADE_DURATION));
  return progress * progress * (3 - 2 * progress);
}

export function writeDeleteGrainFrame(grain: DeleteGrain, elapsed: number, frame: DeleteGrainFrame): void {
  const age: number = Math.max(0, Math.min(1, (elapsed - grain.birth) / grain.lifetime));
  const drift: number = age * age * (3 - 2 * age);
  const curlX: number = Math.sin(grain.phaseX + age * 4.6) - grain.sinPhaseX;
  const curlY: number = Math.cos(grain.phaseY + age * 4.1) - grain.cosPhaseY;
  const spread: number = 12 + drift * 24;
  const twinkle: number = 0.94 + Math.sin(grain.phase + age * 9) * 0.06;
  const tail: number = Math.pow(1 - age, 0.8);
  const emerge: number = deleteSourceDissolve(grain, elapsed);
  frame.x = grain.originX - 24 * drift + curlX * spread + grain.sinPhase * drift * 12;
  frame.y = grain.originY - (9 + grain.drift * 16) * drift + curlY * spread;
  frame.radius = grain.radius * (1 - age * 0.4);
  frame.alpha = grain.alpha * tail * twinkle * emerge;
}

/** Reference renderer for visual comparisons; the app uses native point batches. */
export function drawDeleteDissolve(context: CanvasRenderingContext2D, snapshot: ImageBitmap,
  mesh: DeleteDissolveMesh, elapsed: number): void {
  const padding: number = DELETE_DISSOLVE_PADDING;
  context.clearRect(0, 0, mesh.width + padding * 2, mesh.height + padding * 2);
  context.globalAlpha = 1;
  if (elapsed >= DELETE_DISSOLVE_DURATION) {
    return;
  }
  if (elapsed < DELETE_SOURCE_END) {
    context.drawImage(snapshot, padding, padding, mesh.width, mesh.height);
    context.globalCompositeOperation = 'destination-out';
    context.fillStyle = '#000000';
    for (const grain of mesh.grains) {
      if (elapsed >= grain.birth) {
        context.globalAlpha = deleteSourceDissolve(grain, elapsed);
        context.fillRect(padding + grain.x, padding + grain.y, grain.width + 0.25, grain.height + 0.25);
      }
    }
    context.globalCompositeOperation = 'source-over';
  }
  for (const grain of mesh.grains) {
    if (grain.alpha < 0.03 || elapsed < grain.birth || elapsed >= grain.birth + grain.lifetime) {
      continue;
    }
    const frame: DeleteGrainFrame = deleteGrainFrame(grain, elapsed);
    context.fillStyle = grain.color;
    if (grain.glow) {
      const glowRadius: number = frame.radius * DELETE_GLOW_SCALE;
      context.globalAlpha = frame.alpha * DELETE_GLOW_ALPHA;
      context.fillRect(padding + frame.x - glowRadius,
        padding + frame.y - glowRadius, glowRadius * 2, glowRadius * 2);
    }
    context.globalAlpha = frame.alpha;
    context.fillRect(padding + frame.x - frame.radius, padding + frame.y - frame.radius,
      frame.radius * 2, frame.radius * 2);
  }
  context.globalAlpha = 1;
}
