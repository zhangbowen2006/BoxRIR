import fs from 'node:fs';
import {spawnSync} from 'node:child_process';
import {performance} from 'node:perf_hooks';
import {createBoxRIR} from '../sdk/client.mjs';
const scenarios={
  'spectral-materials':JSON.parse(fs.readFileSync('examples/spectral-before.json')),
  'reference':JSON.parse(fs.readFileSync('examples/reference-omni.json')),
  'convex-max-order':{footprint:Array.from({length:8},(_,i)=>[5+4*Math.cos(i*Math.PI/4),5+4*Math.sin(i*Math.PI/4)]),height:3,source:[4.1,4.7,1.3],receivers:[[6.2,5.4,1.9]],absorption:Array(10).fill(.2),sample_rate:16000,max_order:4,duration_ms:150},
  'large-buffer':{model:'audiolabs_v030',room:[6,4,3],source:[1,1,1],receivers:Array.from({length:8},(_,i)=>[2+i*.1,2,1.2]),beta:Array(6).fill(0),sample_rate:96000,nsample:96000,max_order:0}
};
const [backend,name]=process.argv.slice(2);
if(backend){
  const scene=scenarios[name],start=performance.now();
  const engine=await createBoxRIR({backend,jsModuleURL:new URL('../_build/js/release/build/bridge/bridge.js',import.meta.url),...(backend==='wasm-gc'?{wasmBytes:fs.readFileSync('_build/wasm-gc/release/build/bridge/bridge.wasm')}:{})});
  const init_ms=performance.now()-start;
  // Stress the large convolution with an actual mono Float32 WAV at 96kHz.
  let dry=fs.readFileSync('examples/probe.wav');
  if(name==='large-buffer'){
    const frames=65536;dry=Buffer.alloc(44+frames*4);dry.write('RIFF',0);dry.writeUInt32LE(dry.length-8,4);dry.write('WAVEfmt ',8);dry.writeUInt32LE(16,16);dry.writeUInt16LE(3,20);dry.writeUInt16LE(1,22);dry.writeUInt32LE(96000,24);dry.writeUInt32LE(384000,28);dry.writeUInt16LE(4,32);dry.writeUInt16LE(32,34);dry.write('data',36);dry.writeUInt32LE(frames*4,40);
    for(let i=0;i<frames;i++)dry.writeFloatLE(.1*Math.sin(2*Math.PI*1000*i/96000),44+i*4);
  }
  const before=performance.now(),result=engine.render(scene,{dryWav:dry});
  const view=new DataView(result.wetWav.buffer);for(let i=58;i<result.wetWav.length;i+=4)if(!Number.isFinite(view.getFloat32(i,true)))throw Error('Nonfinite stress output');
  console.log(JSON.stringify({backend,scenario:name,init_ms,render_ms:performance.now()-before,maximum_rss_kib:process.resourceUsage().maxRSS,rir_frames:result.report.config.output_frames,wet_frames:result.report.wet.frames,channels:scene.receivers.length,output_bytes:result.rirWav.length+result.wetWav.length}));
}else{
  const records=[];
  for(const backend of ['js','wasm-gc'])for(const name of Object.keys(scenarios)){
    const run=spawnSync(process.execPath,['--max-old-space-size=768','scripts/benchmark-runtime.mjs',backend,name],{encoding:'utf8',timeout:120000,maxBuffer:262144});
    if(run.status!==0)throw Error(run.stderr||String(run.error));records.push(JSON.parse(run.stdout));
  }
  const result={node:process.version,platform:process.platform,architecture:process.arch,scope:'single cold-process development measurements; no performance superiority or universal memory guarantee',records};
  fs.mkdirSync('generated/runtime-benchmark',{recursive:true});fs.writeFileSync('generated/runtime-benchmark/results.json',JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result));
}
