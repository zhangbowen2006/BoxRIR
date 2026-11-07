# Model contract

This document describes the original BoxRIR renderer. The convex-prism extension
is documented below. The separately selected AudioLabs numerical
profile has different pressure coefficients, interpolation and time-window
semantics; see AUDIOLABS-COMPATIBILITY.md. Do not transfer normalization or
latency assumptions between the modes.

The first release implements an omnidirectional point source and 1..8 point
receivers strictly inside a 3D rectangular room, constant sound speed,
frequency-independent energy absorption on six specular walls, and finite
total reflection order. It does not model diffraction, scattering, obstacles,
frequency-dependent materials, air attenuation or sound level calibration.

Wall order: x-low, x-high, y-low, y-high, z-low, z-high. Coordinates are metres;
absorption alpha is energy loss, so the pressure reflection coefficient is
sqrt(1-alpha). Axis image coordinate is (1-2p)*source + 2*n*room, p in {0,1}.
The low/high wall counts are abs(n-p) and abs(n). Total order is the sum of all
six counts. Pressure gain is product(beta^count)/(4*pi*distance).

All channels share the same physical timeline. A finite, normalized windowed
sinc delay filter contributes the same half-width latency to every channel.
duration_ms determines ceil(fs*duration_ms/1000) physical frames; only paths
arriving before this boundary are retained. Output has an additional 2*half_width
frames, ensuring every retained path has its complete kernel. No truncated
kernel is renormalized. Report omitted late paths and latency explicitly.

No per-channel peak normalization. Different images with identical arrival
times add coherently. Order/time truncation is not an RT60 guarantee.

Bounds: dimensions 0.1..1000 m, speed 100..1000 m/s, source-receiver separation
at least 0.01 m, sample rate 8000..96000 Hz, duration 1..2000 integer ms,
order 0..12, sinc half-width 4..32, at most 1,000,000 total RIR samples.

## Convex prism contract

`prism_scene` accepts 3..8 strictly convex counterclockwise floor vertices with
no repeated closing vertex, each edge >=0.1m and coordinates in 0..1000m.
Height is 0.1..1000m; source and receivers must lie strictly inside every plane.
Wall absorption slots follow polygon edges, then floor, then ceiling. Order is
0..4; at most 8201 reflection words are enumerated for eight vertices.

Every reflected source retains its wall sequence and image history. Backtrace
from each receiver to those successive images and intersect each finite face.
Reject intersections outside the face or on another face, collinear/grazing
segments and edge/corner hits (geometry epsilon 1e-7m). These degenerate paths
are excluded, rather than counted as multiple reflections with ambiguous normals.
For a convex room, segments connecting valid face hits remain inside the room.
`trace_prism` exports ordered wall indices and physical hit points. Unfolded
image distance equals total segment length; test reflection angles separately.

Waveform generation uses the original normalized kernel and latency contract.
This extension does not introduce concave rooms, obstacles or arbitrary 3D
polyhedra. Upstream geometry/visibility comparisons are not waveform equivalence
claims because their interpolation kernels differ.
