import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import crypto from 'node:crypto';
import {createBoxRIR,BoxRIRError} from '../sdk/client.mjs';
const data=JSON.parse(fs.readFileSync('tests/reference/spectral.json'));
const options={jsModuleURL:new URL('../_build/js/release/build/bridge/bridge.js',import.meta.url),wasmBytes:fs.readFileSync('_build/wasm-gc/release/build/bridge/bridge.wasm')};
for(const backend of ['js','wasm-gc']) {
  test(`${backend} per-path spectral synthesis matches independent SciPy complete waveforms`,async()=>{
    const engine=await createBoxRIR({...options,backend});let maximumError=0,samples=0;
    for(const fixture of data.cases){
      const raw=Buffer.from(fixture.float64_le,'base64');assert.equal(crypto.createHash('sha256').update(raw).digest('hex'),fixture.sha256);
      const actual=engine.spectralSamples(fixture.scene);assert.equal(actual.channels.length,fixture.channels);
      for(let ch=0;ch<fixture.channels;ch++){
        assert.equal(actual.channels[ch].length,fixture.frames);
        for(let i=0;i<fixture.frames;i++){
          const expected=raw.readDoubleLE(8*(ch*fixture.frames+i)),error=Math.abs(actual.channels[ch][i]-expected);
          assert.ok(Number.isFinite(error)&&error<=1e-10+1e-9*Math.abs(expected),`${fixture.name}: ${ch},${i}, error=${error}`);
          maximumError=Math.max(maximumError,error);samples++;
        }
      }
      assert.equal(actual.report.config.latency_samples,272);
    }
    for(const fixture of data.atmosphere){
      const result=engine.spectralSamples({...data.cases[0].scene,atmosphere:fixture.input});
      for(let b=0;b<6;b++)assert.ok(Math.abs(result.report.config.air_db_per_m[b]-fixture.expected[b])<1e-12);
    }
    fs.mkdirSync('generated/spectral-verification',{recursive:true});
    fs.writeFileSync(`generated/spectral-verification/${backend}.json`,JSON.stringify({backend,cases:data.cases.length,samples,atmosphere_cases:data.atmosphere.length,maximum_absolute_error:maximumError},null,2)+'\n');
  });
  test(`${backend} spectral schema and buffers reject invalid/mixed models`,async()=>{
    const engine=await createBoxRIR({...options,backend}),base=data.cases[0].scene;
    for(const change of [{model:undefined},{beta:[.5,.5,.5,.5,.5,.5]},{absorption:Array(6).fill(.2)},
      {band_absorption:[[.2]]},{air_db_per_m:[-1,0,0,0,0,0],atmosphere:undefined},{air_db_per_m:Array(6).fill(.1)},
      {atmosphere:{temperature_c:20,relative_humidity_percent:.5}},
      {atmosphere:{temperature_c:20,relative_humidity_percent:50,unknown:1}},{band_filter_half_width:63},{sample_rate:8000}])assert.throws(()=>engine.spectralSamples({...base,...change}),BoxRIRError);
    const rendered=engine.render({...base,atmosphere:undefined},{dryWav:fs.readFileSync('examples/probe.wav')});
    assert.equal(rendered.report.wet.frames,16000+rendered.report.config.output_frames-1);
    const bytes=rendered.rirWav;assert.equal(bytes.byteLength,58+rendered.report.config.output_frames*2*4);
  });
}
