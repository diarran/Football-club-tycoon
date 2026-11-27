#!/usr/bin/env node
/*
 * world-preview.js — vérification + aperçu vue de dessus du monde, SANS Roblox Studio.
 *
 * Ce script :
 *   1. assemble tools/roblox-mock.luau (fausse API Roblox minimale), les VRAIS
 *      modules src/shared/WorldConfig.lua + src/server/World/*.lua et
 *      tools/world-check.luau dans un seul fichier temporaire ;
 *   2. l'exécute avec le binaire `luau` (https://github.com/luau-lang/luau/releases) ;
 *   3. affiche les erreurs détectées (Parts non ancrées, chevauchements, Part
 *      hors de son terrain…) et le nombre de Parts par niveau ;
 *   4. dessine la vue de dessus (géométrie réellement générée par le code) en
 *      PNG avec Playwright/Chromium : docs/world/district-layout.png et
 *      docs/world/plot-layout.png.
 *
 * Utilisation :  LUAU_BIN=/chemin/vers/luau node tools/world-preview.js
 *                (option --no-images pour seulement vérifier)
 * Code de sortie 1 si une vérification échoue.
 */
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const OUT_DIR = path.join(ROOT, 'docs', 'world');
const LUAU = process.env.LUAU_BIN || 'luau';
const noImages = process.argv.includes('--no-images');

// Modules du jeu : [clé, chemin Roblox, classe, fichier].
const MODULES = [
  // Tous les modules partagés (les modules du monde en requièrent de plus en plus).
  ...fs.readdirSync(path.join(ROOT, 'src/shared')).filter((f) => f.endsWith('.lua')).map((f) => {
    const n = f.slice(0, -4);
    return [n, ['ReplicatedStorage', 'Shared', n], 'ModuleScript', `src/shared/${f}`];
  }),
  ...fs.readdirSync(path.join(ROOT, 'src/shared/Lang')).filter((f) => f.endsWith('.lua')).map((f) => {
    const n = f.slice(0, -4);
    return [`Lang_${n}`, ['ReplicatedStorage', 'Shared', 'Lang', n], 'ModuleScript', `src/shared/Lang/${f}`];
  }),
  ...['PartUtil', 'Props', 'Landscape', 'CampusBuildings', 'CampusZone', 'District', 'Pitch', 'Stands', 'LockerRoom', 'TrainingZone', 'Offices', 'Shop', 'Academy', 'VipLounge', 'Entrance', 'Prestige', 'WorldBuilder'].map(
    (n) => [n, ['ServerScriptService', 'Server', 'World', n], 'ModuleScript', `src/server/World/${n}.lua`]
  ),
  ['WorldPreview', ['ServerScriptService', 'Server', 'World', 'WorldPreview'], 'Script', 'src/server/World/WorldPreview.server.lua'],
];

function bundle(tailScript = 'tools/world-check.luau') {
  const read = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8');
  let src = `local mock = (function()\n${read('tools/roblox-mock.luau')}\nend)()\n`;
  src += 'local Vector3, Vector2, CFrame, Color3 = mock.env.Vector3, mock.env.Vector2, mock.env.CFrame, mock.env.Color3\n';
  src += 'local UDim, UDim2, Enum, Instance = mock.env.UDim, mock.env.UDim2, mock.env.Enum, mock.env.Instance\n';
  src += 'local game, workspace, require, task = mock.env.game, mock.env.workspace, mock.env.require, mock.env.task\n';
  src += 'local warn, typeof = mock.env.warn, mock.env.typeof\n';
  src += 'local MODULES = {}\n';
  for (const [key, rbxPath, cls, file] of MODULES) {
    // « export type » n'est autorisé qu'au niveau supérieur d'un fichier : on le
    // transforme en « type » local puisque chaque module est ici enveloppé dans une fonction.
    const body = read(file).replace(/^export type /gm, 'type ');
    src += `MODULES.${key} = mock.register(${JSON.stringify(rbxPath).replace('[', '{').replace(/]$/, '}')}, "${cls}", function(script)\n${body}\nend)\n`;
  }
  src += read(tailScript);
  return src;
}

function runLuau() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fct-world-'));
  const file = path.join(dir, 'bundle.luau');
  fs.writeFileSync(file, bundle());
  let stdout;
  try {
    stdout = execFileSync(LUAU, [file], { encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 });
  } catch (err) {
    console.error('Échec de l’exécution Luau :\n' + (err.stdout || '') + (err.stderr || err.message));
    process.exit(1);
  }
  const begin = stdout.indexOf('@@JSON_BEGIN@@');
  const end = stdout.indexOf('@@JSON_END@@');
  const logs = stdout.slice(0, begin).trim();
  if (logs) console.log(logs);
  return JSON.parse(stdout.slice(begin + '@@JSON_BEGIN@@'.length, end));
}

// ----------------------------------------------------------------------------- dessin SVG
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;');

function partsSvg(parts) {
  return parts
    .slice()
    .sort((a, b) => a.top - b.top)
    .map((p) => {
      const opacity = Math.max(0.25, 1 - p.t);
      if (p.shape === 'Ball' || p.shape === 'Cylinder') {
        const cx = p.pts.reduce((s, q) => s + q[0], 0) / 4;
        const cz = p.pts.reduce((s, q) => s + q[1], 0) / 4;
        const d1 = Math.hypot(p.pts[1][0] - p.pts[0][0], p.pts[1][1] - p.pts[0][1]);
        const d2 = Math.hypot(p.pts[2][0] - p.pts[1][0], p.pts[2][1] - p.pts[1][1]);
        return `<ellipse cx="${cx}" cy="${cz}" rx="${d1 / 2}" ry="${d2 / 2}" fill="${p.c}" fill-opacity="${opacity}"/>`;
      }
      const pts = p.pts.map((q) => q.join(',')).join(' ');
      return `<polygon points="${pts}" fill="${p.c}" fill-opacity="${opacity}" stroke="rgba(0,0,0,0.18)" stroke-width="0.08"/>`;
    })
    .join('\n');
}

const FACILITY_LABELS = {
  Pitch: 'Terrain',
  Stands: 'Tribunes',
  LockerRoom: 'Vestiaires',
  Training: 'Entraînement',
  Offices: 'Bureaux',
  Shop: 'Boutique',
  Academy: 'Formation',
  VIP: 'Espace VIP',
  Entrance: 'Entrée',
};

function districtSvg(data) {
  const [W, H] = data.districtSize;
  const scale = 1.5; // px CSS par stud
  const pad = 30;
  const header = 46;
  const width = W * scale + 2 * pad;
  const height = H * scale + 2 * pad + header;
  const half = data.plotSize[1] / 2;
  // Étiquette au fond de chaque terrain (côté opposé à la route).
  const slots = data.slots
    .map(
      (s) =>
        `<text x="${s.x}" y="${s.z < 0 ? s.z - half + 14 : s.z + half - 8}" font-family="Helvetica, Arial, sans-serif" text-anchor="middle" font-size="11" font-weight="700" fill="#fff" stroke="#000" stroke-width="2.4" paint-order="stroke">Terrain ${s.slot} — ${esc(s.club)} (niv. ${s.level})</text>`
    )
    .join('\n');
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">
  <rect width="100%" height="100%" fill="#1d232c"/>
  <text x="${pad}" y="30" font-family="Helvetica, Arial, sans-serif" font-size="20" font-weight="700" fill="#fff">Football Club Tycoon — quartier sportif (vue de dessus, ${W} × ${H} studs)</text>
  <g transform="translate(${pad + (W * scale) / 2}, ${pad + header + (H * scale) / 2}) scale(${scale})">
    ${partsSvg(data.parts)}
    ${slots}
    <text x="0" y="-3" font-family="Helvetica, Arial, sans-serif" font-size="7" font-weight="700" fill="#1d232c" text-anchor="middle">SPAWN</text>
    <g transform="translate(${-W / 2 + 10}, ${H / 2 - 10})" font-family="Helvetica, Arial, sans-serif">
      <rect x="0" y="-3" width="100" height="3" fill="#fff"/><text x="0" y="-6" font-size="9" fill="#fff">100 studs</text>
    </g>
  </g>
</svg>`;
}

function plotSvg(data) {
  const [PW, PH] = data.plotSize;
  const scale = 1.6;
  const pad = 20;
  const header = 40;
  const caption = 30;
  const panelW = PW * scale;
  const panelH = PH * scale;
  const width = 5 * panelW + 6 * pad;
  const height = panelH + 2 * pad + header + caption;
  const panels = [1, 2, 3, 4, 5]
    .map((slot, i) => {
      const s = data.slots.find((x) => x.slot === slot);
      const parts = data.parts.filter((p) => p.g === `Plot${slot}`);
      const fps = data.footprints.filter((f) => f.slot === slot);
      const ox = pad + i * (panelW + pad);
      const oy = pad + header;
      const outlines =
        slot === 3
          ? fps
              .map((f) => {
                const xs = f.pts.map((q) => q[0]);
                const zs = f.pts.map((q) => q[1]);
                const cx = (Math.min(...xs) + Math.max(...xs)) / 2;
                const top = Math.min(...zs);
                const lbl = FACILITY_LABELS[f.key] || f.key;
                return `<polygon points="${f.pts.map((q) => q.join(',')).join(' ')}" fill="none" stroke="#ffd23f" stroke-width="0.6" stroke-dasharray="3 2"/>
                  <text x="${cx}" y="${f.key === 'Pitch' ? top + 6 : top - 1.5}" font-size="5" font-family="Helvetica, Arial, sans-serif" font-weight="700" fill="#ffd23f" stroke="#000" stroke-width="0.8" paint-order="stroke" text-anchor="middle">${lbl}</text>`;
              })
              .join('\n')
          : '';
      // Le terrain occupe [x ± PW/2, z ± PH/2] (rotation 180° = même rectangle).
      return `<g transform="translate(${ox}, ${oy})">
        <svg x="0" y="0" width="${panelW}" height="${panelH}" viewBox="${s.x - PW / 2} ${s.z - PH / 2} ${PW} ${PH}">
          <rect x="${s.x - PW / 2}" y="${s.z - PH / 2}" width="${PW}" height="${PH}" fill="#56803f"/>
          <g transform="${s.z > 0 ? `rotate(180 ${s.x} ${s.z})` : ''}">${partsSvg(parts)}</g>
          ${outlines}
        </svg>
        <rect width="${panelW}" height="${panelH}" fill="none" stroke="#fff" stroke-width="1"/>
        <text x="${panelW / 2}" y="${panelH + 20}" font-family="Helvetica, Arial, sans-serif" font-size="13" font-weight="700" fill="#fff" text-anchor="middle">Niveau ${slot} — ${esc(s.club)}  (▼ entrée côté route)</text>
      </g>`;
    })
    .join('\n');
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">
  <rect width="100%" height="100%" fill="#1d232c"/>
  <text x="${pad}" y="32" font-family="Helvetica, Arial, sans-serif" font-size="20" font-weight="700" fill="#fff">Terrain de club ${PW} × ${PH} studs — installations aux niveaux 1 à 5 (pointillés : empreintes réservées)</text>
  ${panels}
</svg>`;
}

async function renderPng(svg, file) {
  const { chromium } = require('playwright');
  const browser = await chromium.launch();
  try {
    const m = svg.match(/width="([\d.]+)" height="([\d.]+)"/);
    const page = await browser.newPage({
      viewport: { width: Math.ceil(+m[1]), height: Math.ceil(+m[2]) },
      deviceScaleFactor: 2,
    });
    await page.setContent(`<html><body style="margin:0">${svg}</body></html>`);
    await page.screenshot({ path: file, clip: { x: 0, y: 0, width: +m[1], height: +m[2] } });
  } finally {
    await browser.close();
  }
}

async function main() {
  const data = runLuau();

  console.log(`\nParts du quartier (District) : ${data.districtParts}`);
  console.log('Parts par terrain (toutes les installations au même niveau) :');
  for (const row of data.counts) {
    const detail = Object.entries(row.facilities)
      .map(([k, v]) => `${k}=${v}`)
      .join(', ');
    console.log(`  niveau ${row.level} : ${row.total} Parts  (${detail})`);
  }

  if (data.errors.length) {
    console.error(`\n${data.errors.length} problème(s) détecté(s) :`);
    for (const e of data.errors.slice(0, 50)) console.error('  - ' + e);
  } else {
    console.log('\nVérifications OK : Parts ancrées, aucune Part hors de son terrain ni de son empreinte, aucun chevauchement, API conforme.');
  }

  if (!noImages) {
    fs.mkdirSync(OUT_DIR, { recursive: true });
    await renderPng(districtSvg(data), path.join(OUT_DIR, 'district-layout.png'));
    await renderPng(plotSvg(data), path.join(OUT_DIR, 'plot-layout.png'));
    console.log(`Images écrites dans ${path.relative(ROOT, OUT_DIR)}/ (district-layout.png, plot-layout.png)`);
  }
  process.exit(data.errors.length ? 1 : 0);
}

if (require.main === module) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}

module.exports = { bundle };
