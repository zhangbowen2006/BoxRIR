import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {createBoxRIR,BoxRIRError} from '../sdk/client.mjs';
import {generate_json,render_base64_json} from '../_build/js/release/build/bridge/bridge.js';
const options={jsModuleURL:new URL('../_build/js/release/build/bridge/bridge.js',import.meta.url),wasmBytes:fs.readFileSync(new URL('../_build/wasm-gc/release/build/bridge/bridge.wasm',import.meta.url))};
const fixtures=JSON.parse(fs.readFileSync(new URL('./reference/audiolabs-0.3.0.json',import.meta.url)));
const dry=fs.readFileSync(new URL('../examples/probe.wav',import.meta.url));

for(const backend of ['js','wasm-gc']) {
  test(`${backend} SDK verifies every upstream Float64 sample and compact WAV transport`,async()=>{
    const engine=await createBoxRIR({...options,backend});
    let maximumError=0,samples=0;
    for(const fixture of fixtures.cases) {
      const actual=engine.referenceSamples(fixture.scene),raw=Buffer.from(fixture.float64_le,'base64');
      assert.equal(actual.channels.length,fixture.channels,fixture.name);
      for(let ch=0;ch<fixture.channels;ch++) {
        assert.equal(actual.channels[ch].length,fixture.frames,fixture.name);
        for(let i=0;i<fixture.frames;i++) {
          const expected=raw.readDoubleLE((ch*fixture.frames+i)*8),error=Math.abs(actual.channels[ch][i]-expected);
          assert.ok(Number.isFinite(error) && error<=1e-10+1e-9*Math.abs(expected),`${fixture.name}: ch${ch}, sample${i}, error=${error}`);
          maximumError=Math.max(maximumError,error);samples++;
        }
      }
    }
    for(const name of ['stereo','triangle','reference-cardioid']) {
      const scene=fs.readFileSync(new URL(`../examples/${name}.json`,import.meta.url),'utf8');
      const result=engine.render(scene,{dryWav:dry}),legacy=JSON.parse(generate_json(scene,dry));
      assert.equal(result.backend,backend);assert.equal(result.rirWav.byteOffset,0);
      for(const [actual,expected] of [[result.rirWav,legacy.rir_wav],[result.wetWav,legacy.wet_wav]]) {
        assert.equal(actual.byteLength,expected.length);
        const view=new DataView(actual.buffer),expectedBytes=Buffer.from(expected);
        for(let i=58;i<actual.byteLength;i+=4) {
          const a=view.getFloat32(i,true),b=expectedBytes.readFloatLE(i);
          assert.ok(Math.abs(a-b)<=1e-9+2e-7*Math.abs(b),`${name}: WAV float ${i}`);
        }
      }
      assert.equal(result.report.wet.dry_frames,16000);
    }
    fs.mkdirSync('generated/sdk-verification',{recursive:true});
    fs.writeFileSync(`generated/sdk-verification/${backend}.json`,JSON.stringify({backend,cases:fixtures.cases.length,samples,maximum_absolute_error:maximumError},null,2)+'\n');
  });
  test(`${backend} SDK errors are explicit and bounded`,async()=>{
    const engine=await createBoxRIR({...options,backend}),base=fixtures.cases[0].scene;
    for(const scene of ['{',null,{...base,unknown:1},{...base,receivers:[base.source]},' '.repeat(65537)])assert.throws(()=>engine.render(scene),BoxRIRError);
    assert.throws(()=>engine.render(base,{dryWav:new Uint8Array(4194305)}),{code:'INVALID_AUDIO'});
    assert.throws(()=>engine.render(base,{dryWav:[]}),{code:'INVALID_AUDIO'});
    const cycle={};cycle.x=cycle;assert.throws(()=>engine.inspect(cycle),{code:'INVALID_SCENE'});
    assert.equal(engine.render(base).wetWav,null);
  });
}
test('SDK refuses unsupported backends and artifacts; bridge rejects invalid base64',async()=>{
  await assert.rejects(createBoxRIR({backend:'unknown'}),{code:'INVALID_BACKEND'});
  await assert.rejects(createBoxRIR({backend:'wasm-gc',wasmBytes:new Uint8Array([1,2])}),{code:'ENGINE_LOAD'});
  await assert.rejects(createBoxRIR({jsModuleURL:new URL('./no-such-engine.js',import.meta.url)}),{code:'ENGINE_LOAD'});
  for(const text of ['!!!','a','AAAA=',' '.repeat(5592409)]) assert.equal(JSON.parse(render_base64_json('{}',text)).ok,false);
});
