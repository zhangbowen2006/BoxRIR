import {generate_json} from './bridge.js';
self.onmessage=event=>{
  try{self.postMessage(JSON.parse(generate_json(event.data.scene,new Uint8Array(event.data.dry))));}
  catch(error){self.postMessage({ok:false,error:error.message});}
};
