const fs = require('node:fs/promises');
const path = require('node:path');
const sharp = require('sharp');

// Original Android logo.xml paths, unchanged. Only fills and the uniform
// placement transform differ; no corners, proportions, or cutouts are redrawn.
const parts = [
  'm54.257,32.405 l27.437,0.089 -0.108,43.944 -27.328,-31.371z',
  'm54.257,45.066 l47.389,54.121 -47.397,0.023z',
  'm54.248,99.211 l26.83,-0.015 0.006,18.365 -26.76,26.092z',
  'm81.084,117.56 l-0.024,55.923 -26.748,-26.175 0.012,-3.656z',
  'm81.567,76.26 l37.371,0.014 -17.292,22.913z',
  'm140.794,47.271 l4.958,5.051 -0.047,46.866h-44.059z',
  'm118.966,26.038 l21.828,21.233 -21.856,29.004z',
  'm119.131,99.188 l26.574,0 -0.066,48.882 -26.458,-28.046z',
  'm119.18,120.024 l26.458,28.046 -0.025,18.359 -26.398,-0.021z'
];
const fills = [
  'porcelain', 'snow', 'ice', 'iceFold', 'bridge',
  'snow', 'porcelain', 'blue', 'blueFold'
];
const transform = 'translate(87 86.018375) scale(4.25)';
const markPaths = parts.map((d, index) =>
  `<path id="hita-part-${index + 1}" d="${d}" fill="url(#${fills[index]})"/>`
).join('\n');

const defs = `
  <linearGradient id="porcelain" x1="54" y1="26" x2="145" y2="100" gradientUnits="userSpaceOnUse">
    <stop stop-color="#ffffff"/><stop offset="1" stop-color="#dceaff"/>
  </linearGradient>
  <linearGradient id="snow" x1="80" y1="40" x2="100" y2="115" gradientUnits="userSpaceOnUse">
    <stop stop-color="#edf4ff"/><stop offset=".72" stop-color="#ffffff"/><stop offset="1" stop-color="#e1efff"/>
  </linearGradient>
  <linearGradient id="bridge" x1="85" y1="76" x2="111" y2="99" gradientUnits="userSpaceOnUse">
    <stop stop-color="#cfddf6"/><stop offset="1" stop-color="#eff7ff"/>
  </linearGradient>
  <linearGradient id="ice" x1="65" y1="99" x2="76" y2="147" gradientUnits="userSpaceOnUse">
    <stop stop-color="#edf7ff"/><stop offset="1" stop-color="#b9d5ff"/>
  </linearGradient>
  <linearGradient id="iceFold" x1="70" y1="117" x2="74" y2="174" gradientUnits="userSpaceOnUse">
    <stop stop-color="#c6deff"/><stop offset="1" stop-color="#91b9f4"/>
  </linearGradient>
  <linearGradient id="blue" x1="130" y1="99" x2="145" y2="148" gradientUnits="userSpaceOnUse">
    <stop stop-color="#9ec7ff"/><stop offset=".5" stop-color="#639aff"/><stop offset="1" stop-color="#4175ee"/>
  </linearGradient>
  <linearGradient id="blueFold" x1="120" y1="120" x2="143" y2="167" gradientUnits="userSpaceOnUse">
    <stop stop-color="#5b94ff"/><stop offset="1" stop-color="#2c58d9"/>
  </linearGradient>
  <radialGradient id="atmosphere">
    <stop stop-color="#10264b" stop-opacity=".55"/>
    <stop offset=".48" stop-color="#081326" stop-opacity=".35"/>
    <stop offset="1" stop-color="#000000" stop-opacity="0"/>
  </radialGradient>
  <linearGradient id="ringInk" x1="0" y1="108" x2="0" y2="540" gradientUnits="userSpaceOnUse">
    <stop stop-color="#5b79ae" stop-opacity=".22"/>
    <stop offset=".8" stop-color="#789cdb" stop-opacity=".62"/>
    <stop offset="1" stop-color="#8fb8ff" stop-opacity=".76"/>
  </linearGradient>
  <linearGradient id="rippleInk" x1="0" y1="540" x2="0" y2="882" gradientUnits="userSpaceOnUse">
    <stop stop-color="#87b6ff" stop-opacity=".78"/>
    <stop offset=".32" stop-color="#8ab4f6" stop-opacity=".58"/>
    <stop offset=".8" stop-color="#4468aa" stop-opacity=".18"/>
    <stop offset="1" stop-color="#20395e" stop-opacity="0"/>
  </linearGradient>
  <linearGradient id="horizonInk">
    <stop stop-color="#5b95ff" stop-opacity="0"/>
    <stop offset=".3" stop-color="#7cafff" stop-opacity=".14"/>
    <stop offset=".5" stop-color="#b0d1ff" stop-opacity=".4"/>
    <stop offset=".7" stop-color="#7cafff" stop-opacity=".14"/>
    <stop offset="1" stop-color="#5b95ff" stop-opacity="0"/>
  </linearGradient>
  <filter id="horizonBlur" x="-10%" y="-600%" width="120%" height="1300%">
    <feGaussianBlur stdDeviation="7"/>
  </filter>
  <filter id="markGlow" x="-40%" y="-25%" width="180%" height="150%">
    <feGaussianBlur stdDeviation="2.1"/>
  </filter>`;

let contours = '';
for (let i = 0; i < 43; i++) {
  const radius = 222 + i * 4.55;
  const opacity = 0.69 - (i / 42) * 0.40;
  contours += `<path d="M${512 - radius},540 A${radius},${radius} 0 0 1 ${512 + radius},540" stroke="url(#ringInk)" stroke-opacity="${opacity.toFixed(3)}"/>\n`;
  const points = [];
  for (let j = 0; j <= 150; j++) {
    const theta = Math.PI * j / 150;
    const depth = Math.sin(theta);
    const y = 540 + (radius * .78) * depth;
    const sway = Math.sin((y - 540) * .071 + i * .052) * 17 * depth;
    const x = 512 + Math.cos(theta) * radius + sway;
    points.push(`${j === 0 ? 'M' : 'L'}${x.toFixed(2)},${y.toFixed(2)}`);
  }
  contours += `<path d="${points.join(' ')}" stroke="url(#rippleInk)" stroke-opacity="${(opacity * 1.2).toFixed(3)}"/>\n`;
}

const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<title>HITA NEXT - Harmony-inspired recolour of the original Android mark</title>
<desc>The nine original Android paths are unchanged. Black background, cold white and ice blue facets, fine blue wave contours. No added lettering.</desc>
<defs>${defs}</defs>
<rect width="1024" height="1024" fill="#020306"/>
<ellipse cx="512" cy="550" rx="445" ry="310" fill="url(#atmosphere)"/>
<g fill="none" stroke-width="1.15">${contours}</g>
<path d="M68,540 H956" stroke="url(#horizonInk)" stroke-width="8" filter="url(#horizonBlur)"/>
<path d="M68,540 H956" stroke="url(#horizonInk)" stroke-width="1.2"/>
<g transform="${transform}">
  <g fill="#96beff" opacity=".2" filter="url(#markGlow)">
    ${parts.map(d => `<path d="${d}"/>`).join('\n')}
  </g>
  ${markPaths}
</g>
</svg>`;
const foreground = `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024"><defs>${defs}</defs><g transform="${transform}">${markPaths}</g></svg>`;

async function main() {
  const base = path.join(__dirname, 'hita-next-harmony');
  await fs.writeFile(`${base}.svg`, svg);
  await fs.writeFile(`${base}-foreground.svg`, foreground);
  const rendered = await sharp(Buffer.from(svg), { density: 216 }).png().toBuffer();
  for (const size of [1024, 512, 256, 64]) {
    const filename = size === 1024 ? `${base}.png` : `${base}-${size}.png`;
    await sharp(rendered).resize(size, size).png().toFile(filename);
  }
  await sharp(Buffer.from(foreground), { density: 144 })
    .resize(1024, 1024).png().toFile(`${base}-foreground.png`);
  const metadata = await sharp(`${base}.png`).metadata();
  console.log(`Rendered ${metadata.width} x ${metadata.height} ${metadata.format}`);
  console.log(`Original geometry: ${parts.length} unmodified paths; uniform scale 4.25`);
  console.log(base);
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
