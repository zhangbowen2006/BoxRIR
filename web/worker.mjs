import {createBoxRIR} from './sdk/client.mjs';
const engine=createBoxRIR({backend:'wasm-gc'});
self.onmessage=async event=>{
  try{
    const client=await engine;
    const generated=event.data.dry===null;
    const dryWav=generated
      ? client.defaultProbe(JSON.parse(event.data.scene).sample_rate).wav
      : new Uint8Array(event.data.dry);
    const result=client.render(event.data.scene,{dryWav});
    const buffers=[result.rirWav.buffer];
    if(result.wetWav)buffers.push(result.wetWav.buffer);
    if(generated)buffers.push(dryWav.buffer);
    self.postMessage({
      ok:true,backend:result.backend,report:result.report,
      rir_wav:result.rirWav,wet_wav:result.wetWav,generated_source:generated?dryWav:null,
    },buffers);
  }
  catch(error){self.postMessage({ok:false,error:error.message});}
};
