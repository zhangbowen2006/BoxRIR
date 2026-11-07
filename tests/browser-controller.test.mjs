import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('browser request freezes input, cancels pending file reads and captures the submitted scene',async()=>{
  // Controller-only DOM/Worker doubles. The numeric engine is covered separately.
  const elements=new Map(),workers=[];
  const element=id=>{if(!elements.has(id))elements.set(id,{id,value:'',files:[],disabled:false,checked:true,textContent:'',classList:{add(){},remove(){},toggle(){}},append(){},replaceChildren(){},removeAttribute(){},load(){}});return elements.get(id);};
  element('preset').value='stereo';
  globalThis.document={getElementById:element,createElement:tag=>({tag,append(){}})};
  globalThis.Worker=class{constructor(){this.posts=[];workers.push(this);}terminate(){this.terminated=true;}postMessage(message){this.posts.push(message);}};
  globalThis.fetch=async url=>({ok:true,json:async()=>JSON.parse(fs.readFileSync(new URL('../'+url,import.meta.url))),arrayBuffer:async()=>new ArrayBuffer(12)});
  await import('../web/app.mjs');
  assert.equal(element('run').disabled,false);
  let resolveRead;
  element('source').files=[{size:12,arrayBuffer:()=>new Promise(resolve=>{resolveRead=resolve;})}];
  const pending=element('run').onclick();
  assert.equal(element('scene').disabled,true);assert.equal(element('preset').disabled,true);assert.equal(element('source').disabled,true);
  element('cancel').onclick();resolveRead(new ArrayBuffer(12));await pending;
  assert.equal(workers.reduce((n,w)=>n+w.posts.length,0),0);
  assert.equal(element('run').disabled,false);assert.match(element('status').textContent,/已取消/);
  const submitted=element('scene').value;
  const next=element('run').onclick();element('scene').value='{"changed_after_submit":true}';resolveRead(new ArrayBuffer(12));await next;
  assert.equal(workers.at(-1).posts[0].scene,submitted);
  workers.at(-1).onmessage({data:{ok:false,error:'fixture error'}});
  assert.equal(element('run').disabled,false);assert.equal(element('status').textContent,'fixture error');
  element('scene').value=submitted;element('source').files=[{size:0,arrayBuffer:()=>{throw Error('empty file must not be read');}}];
  await element('run').onclick();assert.match(element('status').textContent,/为空/);
});
