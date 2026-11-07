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
export type Scene = ShoeboxScene | PrismScene | ReferenceScene;
export interface Path { receiver: number; image: Vec3; bounces: number[]; order: number; distance: number; delay_samples: number; reflection: number; gain: number }
export interface Report {
  config: { sample_rate: number; receivers: Vec3[]; output_frames: number; latency_samples: number; [key: string]: unknown };
  paths: Path[]; direct_paths?: Path[]; paths_truncated?: boolean;
  contributing_paths: number[]; omitted_late_paths: number[]; zero_gain_paths: number[]; rir_peaks: number[];
  wet: null | {frames:number;peaks:number[];dry_frames:number};
  [key: string]: unknown;
}
export class BoxRIRError extends Error { constructor(message:string,code?:string,options?:ErrorOptions); readonly code: string }
export interface BoxRIR {
  readonly backend: 'js'|'wasm-gc';
  render(scene: Scene|string, options?: {dryWav?: Uint8Array}): {backend:'js'|'wasm-gc';report:Report;rirWav:Uint8Array;wetWav:Uint8Array|null};
  inspect(scene: Scene|string): {ok:true;[key:string]:unknown};
  referenceSamples(scene: ReferenceScene|string): {ok:true;config:Record<string,unknown>;channels:number[][]};
}
export function createBoxRIR(options?: {backend?:'js'|'wasm-gc';jsModuleURL?:string|URL;wasmURL?:string|URL;wasmBytes?:BufferSource}): Promise<BoxRIR>;
