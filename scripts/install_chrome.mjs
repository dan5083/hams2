// Installs puppeteer's Chromium during the Heroku build.
//
// Three Heroku quirks handled here:
// 1. The stock installer (install.mjs / npx) leaves a handle open on build
//    dynos and hangs the build forever -> we await it and force-exit.
// 2. Builds run in /tmp/build_<hash>, not /app, and the slug is packed from
//    the build dir. An absolute PUPPETEER_CACHE_DIR=/app/... lands OUTSIDE
//    the build dir and gets discarded -> we override the cache dir to
//    <build dir>/.cache/puppeteer (cwd-relative), which ships in the slug
//    and appears at /app/.cache/puppeteer at runtime — matching the
//    PUPPETEER_CACHE_DIR config var Grover/puppeteer use when launching.
// 3. PUPPETEER_SKIP_DOWNLOAD is set as a config var to stop puppeteer's own
//    silent download inside `npm install` (it made cold builds crawl). But
//    downloadBrowser() honours that var too, so without clearing it here
//    THIS download is skipped as well and the slug ships with no Chromium
//    (that's what broke Grover on 07/09). This script is the one download
//    that must always happen, so the skip vars are dropped unconditionally.
delete process.env.PUPPETEER_SKIP_DOWNLOAD;
delete process.env.PUPPETEER_SKIP_CHROMIUM_DOWNLOAD;
process.env.PUPPETEER_CACHE_DIR = `${process.cwd()}/.cache/puppeteer`;
console.log(`Installing Chromium into ${process.env.PUPPETEER_CACHE_DIR}`);

try {
  const { downloadBrowser } = await import('puppeteer/internal/node/install.js');
  await downloadBrowser();
  console.log('Chromium install step complete.');
  process.exit(0);
} catch (error) {
  console.warn('Chromium install failed:', error);
  process.exit(1);
}
