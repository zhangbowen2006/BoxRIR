# Independent image-source fixtures

These are synthetic development fixtures, not measured rooms or claimed user deployments. They do not require Python at production runtime.

## Upstream comparison

`generate_pyroomacoustics.py` requires **pyroomacoustics 0.10.1** (MIT) and verifies the installed version. It calls public APIs to construct 3D `ShoeBox` rooms, then reads the source's image coordinates, total reflection orders and pressure damping. It does not reproduce BoxRIR's closed-form image enumeration.

The fixed seed is `20261031`. There are six half-integer geometry baselines at orders 0 through 5, two extreme-absorption baselines, and 24 seeded asymmetric rooms with distinct wall absorptions and orders 0 through 5. Source and receiver positions are strictly inside the rooms. Data includes zero-pressure images from perfectly absorbing walls, so a production implementation that prunes zero paths must compare the complete geometry before pruning or account for the documented difference.

Wall mapping is checked at generation time:

| Scene slot | pyroomacoustics material name |
|---|---|
| xlow / xhigh | west / east |
| ylow / yhigh | south / north |
| zlow / zhigh | floor / ceiling |

Upstream images and damping are **float32**. Compare each sorted image coordinate with `atol=2e-5, rtol=2e-7` and pressure reflection with `atol=1e-7, rtol=2e-6`; orders and image cardinalities must match exactly. Sort by `(order, image.x, image.y, image.z)`. These tolerances allow upstream single-precision rounding, not different wall semantics. Actual reference and NumPy versions are recorded in the JSON.

No sampled waveform equality is asserted: the FIR kernel and global latency conventions are separate from the geometric image model. The fixtures do not certify real-room accuracy, diffraction, scattering, material frequency response or RT60.

Sources: [pyroomacoustics](https://github.com/LCAV/pyroomacoustics), [official room simulation documentation](https://pyroomacoustics.readthedocs.io/en/pypi-release/pyroomacoustics.room.html), [upstream MIT license](https://github.com/LCAV/pyroomacoustics/blob/master/LICENSE).

## Independent wall-count oracle

`generate_bfs.py` uses only Python's standard library. It begins at one half-integer source position, repeatedly reflects the coordinates across each fixed wall plane, and uses breadth-first search to retain shortest reflection words. It tracks the six wall counts along the words. It never uses the image-index expression or `abs(n-p)` count expression from the planned implementation.

Orders 0 through 4 produce 1, 7, 25, 63 and 129 images. The resulting fixtures include exact half-integer coordinates and six integer bounce counts. They can therefore be compared exactly, without a floating-point tolerance.

## Regenerate

```sh
python -m pip install pyroomacoustics==0.10.1
python tests/reference/generate_pyroomacoustics.py
python tests/reference/generate_bfs.py
```

On the current development machine the dependency is isolated under `D:\CodexProjects\.tools\boxrir-reference`; set `PYTHONPATH` to that directory when using the bundled Python interpreter. Regeneration changes only files in this directory. Successful regeneration is not evidence that the MoonBit implementation has passed a comparison; the consuming tests must actually run.

Generation verified on 2026-10-31 with pyroomacoustics 0.10.1 and NumPy 2.5.4: 32 upstream cases / 2,330 images, and five BFS cases / 225 images. A second regeneration produced identical bytes. The six distinct first-order pressure reflections were also checked against the explicit west/east/south/north/floor/ceiling baseline values 0.9/0.8/0.7/0.6/0.5/0.4.

Recorded fixture SHA256 values for this generation:

- `pyroomacoustics-0.10.1.json`: `4805c9beb0b5e26e4d6df5f0ec04ef21fd5a3b018f23998a749b52dd82b7e802`
- `bfs-images.json`: `1b6ea09776f357cf84f89f4a5c3234c4ea5b15d02a301d4164b37a023d4d88e5`
