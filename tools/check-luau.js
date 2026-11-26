#!/usr/bin/env node
/*
 * check-luau.js — analyse statique (syntaxe + types) de tous les fichiers .lua de src/
 * avec luau-lsp et les définitions de l'API Roblox, sans Roblox Studio.
 *
 * Prérequis (téléchargements uniques) :
 *   - luau-lsp : https://github.com/JohnnyMorganz/luau-lsp/releases (luau-lsp-linux-x86_64.zip…)
 *   - définitions Roblox : https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
 *
 * Utilisation :
 *   LUAU_LSP_BIN=/chemin/luau-lsp ROBLOX_DEFS=/chemin/globalTypes.d.luau node tools/check-luau.js
 *
 * Le script fabrique un « sourcemap » équivalent à l'arborescence Rojo
 * (src/shared -> ReplicatedStorage.Shared, src/server -> ServerScriptService.Server,
 * src/client -> StarterPlayer.StarterPlayerScripts.Client) pour que les
 * require(script.Parent.X) soient résolus et typés.
 */
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const LSP = process.env.LUAU_LSP_BIN || 'luau-lsp';
const DEFS = process.env.ROBLOX_DEFS;
if (!DEFS) {
  console.error('Variable ROBLOX_DEFS manquante (chemin de globalTypes.d.luau).');
  process.exit(2);
}

const MOUNTS = [
  ['src/shared', ['ReplicatedStorage', 'Shared']],
  ['src/server', ['ServerScriptService', 'Server']],
  ['src/client', ['StarterPlayer', 'StarterPlayerScripts', 'Client']],
];

function node(name, className, children = [], filePaths) {
  const n = { name, className, children };
  if (filePaths) n.filePaths = filePaths;
  return n;
}

function scriptInfo(file) {
  const base = path.basename(file);
  for (const [suffix, cls] of [
    ['.server.lua', 'Script'],
    ['.client.lua', 'LocalScript'],
    ['.server.luau', 'Script'],
    ['.client.luau', 'LocalScript'],
    ['.lua', 'ModuleScript'],
    ['.luau', 'ModuleScript'],
  ]) {
    if (base.endsWith(suffix)) return { name: base.slice(0, -suffix.length), cls };
  }
  return null;
}

function walk(dir, rel) {
  const children = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    const relPath = path.join(rel, entry.name);
    if (entry.isDirectory()) {
      children.push(node(entry.name, 'Folder', walk(full, relPath)));
    } else {
      const info = scriptInfo(entry.name);
      if (info) children.push(node(info.name, info.cls, [], [relPath]));
    }
  }
  return children;
}

const files = [];
const services = {};
for (const [dir, rbx] of MOUNTS) {
  const abs = path.join(ROOT, dir);
  if (!fs.existsSync(abs)) continue;
  let parent = services[rbx[0]] || (services[rbx[0]] = node(rbx[0], rbx[0]));
  for (const name of rbx.slice(1, -1)) {
    let child = parent.children.find((c) => c.name === name);
    if (!child) parent.children.push((child = node(name, name)));
    parent = child;
  }
  parent.children.push(node(rbx[rbx.length - 1], 'Folder', walk(abs, dir)));
  (function collect(d) {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const f = path.join(d, e.name);
      if (e.isDirectory()) collect(f);
      else if (scriptInfo(e.name)) files.push(path.relative(ROOT, f));
    }
  })(abs);
}

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'fct-sourcemap-'));
const sourcemap = path.join(tmp, 'sourcemap.json');
fs.writeFileSync(sourcemap, JSON.stringify(node('Game', 'DataModel', Object.values(services))));

console.log(`Analyse de ${files.length} fichier(s)…`);
const res = spawnSync(
  LSP,
  ['analyze', '--platform=roblox', `--definitions=${DEFS}`, `--sourcemap=${sourcemap}`, ...files],
  { cwd: ROOT, encoding: 'utf8' }
);
const output = ((res.stdout || '') + (res.stderr || ''))
  .split('\n')
  .filter((l) => l && !l.startsWith('[INFO]') && !l.startsWith('[WARN]'))
  .join('\n');
if (output) console.log(output);
if (res.error) {
  console.error(res.error.message);
  process.exit(2);
}
console.log(res.status === 0 && !output ? 'Aucune erreur.' : 'Des problèmes ont été trouvés.');
process.exit(res.status === 0 && !output ? 0 : 1);
