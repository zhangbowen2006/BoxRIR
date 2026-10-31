import fs from 'node:fs';
import path from 'node:path';
import {describe_json,generate_json} from '../_build/js/release/build/bridge/bridge.js';

const usage='Usage: node bin/boxrir.mjs inspect scene.json | rir scene.json new-directory | simulate scene.json mono.wav new-directory';
const [command,sceneFile,...args]=process.argv.slice(2);
function read(file,max){const stat=fs.statSync(file);if(!stat.isFile()||stat.size>max)throw new Error(`Input exceeds ${max} bytes or is not a file: ${file}`);return fs.readFileSync(file);}
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
  if(!sceneFile||!['inspect','rir','simulate'].includes(command)||(command==='inspect'&&args.length!==0)||(command==='rir'&&args.length!==1)||(command==='simulate'&&args.length!==2))throw new Error(usage);
  const scene=read(sceneFile,262144).toString('utf8');
  if(command==='inspect'){
    const result=JSON.parse(describe_json(scene));if(!result.ok)throw new Error(result.error);
    console.log(JSON.stringify(result,null,2));
  }else{
    const dry=command==='simulate'?read(args[0],4194304):new Uint8Array();
    if(command==='simulate'&&dry.length===0)throw new Error('Source WAV file is empty');
    const result=JSON.parse(generate_json(scene,dry));if(!result.ok)throw new Error(result.error);
    const directory=path.resolve(args.at(-1));
    if(fs.existsSync(directory))throw new Error('Output directory already exists: '+directory);
    const report=result.report,rir=Buffer.from(result.rir_wav);
    const csv=['receiver,order,distance_m,arrival_sample,gain,x_low,x_high,y_low,y_high,z_low,z_high',...report.paths.map(p=>[p.receiver,p.order,p.distance,p.delay_samples,p.gain,...p.bounces].join(','))].join('\n')+'\n';
    const files=[['rir.wav',rir],['report.json',JSON.stringify(report,null,2)+'\n'],['paths.csv',csv],['response.svg',waveform(rir,report)]];
    if(result.wet_wav!==null)files.push(['wet.wav',Buffer.from(result.wet_wav)]);
    fs.mkdirSync(path.dirname(directory),{recursive:true});fs.mkdirSync(directory);
    const marker=path.join(directory,'.boxrir-incomplete');fs.writeFileSync(marker,'Output is incomplete until this marker is removed.\n',{flag:'wx'});
    for(const [name,data] of files)fs.writeFileSync(path.join(directory,name),data,{flag:'wx'});
    fs.unlinkSync(marker);
    console.log(JSON.stringify({directory,channels:report.config.receivers.length,frames:report.config.output_frames,latency_samples:report.config.latency_samples,contributing_paths:report.contributing_paths,omitted_late_paths:report.omitted_late_paths,wet:report.wet}));
  }
}catch(e){console.error(e.message);process.exitCode=2;}
