import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {createBoxRIR,BoxRIRError} from '../sdk/client.mjs';
const jsModuleURL=new URL('../_build/js/release/build/bridge/bridge.js',import.meta.url),wasmBytes=fs.readFileSync(new URL('../_build/wasm-gc/release/build/bridge/bridge.wasm',import.meta.url));
const scene={room:[4,3,2.5],source:[1,1,1],receivers:[[2,1,1]],absorption:[.2,.3,.4,.5,.6,.7],sample_rate:16000,max_order:0,duration_ms:10};
let seed=20261107;const random=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed;};
const original=fs.readFileSync('examples/probe.wav'),inputs=[];
// RIFF framing, fmt fields, declared sizes and arbitrary metadata mutations.
for(let n=0;n<192;n++) {
  const bytes=Buffer.from(original);
  for(let k=0;k<1+n%4;k++){const offset=random()%Math.min(bytes.length,128);bytes[offset]=random()&255;}
  inputs.push(n%5===0?bytes.subarray(0,random()%Math.min(bytes.length,128)):bytes);
}
for(const backend of ['js','wasm-gc'])test(`${backend}: seeded RIFF mutations and bounded invalid scenes never panic`,async()=>{
  const engine=await createBoxRIR({backend,jsModuleURL,wasmBytes});let accepted=0,rejected=0;
  for(const dryWav of inputs) {
    try {
      const result=engine.render(scene,{dryWav});accepted++;
      if(dryWav.length===0){assert.equal(result.wetWav,null);continue;}
      assert.ok(result.wetWav instanceof Uint8Array);const view=new DataView(result.wetWav.buffer);
      for(let i=58;i<result.wetWav.length;i+=4)assert.ok(Number.isFinite(view.getFloat32(i,true)));
    } catch(error) {assert.ok(error instanceof BoxRIRError,`${backend}: ${error.stack}`);rejected++;}
  }
  for(const text of ['[]','{}','{"room":[]}','{"x":1,"x":2}','{"room":1e999}','['.repeat(64)+']'.repeat(64),JSON.stringify({...scene,source:[1,null,1]}),JSON.stringify({...scene,room:[1e100,3,2.5]})])assert.throws(()=>engine.render(text),BoxRIRError);
  assert.ok(rejected>0);assert.ok(accepted>0);
  fs.mkdirSync('generated/robustness',{recursive:true});
  fs.writeFileSync(`generated/robustness/${backend}.json`,JSON.stringify({seed:20261107,mutated_inputs:inputs.length,accepted,rejected,uncaught_panics:0},null,2)+'\n');
});
