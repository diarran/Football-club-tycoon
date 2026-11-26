// Génère l'identité visuelle du jeu (logo, icône, miniature, écussons, palette).
// Tout est dessiné ici en SVG puis exporté en PNG avec Playwright (Chromium).
// Utilisation : node tools/brand/generate.js [chemin/vers/capture-du-jeu.png]
// Les fichiers sont écrits dans assets/brand/. Tout est fictif.
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const OUT = path.join(__dirname, '..', '..', 'assets', 'brand');
const BG_SHOT = process.argv[2]; // capture du quartier pour la miniature (facultatif)

// Palette : reprend les couleurs du HUD (src/client/Controllers/UIController.lua).
const C = {
  background: '#121826', panel: '#1C2436', card: '#283248',
  accent: '#2EAA5A', accentDark: '#1E7840', gold: '#F5C442', goldDark: '#C9971E',
  text: '#F0F4FA', muted: '#A0AABE', error: '#DC5050', disabled: '#505664',
};
const FONT = "'Inter Display','Inter',Arial,sans-serif";

// Clubs fictifs, couleurs = WorldConfig.CLUB_COLORS (même ordre que les 6 parcelles).
const CLUBS = [
  { name: 'FC Roquerouge', tag: 'FCR', p: '#C82832', s: '#F5F5F5', shape: 'classic', emblem: 'tower' },
  { name: 'Bleuval Olympique', tag: 'BVO', p: '#1E50B4', s: '#FAD228', shape: 'round', emblem: 'star' },
  { name: 'AS Verdaine', tag: 'ASV', p: '#1E8C50', s: '#F5F5F5', shape: 'flat', emblem: 'wing' },
  { name: 'Racing Violaine', tag: 'RCV', p: '#6E2896', s: '#F0AA28', shape: 'heater', emblem: 'crown' },
  { name: 'Sporting Noircastel', tag: 'SNC', p: '#141418', s: '#F0C83C', shape: 'octagon', emblem: 'bolt' },
  { name: 'US Azurport', tag: 'AZP', p: '#28AAD2', s: '#14285A', shape: 'pointed', emblem: 'wave' },
];

// ---------- Formes de base ----------
const star = (cx, cy, R, r = R * 0.45) => {
  let d = '';
  for (let i = 0; i < 10; i++) {
    const a = -Math.PI / 2 + (i * Math.PI) / 5;
    const rr = i % 2 ? r : R;
    d += (i ? 'L' : 'M') + (cx + rr * Math.cos(a)).toFixed(1) + ',' + (cy + rr * Math.sin(a)).toFixed(1);
  }
  return d + 'Z';
};
const poly = (cx, cy, r, n, rot) => {
  let d = '';
  for (let i = 0; i < n; i++) {
    const a = rot + (i * 2 * Math.PI) / n;
    d += (i ? 'L' : 'M') + (cx + r * Math.cos(a)).toFixed(1) + ',' + (cy + r * Math.sin(a)).toFixed(1);
  }
  return d + 'Z';
};
let uid = 0;
function ball(cx, cy, r, ink = C.background) {
  const id = 'b' + uid++;
  const up = -Math.PI / 2;
  let s = `<clipPath id="${id}"><circle cx="${cx}" cy="${cy}" r="${r}"/></clipPath>`;
  s += `<circle cx="${cx}" cy="${cy}" r="${r}" fill="#fff"/>`;
  s += `<g clip-path="url(#${id})" fill="${ink}" stroke="${ink}" stroke-width="${r * 0.05}" stroke-linejoin="round">`;
  s += `<path d="${poly(cx, cy, r * 0.36, 5, up)}"/>`;
  for (let i = 0; i < 5; i++) {
    const a = up + (i * 2 * Math.PI) / 5;
    const va = [cx + r * 0.36 * Math.cos(a), cy + r * 0.36 * Math.sin(a)];
    const vb = [cx + r * 0.68 * Math.cos(a), cy + r * 0.68 * Math.sin(a)];
    s += `<line x1="${va[0]}" y1="${va[1]}" x2="${vb[0]}" y2="${vb[1]}"/>`;
    s += `<path d="${poly(cx + r * 1.02 * Math.cos(a), cy + r * 1.02 * Math.sin(a), r * 0.34, 5, a + Math.PI)}"/>`;
  }
  s += `</g><circle cx="${cx}" cy="${cy}" r="${r}" fill="none" stroke="${ink}" stroke-width="${r * 0.06}"/>`;
  return s;
}

// Contours d'écussons (boîte 256x256).
const SHAPES = {
  classic: 'M128,8 L236,40 V128 C236,192 186,228 128,250 C70,228 20,192 20,128 V40 Z',
  round: 'M128,8 A120,120 0 1 1 127.9,8 Z',
  flat: 'M22,14 H234 V132 C234,198 182,234 128,250 C74,234 22,198 22,132 Z',
  heater: 'M128,6 L242,40 L222,168 L128,250 L34,168 L14,40 Z',
  octagon: poly(128, 128, 124, 8, Math.PI / 8),
  pointed: 'M30,10 H226 L244,40 V140 L128,250 L12,140 V40 Z',
};
// Emblèmes centrés autour de (128,118).
const EMBLEMS = {
  star: `<path d="${star(128, 116, 62)}"/>`,
  crown: '<path d="M66,152 L58,82 L96,112 L128,64 L160,112 L198,82 L190,152 Z"/><rect x="66" y="160" width="124" height="16" rx="4"/>',
  bolt: '<path d="M146,52 L80,134 H122 L106,190 L176,102 H134 Z"/>',
  wave: '<g fill="none" stroke-width="14" stroke-linecap="round" stroke="currentColor"><path d="M58,88 q17.5,-18 35,0 t35,0 t35,0 t35,0"/><path d="M58,122 q17.5,-18 35,0 t35,0 t35,0 t35,0"/><path d="M58,156 q17.5,-18 35,0 t35,0 t35,0 t35,0"/></g>',
  tower: '<path fill-rule="evenodd" d="M84,180 V92 H100 V72 H118 V92 H138 V72 H156 V92 H172 V180 Z M114,172 V146 A14,14 0 0 1 142,146 V172 Z"/>',
  wing: '<path d="M54,160 C76,96 132,62 204,62 C188,84 168,96 146,102 C166,104 184,100 198,94 C184,118 158,130 130,132 C148,136 162,136 176,132 C156,154 116,168 54,160 Z"/>',
};

const TEXT_Y = { classic: 202, round: 206, flat: 204, heater: 190, octagon: 206, pointed: 186 };
function crestSvg(club, withText = true) {
  const sh = SHAPES[club.shape];
  const ty = TEXT_Y[club.shape];
  const em = withText ? `transform="translate(128 ${ty - 96}) scale(0.68) translate(-128 -118)"` : '';
  const inner = 'transform="translate(128 128) scale(0.86) translate(-128 -128)"';
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256">
  <path d="${sh}" fill="${club.s}"/>
  <path d="${sh}" ${inner} fill="${club.p}"/>
  <path d="${sh}" ${inner} fill="url(#shine)"/>
  <defs><linearGradient id="shine" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".18"/><stop offset=".5" stop-color="#fff" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity=".18"/></linearGradient></defs>
  <g fill="${club.s}" color="${club.s}" ${em}>${EMBLEMS[club.emblem]}</g>
  ${withText ? `<text x="128" y="${ty}" text-anchor="middle" font-family="${FONT}" font-weight="900" font-size="32" letter-spacing="2" fill="${club.s}">${club.tag}</text>` : ''}
</svg>`;
}

// Calques blancs teintables dans Roblox (ImageLabel.ImageColor3).
const layer = (inner) => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256">${inner}</svg>`;

// ---------- Écusson du jeu ----------
const GAME_SHIELD = 'M100,4 L196,32 V118 C196,180 152,216 100,236 C48,216 4,180 4,118 V32 Z';
function gameCrest() {
  return `<defs>
    <linearGradient id="gNavy" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2A3652"/><stop offset="1" stop-color="${C.background}"/></linearGradient>
    <linearGradient id="gGold" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FFE08A"/><stop offset=".5" stop-color="${C.gold}"/><stop offset="1" stop-color="${C.goldDark}"/></linearGradient>
    <linearGradient id="gGreen" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${C.accent}"/><stop offset="1" stop-color="${C.accentDark}"/></linearGradient>
    <clipPath id="shieldClip"><path d="${GAME_SHIELD}"/></clipPath>
  </defs>
  <path d="${GAME_SHIELD}" fill="url(#gNavy)" stroke="url(#gGold)" stroke-width="9" stroke-linejoin="round"/>
  <g clip-path="url(#shieldClip)">
    <rect x="0" y="150" width="200" height="100" fill="url(#gGreen)"/>
    <rect x="0" y="150" width="200" height="5" fill="#fff" opacity=".85"/>
    <rect x="0" y="174" width="200" height="14" fill="#fff" opacity=".07"/>
    <rect x="0" y="202" width="200" height="14" fill="#fff" opacity=".07"/>
  </g>
  <path d="${GAME_SHIELD}" fill="none" stroke="url(#gGold)" stroke-width="9" stroke-linejoin="round"/>
  <g fill="url(#gGold)"><path d="${star(70, 40, 11)}"/><path d="${star(100, 32, 14)}"/><path d="${star(130, 40, 11)}"/></g>
  <g fill="url(#gGold)" stroke="${C.background}" stroke-width="2">
    <rect x="44" y="150" width="20" height="34" rx="3"/><rect x="136" y="132" width="20" height="52" rx="3"/>
  </g>
  ${ball(100, 112, 50)}
  <path d="M150,96 L176,70 M176,70 H160 M176,70 V86" stroke="url(#gGold)" stroke-width="8" stroke-linecap="round" fill="none"/>`;
}

const svgDoc = (w, h, body, bg = '') =>
  `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 ${w} ${h}" width="${w}" height="${h}">${bg}${body}</svg>`;

function logoBody() {
  return `<g transform="translate(20 20) scale(2.75)">${gameCrest()}</g>
  <g font-family="${FONT}" font-weight="900">
    <text x="620" y="250" font-size="104" letter-spacing="14" fill="${C.text}" stroke="${C.background}" stroke-width="16" paint-order="stroke" stroke-linejoin="round">FOOTBALL CLUB</text>
    <text x="606" y="500" font-size="272" letter-spacing="4" fill="url(#gGold)" stroke="${C.background}" stroke-width="22" paint-order="stroke" stroke-linejoin="round" transform="skewX(-6) translate(56 0)">TYCOON</text>
    <rect x="626" y="548" width="1010" height="16" rx="8" fill="${C.accent}"/>
  </g>`;
}

function iconBody() {
  return `<defs>
    <radialGradient id="iBg" cx=".5" cy=".42" r=".75"><stop offset="0" stop-color="#3DCB72"/><stop offset=".55" stop-color="${C.accent}"/><stop offset="1" stop-color="${C.accentDark}"/></radialGradient>
  </defs>
  <rect width="512" height="512" fill="url(#iBg)"/>
  ${[0, 1, 2, 3, 4, 5, 6, 7].map((i) => `<rect x="${i * 64}" y="0" width="32" height="512" fill="#fff" opacity=".05"/>`).join('')}
  <circle cx="256" cy="238" r="150" fill="none" stroke="#fff" stroke-width="8" opacity=".25"/>
  <rect x="0" y="234" width="512" height="8" fill="#fff" opacity=".25"/>
  <g transform="translate(116 34) scale(1.4)">${gameCrest()}</g>
  <g transform="translate(256 448)">
    <path d="M-220,-38 H220 L196,0 L220,38 H-220 L-196,0 Z" fill="${C.background}" stroke="url(#gGold)" stroke-width="6" stroke-linejoin="round"/>
    <text x="0" y="22" text-anchor="middle" font-family="${FONT}" font-weight="900" font-size="64" letter-spacing="6" fill="url(#gGold)">TYCOON</text>
  </g>`;
}

function thumbBody(shotB64) {
  const bg = shotB64
    ? `<image href="data:image/png;base64,${shotB64}" x="520" y="0" width="1400" height="1080" preserveAspectRatio="xMidYMid slice"/>`
    : `<rect width="1920" height="1080" fill="${C.accentDark}"/>`;
  const crests = CLUBS.map((c, i) => {
    const svg = crestSvg(c).replace(/<\?xml[^>]*>/, '');
    const inner = svg.replace(/^<svg[^>]*>/, '').replace(/<\/svg>\s*$/, '').replace(/id="shine"/g, `id="shine${i}"`).replace(/url\(#shine\)/g, `url(#shine${i})`);
    return `<g transform="translate(${100 + i * 150} 860) scale(0.5)">${inner}</g>`;
  }).join('');
  return `<defs>
    <linearGradient id="tFade" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="${C.background}"/><stop offset=".36" stop-color="${C.background}" stop-opacity=".96"/><stop offset=".62" stop-color="${C.background}" stop-opacity=".2"/><stop offset="1" stop-color="${C.background}" stop-opacity="0"/></linearGradient>
    <linearGradient id="tBottom" x1="0" y1="0" x2="0" y2="1"><stop offset=".7" stop-color="${C.background}" stop-opacity="0"/><stop offset="1" stop-color="${C.background}" stop-opacity=".8"/></linearGradient>
  </defs>
  ${bg}
  <rect width="1920" height="1080" fill="url(#tFade)"/>
  <rect width="1920" height="1080" fill="url(#tBottom)"/>
  <g transform="translate(80 150) scale(0.62)">${logoBody()}</g>
  <text x="100" y="628" font-family="${FONT}" font-weight="800" font-size="62" fill="${C.text}">Construis ton stade.</text>
  <text x="100" y="706" font-family="${FONT}" font-weight="800" font-size="62" fill="${C.text}">Recrute. <tspan fill="${C.gold}">Deviens une légende.</tspan></text>
  ${['6 clubs par serveur', 'Matchs simulés', 'FC Coins'].map((t, i) => {
    const w = [400, 330, 230][i];
    const x = [100, 520, 870][i];
    return `<g transform="translate(${x} 752)"><rect width="${w}" height="64" rx="32" fill="${C.card}" stroke="${C.accent}" stroke-width="3"/><text x="${w / 2}" y="42" text-anchor="middle" font-family="${FONT}" font-weight="700" font-size="30" fill="${C.text}">${t}</text></g>`;
  }).join('')}
  ${crests}`;
}

function paletteBody() {
  const sw = [
    ['Fond', 'background', C.background], ['Panneau', 'panel', C.panel], ['Carte', 'card', C.card],
    ['Vert terrain', 'accent', C.accent], ['Vert foncé', 'accentDark', C.accentDark], ['Or FC Coins', 'gold', C.gold],
    ['Texte', 'text', C.text], ['Texte secondaire', 'muted', C.muted], ['Erreur', 'error', C.error],
  ];
  return `<rect width="1600" height="900" fill="${C.background}"/>
  <text x="80" y="110" font-family="${FONT}" font-weight="900" font-size="60" fill="${C.text}">Palette <tspan fill="${C.gold}">Football Club Tycoon</tspan></text>
  ${sw.map(([fr, key, hex], i) => {
    const x = 80 + (i % 3) * 490, y = 170 + Math.floor(i / 3) * 230;
    const dark = ['text', 'gold', 'muted'].includes(key);
    return `<g transform="translate(${x} ${y})"><rect width="460" height="200" rx="22" fill="${hex}" stroke="#fff" stroke-opacity=".15" stroke-width="2"/>
    <text x="28" y="60" font-family="${FONT}" font-weight="800" font-size="36" fill="${dark ? C.background : C.text}">${fr}</text>
    <text x="28" y="120" font-family="${FONT}" font-weight="600" font-size="30" fill="${dark ? C.background : C.text}" opacity=".85">${hex}</text>
    <text x="28" y="170" font-family="${FONT}" font-weight="600" font-size="24" fill="${dark ? C.background : C.text}" opacity=".65">COLORS.${key}</text></g>`;
  }).join('')}`;
}

function crestSheetBody() {
  return `<rect width="1800" height="760" fill="${C.background}"/>
  <text x="80" y="100" font-family="${FONT}" font-weight="900" font-size="56" fill="${C.text}">Écussons des clubs <tspan fill="${C.gold}">(fictifs)</tspan></text>
  ${CLUBS.map((c, i) => {
    const inner = crestSvg(c).replace(/^<svg[^>]*>/, '').replace(/<\/svg>\s*$/, '').replace(/id="shine"/g, `id="sh${i}"`).replace(/url\(#shine\)/g, `url(#sh${i})`);
    const x = 70 + i * 280;
    return `<g transform="translate(${x} 170)"><rect x="-10" y="-10" width="270" height="480" rx="24" fill="${C.panel}"/>
    <g transform="translate(5 20)">${inner}</g>
    <text x="125" y="330" text-anchor="middle" font-family="${FONT}" font-weight="800" font-size="26" fill="${C.text}">${c.name.split(' ').slice(0, -1).join(' ') || c.name}</text>
    <text x="125" y="366" text-anchor="middle" font-family="${FONT}" font-weight="800" font-size="26" fill="${C.text}">${c.name.split(' ').slice(-1)}</text>
    <g transform="translate(55 400)"><rect width="60" height="36" rx="8" fill="${c.p}" stroke="#fff" stroke-opacity=".3"/><rect x="80" width="60" height="36" rx="8" fill="${c.s}" stroke="#fff" stroke-opacity=".3"/></g></g>`;
  }).join('')}
  <text x="80" y="720" font-family="${FONT}" font-weight="600" font-size="26" fill="${C.muted}">6 formes × 6 emblèmes en calques blancs teintables : jusqu'à 36 combinaisons pour les clubs générés.</text>`;
}

async function main() {
  fs.mkdirSync(path.join(OUT, 'crests', 'layers'), { recursive: true });
  const jobs = []; // [fichier, largeur, hauteur, svg, transparent]
  const shot = BG_SHOT && fs.existsSync(BG_SHOT) ? fs.readFileSync(BG_SHOT).toString('base64') : null;
  const defsOnly = `<defs>${gameCrest().match(/<defs>([\s\S]*?)<\/defs>/)[1]}</defs>`;

  jobs.push(['logo.png', 1700, 640, svgDoc(1700, 640, logoBody()), true]);
  jobs.push(['emblem.png', 512, 512, svgDoc(208, 244, `<g transform="translate(4 2)">${gameCrest()}</g>`), true]);
  jobs.push(['icon-512.png', 512, 512, svgDoc(512, 512, iconBody()), false]);
  jobs.push(['thumbnail-1920x1080.png', 1920, 1080, svgDoc(1920, 1080, defsOnly + thumbBody(shot)), false]);
  jobs.push(['palette.png', 1600, 900, svgDoc(1600, 900, paletteBody()), false]);
  jobs.push(['crests/apercu-ecussons.png', 1800, 760, svgDoc(1800, 760, crestSheetBody()), false]);
  CLUBS.forEach((c, i) => jobs.push([`crests/club-${i + 1}.png`, 256, 256, crestSvg(c), true]));
  for (const [k, d] of Object.entries(SHAPES)) {
    jobs.push([`crests/layers/shape-${k}-outer.png`, 256, 256, layer(`<path d="${d}" fill="#fff"/>`), true]);
    jobs.push([`crests/layers/shape-${k}-inner.png`, 256, 256, layer(`<path d="${d}" fill="#fff" transform="translate(128 128) scale(0.86) translate(-128 -128)"/>`), true]);
  }
  for (const [k, e] of Object.entries(EMBLEMS)) {
    jobs.push([`crests/layers/emblem-${k}.png`, 256, 256, layer(`<g fill="#fff" color="#fff" transform="translate(128 112) scale(0.82) translate(-128 -118)">${e}</g>`), true]);
  }
  // Sources SVG des pièces principales (le texte utilise la police Inter).
  fs.writeFileSync(path.join(OUT, 'logo.svg'), svgDoc(1700, 640, logoBody()));
  fs.writeFileSync(path.join(OUT, 'palette.json'), JSON.stringify({ hud: C, clubs: CLUBS }, null, 2) + '\n');

  const browser = await chromium.launch();
  const page = await browser.newPage();
  for (const [file, w, h, svg, transparent] of jobs) {
    await page.setViewportSize({ width: w, height: h });
    const sized = svg.replace(/width="\d+" height="\d+"/, `width="${w}" height="${h}"`);
    await page.setContent(`<html><body style="margin:0;background:transparent">${sized}</body></html>`);
    await page.screenshot({ path: path.join(OUT, file), omitBackground: transparent, clip: { x: 0, y: 0, width: w, height: h } });
  }
  await browser.close();
  console.log(`${jobs.length} images écrites dans ${OUT}`);
}

main().catch((e) => { console.error(e); process.exit(1); });
