# Model contract

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
