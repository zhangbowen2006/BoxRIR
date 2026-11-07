const $=id=>document.getElementById(id);
let worker,probe,presets={},urls=[],last,dryURL,requestSerial=0,submittedScene='';
function status(message,error=false){$('status').textContent=message;$('status').classList.toggle('error',error);}
function resetWorker(){worker?.terminate();const next=new Worker(new URL('./worker.mjs',import.meta.url),{type:'module'});worker=next;next.onmessage=e=>{if(worker===next)finish(e.data);};next.onerror=e=>{if(worker===next)finish({ok:false,error:e.message});};}
function busy(value){$('run').disabled=value;$('cancel').disabled=!value;for(const id of ['preset','source','scene'])$(id).disabled=value;}
function blobURL(bytes,type){const url=URL.createObjectURL(new Blob([bytes],{type}));urls.push(url);return url;}
function drawRoom(scene){
  const vertices=scene.footprint||[[0,0],[scene.room[0],0],scene.room.slice(0,2),[0,scene.room[1]]];
  const lx=Math.max(...vertices.map(p=>p[0])),ly=Math.max(...vertices.map(p=>p[1]));if(!(lx>0&&ly>0))return;
  const scale=Math.min(430/lx,190/ly),x=35,y=30,w=lx*scale,h=ly*scale;
  let markup=`<polygon points="${vertices.map(p=>`${x+p[0]*scale},${y+h-p[1]*scale}`).join(' ')}" fill="#edf7f6" stroke="#087e8b" stroke-width="2"/><text x="${x}" y="${y+h+24}" font-size="12" fill="#526b79">${scene.footprint?'凸多边形房间':'矩形房间'} · XY 平面 · 单位 m</text>`;
  const point=(p,color,label)=>`<circle cx="${x+p[0]*scale}" cy="${y+h-p[1]*scale}" r="6" fill="${color}"/><text x="${x+p[0]*scale+9}" y="${y+h-p[1]*scale+4}" font-size="12" fill="#173547">${label}</text>`;
  markup+=point(scene.source,'#c2410c','S');scene.receivers.forEach((p,i)=>{markup+=point(p,'#2563eb',`M${i}`)});$('floor').innerHTML=markup;
}
function audition(){
  if(!last?.wet_wav)return;
  let bytes=new Uint8Array(last.wet_wav),gain=1;
  if($('listen-gain').checked){
    const peak=Math.max(...last.report.wet.peaks);if(peak>0){gain=Math.min(1000,0.85/peak);const view=new DataView(bytes.buffer);for(let i=58;i<bytes.length;i+=4)view.setFloat32(i,view.getFloat32(i,true)*gain,true);}
  }
  $('wet-player').src=blobURL(bytes,'audio/wav');$('gain-note').textContent=`试听增益 ${gain.toFixed(3)} 倍，所有通道统一处理。下载文件保持原始模型增益。`;
}
function finish(result){
  busy(false);if(!result.ok){status(result.error,true);return;}
  last=result;$('results').classList.remove('hidden');$('empty').classList.add('hidden');
  const r=result.report,c=r.config;drawRoom(c);$('channels').textContent=c.receivers.length;$('images').textContent=r.geometric_images;$('latency').textContent=`${(1000*c.latency_samples/c.sample_rate).toFixed(2)} ms`;
  $('dry-player').src=dryURL;audition();
  $('paths').replaceChildren();for(let i=0;i<c.receivers.length;i++){
    const direct=(r.direct_paths||r.paths).find(p=>p.receiver===i&&p.order===0),tr=document.createElement('tr');
    for(const value of [`M${i}`,`${(direct.delay_samples/c.sample_rate*1000).toFixed(3)} ms`,r.contributing_paths[i],r.omitted_late_paths[i]]){const td=document.createElement('td');td.textContent=value;tr.append(td);}$('paths').append(tr);
  }
  $('downloads').replaceChildren();for(const [name,data,type] of [['rir.wav',new Uint8Array(result.rir_wav),'audio/wav'],['wet.wav',new Uint8Array(result.wet_wav),'audio/wav'],['report.json',JSON.stringify(r,null,2),'application/json'],['scene.json',submittedScene,'application/json']]){
    const a=document.createElement('a');a.className='download';a.textContent=name;a.download=name;a.href=blobURL(data,type);$('downloads').append(a);
  }
  status(`计算完成：${c.output_frames} 帧响应，${r.wet.frames} 帧模拟录音。时间窗之外的路径计数见上表。${r.paths_truncated?' 路径明细已达 10000 条上限；波形仍包含全部已计算贡献。':''}`);
}
$('preset').onchange=()=>{$('scene').value=JSON.stringify(presets[$('preset').value],null,2);drawRoom(presets[$('preset').value]);};
$('listen-gain').onchange=audition;
$('cancel').onclick=()=>{requestSerial++;resetWorker();busy(false);status('已取消。可以调整参数后重新计算。');};
$('run').onclick=async()=>{
  const request=++requestSerial;
  try{
    const sceneText=$('scene').value;JSON.parse(sceneText);
    const file=$('source').files[0];if(file&&file.size===0)throw new Error('选择的 WAV 文件为空');if(file&&file.size>4194304)throw new Error('WAV 文件不能超过 4 MiB');
    busy(true);status('正在读取声源…');
    const dry=file?await file.arrayBuffer():probe.slice(0);
    if(request!==requestSerial)return;
    submittedScene=sceneText;
    urls.forEach(URL.revokeObjectURL);urls=[];$('results').classList.add('hidden');last=null;dryURL=blobURL(dry,'audio/wav');
    status('正在计算传播路径与模拟录音…');worker.postMessage({scene:sceneText,dry},[dry]);
  }catch(e){if(request===requestSerial){busy(false);status(e.message,true);}}
};
try{
  const names=['stereo','wall-before','wall-after','array','triangle','trapezoid','pentagon','reference-omni','reference-cardioid','reference-2d'];
  const responses=await Promise.all(names.map(n=>fetch(`examples/${n}.json`).then(r=>{if(!r.ok)throw Error('示例加载失败');return r.json()})));
  names.forEach((n,i)=>presets[n]=responses[i]);probe=await fetch('examples/probe.wav').then(r=>r.arrayBuffer());
  resetWorker();$('preset').onchange();busy(false);status('已就绪。计算在本浏览器内运行。');
}catch(e){status(e.message,true);$('run').disabled=true;}
