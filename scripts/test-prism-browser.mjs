import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
const {chromium}=await import(process.env.PLAYWRIGHT_MODULE?pathToFileURL(process.env.PLAYWRIGHT_MODULE):'playwright');
const browser=await chromium.launch({headless:true,...(process.env.BROWSER_EXECUTABLE?{executablePath:process.env.BROWSER_EXECUTABLE}:{})});
const issues=[],checks=[];
// Browser and Node may differ at the last binary64 rounding bit in FFT math.
let maximumNumericDifference=0;
function compare(a,b,path='report') {
  if(typeof a==='number'&&typeof b==='number') {
    if(Number.isInteger(a)&&Number.isInteger(b)) assert.equal(a,b,path);
    else {const difference=Math.abs(a-b);maximumNumericDifference=Math.max(maximumNumericDifference,difference);assert.ok(Number.isFinite(a)&&Number.isFinite(b)&&difference<=1e-12+1e-12*Math.abs(b),path);}
  } else if(a&&b&&typeof a==='object'&&typeof b==='object') {
    assert.deepEqual(Object.keys(a),Object.keys(b),path);
    for(const key of Object.keys(a)) compare(a[key],b[key],path+'.'+key);
  } else assert.equal(a,b,path);
}
await fs.mkdir('generated/prism-browser',{recursive:true});
try {
  const page=await browser.newPage({viewport:{width:1440,height:1050},acceptDownloads:true});
  page.on('pageerror',e=>issues.push(e.message));
  await page.goto(process.env.BASE_URL||'http://127.0.0.1:4177');
  await page.locator('#run').waitFor({state:'visible'});
  await page.waitForFunction(()=>!document.querySelector('#run').disabled);
  for(const name of ['triangle','trapezoid','pentagon','reference-omni','reference-cardioid','reference-2d']) {
    await page.locator('#preset').selectOption(name);
    assert.equal(await page.locator('#downloads a').count(),0,'Preset changes must invalidate old downloads');
    await page.locator('#run').click();
    await page.waitForFunction(()=>document.querySelector('#status').textContent.includes('计算完成'));
    assert.match(await page.locator('#status').innerText(),/WebAssembly GC/);
    assert.equal(await page.locator('#channels').innerText(),'2');
    assert.match(await page.locator('#floor').innerHTML(),/polygon/);
    assert.equal(await page.locator('#paths tr').count(),2);
    await page.waitForFunction(()=>document.querySelector('#wet-player').readyState>=2);
    const waiting=page.waitForEvent('download');
    await page.getByRole('link',{name:'report.json',exact:true}).click();
    const download=await waiting;
    const file=`generated/prism-browser/${name}.json`;
    await download.saveAs(file);
    const report=JSON.parse(await fs.readFile(file));
    const directory=name.startsWith('reference-')?'reference-workflows':'prism-workflows';
    const cli=JSON.parse(await fs.readFile(`generated/${directory}/${name}/report.json`));
    compare(report,cli);
    if(name.startsWith('reference-')) assert.equal(report.config.latency_samples,0);
    if(name==='reference-omni') assert.match(await page.locator('#status').innerText(),/路径明细已达/);
    checks.push({name,channels:2,contributing_paths:report.contributing_paths,download_agrees_with_cli_within_double_tolerance:true});
  }
  await page.screenshot({path:'generated/prism-browser/workbench.png',fullPage:true});
  const oldPreview=await page.locator('#wet-player').getAttribute('src');
  await page.locator('#listen-gain').uncheck();
  await page.waitForFunction(()=>document.querySelector('#wet-player').readyState>=2);
  assert.notEqual(await page.locator('#wet-player').getAttribute('src'),oldPreview);
  assert.equal(await page.evaluate(url=>fetch(url).then(()=>false,()=>true),oldPreview),true,'Superseded preview buffers must be revoked');
  const text=await page.locator('#scene').inputValue();
  await page.locator('#scene').fill(text+' ');
  assert.equal(await page.locator('#downloads a').count(),0,'Edits must invalidate old audio and download artifacts');
  assert.equal(await page.locator('#wet-player').getAttribute('src'),null);
  await page.locator('#run').click();
  await page.waitForFunction(()=>document.querySelector('#status').textContent.includes('计算完成'));
  await page.locator('#source').setInputFiles({name:'empty.wav',mimeType:'audio/wav',buffer:Buffer.alloc(0)});
  assert.equal(await page.locator('#downloads a').count(),0,'Source changes invalidate results');
  await page.locator('#run').click();assert.match(await page.locator('#status').innerText(),/为空/);
  await page.locator('#source').setInputFiles([]);
  await page.locator('#preset').selectOption('reference-omni');
  await page.locator('#run').click();await page.locator('#cancel').click();
  assert.match(await page.locator('#status').innerText(),/已取消/);
  await page.locator('#run').click();
  await page.waitForFunction(()=>document.querySelector('#status').textContent.includes('计算完成'));
  await page.setViewportSize({width:390,height:844});
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
  assert.deepEqual(issues,[]);
  const result={backend:'wasm-gc',checks,invalidations:['preset','manual-scene','source-wav'],superseded_preview_revoked:true,empty_wav_rejected:true,cancel_and_restart:true,issues,mobile_overflow:false,maximumNumericDifference,browser:await browser.version()};
  await fs.writeFile('generated/prism-browser/results.json',JSON.stringify(result,null,2));
  console.log(JSON.stringify(result));
} finally {await browser.close();}
