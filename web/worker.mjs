import {createBoxRIR} from './sdk/client.mjs';
const engine=createBoxRIR({backend:'wasm-gc'});
self.onmessage=async event=>{
  try{
    const result=(await engine).render(event.data.scene,{dryWav:new Uint8Array(event.data.dry)});
    const buffers=[result.rirWav.buffer];if(result.wetWav)buffers.push(result.wetWav.buffer);
    self.postMessage({ok:true,backend:result.backend,report:result.report,rir_wav:result.rirWav,wet_wav:result.wetWav},buffers);
  }
  catch(error){self.postMessage({ok:false,error:error.message});}
};
