// Explicit browser test. Set PLAYWRIGHT_MODULE to an installed playwright module
// and OUTLINE_BROWSER to a Chromium executable; uses a disposable browser profile.
import assert from 'node:assert/strict';
import {mkdtempSync, readFileSync, writeFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
const {chromium} = await import(pathToFileURL(process.env.PLAYWRIGHT_MODULE).href);
const directory = mkdtempSync(join(tmpdir(), 'bbtex-outline-browser-test-'));
let worker, browser;
try {
  const files = [];
  for(let i=0;i<120;i++){
    const name=`chapter-${i}.tex`;
    writeFileSync(join(directory,name),Array.from({length:40},(_,j)=>
      `\\section{Heading ${i}-${j}}\n\\label{sec:${i}:${j}}\nBody.\n`).join(''));
    files.push(`\\input{${name}}`);
  }
  const source=join(directory,'main.tex');
  writeFileSync(source,'\\documentclass{article}\n\\begin{document}\n'+files.join('\n')+
    '\n\\section{</script><img src=x onerror="window.injected=1">}\n\\end{document}\n');
  worker=spawn(resolve('_build/default/bin/main.exe'),['outline-window-prototype',source,directory,'no-open']);
  let output='', errors='';
  worker.stdout.on('data',data=>{output+=data;});
  worker.stderr.on('data',data=>{errors+=data;});
  const deadline=Date.now()+10000;
  while(!output.includes('endpoint: ')){
    assert.equal(worker.exitCode,null,errors);
    assert.ok(Date.now()<deadline,'Listener did not start');
    await new Promise(resolve=>setTimeout(resolve,20));
  }
  const file=output.match(/page: (.*)/)[1];
  const endpoint=output.match(/endpoint: (.*)/)[1];
  browser=await chromium.launch({headless:true,executablePath:process.env.OUTLINE_BROWSER});
  const context=await browser.newContext();
  const page=await context.newPage();
  const started=Date.now();
  await page.goto(pathToFileURL(file).href);
  await page.waitForFunction(()=>document.getElementById('feedback').textContent.includes('Connected.'));
  console.log(`Browser initial render/readiness: ${Date.now()-started} ms, 9601 entries`);
  assert.equal(await page.locator('#outline li').count(),9601);
  assert.equal(await page.locator('img, svg').count(),0);
  assert.equal(await page.evaluate(()=>window.injected),undefined);
  const searchTime=await page.evaluate(async()=>{
    const started=performance.now(), input=document.getElementById('search');
    input.value='sec:119:39'; input.dispatchEvent(new Event('input'));
    await new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)));
    return performance.now()-started;
  });
  console.log(`Search through next paint: ${searchTime.toFixed(1)} ms`);
  assert.equal(await page.locator('#outline li:not([hidden])').count(),2);
  await page.locator('#search').fill('');
  const button=page.locator('button[data-entry="1"]');
  await button.focus();
  const saved=readFileSync(source,'utf8');
  writeFileSync(source,'% line movement\n'+saved);
  await page.waitForFunction(()=>document.getElementById('outline').dataset.revision==='1');
  assert.equal(await page.evaluate(()=>document.activeElement.dataset.entry),'1','Refresh lost keyboard focus');
  // Return on a focused entry must still invoke its exact navigation endpoint.
  let navigated=false;
  await page.route(endpoint+'/jump/**',async route=>{navigated=true;await route.fulfill({body:'Opened saved source.',headers:{'Access-Control-Allow-Origin':'null'}});});
  await page.keyboard.press('Enter');
  await page.waitForFunction(()=>document.getElementById('feedback').textContent==='Opened saved source.');
  assert.ok(navigated);
  // Headless Chromium reports multiple pages as focused. Native window focus
  // is tested separately in check_outline_large.py, against real BBEdit windows.
  console.log('Browser: malicious text inert, large-tree search, refresh focus and Return passed');
} finally {
  if(browser)await browser.close();
  if(worker && worker.exitCode===null){worker.kill('SIGTERM');await once(worker,'exit');}
  rmSync(directory,{recursive:true,force:true});
}
