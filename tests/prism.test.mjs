import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {describe_json, generate_json} from '../_build/js/release/build/bridge/bridge.js';
const fixture = JSON.parse(fs.readFileSync(new URL('./reference/prism-pyroomacoustics-0.10.1.json', import.meta.url)));
const distance = (a,b) => Math.hypot(...a.map((x,i)=>x-b[i]));

test(`convex prism paths match independent finite-wall visibility across ${fixture.cases.length} upstream scenes`, () => {
  for (const c of fixture.cases) {
    const result = JSON.parse(describe_json(JSON.stringify(c.scene)));
    assert.equal(result.ok, true, result.error);
    assert.equal(result.paths.length, c.expected_paths.length, c.name);
    const used = new Set();
    for (const path of result.paths) {
      // Upstream stores successive plane reflections in Float32. At order 4,
      // analytic rectangle x=-22.63 becomes -22.629959106445312 upstream.
      // The MoonBit rectangle/closed-form test separately requires 1e-8 m.
      const index = c.expected_paths.findIndex((expected,i) => !used.has(i) && expected.receiver === path.receiver && expected.order === path.order && distance(expected.image,path.image) < 5e-5);
      assert.ok(index >= 0, `${c.name}: unmatched path ${JSON.stringify(path)}`);
      used.add(index);
      assert.ok(Math.abs(path.reflection-c.expected_paths[index].reflection) < 3e-6);
    }
    assert.equal(result.specular_paths.length,result.paths.length);
  }
});

test('new geometry rejects incomplete or mixed schemas and excess reflection order', () => {
  const scene = fixture.cases[1].scene;
  for (const value of [{...scene,room:[6,4,3]},{...scene,height:undefined},{...scene,footprint:undefined},{...scene,max_order:5},{...scene,absorption:[0.2]}]) {
    assert.equal(JSON.parse(describe_json(JSON.stringify(value))).ok,false);
  }
});

test('nonrectangular scenes produce usable multichannel impulse responses and source convolution', () => {
  for (const name of ['triangle','trapezoid','pentagon']) {
    const scene=JSON.parse(fs.readFileSync(`examples/${name}.json`));
    const result=JSON.parse(generate_json(JSON.stringify(scene),fs.readFileSync('examples/probe.wav')));
    assert.equal(result.ok,true,result.error);
    assert.equal(result.report.config.geometry,'convex_prism');
    assert.equal(result.report.contributing_paths.length,scene.receivers.length);
    assert.ok(result.wet_wav.length > result.rir_wav.length);
    assert.equal(result.report.wet.frames,result.report.wet.dry_frames+result.report.config.output_frames-1);
    const buffer=Buffer.from(result.rir_wav);
    assert.equal(buffer.readUInt16LE(22),scene.receivers.length);
    assert.equal(buffer.readUInt32LE(24),scene.sample_rate);
    for(let i=58;i<buffer.length;i+=4) assert.ok(Number.isFinite(buffer.readFloatLE(i)));
  }
});
