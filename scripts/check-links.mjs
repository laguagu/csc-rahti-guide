#!/usr/bin/env node
/**
 * Validates every relative markdown link in the repository:
 *   - the target file exists
 *   - a #anchor, if present, matches a heading in that file
 *
 * Usage: node scripts/check-links.mjs
 * Exits 1 if anything is broken, so it works as a CI gate.
 */
import { readdirSync, readFileSync, statSync, existsSync } from "node:fs";
import { join, dirname, resolve, relative, extname } from "node:path";

const ROOT = resolve(new URL("..", import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1"));
const SKIP_DIRS = new Set([".git", "node_modules"]);

function walk(dir, out = []) {
  for (const entry of readdirSync(dir)) {
    if (SKIP_DIRS.has(entry)) continue;
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) walk(full, out);
    else out.push(full);
  }
  return out;
}

/** GitHub heading -> anchor slug. */
function slug(heading) {
  return heading
    .trim()
    .toLowerCase()
    .replace(/`/g, "")
    .replace(/!?\[([^\]]*)\]\([^)]*\)/g, "$1") // links -> their text
    .replace(/[*_~]/g, "")
    .replace(/[^\p{L}\p{N}\s-]/gu, "")
    // GitHub turns each whitespace character into one hyphen, so "a / b" -> "a--b".
    .replace(/\s/g, "-");
}

const anchorCache = new Map();
function anchorsOf(file) {
  if (anchorCache.has(file)) return anchorCache.get(file);
  const set = new Set();
  if (existsSync(file) && extname(file) === ".md") {
    let inFence = false;
    for (const line of readFileSync(file, "utf8").split(/\r?\n/)) {
      if (/^\s*```/.test(line)) inFence = !inFence;
      if (inFence) continue;
      const m = /^(#{1,6})\s+(.*)$/.exec(line);
      if (m) set.add(slug(m[2]));
    }
  }
  anchorCache.set(file, set);
  return set;
}

const files = walk(ROOT).filter((f) => extname(f) === ".md");
const problems = [];
let checked = 0;

for (const file of files) {
  const text = readFileSync(file, "utf8");
  // Strip fenced code blocks so example links are not checked.
  const body = text.replace(/```[\s\S]*?```/g, "");
  const linkRe = /!?\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)|<img[^>]+src="([^"]+)"/g;

  for (const m of body.matchAll(linkRe)) {
    const raw = m[1] ?? m[2];
    if (!raw || /^(https?:|mailto:|#|tel:)/.test(raw)) {
      if (raw?.startsWith("#")) {
        checked++;
        const want = decodeURIComponent(raw.slice(1)).toLowerCase();
        if (!anchorsOf(file).has(want)) {
          problems.push(`${relative(ROOT, file)} -> ${raw} (no such heading in this file)`);
        }
      }
      continue;
    }
    checked++;
    const [path, hash] = raw.split("#");
    const target = resolve(dirname(file), decodeURIComponent(path));

    if (!existsSync(target)) {
      problems.push(`${relative(ROOT, file)} -> ${raw} (missing file)`);
      continue;
    }
    if (hash) {
      const want = decodeURIComponent(hash).toLowerCase();
      if (statSync(target).isFile() && !anchorsOf(target).has(want)) {
        problems.push(`${relative(ROOT, file)} -> ${raw} (no such heading in target)`);
      }
    }
  }
}

console.log(`Checked ${checked} links in ${files.length} markdown files.`);
if (problems.length) {
  console.error(`\n${problems.length} broken link(s):`);
  for (const p of problems) console.error(`  ${p}`);
  process.exit(1);
}
console.log("All links OK.");
