# BoxRIR 0.3.0 runtime

This standalone bundle needs Node.js 24 or later; it does not need MoonBit,
Python, npm install or a native compiler. The core is compiled from MoonBit.

```sh
node bin/boxrir.mjs --version
node bin/boxrir.mjs simulate examples/spectral-before.json examples/probe.wav output-spectral
node bin/boxrir.mjs rir examples/stereo.json output-stereo
node bin/boxrir.mjs simulate examples/triangle.json examples/probe.wav output-triangle
node bin/boxrir.mjs --backend wasm-gc simulate examples/reference-cardioid.json examples/probe.wav output-cardioid
```

Output directories must be new. Each successful run includes the input scene
and source WAV (if used), WAV outputs, path CSV, JSON report, SVG, and a
`run-manifest.json` binding inputs, engine and outputs with SHA-256 hashes.
Treat a directory as complete only when the manifest exists and
`.boxrir-incomplete` is absent. On ordinary write failures, files created by
the invocation are rolled back. Power loss cannot be made transactional across
filesystems: keep the incomplete marker and retry into a new directory.

```js
import {createBoxRIR} from './sdk/client.mjs';
import fs from 'node:fs';
const engine=await createBoxRIR(); // explicit JS backend by default
const scene=JSON.parse(fs.readFileSync('examples/reference-cardioid.json','utf8'));
const {rirWav,wetWav,report}=engine.render(scene,{dryWav:fs.readFileSync('examples/probe.wav')});
fs.writeFileSync('my-rir.wav',rirWav);
```

For Node Wasm: pass `backend:'wasm-gc'` and `wasmBytes:fs.readFileSync('sdk/boxrir.wasm')`.
For browsers: serve the entire `sdk` directory over HTTP(S), then call
`createBoxRIR({backend:'wasm-gc'})`. Wasm GC and JS string builtins are required.
Unsupported engines fail explicitly; no silent backend fallback occurs.
Render is synchronous after initialization: use a Web Worker for interactive
applications and terminate that worker to cancel. Type declarations accompany
the SDK. `inspect` exposes geometry; `referenceSamples` returns Float64 arrays
for numerical work. `render` returns Float32 WAV bytes with model amplitudes.

Four separate contracts: octave_bands adds path-specific six-band materials and atmospheric loss with sample-rate-scaled complementary FIR synthesis (see SPECTRAL.md).  legacy shoebox uses normalized Hann-sinc with common
kernel latency; convex prisms add finite-face visibility; `audiolabs_v030` ports
AudioLabs RIR Generator v0.3.0 with signed pressure coefficients, five receiver
patterns, 2D/3D reflections, 8ms interpolation and optional 100Hz high-pass.
It preserves the upstream sample window and adds no latency. Do not interchange
pressure `beta` with energy `absorption` or claim measured-room accuracy.

Resource limits are enforced, rather than advertised as arbitrary room sizes:
one source, 1–8 receivers, 8–96kHz, <=1M RIR samples, <=2M convolution samples,
<=262144 output frames/channel, <=4MiB mono input, matching sample rate. Reference
mode accepts 1–192000 frames, order -1..12, <=2M candidate images and <=64M
interpolation operations; diagnostics cap at 10000 paths (waveforms are not
truncated by that reporting cap). Convex prisms require 3–8 strictly convex
counterclockwise vertices, order 0..4 and no edge/corner-degenerate paths.
Unknown fields, duplicate keys, invalid geometry, NaN/Inf audio and unsupported
formats fail. No implicit resampling, downmix, limiting or peak normalization.

This package does not implement obstacles, diffraction, scattering, arbitrary
polyhedra, moving geometry or continuously frequency-dependent materials.
Use a full acoustic simulator when those are required. The synthetic probe is
a reproducibility input, not a real-room measurement or adoption claim.

Retain `LICENSE`, `NOTICE` and `licenses/` when distributing. BoxRIR is Apache-2.0; atmospheric equations retain BSD-3-Clause terms;
the AudioLabs numerical port and MoonWavKit carry MIT notices. `SHA256SUMS.json`
binds the packaged files; `sdk/build-info.json` records source provenance.
