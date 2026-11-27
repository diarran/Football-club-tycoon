// Génère les 10 images des badges Roblox (512 × 512, rondes, sans texte à traduire).
// Dessinées en SVG puis exportées en PNG avec Playwright (Chromium).
// Utilisation : node tools/brand/badges.js  → assets/brand/badges/<id>.png
// L'ordre et les identifiants suivent Achievements.BADGE_IDS (src/shared/Achievements.lua).
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const OUT = path.join(__dirname, '..', '..', 'assets', 'brand', 'badges');
const C = { background: '#121826', panel: '#1C2436', accent: '#2EAA5A', gold: '#F5C442', text: '#F0F4FA' };
const TIERS = {
  bronze: ['#E0A070', '#9A5A2E'],
  silver: ['#E6ECF4', '#8C96A8'],
  gold: ['#FFE07A', '#C9971E'],
};
const FONT = "'Inter Display','Inter','DejaVu Sans',Arial,sans-serif";

const star = (cx, cy, R, r = R * 0.45) => {
  let d = '';
  for (let i = 0; i < 10; i++) {
    const a = -Math.PI / 2 + (i * Math.PI) / 5;
    const rr = i % 2 ? r : R;
    d += (i ? 'L' : 'M') + (cx + rr * Math.cos(a)).toFixed(1) + ',' + (cy + rr * Math.sin(a)).toFixed(1);
  }
  return d + 'Z';
};
const ball = (cx, cy, r) => {
  let s = `<circle cx="${cx}" cy="${cy}" r="${r}" fill="#fff" stroke="${C.background}" stroke-width="${r * 0.08}"/>`;
  let d = '';
  for (let i = 0; i < 5; i++) {
    const a = -Math.PI / 2 + (i * 2 * Math.PI) / 5;
    d += (i ? 'L' : 'M') + (cx + r * 0.38 * Math.cos(a)).toFixed(1) + ',' + (cy + r * 0.38 * Math.sin(a)).toFixed(1);
  }
  s += `<path d="${d}Z" fill="${C.background}"/>`;
  for (let i = 0; i < 5; i++) {
    const a = -Math.PI / 2 + (i * 2 * Math.PI) / 5;
    s += `<line x1="${cx + r * 0.38 * Math.cos(a)}" y1="${cy + r * 0.38 * Math.sin(a)}" x2="${cx + r * 0.95 * Math.cos(a)}" y2="${cy + r * 0.95 * Math.sin(a)}" stroke="${C.background}" stroke-width="${r * 0.05}"/>`;
  }
  return s;
};
const trophy = (fill) =>
  `<g fill="${fill}" stroke="${C.background}" stroke-width="6" stroke-linejoin="round">
    <path d="M186,150 h140 v40 c0,60 -30,100 -70,108 c-40,-8 -70,-48 -70,-108 Z"/>
    <path d="M186,170 h-34 c0,44 20,70 46,74" fill="none" stroke="${fill}" stroke-width="16"/>
    <path d="M326,170 h34 c0,44 -20,70 -46,74" fill="none" stroke="${fill}" stroke-width="16"/>
    <rect x="240" y="296" width="32" height="40"/>
    <rect x="200" y="334" width="112" height="26" rx="6"/>
  </g>`;
const big = (text, size = 150, y = 300) =>
  `<text x="256" y="${y}" text-anchor="middle" font-family="${FONT}" font-weight="900" font-size="${size}" fill="${C.text}" stroke="${C.background}" stroke-width="10" paint-order="stroke">${text}</text>`;
const stars = (n, y = 400) => {
  let s = '';
  for (let i = 0; i < n; i++) s += `<path d="${star(256 + (i - (n - 1) / 2) * 50, y, 20)}" fill="${C.gold}"/>`;
  return s;
};
const stadium = `<g stroke="${C.background}" stroke-width="6">
    <ellipse cx="256" cy="290" rx="150" ry="70" fill="#2B3550"/>
    <ellipse cx="256" cy="282" rx="110" ry="44" fill="${C.accent}"/>
    <line x1="256" y1="240" x2="256" y2="324" stroke="#fff" stroke-width="5"/>
    <ellipse cx="256" cy="282" rx="26" ry="11" fill="none" stroke="#fff" stroke-width="5"/>
    <rect x="96" y="160" width="10" height="110" fill="#C8D0DC"/><rect x="406" y="160" width="10" height="110" fill="#C8D0DC"/>
    <rect x="80" y="140" width="42" height="26" rx="4" fill="${C.gold}"/><rect x="390" y="140" width="42" height="26" rx="4" fill="${C.gold}"/>
  </g>`;
const crown = `<g fill="${C.gold}" stroke="${C.background}" stroke-width="8" stroke-linejoin="round">
    <path d="M140,330 L124,170 L196,232 L256,140 L316,232 L388,170 L372,330 Z"/>
    <rect x="140" y="336" width="232" height="34" rx="8"/>
  </g>`;

// id → { tier, art }
const BADGES = [
  { id: 'first_win', tier: 'bronze', art: ball(256, 250, 96) + big('1', 90, 420) },
  { id: 'goals_100', tier: 'silver', art: ball(256, 190, 70) + big('100', 140, 380) },
  { id: 'promo_D5', tier: 'bronze', art: big('D5', 190, 320) + stars(1) },
  { id: 'promo_D3', tier: 'silver', art: big('D3', 190, 320) + stars(2) },
  { id: 'promo_D1', tier: 'gold', art: big('D1', 190, 320) + stars(3) },
  { id: 'cup_winner', tier: 'gold', art: trophy(C.gold) },
  { id: 'tournament_winner', tier: 'silver', art: trophy('#E6ECF4') + `<path d="${star(256, 210, 30)}" fill="${C.gold}"/>` },
  { id: 'player_80', tier: 'gold', art: `<path d="${star(256, 220, 110)}" fill="${C.gold}" stroke="${C.background}" stroke-width="8"/>` + big('80', 120, 410) },
  { id: 'stadium_max', tier: 'gold', art: stadium },
  { id: 'd1_title', tier: 'gold', art: crown + stars(3, 120) },
];

function badgeSvg(b) {
  const [light, dark] = TIERS[b.tier];
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">
  <defs>
    <linearGradient id="ring-${b.id}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="${light}"/><stop offset="1" stop-color="${dark}"/></linearGradient>
    <radialGradient id="bg-${b.id}" cx="0.5" cy="0.4" r="0.6"><stop offset="0" stop-color="${C.panel}"/><stop offset="1" stop-color="${C.background}"/></radialGradient>
  </defs>
  <circle cx="256" cy="256" r="250" fill="url(#ring-${b.id})"/>
  <circle cx="256" cy="256" r="212" fill="url(#bg-${b.id})"/>
  <circle cx="256" cy="256" r="200" fill="none" stroke="${light}" stroke-width="4" opacity="0.6"/>
  ${b.art}
</svg>`;
}

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 512, height: 512 } });
  for (const b of BADGES) {
    await page.setContent(`<html><body style="margin:0;background:transparent">${badgeSvg(b)}</body></html>`);
    await page.screenshot({ path: path.join(OUT, `${b.id}.png`), omitBackground: true, clip: { x: 0, y: 0, width: 512, height: 512 } });
  }
  // Planche d'aperçu (5 × 2).
  const sheet = BADGES.map((b) => `<div style="display:inline-block;width:200px;height:200px">${badgeSvg(b).replace('width="512" height="512"', 'width="200" height="200"')}</div>`).join('');
  await page.setViewportSize({ width: 1000, height: 400 });
  await page.setContent(`<html><body style="margin:0;background:#0B0F18;width:1000px">${sheet}</body></html>`);
  await page.screenshot({ path: path.join(OUT, 'apercu-badges.png'), clip: { x: 0, y: 0, width: 1000, height: 400 } });
  await browser.close();
  console.log(`${BADGES.length} badges écrits dans ${OUT}`);
})();
