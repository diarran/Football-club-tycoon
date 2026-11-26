#!/usr/bin/env node
/*
 * world-3d.js — exporte la géométrie réellement générée par src/server/World
 * (via le mock Roblox et le binaire `luau`) en JSON, pour l'aperçu 3D web.
 * Utilisation : LUAU_BIN=/chemin/vers/luau node tools/world-3d.js build/world-parts.json
 */
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');
const { bundle } = require('./world-preview.js');

const out = process.argv[2] || path.join(__dirname, '..', 'build', 'world-parts.json');
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fct-3d-'));
const file = path.join(dir, 'bundle.luau');
fs.writeFileSync(file, bundle('tools/world-export3d.luau'));
const stdout = execFileSync(process.env.LUAU_BIN || 'luau', [file], { encoding: 'utf8', maxBuffer: 512 * 1024 * 1024 });
const json = stdout.slice(stdout.indexOf('@@JSON_BEGIN@@') + 14, stdout.indexOf('@@JSON_END@@'));
const parts = JSON.parse(json);
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, JSON.stringify(parts));
console.log(`${parts.length} Parts exportées dans ${out}`);
