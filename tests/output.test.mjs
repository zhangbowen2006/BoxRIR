import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {publishBundle,sha256} from '../bin/output.mjs';
const parent=path.resolve('generated/output-tests');
fs.mkdirSync(parent,{recursive:true});
function temp(){return fs.mkdtempSync(path.join(parent,'run-'));}
function cleanup(dir){assert.equal(path.dirname(path.resolve(dir)),parent);fs.rmSync(dir,{recursive:true,force:true});}
function cli(args){return new Promise((resolve,reject)=>{const child=spawn(process.execPath,['bin/boxrir.mjs',...args],{stdio:['ignore','pipe','pipe']});let stdout='',stderr='';child.stdout.on('data',x=>stdout+=x);child.stderr.on('data',x=>stderr+=x);child.on('error',reject);child.on('exit',status=>resolve({status,stdout,stderr}));});}
function verify(dir){
  assert.equal(fs.existsSync(path.join(dir,'.boxrir-incomplete')),false);
  const manifest=JSON.parse(fs.readFileSync(path.join(dir,'run-manifest.json')));assert.equal(manifest.state,'complete');
  for(const [name,expected] of Object.entries(manifest.files)) {const bytes=fs.readFileSync(path.join(dir,name));assert.equal(bytes.length,expected.bytes);assert.equal(sha256(bytes),expected.sha256,name);}
  return manifest;
}

test('completed CLI bundles bind exact inputs, engine and every output; JS and Wasm consumers work',async()=>{
  const dir=temp();
  try {
    for(const backend of ['js','wasm-gc']) {
      const output=path.join(dir,backend),result=await cli(['--backend',backend,'simulate','examples/reference-cardioid.json','examples/probe.wav',output]);
      assert.equal(result.status,0,result.stderr);
      const manifest=verify(output);assert.equal(manifest.backend,backend);
      assert.equal(manifest.inputs.scene_sha256,sha256(fs.readFileSync('examples/reference-cardioid.json')));
      assert.equal(manifest.inputs.source_sha256,sha256(fs.readFileSync('examples/probe.wav')));
      assert.match(manifest.engine_sha256,/^[a-f0-9]{64}$/);
    }
  } finally {cleanup(dir);}
});

test('a partial disk write rolls back files owned by this run',t=>{
  const dir=temp(),output=path.join(dir,'output'),original=fs.writeFileSync;
  let writes=0;
  try {
    t.mock.method(fs,'writeFileSync',function(fd,data,...args){
      if(++writes===3){original(fd,'partial');throw Object.assign(Error('simulated disk full'),{code:'ENOSPC'});}
      return original(fd,data,...args);
    });
    assert.throws(()=>publishBundle(output,[['first.bin',Buffer.from('first')],['second.bin',Buffer.from('second')]],{}),/simulated disk full/);
    assert.equal(fs.existsSync(output),false);
  } finally {t.mock.restoreAll();cleanup(dir);}
});

test('rollback preserves unexpected files, and incomplete artifacts have no completion manifest',t=>{
  const dir=temp(),output=path.join(dir,'output'),original=fs.writeFileSync;
  let writes=0;
  try {
    t.mock.method(fs,'writeFileSync',function(fd,data,...args){
      if(++writes===2){original(path.join(output,'foreign.txt'),'preserve me');throw Error('write failure');}
      return original(fd,data,...args);
    });
    assert.throws(()=>publishBundle(output,[['first.bin','first']],{}),/rollback incomplete/);
    assert.equal(fs.readFileSync(path.join(output,'foreign.txt'),'utf8'),'preserve me');
    assert.equal(fs.existsSync(path.join(output,'run-manifest.json')),false);
  } finally {t.mock.restoreAll();cleanup(dir);}
});

test('two concurrent CLI runs never merge or replace output directories',async()=>{
  const dir=temp(),output=path.join(dir,'claimed');
  try {
    const results=await Promise.all([cli(['rir','examples/stereo.json',output]),cli(['rir','examples/stereo.json',output])]);
    assert.deepEqual(results.map(r=>r.status).sort(),[0,2]);
    assert.match(results.find(r=>r.status===2).stderr,/already exists/);
    verify(output);
    const invalid=await cli(['rir','does-not-exist.json',output]);
    assert.equal(invalid.status,2);assert.match(invalid.stderr,/already exists/);
  } finally {cleanup(dir);}
});

test('CLI reports invalid UTF-8 and validates bundle names before touching disk',async()=>{
  const dir=temp();
  try {
    const input=path.join(dir,'bad.json');fs.writeFileSync(input,Buffer.from([0xc3,0x28]));
    assert.equal((await cli(['rir',input,path.join(dir,'no-output')])).status,2);
    assert.equal(fs.existsSync(path.join(dir,'no-output')),false);
    assert.throws(()=>publishBundle(path.join(dir,'bad'),[['../escape','x']],{}),/Invalid bundle/);
    assert.equal(fs.existsSync(path.join(dir,'bad')),false);
  } finally {cleanup(dir);}
});
