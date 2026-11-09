import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import crypto from 'node:crypto';
import {reference_samples_json,generate_json} from '../_build/js/release/build/bridge/bridge.js';
const data=JSON.parse(fs.readFileSync(new URL('./reference/audiolabs-0.3.0.json',import.meta.url)));

test('reference diagnostics separate admitted images from evaluated loop candidates',()=>{
  for(const [order,expected] of [[0,1],[1,7],[2,25]]){
    const result=JSON.parse(generate_json(JSON.stringify({...data.cases[0].scene,dimension:3,max_order:order}),new Uint8Array()));
    assert.equal(result.ok,true,result.error);const report=result.report;
    assert.equal(report.geometric_images,expected);
    for(let ch=0;ch<2;ch++)assert.equal(report.contributing_paths[ch]+report.omitted_late_paths[ch]+report.zero_gain_paths[ch],expected);
    assert.ok(report.evaluated_candidates>=expected*2);
  }
});

test('AudioLabs 0.3.0 complete waveform parity: all five patterns, filters, orders and dimensions',()=>{
  const embedded=fs.readFileSync(new URL('../cmd/reference-parity/fixtures.mbt',import.meta.url),'utf8').split('\n').filter(line=>line.trimStart().startsWith('#|')).map(line=>line.slice(line.indexOf('#|')+2)).join('\n');
  const digest=value=>crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
  assert.equal(digest(JSON.parse(embedded)),digest(data),'Portable fixtures must match the canonical upstream data');
  const records=[];
  for(const c of data.cases){
    const actual=JSON.parse(reference_samples_json(JSON.stringify(c.scene)));
    assert.equal(actual.ok,true,`${c.name}: ${actual.error}`);
    assert.equal(actual.channels.length,c.channels,c.name);
    const raw=Buffer.from(c.float64_le,'base64');
    assert.equal(crypto.createHash('sha256').update(raw).digest('hex'),c.sha256);
    let maxError=0,peak=0;
    for(let channel=0;channel<c.channels;channel++){
      assert.equal(actual.channels[channel].length,c.frames,c.name);
      for(let sample=0;sample<c.frames;sample++){
        const expected=raw.readDoubleLE((channel*c.frames+sample)*8);
        const error=Math.abs(actual.channels[channel][sample]-expected);
        peak=Math.max(peak,Math.abs(expected));maxError=Math.max(maxError,error);
        assert.ok(error<=1e-10+1e-9*Math.abs(expected),`${c.name}: ch${channel} sample${sample}: error ${error}`);
      }
    }
    records.push({name:c.name,frames:c.frames,channels:c.channels,maximum_absolute_error:maxError,reference_peak:peak});
  }
  fs.mkdirSync('generated/audiolabs-verification',{recursive:true});
  fs.writeFileSync('generated/audiolabs-verification/waveform-parity.json',JSON.stringify({cases:records,sample_count:data.cases.reduce((n,c)=>n+c.channels*c.frames,0),maximum_absolute_error:Math.max(...records.map(r=>r.maximum_absolute_error)),method:'every sample at the same index; no alignment, normalization or fitting'},null,2));
});

test('reference API rejects incompatible fields and nonphysical or unbounded inputs',()=>{
  const base=data.cases[0].scene;
  for(const value of [{...base,beta:undefined},{...base,reverberation_time:.4},{...base,beta:[1,2,3]},
    {...base,beta:[2,0,0,0,0,0]},{...base,dimension:4},{...base,microphone:'unknown'},
    {...base,orientation:[0,0,0]},{...base,max_order:13},{...base,nsample:0},
    {...base,footprint:[[0,0],[5,0],[0,5]]},{...base,nsample:192000,room:[.1,.1,.1],source:[.02,.02,.02],receivers:[[.07,.07,.07]],max_order:-1}]){
    assert.equal(JSON.parse(reference_samples_json(JSON.stringify(value))).ok,false,JSON.stringify(value));
  }
  const lexical=JSON.stringify(base).replace('"sample_rate":8000','"sample_rate":8000.0');
  assert.equal(JSON.parse(reference_samples_json(lexical)).ok,false);
});

test('reference WAV and convolution preserve upstream window and zero added latency',()=>{
  const scene={...data.cases[0].scene,sample_rate:16000,nsample:1024};
  const result=JSON.parse(generate_json(JSON.stringify(scene),fs.readFileSync('examples/probe.wav')));
  assert.equal(result.ok,true,result.error);
  assert.equal(result.report.config.latency_samples,0);
  assert.equal(result.report.config.output_frames,1024);
  assert.equal(result.report.wet.frames,16000+1024-1);
  const wav=Buffer.from(result.rir_wav);
  assert.equal(wav.readUInt32LE(54),1024*2*4);
  const native=JSON.parse(reference_samples_json(JSON.stringify(scene)));
  for(let i=0;i<1024;i++)for(let ch=0;ch<2;ch++) assert.equal(wav.readFloatLE(58+4*(i*2+ch)),Math.fround(native.channels[ch][i]));
});
