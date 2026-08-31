#!/usr/bin/env node
/**
 * Renders the guide into one printable PDF per language, for sharing with people who
 * cannot or do not want to read it on GitHub.
 *
 *   pnpm install
 *   node scripts/build-pdf.mjs          # both languages
 *   node scripts/build-pdf.mjs fi       # just Finnish
 *
 * Chapters are concatenated in numeric order, images are inlined as data URIs, and
 * Chrome prints the result to docs/pdf/. The generated PDFs ARE committed so the repo
 * can be shared as a single file — re-run this script whenever a chapter changes.
 *
 * Requires: Node 18+, `marked` (devDependency) and a local Chrome or Edge.
 * Override the browser with CHROME_PATH.
 */
import { readFileSync, readdirSync, writeFileSync, mkdirSync, existsSync, rmSync } from "node:fs";
import { join, resolve, extname } from "node:path";
import { execFileSync } from "node:child_process";
import { marked } from "marked";

const ROOT = resolve(new URL("..", import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1"));
const OUT = join(ROOT, "docs", "pdf");
const TMP = join(ROOT, "build");
const LOGO = join(ROOT, "assets", "haaga-helia-logo.jpg");

const LANGS = {
  fi: {
    dir: join(ROOT, "docs", "fi"),
    file: "csc-rahti-opas-fi.pdf",
    title: "CSC Rahti 2 -käsikirja",
    subtitle: "Sovellusten julkaisu CSC:n konttipilveen — selaimesta, komentoriviltä ja agentilla",
    note: "Yhteisöohje, ei CSC:n virallinen dokumentaatio. Ajantasainen versio ja agenttiskillit:",
    generated: "Koostettu",
  },
  en: {
    dir: join(ROOT, "docs", "en"),
    file: "csc-rahti-guide-en.pdf",
    title: "CSC Rahti 2 Handbook",
    subtitle: "Deploying applications to CSC's container cloud — browser, CLI and agent",
    note: "A community guide, not official CSC documentation. Latest version and agent skills:",
    generated: "Generated",
  },
};

const REPO = "https://github.com/laguagu/csc-rahti-guide";

const CHROME_CANDIDATES = [
  process.env.CHROME_PATH,
  "C:/Program Files/Google/Chrome/Application/chrome.exe",
  "C:/Program Files (x86)/Google/Chrome/Application/chrome.exe",
  "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe",
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/usr/bin/google-chrome",
  "/usr/bin/chromium",
].filter(Boolean);

const MIME = {
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".svg": "image/svg+xml",
};

const CSS = `
  @page { size: A4; margin: 18mm 16mm; }
  body { font: 11pt/1.55 "Segoe UI", system-ui, sans-serif; color: #1a1a1a; }

  h1 { font-size: 20pt; color: #0f3c3b; border-bottom: 2px solid #007a78;
       padding-bottom: .3em; margin: 0 0 .8em; page-break-before: always; }
  h2 { font-size: 14pt; color: #005f5d; margin-top: 1.6em; }
  h3 { font-size: 12pt; margin-top: 1.3em; }
  h2, h3, h4 { page-break-after: avoid; }
  p, li { orphans: 2; widows: 2; }

  code { font-family: "Cascadia Mono", Consolas, monospace; font-size: 9.5pt;
         background: #f2f4f4; padding: .1em .3em; border-radius: 3px; }
  pre { background: #f7f8f8; border: 1px solid #dfe3e3; border-left: 3px solid #007a78;
        padding: .7em .9em; border-radius: 4px; page-break-inside: avoid;
        white-space: pre-wrap; word-wrap: break-word; }
  pre code { background: none; padding: 0; font-size: 8.8pt; }

  table { border-collapse: collapse; width: 100%; margin: 1em 0; font-size: 9.5pt;
          page-break-inside: avoid; }
  th, td { border: 1px solid #d5d9d9; padding: .4em .6em; text-align: left; vertical-align: top; }
  th { background: #eef3f3; }

  blockquote { border-left: 3px solid #7fb6b4; margin: 1em 0; padding: .4em 1em;
               background: #f6faf9; page-break-inside: avoid; }
  blockquote p { margin: .3em 0; }

  img { max-width: 100%; border: 1px solid #dfe3e3; border-radius: 4px;
        page-break-inside: avoid; }
  a { color: #00615f; text-decoration: none; }
  hr { border: none; border-top: 1px solid #dfe3e3; margin: 2em 0; }

  /* Cover */
  .cover { page-break-after: always; height: 245mm; display: flex; flex-direction: column; }
  .cover-logo { width: 52mm; border: none; border-radius: 0; }
  .cover-mid { margin-top: auto; }
  .cover h1 { border: none; page-break-before: avoid; font-size: 30pt; margin: 0 0 .3em;
              color: #0f3c3b; }
  .cover .sub { font-size: 13pt; color: #4a5c5c; margin: 0 0 2.5em; max-width: 46em; }
  .cover .toc { column-count: 2; font-size: 10.5pt; color: #333; margin-bottom: 2.5em; }
  .cover .toc div { break-inside: avoid; padding: .18em 0; }
  .cover .toc span { color: #7a8c8c; display: inline-block; width: 1.6em; }
  .cover .foot { margin-top: auto; font-size: 9.5pt; color: #5a6b6b;
                 border-top: 1px solid #dfe3e3; padding-top: .8em; }
`;

function dataUri(file) {
  const mime = MIME[extname(file).toLowerCase()];
  if (!mime || !existsSync(file)) return null;
  return `data:${mime};base64,${readFileSync(file).toString("base64")}`;
}

function inlineImages(html, baseDir) {
  return html.replace(/src="([^"]+)"/g, (whole, src) => {
    if (/^(https?:|data:)/.test(src)) return whole;
    const uri = dataUri(resolve(baseDir, src));
    return uri ? `src="${uri}"` : whole;
  });
}

function findChrome() {
  const found = CHROME_CANDIDATES.find((p) => existsSync(p));
  if (!found) {
    throw new Error("Chrome or Edge not found. Set CHROME_PATH to the browser executable.");
  }
  return found;
}

/** First H1 of each chapter, for the cover's table of contents. */
function chapterTitle(text) {
  const m = /^#\s+(.*)$/m.exec(text);
  return m ? m[1].replace(/^\d+\.\s*/, "") : "";
}

function build(lang) {
  const cfg = LANGS[lang];
  if (!existsSync(cfg.dir)) {
    console.warn(`skip ${lang}: ${cfg.dir} does not exist`);
    return;
  }

  const chapters = readdirSync(cfg.dir)
    .filter((f) => f.endsWith(".md"))
    .sort();

  const sources = chapters.map((f) => readFileSync(join(cfg.dir, f), "utf8"));

  // Drop the per-chapter Previous/Next footers — meaningless in one document.
  const body = sources
    .map((t) => t.replace(/\n---\n\n\*\*(Edellinen|Previous)[\s\S]*$/, "\n"))
    .join("\n\n");

  const toc = sources
    .map((t, i) => `<div><span>${i + 1}.</span>${chapterTitle(t)}</div>`)
    .join("\n");

  const logo = dataUri(LOGO);
  const date = new Date().toISOString().slice(0, 10);

  const cover = `<div class="cover">
  ${logo ? `<img class="cover-logo" src="${logo}" alt="Haaga-Helia">` : ""}
  <div class="cover-mid">
    <h1>${cfg.title}</h1>
    <p class="sub">${cfg.subtitle}</p>
    <div class="toc">${toc}</div>
  </div>
  <div class="foot">${cfg.note}<br><strong>${REPO}</strong><br>${cfg.generated} ${date}</div>
</div>`;

  const html = `<!doctype html><html lang="${lang}"><head><meta charset="utf-8">
<title>${cfg.title}</title><style>${CSS}</style></head><body>
${cover}
${inlineImages(marked.parse(body), cfg.dir)}
</body></html>`;

  mkdirSync(OUT, { recursive: true });
  mkdirSync(TMP, { recursive: true });
  const htmlPath = join(TMP, `rahti-guide-${lang}.html`);
  const pdfPath = join(OUT, cfg.file);
  writeFileSync(htmlPath, html, "utf8");

  execFileSync(
    findChrome(),
    [
      "--headless",
      "--disable-gpu",
      "--no-pdf-header-footer",
      `--print-to-pdf=${pdfPath}`,
      `file:///${htmlPath.replace(/\\/g, "/")}`,
    ],
    { stdio: "pipe" }
  );

  const kb = Math.round(readFileSync(pdfPath).length / 1024);
  console.log(`${lang}: ${chapters.length} chapters -> docs/pdf/${cfg.file} (${kb} kB)`);
}

const langs = process.argv.slice(2).filter((a) => a in LANGS);
for (const lang of langs.length ? langs : Object.keys(LANGS)) build(lang);
rmSync(TMP, { recursive: true, force: true });
