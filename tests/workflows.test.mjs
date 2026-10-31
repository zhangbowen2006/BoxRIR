import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {spawnSync} from 'node:child_process';
import {describe_json,generate_json} from '../_build/js/release/build/bridge/bridge.js';
const scene=name=>fs.readFileSync(new URL(`../examples/${name}.json`,import.meta.url),'utf8');
function numericalEqual(a,b){
  if(typeof b==='number'){
    if(Number.isInteger(b))assert.equal(a,b);
    else assert.ok(typeof a==='number'&&Math.abs(a-b)<=1e-10+2e-7*Math.abs(b),`${a} vs ${b}`);
  }else if(Array.isArray(b)){assert.equal(a.length,b.length);b.forEach((v,i)=>numericalEqual(a[i],v));}
  else if(b&&typeof b==='object'){assert.deepEqual(Object.keys(a).sort(),Object.keys(b).sort());for(const k of Object.keys(b))numericalEqual(a[k],b[k]);}
  else assert.equal(a,b);
}
function floatWavEqual(actual,expected){
  assert.equal(actual.length,expected.length);assert.deepEqual(actual.subarray(0,58),expected.subarray(0,58));
  for(let i=58;i<actual.length;i+=4){const a=actual.readFloatLE(i),b=expected.readFloatLE(i);assert.ok(Math.abs(a-b)<=2e-10+3e-7*Math.abs(b),`WAV sample ${i}: ${a} vs ${b}`);}
}
test('three independent workflows generate current reproducible samples',()=>{
  for(const name of ['stereo','wall-before','wall-after','array']){
    const dry=name==='array'?fs.readFileSync(new URL('../examples/probe.wav',import.meta.url)):new Uint8Array();
    const actual=JSON.parse(generate_json(scene(name),dry));assert.equal(actual.ok,true,actual.error);
    const expected=JSON.parse(fs.readFileSync(new URL(`../outputs/${name}/report.json`,import.meta.url)));
    numericalEqual(actual.report,expected);
    floatWavEqual(Buffer.from(actual.rir_wav),fs.readFileSync(new URL(`../outputs/${name}/rir.wav`,import.meta.url)));
    if(dry.length)floatWavEqual(Buffer.from(actual.wet_wav),fs.readFileSync(new URL(`../outputs/${name}/wet.wav`,import.meta.url)));
  }
});
test('CLI performs file I/O and never replaces an existing output directory',()=>{
  const temp=fs.mkdtempSync(path.join(os.tmpdir(),'boxrir-cli-'));
  try{
    const dest=path.join(temp,'render');
    const a=spawnSync(process.execPath,['bin/boxrir.mjs','rir','examples/stereo.json',dest],{encoding:'utf8'});
    assert.equal(a.status,0,a.stderr);assert.ok(fs.existsSync(path.join(dest,'rir.wav')));
    assert.ok(!fs.existsSync(path.join(dest,'.boxrir-incomplete')));
    const b=spawnSync(process.execPath,['bin/boxrir.mjs','rir','examples/stereo.json',dest],{encoding:'utf8'});
    assert.equal(b.status,2);assert.match(b.stderr,/already exists/);
  }finally{assert.equal(path.dirname(temp),os.tmpdir());fs.rmSync(temp,{recursive:true,force:true});}
});
test('invalid configurations fail before simulation rather than silently correcting values',()=>{
  const base=JSON.parse(scene('stereo'));
  for(const change of [{max_order:13},{duration_ms:0},{room:[5,0,3]},{absorption:[0,0,0,0,0,1.01]},{receivers:[base.source]},{receivers:Array(9).fill([3,2,1])},{unexpected:1}]){
    const result=JSON.parse(describe_json(JSON.stringify({...base,...change})));assert.equal(result.ok,false,JSON.stringify(change));
  }
  assert.equal(JSON.parse(describe_json(scene('stereo').replace('"max_order":6','"max_order":6.000000000000000001'))).ok,false);
  const dry=fs.readFileSync(new URL('../examples/probe.wav',import.meta.url));
  const mismatch=JSON.parse(generate_json(JSON.stringify({...base,sample_rate:8000}),dry));
  assert.match(mismatch.error,/sample rates must match/);
});
