import {createBoxRIR,BoxRIRError,type Scene,type ReferenceScene,type SpectralScene} from '../sdk/client.mjs';
const reference:ReferenceScene={model:'audiolabs_v030',room:[6,4,3],source:[1,1,1],receivers:[[2,2,1]],sample_rate:16000,beta:[.7,.7,.7,.7,.7,.7],nsample:1024,microphone:'cardioid'};
const scene:Scene={footprint:[[0,0],[6,0],[0,4]],height:3,source:[1,1,1],receivers:[[2,1,1]],absorption:[.3,.3,.3,.3,.3],sample_rate:16000,max_order:3,duration_ms:100};
const engine=await createBoxRIR({backend:'wasm-gc',wasmBytes:new Uint8Array()});
const result=engine.render(scene,{dryWav:new Uint8Array()});
const wav:Uint8Array=result.rirWav,wet:Uint8Array|null=result.wetWav;
const channel:number[]=engine.referenceSamples(reference).channels[0];
new BoxRIRError(String(wav.length+(wet?.length||0)+channel.length),'INVALID_AUDIO',{cause:new Error()});
const spectral:SpectralScene={model:'octave_bands',room:[6,4,3],source:[1,1,1],receivers:[[2,2,1]],sample_rate:16000,max_order:2,duration_ms:60,band_absorption:Array.from({length:6},()=>Array(6).fill(.2)),atmosphere:{temperature_c:20,relative_humidity_percent:50}};
engine.spectralSamples(spectral).report.wet?.frames;

const {source: _source, ...recordingScene} = scene;
const probe = engine.probe({kind:'sine', sample_rate:16000, active_frames:1600, frequency_hz:1000});
const mixed = engine.mix({version:1, scene:recordingScene, tracks:[
  {id:'front',source:[1,1,1],start_frame:0,gain:0.5},
]}, [probe.wav]);
const recorded: Uint8Array = mixed.wetWav;
const response = engine.estimateResponse(probe.wav, recorded, {response_frames:1024});
const fit: number|null = engine.analyzeResponse(response.rirWav, {curve_points:128}).channels[0].t20.seconds_for_60db;
const lag: number = engine.compareResponses(response.rirWav, response.rirWav, {lag_radius:2}).channels[0].observed_lag_frames;
const converted: Uint8Array = engine.resample(recorded, 48000).wav;
