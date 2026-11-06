// Moves a set of functions out of game/scripts/arena.gd into a RefCounted component script.
//
//   node tools/extract_arena_module.mjs <spec.json> [--dry-run]
//
// spec: {"module": "loot", "script": "arena_loot.gd", "doc": ["## ..."], "functions": ["f", ...],
//        "vars": ["v", ...]}   (vars optional: arena state moved into the module)
//
// Inside moved functions, bare references to arena members are rewritten: vars and functions
// become arena.<name>, constants Arena.<name>, self becomes arena. Locals, parameters and
// functions moved together stay bare. Every moved function that anything outside the module
// still refers to (arena itself, other scripts, tests, string calls) keeps a one-line delegate in
// arena.gd, so the public surface tests rely on is unchanged. The component is created where
// arena's members are declared: `var <module> = <Const>.new(self)`.
//
// The tool prints bare calls it could not classify (likely Node methods inherited by arena);
// they are rewritten to arena.<name> as well. Godot's compiler is the final check.
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1')), '..');
const arenaPath = path.join(root, 'game/scripts/arena.gd');
const specPath = process.argv[2];
const dryRun = process.argv.includes('--dry-run');
const spec = JSON.parse(fs.readFileSync(specPath, 'utf8'));
const src = fs.readFileSync(arenaPath, 'utf8');
const eol = src.includes('\r\n') ? '\r\n' : '\n';
const lines = src.split(/\r?\n/);

const KEYWORDS = new Set(('if elif else for while match break continue pass return class class_name extends is in as ' +
  'self signal func static const enum var breakpoint preload await yield assert void true false null not and or ' +
  'PI TAU INF NAN super when').split(' '));
// @GlobalScope / @GDScript functions and builtin types callable bare.
const GLOBALS = new Set(('abs absf absi acos acosh angle_difference asin asinh atan atan2 atanh bezier_derivative ' +
  'bezier_interpolate bytes_to_var ceil ceilf ceili clamp clampf clampi cos cosh cubic_interpolate db_to_linear ' +
  'deg_to_rad ease error_string exp floor floorf floori fmod fposmod hash instance_from_id inverse_lerp ' +
  'is_equal_approx is_finite is_inf is_instance_id_valid is_instance_valid is_nan is_same is_zero_approx lerp ' +
  'lerp_angle lerpf linear_to_db log max maxf maxi min minf mini move_toward nearest_po2 pingpong posmod pow ' +
  'print print_rich print_verbose printerr printraw prints printt push_error push_warning rad_to_deg rand_from_seed ' +
  'randf randf_range randfn randi randi_range randomize remap rotate_toward round roundf roundi seed sign signf ' +
  'signi sin sinh smoothstep snapped snappedf snappedi sqrt step_decimals str str_to_var tan tanh type_convert ' +
  'type_string typeof var_to_bytes var_to_str weakref wrap wrapf wrapi Color char convert dict_to_inst ' +
  'get_stack inst_to_dict len load range type_exists ord ' +
  'bool int float String StringName NodePath Vector2 Vector2i Vector3 Vector3i Vector4 Vector4i Rect2 Rect2i ' +
  'Transform2D Transform3D Plane Quaternion AABB Basis Projection RID Callable Signal Dictionary Array ' +
  'PackedByteArray PackedInt32Array PackedInt64Array PackedFloat32Array PackedFloat64Array PackedStringArray ' +
  'PackedVector2Array PackedVector3Array PackedColorArray PackedVector4Array').split(' '));

// --- Top-level members of arena.gd.
const vars = new Set(), consts = new Set(), funcs = new Map();
lines.forEach((line, i) => {
  let m;
  if ((m = line.match(/^(?:@[\w_]+(?:\([^)]*\))?\s+)*var\s+([A-Za-z_]\w*)/))) vars.add(m[1]);
  else if ((m = line.match(/^const\s+([A-Za-z_]\w*)/))) consts.add(m[1]);
  else if ((m = line.match(/^func\s+([A-Za-z_]\w*)\s*\(/))) funcs.set(m[1], i);
});
const moved = new Set(spec.functions);
const movedVars = new Set(spec.vars || []);
for (const name of moved) if (!funcs.has(name)) throw new Error(`arena.gd has no func ${name}`);
for (const name of movedVars) if (!vars.has(name)) throw new Error(`arena.gd has no var ${name}`);

// A function block: its leading comment lines, the signature and every following line until the
// next top-level statement (indented lines, blank lines and comments between belong to it).
function blockOf(name) {
  const start = funcs.get(name);
  let first = start;
  while (first > 0 && /^#/.test(lines[first - 1])) first--;
  let end = start + 1;
  while (end < lines.length && !/^[^\s#]/.test(lines[end])) end++;
  // Trailing blank lines and column-0 comments belong to the next top-level statement.
  let last = end - 1;
  while (last > start && (/^\s*$/.test(lines[last]) || /^#/.test(lines[last]))) last--;
  return { first, start, last };
}
function varBlock(name) {
  const i = lines.findIndex(l => new RegExp(`^(?:@[\\w_]+(?:\\([^)]*\\))?\\s+)*var\\s+${name}\\b`).test(l));
  let first = i;
  while (first > 0 && /^#/.test(lines[first - 1])) first--;
  return { first, start: i, last: i };
}

// --- Tokenizer that leaves strings and comments alone.
function rewriteCode(text, keep, report) {
  let out = '', i = 0;
  while (i < text.length) {
    const c = text[i];
    if (c === '#') { const j = text.indexOf('\n', i); const e = j < 0 ? text.length : j; out += text.slice(i, e); i = e; continue; }
    if (c === '"' || c === "'") {
      const triple = text.startsWith(c.repeat(3), i);
      const q = triple ? c.repeat(3) : c;
      let j = i + q.length;
      while (j < text.length && !text.startsWith(q, j)) { if (text[j] === '\\') j++; j++; }
      j += q.length; out += text.slice(i, j); i = j; continue;
    }
    if (/[A-Za-z_]/.test(c) && !/[\w]/.test(text[i - 1] || '')) {
      let j = i; while (j < text.length && /\w/.test(text[j])) j++;
      const word = text.slice(i, j);
      let k = i - 1; while (k >= 0 && (text[k] === ' ' || text[k] === '\t')) k--;
      // Member access (a.b), node paths ($a) and annotations (@a) are not arena references.
      const afterDot = text[k] === '.' || text[k] === '$' || text[k] === '@';
      const isCall = text[j] === '(';
      out += afterDot ? word : resolve(word, isCall, keep, report);
      i = j; continue;
    }
    if (/[0-9]/.test(c)) { let j = i; while (j < text.length && /[\w.]/.test(text[j])) j++; out += text.slice(i, j); i = j; continue; }
    out += c; i++;
  }
  return out;
}
function resolve(word, isCall, keep, report) {
  if (word === 'self') return 'arena';
  if (KEYWORDS.has(word) || keep.has(word)) return word;
  if (moved.has(word)) return word;
  if (movedVars.has(word)) return word;
  if (vars.has(word) || funcs.has(word)) return `arena.${word}`;
  if (consts.has(word)) return `Arena.${word}`;
  if (isCall && !GLOBALS.has(word) && /^[a-z_]/.test(word)) { report.add(word); return `arena.${word}`; }
  return word;
}
function localsOf(text) {
  const names = new Set();
  for (const m of text.matchAll(/\b(?:var|const)\s+([A-Za-z_]\w*)/g)) names.add(m[1]);
  for (const m of text.matchAll(/\bfor\s+([A-Za-z_]\w*)\s+in\b/g)) names.add(m[1]);
  for (const m of text.matchAll(/\bfunc\s*\w*\s*\(([^)]*)\)/g)) {
    for (const p of m[1].split(',')) { const n = p.trim().match(/^([A-Za-z_]\w*)/); if (n) names.add(n[1]); }
  }
  return names;
}

// --- Collect blocks to move.
const blocks = [...moved].map(name => ({ name, ...blockOf(name) }));
const varBlocks = [...movedVars].map(name => ({ name, ...varBlock(name) }));
const unknownCalls = new Set();
const movedText = blocks.sort((a, b) => a.first - b.first).map(b => {
  const text = lines.slice(b.first, b.last + 1).join('\n');
  return rewriteCode(text, localsOf(lines.slice(b.start, b.last + 1).join('\n')), unknownCalls);
});
const movedVarText = varBlocks.sort((a, b) => a.first - b.first).map(b =>
  rewriteCode(lines.slice(b.first, b.last + 1).join('\n'), new Set(), unknownCalls));

// --- Which moved functions are still referenced from outside the module?
const outsideSources = [];
const removed = new Set();
for (const b of [...blocks, ...varBlocks]) for (let i = b.first; i <= b.last; i++) removed.add(i);
outsideSources.push(lines.filter((_, i) => !removed.has(i)).join('\n'));
for (const dir of ['game/scripts', 'game/tests', 'game/tests/helpers']) {
  for (const f of fs.readdirSync(path.join(root, dir))) {
    if (!f.endsWith('.gd') || f === 'arena.gd' || f === spec.script) continue;
    outsideSources.push(fs.readFileSync(path.join(root, dir, f), 'utf8'));
  }
}
const outside = outsideSources.join('\n');
const needsDelegate = name => new RegExp(`(?<![\\w])${name}(?![\\w])`).test(outside);
for (const v of movedVars) if (new RegExp(`(?<![\\w])${v}(?![\\w])`).test(outside)) {
  throw new Error(`var ${v} is still used outside the module; keep it on arena`);
}

// --- Delegates, in the moved functions' original order.
const constName = spec.const || spec.script.replace(/\.gd$/, '').split('_').map(s => s[0].toUpperCase() + s.slice(1)).join('');
const delegates = [];
for (const b of blocks) {
  if (!needsDelegate(b.name)) continue;
  const sig = lines[b.start];
  const m = sig.match(/^func\s+(\w+)\s*\((.*)\)\s*(->\s*([^:]+))?:\s*(.*)$/);
  if (!m) throw new Error(`cannot parse signature: ${sig}`);
  if (m[5].trim()) throw new Error(`single-line function body not supported: ${sig}`);
  const args = m[2].split(',').map(p => p.trim()).filter(Boolean).map(p => p.match(/^(\w+)/)[1]);
  const body = lines.slice(b.start + 1, b.last + 1).join('\n');
  const isAwait = /\bawait\b/.test(body);
  const call = `${isAwait ? 'await ' : ''}${spec.module}.${b.name}(${args.join(', ')})`;
  const ret = (m[4] || '').trim();
  delegates.push(`func ${m[1]}(${m[2]})${m[3] ? ' ' + m[3].trim() : ''}:`, ret === 'void' ? `\t${call}` : (ret === '' && !/\breturn\s+\S/.test(body) ? `\t${call}` : `\treturn ${call}`));
}

// --- New arena.gd.
const firstBlock = Math.min(...blocks.map(b => b.first));
const out = [];
let inserted = false;
for (let i = 0; i < lines.length; i++) {
  if (removed.has(i)) {
    if (!inserted && i === firstBlock && delegates.length) {
      out.push(`# ${spec.module}: ${spec.script} (delegates keep arena's existing surface).`, ...delegates, '');
      inserted = true;
    }
    continue;
  }
  out.push(lines[i]);
}
// Collapse runs of more than one blank line created by removals.
const compact = [];
for (const l of out) { if (l.trim() === '' && compact.length && compact[compact.length - 1].trim() === '') continue; compact.push(l); }
// Component declaration after the last preload const and the last top-level var.
const preloadIdx = compact.findLastIndex(l => /^const\s+\w+\s*=\s*preload\(/.test(l));
compact.splice(preloadIdx + 1, 0, `const ${constName} = preload("res://scripts/${spec.script}")`);
const lastVar = compact.findLastIndex(l => /^(?:@[\w_]+(?:\([^)]*\))?\s+)*var\s/.test(l));
compact.splice(lastVar + 1, 0, `var ${spec.module} = ${constName}.new(self)`);
if (!compact.some(l => /^class_name\s+Arena\b/.test(l))) {
  const ext = compact.findIndex(l => /^extends\s/.test(l));
  compact.splice(ext + 1, 0, 'class_name Arena');
}

const moduleText = [
  'extends RefCounted',
  ...(spec.doc || []),
  'var arena: Arena',
  ...(movedVarText.length ? ['', ...movedVarText] : []),
  '',
  'func _init(owner: Arena) -> void:',
  '\tarena = owner',
  '',
  movedText.join('\n\n'),
  ''
].join('\n');

const report = {
  moved_functions: blocks.length, delegates: delegates.length / 2, moved_vars: varBlocks.length,
  arena_lines_before: lines.length, arena_lines_after: compact.length,
  module_lines: moduleText.split('\n').length, unclassified_bare_calls: [...unknownCalls].sort()
};
console.log(JSON.stringify(report, null, 2));
if (!dryRun) {
  fs.writeFileSync(arenaPath, compact.join(eol), 'utf8');
  fs.writeFileSync(path.join(root, 'game/scripts', spec.script), moduleText.split('\n').join(eol), 'utf8');
}
