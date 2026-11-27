#!/usr/bin/env node
/*
 * world-render.js — rend des images PNG « semi-réalistes » du monde généré.
 *
 * Utilisation :
 *   LUAU_BIN=luau node tools/world-3d.js build/world-parts.json
 *   THREE_DIR=/chemin/vers/three/package node tools/world-render.js build/world-parts.json vues.json dossier-sortie
 *
 * vues.json = [{ "name": "club", "pos": [x,y,z], "target": [x,y,z], "fov": 45, "sun": [x,y,z] }]
 * THREE_DIR = dossier « package » de three.js (npm pack three && tar xzf three-*.tgz).
 *
 * Ce n'est PAS le moteur de Roblox : matériaux et lumière sont imités (textures
 * procédurales, ombres, reflets), pour montrer formes, couleurs et ambiance.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const http = require('http');
const { chromium } = require('playwright');

const [partsFile, viewsFile, outDir] = process.argv.slice(2);
const THREE_DIR = process.env.THREE_DIR;
if (!partsFile || !viewsFile || !outDir || !THREE_DIR) {
  console.error('Utilisation : THREE_DIR=… node tools/world-render.js parts.json vues.json dossier');
  process.exit(1);
}
const WIDTH = Number(process.env.WIDTH || 1600);
const HEIGHT = Number(process.env.HEIGHT || 900);

const PAGE = String.raw`<!DOCTYPE html><html><body style="margin:0;background:#000">
<script type="importmap">{"imports":{"three":"/three/build/three.module.js","three/addons/":"/three/examples/jsm/"}}</script>
<script type="module">
import * as THREE from 'three';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import { Sky } from 'three/addons/objects/Sky.js';

const W = ${WIDTH}, H = ${HEIGHT};
const renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true });
renderer.setSize(W, H);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 0.8;
renderer.outputColorSpace = THREE.SRGBColorSpace;
document.body.appendChild(renderer.domElement);

const scene = new THREE.Scene();
const pmrem = new THREE.PMREMGenerator(renderer);
scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;

// --- textures procédurales (motif clair multiplié par la couleur de la Part)
function canvasTex(size, draw, srgb = true) {
  const c = document.createElement('canvas'); c.width = c.height = size;
  const g = c.getContext('2d'); draw(g, size);
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping; t.anisotropy = 8;
  if (srgb) t.colorSpace = THREE.SRGBColorSpace;
  return t;
}
function rnd(seed) { let s = seed; return () => (s = (s * 16807) % 2147483647) / 2147483647; }
function noise(g, n, amp, base, seed, blob = 1) {
  const r = rnd(seed); g.fillStyle = 'rgb(' + base + ',' + base + ',' + base + ')'; g.fillRect(0, 0, n, n);
  for (let i = 0; i < n * n / 6; i++) { const v = base + (r() - 0.5) * 2 * amp; g.fillStyle = 'rgba(' + v + ',' + v + ',' + v + ',0.5)'; g.fillRect(r() * n, r() * n, blob, blob); }
}
const TEX = {
  Concrete: canvasTex(256, (g, n) => { noise(g, n, 26, 225, 7, 2); }),
  Grass: canvasTex(256, (g, n) => { noise(g, n, 40, 215, 3, 2); }),
  Asphalt: canvasTex(256, (g, n) => { noise(g, n, 40, 200, 11, 1); }),
  Metal: canvasTex(256, (g, n) => { g.fillStyle = '#eee'; g.fillRect(0, 0, n, n); const r = rnd(5); for (let y = 0; y < n; y++) { const v = 225 + r() * 30; g.fillStyle = 'rgb(' + v + ',' + v + ',' + v + ')'; g.fillRect(0, y, n, 1); } }),
  Brick: canvasTex(256, (g, n) => { g.fillStyle = '#bbb'; g.fillRect(0, 0, n, n); const r = rnd(9); const bh = n / 8; for (let y = 0; y < 8; y++) for (let x = -1; x < 5; x++) { const v = 215 + r() * 40; g.fillStyle = 'rgb(' + v + ',' + v * 0.97 + ',' + v * 0.95 + ')'; g.fillRect(x * n / 4 + (y % 2) * n / 8 + 2, y * bh + 2, n / 4 - 4, bh - 4); } }),
  WoodPlanks: canvasTex(256, (g, n) => { const r = rnd(13); for (let y = 0; y < 8; y++) { const v = 200 + r() * 50; g.fillStyle = 'rgb(' + v + ',' + v + ',' + v + ')'; g.fillRect(0, y * n / 8, n, n / 8 - 2); g.fillStyle = 'rgba(0,0,0,0.25)'; g.fillRect(r() * n, y * n / 8, 2, n / 8); } }),
  Wood: canvasTex(256, (g, n) => { const r = rnd(17); for (let y = 0; y < n; y += 2) { const v = 210 + Math.sin(y * 0.15 + r()) * 25; g.fillStyle = 'rgb(' + v + ',' + v + ',' + v + ')'; g.fillRect(0, y, n, 2); } }),
  Marble: canvasTex(512, (g, n) => { g.fillStyle = '#f4f4f4'; g.fillRect(0, 0, n, n); const r = rnd(21); g.strokeStyle = 'rgba(120,120,130,0.35)'; for (let i = 0; i < 14; i++) { g.lineWidth = 0.5 + r() * 2; g.beginPath(); let x = r() * n, y = 0; g.moveTo(x, y); while (y < n) { x += (r() - 0.5) * 40; y += 20; g.lineTo(x, y); } g.stroke(); } }),
  Tiles: canvasTex(256, (g, n) => { g.fillStyle = '#aaa'; g.fillRect(0, 0, n, n); for (let y = 0; y < 4; y++) for (let x = 0; x < 4; x++) { g.fillStyle = '#f0f0f0'; g.fillRect(x * n / 4 + 1, y * n / 4 + 1, n / 4 - 2, n / 4 - 2); } }),
  Fabric: canvasTex(128, (g, n) => { g.fillStyle = '#ddd'; g.fillRect(0, 0, n, n); g.fillStyle = 'rgba(255,255,255,0.4)'; for (let i = 0; i < n; i += 4) { g.fillRect(i, 0, 1, n); g.fillRect(0, i, n, 1); } }),
  Plate: canvasTex(128, (g, n) => { g.fillStyle = '#ccc'; g.fillRect(0, 0, n, n); g.fillStyle = '#fff'; for (let y = 0; y < n; y += 16) for (let x = (y / 16) % 2 * 8; x < n; x += 16) g.fillRect(x, y, 6, 2); }),
};
// [texture, taille d'une répétition en studs, rugosité, métal]
const MAT = {
  Plastic: [null, 8, 0.6, 0], SmoothPlastic: [null, 8, 0.45, 0],
  Concrete: ['Concrete', 12, 0.92, 0], Pavement: ['Tiles', 8, 0.9, 0], Cobblestone: ['Tiles', 4, 0.9, 0],
  Grass: ['Grass', 10, 1, 0], LeafyGrass: ['Grass', 10, 1, 0], Ground: ['Grass', 10, 1, 0], Sand: ['Concrete', 10, 1, 0],
  Asphalt: ['Asphalt', 10, 0.85, 0], Slate: ['Concrete', 8, 0.8, 0], Granite: ['Concrete', 6, 0.5, 0], Basalt: ['Concrete', 6, 0.7, 0],
  Metal: ['Metal', 4, 0.32, 0.85], DiamondPlate: ['Plate', 3, 0.4, 0.8], CorrodedMetal: ['Concrete', 4, 0.7, 0.5], Foil: [null, 4, 0.2, 1],
  Brick: ['Brick', 6, 0.9, 0], WoodPlanks: ['WoodPlanks', 8, 0.75, 0], Wood: ['Wood', 6, 0.7, 0],
  Marble: ['Marble', 12, 0.18, 0], CeramicTiles: ['Tiles', 4, 0.3, 0], Plaster: ['Concrete', 12, 0.95, 0],
  Fabric: ['Fabric', 2, 1, 0], Carpet: ['Fabric', 2, 1, 0], Leather: [null, 4, 0.55, 0], Rubber: [null, 4, 0.9, 0],
  Pebble: ['Concrete', 3, 0.95, 0], Ice: [null, 8, 0.1, 0], Limestone: ['Concrete', 6, 0.85, 0], Sandstone: ['Concrete', 6, 0.9, 0],
};
const mats = new Map();
function material(p) {
  const key = p.m + '|' + p.c.join(',') + '|' + p.t;
  let m = mats.get(key); if (m) return m;
  const color = new THREE.Color().setRGB(p.c[0], p.c[1], p.c[2], THREE.SRGBColorSpace);
  if (p.m === 'Neon') m = new THREE.MeshStandardMaterial({ color, emissive: color, emissiveIntensity: 1.6 });
  else if (p.m === 'Glass') m = new THREE.MeshPhysicalMaterial({ color: color.clone().lerp(new THREE.Color(0.12, 0.16, 0.2), 0.55), roughness: 0.04, metalness: 0.3, transparent: true, opacity: Math.min(0.92, 0.55 + (1 - p.t) * 0.4), envMapIntensity: 2.2, clearcoat: 1 });
  else {
    const def = MAT[p.m] || MAT.Plastic;
    m = new THREE.MeshStandardMaterial({ color, roughness: def[2], metalness: def[3], map: def[0] ? TEX[def[0]] : null, envMapIntensity: def[3] > 0.5 ? 1.4 : 0.7 });
    if (p.t > 0) { m.transparent = true; m.opacity = 1 - p.t; }
  }
  mats.set(key, m); return m;
}
function tileOf(p) { return (MAT[p.m] || MAT.Plastic)[1]; }
// UV en studs : chaque face répète la texture selon sa taille réelle.
function boxGeo(s, tile) {
  const g = new THREE.BoxGeometry(s[0], s[1], s[2]);
  const uv = g.attributes.uv; const dims = [[s[2], s[1]], [s[2], s[1]], [s[0], s[2]], [s[0], s[2]], [s[0], s[1]], [s[0], s[1]]];
  for (let f = 0; f < 6; f++) for (let v = 0; v < 4; v++) { const i = f * 4 + v; uv.setXY(i, uv.getX(i) * dims[f][0] / tile, uv.getY(i) * dims[f][1] / tile); }
  return g;
}
function wedgeGeo(s) {
  const [w, h, d] = s; const shape = new THREE.Shape();
  shape.moveTo(-d / 2, -h / 2); shape.lineTo(d / 2, -h / 2); shape.lineTo(d / 2, h / 2); shape.lineTo(-d / 2, -h / 2);
  const g = new THREE.ExtrudeGeometry(shape, { depth: w, bevelEnabled: false });
  g.translate(0, 0, -w / 2); g.rotateY(-Math.PI / 2); // profil (z, y) extrudé le long de X
  return g;
}
const FACES = { Front: [0, 0, -1], Back: [0, 0, 1], Right: [1, 0, 0], Left: [-1, 0, 0], Top: [0, 1, 0], Bottom: [0, -1, 0] };
function labelMesh(p, l) {
  const n = FACES[l.f] || FACES.Front; const s = p.s;
  const fw = n[0] ? s[2] : s[0], fh = n[1] ? s[2] : s[1];
  const ppu = 48; const cw = Math.max(16, Math.min(2048, Math.round(fw * ppu))), ch = Math.max(16, Math.min(2048, Math.round(fh * ppu)));
  const c = document.createElement('canvas'); c.width = cw; c.height = ch; const g = c.getContext('2d');
  if (l.bg) { g.fillStyle = 'rgb(' + l.bg.map((v) => v * 255).join(',') + ')'; g.fillRect(0, 0, cw, ch); }
  g.fillStyle = 'rgb(' + l.tc.map((v) => v * 255).join(',') + ')';
  let size = ch * 0.8; g.font = 'bold ' + size + 'px Arial';
  const tw = g.measureText(l.x).width; if (tw > cw * 0.92) { size *= cw * 0.92 / tw; g.font = 'bold ' + size + 'px Arial'; }
  g.textAlign = 'center'; g.textBaseline = 'middle'; g.fillText(l.x, cw / 2, ch / 2);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 8;
  const mesh = new THREE.Mesh(new THREE.PlaneGeometry(fw, fh), new THREE.MeshStandardMaterial({ map: t, transparent: !l.bg, roughness: 0.6, emissive: new THREE.Color(1, 1, 1), emissiveMap: t, emissiveIntensity: 0.35 }));
  const off = 0.02; mesh.position.set(n[0] * (s[0] / 2 + off), n[1] * (s[1] / 2 + off), n[2] * (s[2] / 2 + off));
  mesh.lookAt(n[0] * 10, n[1] * 10, n[2] * 10);
  return mesh;
}
window.build = (parts) => {
  for (const p of parts) {
    let geo;
    if (p.h === 'Cylinder') { geo = new THREE.CylinderGeometry(Math.min(p.s[1], p.s[2]) / 2, Math.min(p.s[1], p.s[2]) / 2, p.s[0], 28); geo.rotateZ(Math.PI / 2); }
    else if (p.h === 'Ball') geo = new THREE.SphereGeometry(Math.min(...p.s) / 2, 24, 16);
    else if (p.h === 'Wedge') geo = wedgeGeo(p.s);
    else geo = boxGeo(p.s, tileOf(p));
    const mesh = new THREE.Mesh(geo, material(p));
    const r = p.r;
    const m4 = new THREE.Matrix4().set(r[0], r[1], r[2], p.p[0], r[3], r[4], r[5], p.p[1], r[6], r[7], r[8], p.p[2], 0, 0, 0, 1);
    mesh.applyMatrix4(m4);
    mesh.castShadow = p.t < 0.5 && p.m !== 'Glass' && p.s[1] > 0.12; mesh.receiveShadow = true;
    for (const l of p.l || []) mesh.add(labelMesh(p, l));
    scene.add(mesh);
  }
  // grand sol autour du quartier
  const ground = new THREE.Mesh(new THREE.PlaneGeometry(6000, 6000), new THREE.MeshStandardMaterial({ color: 0x5b7f45, roughness: 1, map: TEX.Grass }));
  TEX.Grass.repeat.set(1, 1); ground.rotation.x = -Math.PI / 2; ground.position.y = -0.3; ground.receiveShadow = true; scene.add(ground);
};
const sky = new Sky(); sky.scale.setScalar(10000); scene.add(sky);
const su = sky.material.uniforms; su.turbidity.value = 4; su.rayleigh.value = 1.2; su.mieCoefficient.value = 0.004; su.mieDirectionalG.value = 0.8;
const sunLight = new THREE.DirectionalLight(0xfff1dc, 3.2); sunLight.castShadow = true;
sunLight.shadow.mapSize.set(4096, 4096); sunLight.shadow.bias = -0.0004; sunLight.shadow.normalBias = 0.6;
scene.add(sunLight); scene.add(sunLight.target);
scene.add(new THREE.HemisphereLight(0xcfe3ff, 0x5a6b45, 0.55));
scene.fog = new THREE.Fog(0xc9d6e3, 500, 2600);
window.shot = (v) => {
  const cam = new THREE.PerspectiveCamera(v.fov || 45, W / H, 0.5, 8000);
  cam.position.set(...v.pos); cam.lookAt(...v.target);
  const sunDir = new THREE.Vector3(...(v.sun || [-0.5, 0.75, -0.45])).normalize();
  su.sunPosition.value.copy(sunDir);
  const t = new THREE.Vector3(...v.target); const span = v.shadowSpan || 220;
  sunLight.position.copy(t).addScaledVector(sunDir, 600); sunLight.target.position.copy(t);
  const sc = sunLight.shadow.camera; sc.left = -span; sc.right = span; sc.top = span; sc.bottom = -span; sc.near = 10; sc.far = 1400; sc.updateProjectionMatrix();
  renderer.render(scene, cam);
  return renderer.domElement.toDataURL('image/png');
};
window.ready = true;
</script></body></html>`;

const MIME = { '.js': 'text/javascript', '.html': 'text/html' };
const server = http.createServer((req, res) => {
  const url = decodeURIComponent(req.url.split('?')[0]);
  if (url === '/') { res.writeHead(200, { 'content-type': 'text/html' }); return res.end(PAGE); }
  if (url.startsWith('/three/')) {
    const file = path.join(THREE_DIR, url.slice(7));
    if (file.startsWith(path.resolve(THREE_DIR)) && fs.existsSync(file)) {
      res.writeHead(200, { 'content-type': MIME[path.extname(file)] || 'application/octet-stream' });
      return res.end(fs.readFileSync(file));
    }
  }
  res.writeHead(404); res.end();
});

(async () => {
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const port = server.address().port;
  const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const page = await browser.newPage({ viewport: { width: WIDTH, height: HEIGHT } });
  page.on('console', (m) => { if (m.type() === 'error') console.error('[page]', m.text()); });
  page.on('pageerror', (e) => console.error('[page]', e.message));
  await page.goto(`http://127.0.0.1:${port}/`);
  await page.waitForFunction(() => window.ready === true, null, { timeout: 120000 });
  const parts = JSON.parse(fs.readFileSync(partsFile, 'utf8'));
  await page.evaluate((p) => window.build(p), parts);
  fs.mkdirSync(outDir, { recursive: true });
  for (const view of JSON.parse(fs.readFileSync(viewsFile, 'utf8'))) {
    const data = await page.evaluate((v) => window.shot(v), view);
    const out = path.join(outDir, `${view.name}.png`);
    fs.writeFileSync(out, Buffer.from(data.split(',')[1], 'base64'));
    console.log('Image :', out);
  }
  await browser.close();
  server.close();
})().catch((e) => { console.error(e); process.exit(1); });
