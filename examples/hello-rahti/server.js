// Minimal zero-dependency server that follows every Rahti requirement:
// binds 0.0.0.0, reads PORT from the environment, runs as an arbitrary UID,
// and exposes an unauthenticated /health path for the readiness probe.
const http = require("http");

const PORT = Number(process.env.PORT) || 8080;
const MESSAGE = process.env.GREETING || "Hello from CSC Rahti 2";
const started = new Date().toISOString();

const page = () => `<!doctype html>
<html lang="fi"><meta charset="utf-8"><title>${MESSAGE}</title>
<style>
  body{font:16px/1.6 system-ui,sans-serif;margin:0;display:grid;place-items:center;
       min-height:100vh;background:#0f1417;color:#e6edf0}
  main{max-width:34rem;padding:2rem;border:1px solid #24313a;border-radius:12px;background:#151c21}
  h1{margin:0 0 .5rem;font-size:1.5rem;color:#7fd1cd}
  dt{color:#8fa3ad;font-size:.85rem;margin-top:.8rem}
  dd{margin:0;font-family:ui-monospace,monospace}
</style>
<main>
  <h1>${MESSAGE}</h1>
  <p>Jos näet tämän sivun, kontti käynnistyi, Service löysi podin ja Route vastaa.</p>
  <dl>
    <dt>Pod</dt><dd>${process.env.HOSTNAME || "unknown"}</dd>
    <dt>UID</dt><dd>${process.getuid ? process.getuid() : "n/a"} (gid ${process.getgid ? process.getgid() : "n/a"})</dd>
    <dt>Portti</dt><dd>${PORT}</dd>
    <dt>Käynnistetty</dt><dd>${started}</dd>
  </dl>
</main>`;

http
  .createServer((req, res) => {
    if (req.url === "/health") {
      res.writeHead(200, { "content-type": "application/json" });
      return res.end(JSON.stringify({ status: "ok", started }));
    }
    res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
    res.end(page());
  })
  .listen(PORT, "0.0.0.0", () => console.log(`listening on 0.0.0.0:${PORT}`));
