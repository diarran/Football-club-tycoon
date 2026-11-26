#!/usr/bin/env node
/*
 * run-tests.js — lance les tests automatiques du serveur, sans Roblox Studio.
 *
 * Pour chaque fichier tests/specs/*.spec.luau, le script assemble dans un seul
 * fichier temporaire :
 *   1. tools/roblox-mock.luau  (fausse API Roblox de base) ;
 *   2. tests/harness.luau      (horloge, DataStore en mémoire, joueurs, remotes…) ;
 *   3. TOUS les vrais fichiers de src/ (serveur, partagé, client), rangés comme
 *      Rojo les range dans le jeu ;
 *   4. le fichier de test.
 * puis l'exécute avec le binaire `luau` (https://github.com/luau-lang/luau/releases).
 * Chaque fichier de test démarre donc sur un serveur neuf.
 *
 * Utilisation :  LUAU_BIN=/chemin/vers/luau node tests/run-tests.js [filtre]
 */
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const LUAU = process.env.LUAU_BIN || 'luau';
const read = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8');

const MOUNTS = [
  ['src/shared', ['ReplicatedStorage', 'Shared'], ''],
  ['src/server', ['ServerScriptService', 'Server'], ''],
  ['src/client', ['StarterPlayer', 'StarterPlayerScripts', 'Client'], 'Client_'],
];

function collectModules() {
  const modules = [];
  for (const [dir, rbxRoot, prefix] of MOUNTS) {
    const walk = (rel, rbxPath) => {
      for (const entry of fs.readdirSync(path.join(ROOT, rel), { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
        const file = `${rel}/${entry.name}`;
        if (entry.isDirectory()) {
          walk(file, [...rbxPath, entry.name]);
          continue;
        }
        const m = entry.name.match(/^(.*?)(\.server|\.client)?\.luau?$/);
        if (!m) continue;
        const cls = m[2] === '.server' ? 'Script' : m[2] === '.client' ? 'LocalScript' : 'ModuleScript';
        modules.push({ key: prefix + m[1], rbxPath: [...rbxPath, m[1]], cls, file });
      }
    };
    walk(dir, rbxRoot);
  }
  return modules;
}

function bundle(specFile) {
  let src = `local mock = (function()\n${read('tools/roblox-mock.luau')}\nend)()\n`;
  src += `local H = (function()\n${read('tests/harness.luau')}\nend)()\n`;
  src += 'local Vector3, Vector2, CFrame, Color3 = mock.env.Vector3, mock.env.Vector2, mock.env.CFrame, mock.env.Color3\n';
  src += 'local UDim, UDim2, Enum = mock.env.UDim, mock.env.UDim2, mock.env.Enum\n';
  src += 'local game, workspace, require, typeof = mock.env.game, mock.env.workspace, mock.env.require, mock.env.typeof\n';
  src += 'local Instance, task, os, Random, print, warn, TweenInfo = H.Instance, H.task, H.os, H.Random, H.print, H.warn, H.TweenInfo\n';
  src += 'local MODULES = {}\n';
  for (const { key, rbxPath, cls, file } of collectModules()) {
    // « export type » n'est permis qu'au niveau supérieur d'un fichier.
    const body = read(file).replace(/^export type /gm, 'type ');
    const luaPath = '{' + rbxPath.map((s) => JSON.stringify(s)).join(', ') + '}';
    src += `MODULES[${JSON.stringify(key)}] = mock.register(${luaPath}, "${cls}", function(script)\n${body}\nend)\n`;
  }
  src += `do\n${fs.readFileSync(specFile, 'utf8')}\nend\nH.finish()\n`;
  return src;
}

const filter = process.argv[2] || '';
const specDir = path.join(ROOT, 'tests', 'specs');
const specs = fs.readdirSync(specDir).filter((f) => f.endsWith('.spec.luau') && f.includes(filter)).sort();
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'fct-tests-'));

let passed = 0;
let failed = 0;
let crashed = 0;
for (const spec of specs) {
  console.log(`\n▶ ${spec}`);
  const file = path.join(tmp, spec.replace('.spec.luau', '.bundle.luau'));
  fs.writeFileSync(file, bundle(path.join(specDir, spec)));
  const run = spawnSync(LUAU, [file], { encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 });
  if (run.error) {
    console.error(`Impossible de lancer « ${LUAU} » : ${run.error.message}`);
    process.exit(2);
  }
  const out = (run.stdout || '') + (run.stderr || '');
  const m = out.match(/@@RESULT (\d+) (\d+)/);
  process.stdout.write(out.replace(/@@RESULT.*\n?/, ''));
  if (!m || run.status !== 0) {
    crashed += 1;
    console.log(`  ✘ le fichier de test s'est arrêté avant la fin (code ${run.status})`);
  }
  if (m) {
    passed += Number(m[1]);
    failed += Number(m[2]);
  }
}

console.log(`\n${passed} test(s) réussi(s), ${failed} échoué(s)${crashed ? `, ${crashed} fichier(s) interrompu(s)` : ''}.`);
process.exit(failed > 0 || crashed > 0 || specs.length === 0 ? 1 : 0);
