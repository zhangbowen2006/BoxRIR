import fs from 'node:fs';
import path from 'node:path';
import {createBoxRIR} from '../sdk/client.mjs';
import {version} from '../sdk/version.mjs';
import {publishBundle,sha256} from './output.mjs';

const usage='Usage: node bin/boxrir.mjs [--backend js|wasm-gc] inspect scene.json | rir scene.json new-directory | simulate scene.json mono.wav new-directory';
const argv=process.argv.slice(2);
let backend='js';
if(argv[0]==='--backend'){argv.shift();backend=argv.shift();}
const [command,sceneFile,...args]=argv;
function read(file,max){
  const fd=fs.openSync(file,'r');
  try {
    const stat=fs.fstatSync(fd);if(!stat.isFile()||stat.size>max)throw new Error(`Input exceeds ${max} bytes or is not a file: ${file}`);
    // Read at most max+1 even if another process grows the file after stat.
    const bytes=Buffer.alloc(max+1);let offset=0,count;
    while(offset<bytes.length && (count=fs.readSync(fd,bytes,offset,bytes.length-offset,null))>0)offset+=count;
    if(offset>max)throw Error(`Input exceeds ${max} bytes: ${file}`);
    return bytes.subarray(0,offset);
  } finally {fs.closeSync(fd);}
}
function waveform(wav,report){
  const rate=report.config.sample_rate,channels=report.config.receivers.length,frames=(wav.length-58)/(4*channels);
  const width=960,height=80+channels*120,palette=['#0f766e','#2563eb','#c2410c','#7c3aed'];
  let svg=`<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}"><rect width="100%" height="100%" fill="#fff"/><g font-family="sans-serif" fill="#243b53"><text x="45" y="24" font-size="17">BoxRIR: room impulse responses</text><text x="45" y="44" font-size="12">Output timeline; common kernel latency ${report.config.latency_samples} samples (${(1000*report.config.latency_samples/rate).toFixed(3)} ms). Shared amplitude scale.</text>`;
  let peak=0;for(let i=58;i<wav.length;i+=4)peak=Math.max(peak,Math.abs(wav.readFloatLE(i)));peak=peak||1;
  for(let ch=0;ch<channels;ch++){
    const y=100+ch*120;svg+=`<path d="M 60 ${y} H 920" stroke="#cbd5e1"/><text x="8" y="${y+4}" font-size="11">Mic ${ch}</text>`;
    let d='';for(let x=0;x<860;x++){
      const lo=Math.floor(x*frames/860),hi=Math.max(lo+1,Math.floor((x+1)*frames/860));let min=0,max=0;
      for(let i=lo;i<Math.min(hi,frames);i++){const v=wav.readFloatLE(58+4*(i*channels+ch));min=Math.min(min,v);max=Math.max(max,v);}
      d+=`M${60+x},${(y-45*max/peak).toFixed(2)}V${(y-45*min/peak).toFixed(2)} `;
    }
    svg+=`<path d="${d}" fill="none" stroke="${palette[ch%palette.length]}" stroke-width="1"/><text x="60" y="${y+60}" font-size="11">0 ms</text><text x="845" y="${y+60}" font-size="11">${(1000*frames/rate).toFixed(1)} ms</text>`;
  }
  return svg+'</g></svg>';
}
try{
  if(command==='--help' && !sceneFile){console.log(usage);process.exit(0);}
  if(command==='--version' && !sceneFile){console.log(version);process.exit(0);}
  if(!sceneFile||!['inspect','rir','simulate'].includes(command)||(command==='inspect'&&args.length!==0)||(command==='rir'&&args.length!==1)||(command==='simulate'&&args.length!==2))throw new Error(usage);
  const directory=command==='inspect'?null:path.resolve(args.at(-1));
  if(directory && fs.existsSync(directory))throw new Error('Output directory already exists: '+directory);
  const sceneBytes=read(sceneFile,262144),scene=new TextDecoder('utf-8',{fatal:true}).decode(sceneBytes);
  const bundled=new URL('../sdk/bridge.js',import.meta.url);
  const jsModuleURL=fs.existsSync(bundled)?bundled:new URL('../_build/js/release/build/bridge/bridge.js',import.meta.url);
  const wasmURL=fs.existsSync(new URL('../sdk/boxrir.wasm',import.meta.url))?new URL('../sdk/boxrir.wasm',import.meta.url):new URL('../_build/wasm-gc/release/build/bridge/bridge.wasm',import.meta.url);
  const engineFile=backend==='wasm-gc'?wasmURL:jsModuleURL;
  const engine=await createBoxRIR({backend,jsModuleURL,...(backend==='wasm-gc'?{wasmBytes:fs.readFileSync(wasmURL)}:{})});
  if(command==='inspect'){
    console.log(JSON.stringify(engine.inspect(scene),null,2));
  }else{
    const dry=command==='simulate'?read(args[0],4194304):new Uint8Array();
    if(command==='simulate'&&dry.length===0)throw new Error('Source WAV file is empty');
    const result=engine.render(scene,{dryWav:dry});
    const report=result.report,rir=Buffer.from(result.rirWav);
    const walls=report.config.geometry==='convex_prism'?[...report.config.footprint.map((_,i)=>`edge_${i}`),'floor','ceiling']:['x_low','x_high','y_low','y_high','z_low','z_high'];
    const csv=[['receiver','order','distance_m','arrival_sample','gain',...walls].join(','),...report.paths.map(p=>[p.receiver,p.order,p.distance,p.delay_samples,p.gain,...p.bounces].join(','))].join('\n')+'\n';
    const files=[['scene.json',sceneBytes],['rir.wav',rir],['report.json',JSON.stringify(report,null,2)+'\n'],['paths.csv',csv],['response.svg',waveform(rir,report)]];
    if(result.wetWav!==null)files.push(['wet.wav',Buffer.from(result.wetWav)],['source.wav',dry]);
    publishBundle(directory,files,{version,backend,engine_sha256:sha256(fs.readFileSync(engineFile)),inputs:{scene_sha256:sha256(sceneBytes),source_sha256:dry.length?sha256(dry):null}});
    console.log(JSON.stringify({directory,version,backend,channels:report.config.receivers.length,frames:report.config.output_frames,latency_samples:report.config.latency_samples,contributing_paths:report.contributing_paths,omitted_late_paths:report.omitted_late_paths,paths_exported:report.paths.length,paths_truncated:report.paths_truncated||false,wet:report.wet}));
  }
}catch(e){console.error(e.message);process.exitCode=2;}
