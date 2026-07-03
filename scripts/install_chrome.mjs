// Installs puppeteer's Chromium into PUPPETEER_CACHE_DIR during the Heroku
// build. Wraps puppeteer's own installer but forces the process to exit,
// because the stock install script (install.mjs / `npx puppeteer browsers
// install`) leaves a handle open on Heroku build dynos after the download
// completes and hangs the build indefinitely. The "downloaded to" log lines
// are emitted after extraction, so by the time downloadBrowser() resolves the
// binaries are fully on disk and a hard exit is safe.
// Idempotent: with the browser already present in the cache this is a no-op.
try {
  const { downloadBrowser } = await import('puppeteer/internal/node/install.js');
  await downloadBrowser();
  console.log('Chromium install step complete.');
  process.exit(0);
} catch (error) {
  console.warn('Chromium install failed:', error);
  process.exit(1);
}
