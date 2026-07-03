// Installs puppeteer's Chromium during the Heroku build.
//
// Two Heroku quirks handled here:
// 1. The stock installer (install.mjs / npx) leaves a handle open on build
//    dynos and hangs the build forever -> we await it and force-exit.
// 2. Builds run in /tmp/build_<hash>, not /app, and the slug is packed from
//    the build dir. An absolute PUPPETEER_CACHE_DIR=/app/... lands OUTSIDE
//    the build dir and gets discarded -> we override the cache dir to
//    <build dir>/.cache/puppeteer (cwd-relative), which ships in the slug
//    and appears at /app/.cache/puppeteer at runtime — matching the
//    PUPPETEER_CACHE_DIR config var Grover/puppeteer use when launching.
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
