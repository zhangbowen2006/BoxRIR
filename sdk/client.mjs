/** BoxRIR host API. All acoustics are executed by the compiled MoonBit core. */
export class BoxRIRError extends Error {
  constructor(message, code = 'ENGINE_ERROR', options) {
    super(message, options); this.name = 'BoxRIRError'; this.code = code;
  }
}

function sceneText(scene) {
  let text;
  try { text = typeof scene === 'string' ? scene : JSON.stringify(scene); }
  catch (cause) { throw new BoxRIRError('Scene must be serializable JSON', 'INVALID_SCENE', {cause}); }
  if (typeof text !== 'string' || text.length > 65536) throw new BoxRIRError('Scene JSON limit: 65536 characters', 'INVALID_SCENE');
  return text;
}

function encode(bytes, limit = 4194304) {
  if (!(bytes instanceof Uint8Array)) throw new BoxRIRError('WAV must be a Uint8Array', 'INVALID_AUDIO');
  if (bytes.byteLength > limit) throw new BoxRIRError(`WAV exceeds ${limit} bytes`, 'INVALID_AUDIO');
  if (typeof Buffer !== 'undefined') return Buffer.from(bytes.buffer,bytes.byteOffset,bytes.byteLength).toString('base64');
  const chunks=[];
  for(let i=0;i<bytes.length;i+=32768) chunks.push(String.fromCharCode(...bytes.subarray(i,i+32768)));
  return btoa(chunks.join(''));
}

function decode(value) {
  if (value === null) return null;
  if (typeof value !== 'string') throw new BoxRIRError('Invalid engine audio encoding', 'INVALID_RESPONSE');
  // Own the underlying buffer; never expose pooled Node Buffer storage.
  if (typeof Buffer !== 'undefined') return Uint8Array.from(Buffer.from(value,'base64'));
  const text=atob(value), bytes=new Uint8Array(text.length);
  for(let i=0;i<bytes.length;i++) bytes[i]=text.charCodeAt(i);
  return bytes;
}

function response(text) {
  let result;
  try {result=JSON.parse(text);}
  catch(cause) {throw new BoxRIRError('Malformed engine response','INVALID_RESPONSE',{cause});}
  if(!result || typeof result.ok!=='boolean') throw new BoxRIRError('Invalid engine response','INVALID_RESPONSE');
  if (!result.ok) throw new BoxRIRError(result.error || 'Engine rejected the input');
  return result;
}

/** Create once, then render synchronously. Put long computations in a Worker. */
export async function createBoxRIR({backend='js',jsModuleURL=new URL('./bridge.js',import.meta.url),wasmURL=new URL('./boxrir.wasm',import.meta.url),wasmBytes}={}) {
  let engine;
  if (backend === 'js') {
    try {engine=await import(String(jsModuleURL));}
    catch(cause) {throw new BoxRIRError('Cannot load JS engine artifact','ENGINE_LOAD',{cause});}
  }
  else if (backend === 'wasm-gc') {
    let bytes=wasmBytes;
    try {
      if (!bytes) {
        const result=await fetch(wasmURL);
        if (!result.ok) throw new Error(`HTTP ${result.status}`);
        bytes=await result.arrayBuffer();
      }
      const module=await WebAssembly.compile(bytes,{builtins:['js-string'],importedStringConstants:'_'});
      if (WebAssembly.Module.imports(module).length) throw new Error('Unexpected non-builtin host imports');
      engine=(await WebAssembly.instantiate(module,{})).exports;
    } catch (cause) { throw new BoxRIRError('Wasm GC/string-builtins engine unavailable; use a supported browser/Node or explicitly select the JS backend', 'ENGINE_LOAD',{cause}); }
  } else throw new BoxRIRError('backend must be js or wasm-gc', 'INVALID_BACKEND');
  if (typeof engine.render_base64_json !== 'function') throw new BoxRIRError('Incompatible engine artifact', 'ENGINE_LOAD');
  return Object.freeze({
    backend,
    render(scene,{dryWav=new Uint8Array()}={}) {
      const result=response(engine.render_base64_json(sceneText(scene),encode(dryWav)));
      return {backend,report:result.report,rirWav:decode(result.rir_wav),wetWav:decode(result.wet_wav)};
    },
    inspect(scene) { return response(engine.describe_json(sceneText(scene))); },
    referenceSamples(scene) { return response(engine.reference_samples_json(sceneText(scene))); },
    spectralSamples(scene) { return response(engine.spectral_samples_json(sceneText(scene))); },
    mix(scene, dryWavs) {
      if (!Array.isArray(dryWavs) || dryWavs.length < 1 || dryWavs.length > 4 ||
          dryWavs.some(bytes => !(bytes instanceof Uint8Array))) {
        throw new BoxRIRError('Provide 1..4 WAV byte arrays in track order', 'INVALID_AUDIO');
      }
      if (dryWavs.reduce((total, bytes) => total + bytes.byteLength, 0) > 8388608) {
        throw new BoxRIRError('Track WAV total exceeds 8 MiB', 'INVALID_AUDIO');
      }
      const result = response(engine.mix_recordings_json(sceneText(scene),
        JSON.stringify(dryWavs.map(bytes => encode(bytes)))));
      return {backend, report:result.report, wetWav:decode(result.wet_wav)};
    },
    probe(settings) {
      const result = response(engine.probe_json(sceneText(settings)));
      return {sampleRate:result.sample_rate, frames:result.frames, wav:decode(result.probe_wav)};
    },
    defaultProbe(sampleRate) {
      if (!Number.isInteger(sampleRate)) throw new BoxRIRError('Sample rate must be an integer', 'INVALID_AUDIO');
      const result = response(engine.default_probe_json(sampleRate));
      return {sampleRate:result.sample_rate, frames:result.frames, wav:decode(result.probe_wav)};
    },
    analyzeResponse(wav, options = {}) {
      return response(engine.analyze_response_json(sceneText(options),encode(wav,8388608))).report;
    },
    estimateResponse(probeWav, recordedWav, options) {
      const result = response(engine.estimate_response_json(sceneText(options),encode(probeWav),
        encode(recordedWav,8388608)));
      return {backend, report:result.report, rirWav:decode(result.rir_wav)};
    },
    compareResponses(referenceWav, observedWav, options = {}) {
      return response(engine.compare_responses_json(sceneText(options),
        encode(referenceWav,8388608),encode(observedWav,8388608))).report;
    },
    resample(wav, sampleRate) {
      if (!Number.isInteger(sampleRate)) throw new BoxRIRError('Sample rate must be an integer', 'INVALID_AUDIO');
      const result = response(engine.resample_audio_json(
        JSON.stringify({sample_rate:sampleRate}),encode(wav,8388608)));
      return {backend,report:result.report,wav:decode(result.wav)};
    },
  });
}
