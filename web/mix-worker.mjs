import {createBoxRIR} from './sdk/client.mjs';

function tone(engine, sampleRate, frequency) {
  return engine.probe({
    kind: 'sine',
    sample_rate: sampleRate,
    frequency_hz: frequency,
    active_frames: Math.round(sampleRate * 0.6),
    fade_frames: Math.round(sampleRate * 0.018),
    amplitude: 0.6,
  }).wav;
}

self.onmessage = async ({data}) => {
  try {
    const engine = await createBoxRIR({backend: 'wasm-gc'});
    const dryWavs = data.tracks.map(({bytes, frequency}) => (
      bytes === null ? tone(engine, data.sampleRate, frequency) : new Uint8Array(bytes)
    ));
    const {report, wetWav} = engine.mix(data.scene, dryWavs);
    self.postMessage({ok: true, report, wetWav}, [wetWav.buffer]);
  } catch (error) {
    self.postMessage({ok: false, error: error.message});
  }
};
