import {createBoxRIR,BoxRIRError,type Scene,type ReferenceScene} from '../sdk/client.mjs';
const reference:ReferenceScene={model:'audiolabs_v030',room:[6,4,3],source:[1,1,1],receivers:[[2,2,1]],sample_rate:16000,beta:[.7,.7,.7,.7,.7,.7],nsample:1024,microphone:'cardioid'};
const scene:Scene={footprint:[[0,0],[6,0],[0,4]],height:3,source:[1,1,1],receivers:[[2,1,1]],absorption:[.3,.3,.3,.3,.3],sample_rate:16000,max_order:3,duration_ms:100};
const engine=await createBoxRIR({backend:'wasm-gc',wasmBytes:new Uint8Array()});
const result=engine.render(scene,{dryWav:new Uint8Array()});
const wav:Uint8Array=result.rirWav,wet:Uint8Array|null=result.wetWav;
const channel:number[]=engine.referenceSamples(reference).channels[0];
new BoxRIRError(String(wav.length+(wet?.length||0)+channel.length),'INVALID_AUDIO',{cause:new Error()});
