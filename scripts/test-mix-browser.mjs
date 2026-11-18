import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {pathToFileURL} from 'node:url';

const {chromium} = await import(
  process.env.PLAYWRIGHT_MODULE ? pathToFileURL(process.env.PLAYWRIGHT_MODULE) : 'playwright'
);
const base = process.env.BASE_URL || 'http://127.0.0.1:4177/';
const mixURL = new URL('mix.html', base.endsWith('/') ? base : base + '/');
const output = 'generated/mix-browser';
await fs.mkdir(output, {recursive: true});
const browser = await chromium.launch({
  headless: true,
  ...(process.env.BROWSER_EXECUTABLE ? {executablePath: process.env.BROWSER_EXECUTABLE} : {}),
});

function pcm16(frames, sampleRate) {
  const wav = Buffer.alloc(44 + 2 * frames);
  wav.write('RIFF', 0);
  wav.writeUInt32LE(wav.length - 8, 4);
  wav.write('WAVEfmt ', 8);
  wav.writeUInt32LE(16, 16);
  wav.writeUInt16LE(1, 20);
  wav.writeUInt16LE(1, 22);
  wav.writeUInt32LE(sampleRate, 24);
  wav.writeUInt32LE(sampleRate * 2, 28);
  wav.writeUInt16LE(2, 32);
  wav.writeUInt16LE(16, 34);
  wav.write('data', 36);
  wav.writeUInt32LE(2 * frames, 40);
  for (let i = 0; i < frames; i++) wav.writeInt16LE(i % 2 ? -10000 : 16000, 44 + 2 * i);
  return wav;
}

async function download(page, name, destination) {
  const waiting = page.waitForEvent('download');
  await page.getByRole('link', {name, exact: true}).click();
  const file = await waiting;
  await file.saveAs(destination);
  return fs.readFile(destination);
}

async function finished(page) {
  await page.waitForFunction(() => document.getElementById('status').textContent.includes('计算完成'));
  await page.locator('#results').waitFor({state: 'visible'});
}

try {
  const page = await browser.newPage({viewport: {width: 1280, height: 920}, acceptDownloads: true});
  const errors = [];
  const offOrigin = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('request', request => {
    const url = new URL(request.url());
    if (['http:', 'https:'].includes(url.protocol) && url.origin !== mixURL.origin) {
      offOrigin.push(url.toString());
    }
  });
  await page.addInitScript(() => {
    const read = File.prototype.arrayBuffer;
    File.prototype.arrayBuffer = function() {
      if (this.name !== 'controlled.wav') return read.call(this);
      return new Promise((resolve, reject) => {
        window.releaseTestRead = () => read.call(this).then(resolve, reject);
      });
    };
  });
  await page.goto(mixURL.href);
  const run = page.locator('#run');
  const scene = page.locator('#scene');
  const status = page.locator('#status');
  const files = page.locator('#track-files input');
  const links = page.locator('#downloads a');
  assert.equal(await files.count(), 2);

  await run.click();
  await finished(page);
  assert.equal(await page.locator('#rate').innerText(), '16000 Hz');
  assert.equal(await page.locator('#channels').innerText(), '2');
  assert.equal(await page.locator('#track-report tr').count(), 2);
  await page.waitForFunction(() => document.getElementById('wet-player').readyState >= 1);
  const preview = await page.locator('#wet-player').getAttribute('src');
  const report = JSON.parse(await download(page, 'report.json', output + '/report.json'));
  const wet = await download(page, 'wet.wav', output + '/wet.wav');
  assert.equal(report.sample_rate, 16000);
  assert.equal(report.channels, 2);
  assert.equal(report.latency_samples, 16);
  assert.equal(report.frames, 17631);
  assert.deepEqual(report.tracks.map(track => [track.id, track.start_frame, track.end_frame]), [
    ['foreground', 0, 13631],
    ['background', 4000, 17631],
  ]);
  assert.equal(wet.toString('ascii', 0, 4), 'RIFF');
  assert.equal(wet.readUInt16LE(20), 3, 'Float32 encoding');
  assert.equal(wet.readUInt16LE(22), 2);
  assert.equal(wet.readUInt32LE(24), 16000);
  assert.equal(wet.readUInt32LE(46), report.frames);
  assert.equal(wet.readUInt32LE(54), report.frames * 2 * 4);
  assert.equal(wet.length, 58 + report.frames * 2 * 4);

  const preset = JSON.parse(await scene.inputValue());
  await scene.fill(JSON.stringify({...preset, scene: {...preset.scene, sample_rate: 24000}}));
  assert.equal(await links.count(), 0);
  assert.equal(await page.locator('#wet-player').getAttribute('src'), null);
  assert.equal(await page.evaluate(url => fetch(url).then(() => false, () => true), preview), true);
  await run.click();
  await finished(page);
  assert.equal(await page.locator('#rate').innerText(), '24000 Hz');
  assert.equal(await page.locator('#frames').innerText(), '24431');

  await page.locator('#preset').click();
  await page.locator('#dry-foreground').setInputFiles({
    name: 'dry-17.wav', mimeType: 'audio/wav', buffer: pcm16(17, 16000),
  });
  await scene.fill(JSON.stringify({...preset, tracks: preset.tracks.toReversed()}));
  assert.match(await page.locator('#track-files').innerText(), /dry-17\.wav/);
  await run.click();
  await finished(page);
  const reordered = JSON.parse(await download(page, 'report.json', output + '/reordered.json'));
  assert.deepEqual(reordered.tracks.map(track => [track.id, track.dry_frames]), [
    ['background', 9600],
    ['foreground', 17],
  ]);

  const invalidFiles = [
    {name: 'empty.wav', buffer: Buffer.alloc(0), expected: /文件为空/},
    {name: 'oversize.wav', buffer: Buffer.alloc(4194305), expected: /不能超过 4 MiB/},
    {name: 'invalid.wav', buffer: Buffer.from('invalid WAV'), expected: /header is truncated/},
    {name: 'wrong-rate.wav', buffer: pcm16(20, 8000), expected: /sample rate does not match/},
  ];
  for (const {name, buffer, expected} of invalidFiles) {
    await page.locator('#dry-foreground').setInputFiles({name, mimeType: 'audio/wav', buffer});
    assert.equal(await links.count(), 0);
    await run.click();
    await page.waitForFunction(() => document.getElementById('status').classList.contains('error'));
    assert.match(await status.innerText(), expected);
    assert.equal(await links.count(), 0);
  }

  await page.locator('#dry-foreground').setInputFiles({
    name: 'controlled.wav', mimeType: 'audio/wav', buffer: pcm16(17, 16000),
  });
  await run.click();
  await page.waitForFunction(() => typeof window.releaseTestRead === 'function');
  await page.locator('#cancel').click();
  await page.evaluate(() => window.releaseTestRead());
  assert.equal(await status.innerText(), '已取消。');
  assert.equal(await links.count(), 0);
  await page.locator('#preset').click();
  await run.click();
  await finished(page);
  assert.equal(await links.count(), 2);

  await page.setViewportSize({width: 390, height: 844});
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false);
  assert.deepEqual(errors, []);
  assert.deepEqual(offOrigin, []);
  const evidence = {
    backend: 'wasm-gc',
    browser: await browser.version(),
    preset: {channels: report.channels, sampleRate: report.sample_rate, frames: report.frames},
    supplied_wav_reordering: true,
    resynthesized_default_sample_rate: 24000,
    invalid_audio: ['empty', 'oversize', 'invalid_riff', 'sample_rate_mismatch'],
    cancellation_during_file_read: true,
    old_urls_revoked_on_scene_edit: true,
    preview_decoded: true,
    mobile_overflow: false,
    off_origin_requests: offOrigin,
  };
  await fs.writeFile(output + '/results.json', JSON.stringify(evidence, null, 2) + '\n');
  console.log(JSON.stringify(evidence));
} finally {
  await browser.close();
}
