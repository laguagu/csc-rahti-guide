#!/usr/bin/env node
/**
 * Renders the guide into one printable PDF per language.
 *
 *   pnpm install
 *   node scripts/build-pdf.mjs          # both languages
 *   node scripts/build-pdf.mjs fi       # just Finnish
 *
 * Chapters are concatenated in numeric order, images are inlined as data URIs, and
 * Chrome prints the result. Output goes to build/ (gitignored) — PDFs are deliberately
 * not committed, because they go stale the moment a chapter changes.
 *
 * Requires: Node 18+, `marked` (devDependency) and a local Chrome/Edge installation.
 */
import { readFileSync, readdirSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { join, dirname, resolve, extname } from "node:path";
import { execFileSync } from "node:child_process";
import { marked } from "marked";

const ROOT = resolve(new URL("..", import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1"));
const OUT = join(ROOT, "build");

const LANGS = {
  fi: { dir: join(ROOT, "docs", "fi"), title: "CSC Rahti 2 -käsikirja" },
  en: { dir: join(ROOT, "docs", "en"), title: "CSC Rahti 2 Handbook" },
};

const CHROME_CANDIDATES = [
  process.env.CHROME_PATH,
  "C:/Program Files/Google/Chrome/Application/chrome.exe",
  "C:/Program Files (x86)/Google/Chrome/Application/chrome.exe",
  "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe",
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/usr/bin/google-chrome",
  "/usr/bin/chromium",
].filter(Boolean);

const MIME = { ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".svg": "image/svg+xml" };

const CSS = `
  @page { size: A4; margin: 18mm 16mm; }
  body { font: 11pt/1.55 "Segoe UI", system-ui, sans-serif; color: #1a1a1a; }
  h1 { font-size: 21pt; border-bottom: 2px solid #007a78; padding-bottom: .3em;
       margin-top: 0; page-break-before: always; }
  h1:first-of-type { page-break-before: avoid; }
  h2 { font-size: 15pt; color: #005f5d; margin-top: 1.6em; }
  h3 { font-size: 12.5pt; margin-top: 1.3em; }
  h2, h3, h4 { page-break-after: avoid; }
  code { font-family: "Cascadia Mono", Consolas, monospace; font-size: 9.5pt;
         background: #f2f4f4; padding: .1em .3em; border-radius: 3px; }
  pre { background: #f7f8f8; border: 1px solid #dfe3e3; border-left: 3px solid #007a78;
        padding: .7em .9em; border-radius: 4px; overflow-x: auto; page-break-inside: avoid; }
  pre code { background: none; padding: 0; font-size: 9pt; }
  table { border-collapse: collapse; width: 100%; margin: 1em 0; font-size: 10pt;
          page-break-inside: avoid; }
  th, td { border: 1px solid #d5d9d9; padding: .4em .6em; text-align: left; vertical-align: top; }
  th { background: #eef3f3; }
  blockquote { border-left: 3px solid #b8c4c4; margin: 1em 0; padding: .2em 1em;
               color: #444; background: #fafbfb; }
  img { max-width: 100%; border: 1px solid #dfe3e3; border-radius: 4px; page-break-inside: avoid; }
  a { color: #00615f; text-decoration: none; }
  hr { border: none; border-top: 1px solid #dfe3e3; margin: 2em 0; }
  .cover { page-break-after: always; padding-top: 28vh; text-align: center; }
  .cover h1 { border: none; font-size: 30pt; page-break-before: avoid; }
  .cover p { color: #555; }
`;

function inlineImages(html, baseDir) {
  return html.replace(/src="([^"]+)"/g, (whole, src) => {
    if (/^(https?:|data:)/.test(src)) return whole;
    const file = resolve(baseDir, src);
    if (!existsSync(file)) return whole;
    const mime = MIME[extname(file).toLowerCase()];
    if (!mime) return whole;
    return `src="data:${mime};base64,${readFileSync(file).toString("base64")}"`;
  });
}

function findChrome() {
  const found = CHROME_CANDIDATES.find((p) => existsSync(p));
  if (!found) {
    throw new Error(
      "Chrome or Edge not found. Set CHROME_PATH to the browser executable and re-run."
    );
  }
  return found;
}

function build(lang) {
  const { dir, title } = LANGS[lang];
  if (!existsSync(dir)) {
    console.warn(`skip ${lang}: ${dir} does not exist`);
    return;
  }

  const chapters = readdirSync(dir)
    .filter((f) => f.endsWith(".md"))
    .sort();

  // Strip the per-chapter Previous/Next footers — meaningless in a single document.
  const body = chapters
    .map((f) => readFileSync(join(dir, f), "utf8").replace(/\n---\n\n\*\*(Edellinen|Previous)[\s\S]*$/, "\n"))
    .join("\n\n");

  const generated = new Date().toISOString().slice(0, 10);
  const cover = `<div class="cover"><h1>${title}</h1><p>${generated}</p></div>`;
  const html = `<!doctype html><html lang="${lang}"><head><meta charset="utf-8">
<title>${title}</title><style>${CSS}</style></head><body>
${cover}
${inlineImages(marked.parse(body), dir)}
</body></html>`;

  mkdirSync(OUT, { recursive: true });
  const htmlPath = join(OUT, `rahti-guide-${lang}.html`);
  const pdfPath = join(OUT, `rahti-guide-${lang}.pdf`);
  writeFileSync(htmlPath, html, "utf8");

  execFileSync(findChrome(), [
    "--headless",
    "--disable-gpu",
    "--no-pdf-header-footer",
    `--print-to-pdf=${pdfPath}`,
    `file:///${htmlPath.replace(/\\/g, "/")}`,
  ], { stdio: "pipe" });

  console.log(`${lang}: ${chapters.length} chapters -> ${pdfPath}`);
}

const langs = process.argv.slice(2).filter((a) => a in LANGS);
for (const lang of langs.length ? langs : Object.keys(LANGS)) build(lang);
