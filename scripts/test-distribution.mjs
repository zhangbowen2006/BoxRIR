import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {root} from './build-support.mjs';
const original=path.join(root,'_build/distribution');
const parent=path.join(root,'generated/consumer-tests');fs.mkdirSync(parent,{recursive:true});
const destination=fs.mkdtempSync(path.join(parent,'standalone-'));
fs.cpSync(original,destination,{recursive:true});
const sums=JSON.parse(fs.readFileSync(path.join(destination,'SHA256SUMS.json')));
for(const [file,expected] of Object.entries(sums))assert.equal(createHash('sha256').update(fs.readFileSync(path.join(destination,file))).digest('hex'),expected,file);
for(const name of ['MoonBit-core.txt','MoonSpectrum.txt','MoonWavKit.txt','rir-generator.txt','audiolabs-rir-generator-MIT.txt','python-acoustics-BSD.txt'])assert.ok(fs.statSync(path.join(destination,'licenses',name)).size>100);
assert.ok(fs.existsSync(path.join(destination,'provenance/audiolabs-source-manifest.json')));
assert.ok(fs.existsSync(path.join(destination,'provenance/python-acoustics.json')));
const {createBoxRIR}=await import(pathToFileURL(path.join(destination,'sdk/client.mjs')));
const result=[];
const standaloneEnv = {...process.env, MOON_HOME:'', MOON_PATH:'', PATH:path.dirname(process.execPath)};
function runCLI(args) {
  const run = spawnSync(process.execPath, ['bin/boxrir.mjs', ...args], {
    cwd:destination, encoding:'utf8', env:standaloneEnv,
  });
  assert.equal(run.status, 0, run.stderr);
}
for(const backend of ['js','wasm-gc']){
  const engine=await createBoxRIR({backend,...(backend==='wasm-gc'?{wasmBytes:fs.readFileSync(path.join(destination,'sdk/boxrir.wasm'))}:{})});
  const scene=fs.readFileSync(path.join(destination,'examples/reference-cardioid.json'),'utf8');
  const audio=engine.render(scene,{dryWav:fs.readFileSync(path.join(destination,'examples/probe.wav'))});
  assert.equal(audio.report.config.output_frames,2048);assert.equal(audio.report.wet.frames,18047);
  const spectral=engine.render(fs.readFileSync(path.join(destination,'examples/spectral-before.json'),'utf8'));
  assert.equal(spectral.report.config.model,'octave_bands');assert.equal(spectral.report.config.latency_samples,272);
  runCLI(['--backend',backend,'simulate','examples/triangle.json','examples/probe.wav','output-'+backend]);
  assert.equal(JSON.parse(fs.readFileSync(path.join(destination,'output-'+backend,'run-manifest.json'))).backend,backend);

  const mixSpec = fs.readFileSync(path.join(destination, 'examples/mixed-recording.json'), 'utf8');
  const trackNames = ['foreground', 'background'];
  const tracks = trackNames.map(name => engine.probe(
    fs.readFileSync(path.join(destination, 'examples', 'probe-' + name + '.json'), 'utf8'),
  ));
  const filenames = tracks.map((track, index) => {
    const filename = `probe-${backend}-${index}.wav`;
    fs.writeFileSync(path.join(destination, filename), track.wav);
    return filename;
  });
  const mixOutput = 'mix-' + backend;
  runCLI(['--backend', backend, 'mix', 'examples/mixed-recording.json', mixOutput, ...filenames]);
  runCLI(['verify', mixOutput]);
  const mixed = engine.mix(mixSpec, tracks.map(track => track.wav));
  assert.equal(mixed.report.channels, 2);
  assert.equal(mixed.report.frames, 15631);
  assert.deepEqual(fs.readFileSync(path.join(destination, mixOutput, 'wet.wav')), Buffer.from(mixed.wetWav));
  result.push({backend,sdk:true,cli:true,mix_and_manifest:true,moonbit_python_and_native_compiler_not_required:true});
}
const evidence={version:JSON.parse(fs.readFileSync(path.join(destination,'package.json'))).version,packaged_files:Object.keys(sums).length,sha256_verified:true,checks:result};
fs.mkdirSync(path.join(root,'generated/distribution-verification'),{recursive:true});
fs.writeFileSync(path.join(root,'generated/distribution-verification/result.json'),JSON.stringify(evidence,null,2)+'\n');
console.log(JSON.stringify(evidence));
