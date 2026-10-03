# HITA NEXT Application Icon

Harmony-inspired recolour of the original HITA Android mark.

- All nine path definitions are copied unchanged from
  `HITA_Android_src/app/src/main/res/drawable/logo.xml`.
- The mark uses one uniform scale and translation. Its proportions, corners,
  negative spaces, and facet boundaries are preserved.
- Only the palette, lighting, and background are redesigned: cold white,
  ice blue, a black field, and fine blue wave contours.
- No HarmonyOS wordmark or replacement ring symbol is added.
- The 1024 px master is installed as the application, launcher, and start icon.

## Files

- `hita-next-harmony.png`: full-bleed 1024 x 1024 master.
- `hita-next-harmony.svg`: editable, scalable vector source.
- `hita-next-harmony-{512,256,64}.png`: smaller exports.
- `hita-next-harmony-foreground.png`: 1024 x 1024 transparent mark.
- `hita-next-harmony-foreground.svg`: transparent vector mark.

The square master has no baked-in rounded corners, so the launcher can apply
its own icon mask.

## Application Resources

The following resources contain the same 1024 px master:

- `AppScope/resources/base/media/app_icon.png`
- `entry/src/main/resources/base/media/app_icon.png`
- `entry/src/main/resources/base/media/ic_launcher.png`
- `entry/src/main/resources/base/media/startIcon.png`

## Rebuild

With Node.js and `sharp` available, run `node render.cjs` in this directory.
The renderer writes only the design exports alongside this README. After an
approved redesign, copy the master PNG to all four application resources above.
