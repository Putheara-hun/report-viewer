// Copy the Report Viewer and the report engine it uses from the ReportTool designer project.
//   npm run sync                      (ReportTool next to this folder: ../ReportTool)
//   npm run sync -- D:\path\ReportTool
// Only the files the viewer needs are copied: everything reachable from src/viewer/main.ts (static and dynamic
// imports), plus env.d.ts and public/viewer.js. The designer stays the one place where the engine is changed.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const RT = path.resolve(process.argv[2] || path.join(HERE, '..', 'ReportTool'));
const FROM = path.join(RT, 'src');
if (!fs.existsSync(path.join(FROM, 'viewer', 'main.ts'))) {
  console.error(`ReportTool not found at ${RT} (expected src/viewer/main.ts). Pass its folder: npm run sync -- <path>`);
  process.exit(1);
}

const seen = new Set();
function resolve(from, spec) {
  const base = path.resolve(path.dirname(from), spec);
  for (const c of [base, base + '.ts', base + '.vue', base + '.js', path.join(base, 'index.ts')]) if (fs.existsSync(c) && fs.statSync(c).isFile()) return c;
  return null;
}
function visit(file) {
  if (seen.has(file)) return;
  seen.add(file);
  const text = fs.readFileSync(file, 'utf8');
  const re = /(?:import|export)\s[^'"]*?from\s*['"]([^'"]+)['"]|import\(\s*['"]([^'"]+)['"]\s*\)|^\s*import\s+['"]([^'"]+)['"]/gm;
  for (const m of text.matchAll(re)) {
    const spec = m[1] ?? m[2] ?? m[3];
    if (!spec.startsWith('.')) continue;
    const r = resolve(file, spec);
    if (!r) throw new Error(`cannot resolve "${spec}" in ${path.relative(FROM, file)}`);
    visit(r);
  }
}
visit(path.join(FROM, 'viewer', 'main.ts'));
seen.add(path.join(FROM, 'env.d.ts'));

const copies = [...seen].map((f) => [f, path.join(HERE, 'src', path.relative(FROM, f))]);
copies.push([path.join(RT, 'public', 'viewer.js'), path.join(HERE, 'public', 'viewer.js')]);

// files that were copied before but are no longer needed are removed (src/ holds copies only)
const wanted = new Set(copies.map(([, to]) => path.resolve(to)));
function prune(dir) {
  if (!fs.existsSync(dir)) return;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) {
      prune(p);
      if (!fs.readdirSync(p).length) fs.rmdirSync(p);
    } else if (!wanted.has(path.resolve(p))) {
      fs.rmSync(p);
      console.log('removed  ' + path.relative(HERE, p));
    }
  }
}
prune(path.join(HERE, 'src'));

let changed = 0;
for (const [from, to] of copies) {
  const data = fs.readFileSync(from);
  if (fs.existsSync(to) && fs.readFileSync(to).equals(data)) continue;
  fs.mkdirSync(path.dirname(to), { recursive: true });
  fs.writeFileSync(to, data);
  changed++;
  console.log('updated  ' + path.relative(HERE, to));
}
console.log(`${copies.length} files from ${RT} — ${changed} updated`);
