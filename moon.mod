// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "zhangbowen2006/boxrir"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/zhangbowen2006/BoxRIR"

license = "Apache-2.0"

keywords = [ "acoustics", "image-source", "rir", "simulation" ]

preferred_target = "wasm"

description = "Finite-order shoebox propagation, multichannel room impulse responses and recording simulation in MoonBit"

import {
  "chgttyyr/MoonSpectrum@0.2.2",
  "Ridge-Lab/moonwavkit@0.1.3",
}
