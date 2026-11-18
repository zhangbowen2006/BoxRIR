export type Vec3 = [number, number, number];
export type Point2 = [number, number];
export interface CommonScene { source: Vec3; receivers: Vec3[]; sample_rate: number; speed?: number }
export interface ShoeboxScene extends CommonScene { room: Vec3; absorption: number[]; max_order: number; duration_ms: number; half_width?: number }
export interface PrismScene extends CommonScene { footprint: Point2[]; height: number; absorption: number[]; max_order: number; duration_ms: number; half_width?: number }
export interface ReferenceScene extends CommonScene {
  model: 'audiolabs_v030'; room: Vec3; beta?: number[] | [Point2, Point2, Point2];
  reverberation_time?: number; nsample?: number; max_order?: number; dimension?: 2|3;
  microphone?: 'o'|'b'|'c'|'s'|'h'|'omnidirectional'|'bidirectional'|'cardioid'|'subcardioid'|'hypercardioid';
  orientation?: []|[number]|[number,number]; high_pass?: boolean;
}
export interface SpectralScene extends CommonScene {
  model:'octave_bands';room?:Vec3;footprint?:Point2[];height?:number;
  band_absorption:number[][];air_db_per_m?:number[];
  atmosphere?:{temperature_c:number;relative_humidity_percent:number;pressure_kpa?:number};
  max_order:number;duration_ms:number;half_width?:number;band_filter_half_width?:number;
}
export type Scene = ShoeboxScene | PrismScene | ReferenceScene | SpectralScene;
export interface Path { receiver: number; image: Vec3; bounces: number[]; order: number; distance: number; delay_samples: number; reflection: number; gain: number }
export interface Report {
  config: { sample_rate: number; receivers: Vec3[]; output_frames: number; latency_samples: number; [key: string]: unknown };
  paths: Path[]; direct_paths?: Path[]; paths_truncated?: boolean;
  contributing_paths: number[]; omitted_late_paths: number[]; zero_gain_paths: number[]; rir_peaks: number[];
  wet: null | {frames:number;peaks:number[];dry_frames:number};
  [key: string]: unknown;
}
export type RecordingScene = Omit<ShoeboxScene,'source'> | Omit<PrismScene,'source'> | Omit<SpectralScene,'source'>;
export interface RecordingTrack {
  id: string;
  source: Vec3;
  start_frame: number;
  gain: number;
}
export interface RecordingSpec {version: 1; scene: RecordingScene; tracks: RecordingTrack[]}
export interface RecordingTrackReport extends RecordingTrack {
  dry_frames: number;
  rir_frames: number;
  wet_frames: number;
  end_frame: number;
  latency_samples: number;
  contributing_paths: number[];
  omitted_late_paths: number[];
  zero_gain_paths: number[];
}
export interface RecordingReport {
  version: 1;
  scene: RecordingScene;
  sample_rate: number;
  channels: number;
  frames: number;
  latency_samples: number;
  peaks: number[];
  tracks: RecordingTrackReport[];
}
export interface ProbeWindow {
  sample_rate: number;
  active_frames: number;
  lead_frames?: number;
  tail_frames?: number;
  fade_frames?: number;
  amplitude?: number;
}
export type ProbeSpec = ProbeWindow & (
  {kind:'impulse'} | {kind:'sine';frequency_hz:number} |
  {kind:'log_sweep';start_hz:number;end_hz:number} | {kind:'white_noise';seed:number}
);
export interface ProbeAudio {sampleRate:number;frames:number;wav:Uint8Array}
export interface DecayFit {
  status: 'estimated'|'weak_fit'|'no_energy'|'insufficient_decay_range'|'insufficient_fit_samples';
  seconds_for_60db: number|null;
  slope_db_per_second: number|null;
  r_squared: number|null;
  samples_used: number;
  start_frame: number|null;
  end_frame: number|null;
}
export interface DecayChannel {
  onset_frame:number|null;
  window_end_exclusive:number;
  peak:number;
  power_sum:number;
  d50:number|null;
  c50_db:number|null;
  c80_db:number|null;
  center_time_ms:number|null;
  edt:DecayFit;
  t20:DecayFit;
  t30:DecayFit;
  curve:{frame_from_onset:number;energy_db:number}[];
}
export interface DecayOptions {onset_frames?:number[]; end_exclusive?:number; curve_points?:number}
export interface DecayReport {
  schema_version:1;
  sample_rate:number;
  frames:number;
  onset_mode:'explicit'|'threshold_minus_40db';
  channels:DecayChannel[];
}
export interface TransferOptions {response_frames:number; regularization_db?:number}
export interface TransferReport {
  schema_version:1;
  sample_rate:number;
  frames:number;
  transform_frames:number;
  recording_frames:number;
  probe_frames:number;
  regularization_db:number;
  reliable_bins:number;
  unique_bins:number;
  channels:{
    peak:number;
    outside_window_energy_fraction:number|null;
    reconstruction_error_fraction:number|null;
  }[];
}
export interface CompareOptions {
  frames?:number;
  reference_starts?:number[];
  observed_starts?:number[];
  lag_radius?:number;
}
export interface ComparisonReport {
  schema_version:1;
  sample_rate:number;
  reference_frames:number;
  observed_frames:number;
  compared_frames:number;
  channels:{
    status:'compared'|'both_silent'|'reference_silent'|'observed_silent';
    reference_start:number;
    requested_observed_start:number;
    observed_start:number;
    observed_lag_frames:number;
    lag_trials:number;
    signed_correlation:number|null;
    reference_to_observed_gain:number|null;
    observed_energy_delta_db:number|null;
    raw_error_ratio:number|null;
    adjusted_error_ratio:number|null;
  }[];
}
export interface ResampleReport {
  schema_version:1;
  sample_rate:number;
  frames:number;
  channels:number;
  input_rate:number;
  input_frames:number;
  tap_radius:number;
  cached_phases:number;
  latency_samples:0;
}
export class BoxRIRError extends Error { constructor(message:string,code?:string,options?:ErrorOptions); readonly code: string }
export interface BoxRIR {
  readonly backend: 'js'|'wasm-gc';
  render(scene: Scene|string, options?: {dryWav?: Uint8Array}): {backend:'js'|'wasm-gc';report:Report;rirWav:Uint8Array;wetWav:Uint8Array|null};
  inspect(scene: Scene|string): {ok:true;[key:string]:unknown};
  referenceSamples(scene: ReferenceScene|string): {ok:true;config:Record<string,unknown>;channels:number[][]};
  spectralSamples(scene: SpectralScene|string): {ok:true;report:Report;channels:number[][]};
  mix(scene:RecordingSpec|string, dryWavs:Uint8Array[]): {backend:'js'|'wasm-gc';report:RecordingReport;wetWav:Uint8Array};
  probe(settings:ProbeSpec|string): ProbeAudio;
  defaultProbe(sampleRate:number): ProbeAudio;
  analyzeResponse(wav:Uint8Array, options?:DecayOptions|string): DecayReport;
  estimateResponse(probeWav:Uint8Array, recordedWav:Uint8Array, options:TransferOptions|string): {backend:'js'|'wasm-gc';report:TransferReport;rirWav:Uint8Array};
  compareResponses(referenceWav:Uint8Array, observedWav:Uint8Array, options?:CompareOptions|string): ComparisonReport;
  resample(wav:Uint8Array, sampleRate:number): {backend:'js'|'wasm-gc';report:ResampleReport;wav:Uint8Array};
}
export function createBoxRIR(options?: {backend?:'js'|'wasm-gc';jsModuleURL?:string|URL;wasmURL?:string|URL;wasmBytes?:BufferSource}): Promise<BoxRIR>;
