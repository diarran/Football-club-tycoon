#!/usr/bin/env node
/*
 * economy-sim.js — simule la progression de joueurs types sur le vrai code du jeu.
 *
 * Assemble tools/economy-sim.luau comme un fichier de test (voir tests/run-tests.js)
 * et l'exécute avec Luau. Affiche un rapport en Markdown : temps et nombre de
 * matchs pour monter de D7 à D5, moment où chaque amélioration devient abordable,
 * sources de monnaie anormales ou blocages.
 *
 * Utilisation :  LUAU_BIN=/chemin/vers/luau node tools/economy-sim.js [parties] [--strict]
 *   --strict : code de sortie 1 si un problème est détecté (utilisé par la CI).
 */
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const { bundle, LUAU } = require('../tests/run-tests.js');

const args = process.argv.slice(2);
const strict = args.includes('--strict');
const runs = Number(args.find((a) => /^\d+$/.test(a)) || 40);

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'fct-sim-'));
const spec = path.join(tmp, 'economy-sim.luau');
fs.writeFileSync(spec, `local SIM_RUNS = ${runs}\n` + fs.readFileSync(path.join(__dirname, 'economy-sim.luau'), 'utf8'));
const file = path.join(tmp, 'economy-sim.bundle.luau');
fs.writeFileSync(file, bundle(spec));

const run = spawnSync(LUAU, [file], { encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 });
if (run.error) {
  console.error(`Impossible de lancer « ${LUAU} » : ${run.error.message}`);
  process.exit(2);
}
const out = (run.stdout || '') + (run.stderr || '');
process.stdout.write(out.replace(/@@RESULT.*\n?/, ''));
if (run.status !== 0 || !/@@RESULT/.test(out)) {
  console.error('La simulation s\'est arrêtée avant la fin.');
  process.exit(1);
}
process.exit(strict && /⚠/.test(out) ? 1 : 0);
