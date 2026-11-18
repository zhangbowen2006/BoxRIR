import fs from 'node:fs';
import path from 'node:path';
import {publishBundle, sha256} from './output.mjs';

const MiB = 1024 * 1024;
const textDecoder = new TextDecoder('utf-8', {fatal:true});
const json = value => JSON.stringify(value, null, 2) + '\n';

function readTracks(files, read) {
  let remaining = 8 * MiB;
  return files.map(file => {
    const bytes = read(file, Math.min(4 * MiB, remaining));
    if (bytes.length === 0) throw new Error('Track WAV is empty: ' + file);
    remaining -= bytes.length;
    return bytes;
  });
}

const validators = {
  mix: args => args.length >= 3 && args.length <= 6,
  probe: args => args.length === 2,
  analyze: args => args.length === 2 || args.length === 3,
  estimate: args => args.length === 4,
  compare: args => args.length === 4,
  resample: args => args.length === 3 && /^[0-9]{4,5}$/.test(args[1]),
};

export const experiments = Object.freeze(validators);

function mix([settingsFile, , ...trackFiles], {read,engine}) {
  const settings = read(settingsFile, 262144);
  const tracks = readTracks(trackFiles, read);
  const result = engine.mix(textDecoder.decode(settings), tracks);
  return {
    outputs:[['wet.wav', result.wetWav]],
    inputs:[['mix.json', settings], ...tracks.map((bytes,i) => [`track-${i+1}.wav`, bytes])],
    report:result.report,
  };
}

function probe([settingsFile], {read,engine}) {
  const settings = read(settingsFile, 16384);
  const result = engine.probe(textDecoder.decode(settings));
  return {
    outputs:[['probe.wav', result.wav]],
    inputs:[['probe.json', settings]],
    report:{sample_rate:result.sampleRate, frames:result.frames, channels:1},
  };
}

function analyze([responseFile, , settingsFile], {read,engine}) {
  const input = read(responseFile, 8 * MiB);
  const settings = settingsFile ? read(settingsFile, 16384) : Buffer.from('{}\n');
  return {
    outputs:[],
    inputs:[['response.wav', input], ['analysis-options.json', settings]],
    report:engine.analyzeResponse(input, textDecoder.decode(settings)),
  };
}

function estimate([probeFile, recordingFile, settingsFile], {read,engine}) {
  const source = read(probeFile, 4 * MiB);
  const recording = read(recordingFile, 8 * MiB);
  const settings = read(settingsFile, 16384);
  const result = engine.estimateResponse(source, recording, textDecoder.decode(settings));
  return {
    outputs:[['estimated-rir.wav', result.rirWav]],
    inputs:[['probe.wav', source], ['recorded.wav', recording], ['estimate-options.json', settings]],
    report:result.report,
  };
}

function compare([referenceFile, observedFile, settingsFile], {read,engine}) {
  const reference = read(referenceFile, 8 * MiB);
  const observed = read(observedFile, 8 * MiB);
  const settings = read(settingsFile, 16384);
  return {
    outputs:[],
    inputs:[['reference.wav', reference], ['observed.wav', observed], ['compare-options.json', settings]],
    report:engine.compareResponses(reference, observed, textDecoder.decode(settings)),
  };
}

function resample([sourceFile, rate], {read,engine}) {
  const source = read(sourceFile, 8 * MiB);
  const result = engine.resample(source, Number(rate));
  return {
    inputs:[['source.wav', source], ['resample-options.json', json({sample_rate:Number(rate)})]],
    outputs:[['resampled.wav', result.wav]],
    report:result.report,
  };
}

const execute = {mix,probe,analyze,estimate,compare,resample};
const outputArgument = {estimate:3,compare:3,resample:2};

export function runExperiment(command, args, context) {
  if (!Object.hasOwn(validators,command) || !validators[command](args)) throw new Error(context.usage);
  const directory = path.resolve(args[outputArgument[command]??1]);
  if (fs.existsSync(directory)) throw new Error('Output directory already exists: ' + directory);
  const result = execute[command](args,context);
  publishBundle(directory,[
    ...result.inputs,
    ...result.outputs,
    ['report.json',json(result.report)],
  ],{
    version:context.version,
    backend:context.backend,
    command,
    engine_sha256:context.engineDigest,
    inputs:Object.fromEntries(result.inputs.map(([name,bytes]) => [name,sha256(bytes)])),
  });
  return {directory,version:context.version,backend:context.backend,command,
    sample_rate:result.report.sample_rate,frames:result.report.frames??result.report.compared_frames};
}
