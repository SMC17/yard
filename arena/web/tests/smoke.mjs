import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const playwrightModule = process.env.PLAYWRIGHT_MODULE;
const scorecardPath = process.env.ARENA_SCORECARD;
assert(playwrightModule, "PLAYWRIGHT_MODULE is required");
assert(scorecardPath, "ARENA_SCORECARD is required");

const { chromium } = await import(playwrightModule);
const browser = await chromium.launch({
  executablePath: process.env.CHROMIUM_PATH || "/usr/bin/chromium",
  headless: true,
  args: ["--no-sandbox", "--disable-gpu"]
});

const errors = [];
try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  page.on("console", (message) => {
    if (message.type() === "error") errors.push(`console: ${message.text()}`);
  });
  page.on("pageerror", (error) => errors.push(`pageerror: ${error.message}`));

  const indexPath = path.resolve("arena/web/index.html");
  await page.goto(pathToFileURL(indexPath).href, { waitUntil: "load" });
  await page.waitForFunction(() => document.querySelector("#gate-summary")?.textContent.includes("16 / 16"));

  assert.equal(await page.locator("#design-status").textContent(), "SCREENING PASS");
  assert((await page.locator("#merchantman-image").evaluate((image) => image.naturalWidth)) > 0);
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), true);

  await page.locator("#length").fill("60");
  assert.match(await page.locator("#design-status").textContent(), /GATE/);
  await page.locator("#reset-builder").click();
  assert.equal(await page.locator("#design-status").textContent(), "SCREENING PASS");

  await page.locator("#tab-leaderboard").click();
  assert.equal(await page.locator("#leaderboard-body tr").count(), 8);
  assert((await page.locator("#pareto-chart circle").count()) >= 6);
  const svgBox = await page.locator("#pareto-chart").boundingBox();
  assert(svgBox && svgBox.width > 500 && svgBox.height > 200);

  await page.locator('[data-track="human_ai"]').click();
  assert.equal(await page.locator("#leaderboard-body tr").count(), 3);
  const invalidScorecard = JSON.parse(fs.readFileSync(scorecardPath, "utf8"));
  delete invalidScorecard.environment_sha256;
  await page.locator("#scorecard-file").setInputFiles({
    name: "missing-environment.json",
    mimeType: "application/json",
    buffer: Buffer.from(JSON.stringify(invalidScorecard))
  });
  await page.waitForFunction(() => document.querySelector("#import-status")?.textContent.includes("Import rejected"));
  assert.equal(await page.locator("#leaderboard-body tr").count(), 3);

  await page.locator("#scorecard-file").setInputFiles(path.resolve(scorecardPath));
  await page.waitForFunction(() => document.querySelector("#import-status")?.textContent.includes("imported locally"));
  assert.equal(await page.locator("#leaderboard-body tr").count(), 4);
  assert.match(await page.locator("#provenance-status").textContent(), /CONTRACT VALID/);
  assert.match(await page.locator("#provenance-backend").textContent(), /yard-mercury-empirical-sail/);
  assert.match(await page.locator("#provenance-replay").textContent(), /770 events/);
  assert.equal((await page.locator("#provenance-environment").textContent()).length, 64);
  assert.match(await page.locator(".leaderboard-table thead").textContent(), /Freight rate/);
  assert.match(await page.locator("#leaderboard-body tr").last().textContent(), /0\.347/);

  await page.waitForFunction(() => document.querySelector("#toast")?.hidden);
  await page.screenshot({ path: "/tmp/yard-arena-leaderboard.png", fullPage: true });
  await page.setViewportSize({ width: 390, height: 844 });
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), true);
  await page.locator("#tab-evidence").click();
  assert.match(await page.locator("#panel-evidence").textContent(), /76,184/);
  assert.match(await page.locator("#panel-evidence").textContent(), /216 d/);
  assert.match(await page.locator("#panel-evidence").textContent(), /daily transcription is not yet bundled/);
  await page.screenshot({ path: "/tmp/yard-arena-evidence-mobile.png", fullPage: true });
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), true);

  assert.deepEqual(errors, []);
  process.stdout.write("yard-arena web smoke: ok builder=true pareto6=true import-contract=true provenance=true responsive=true console=clean\n");
} finally {
  await browser.close();
}
