///|
/// Deterministic excitation waveforms for offline recording and experiments.
/// Frequencies are in Hz and every duration is measured in samples.
pub(all) enum Excitation {
  Impulse
  Sine(Double)
  LogSweep(Double, Double)
  WhiteNoise(UInt32)
}

///|
pub(all) struct ProbeSpec {
  sample_rate : Int32
  active_frames : Int32
  lead_frames : Int32
  tail_frames : Int32
  fade_frames : Int32
  amplitude : Double
  excitation : Excitation
}

///|
fn valid_audio_rate(sample_rate : Int32) -> Bool {
  sample_rate >= 8000 && sample_rate <= 96000
}

///|
fn valid_tone_frequency(frequency : Double, sample_rate : Int32) -> Bool {
  frequency >= 10.0 && frequency <= 0.45 * sample_rate.to_double()
}

///|
fn probe_envelope(index : Int32, active : Int32, fade : Int32) -> Double {
  if fade == 0 {
    return 1.0
  }
  let from_edge = index.min(active - 1 - index)
  if from_edge >= fade {
    1.0
  } else {
    0.5 * (1.0 - @math.cos(PI * from_edge.to_double() / fade.to_double()))
  }
}

///|
fn next_noise_state(seed : UInt32) -> UInt32 {
  let shifted = seed ^ (seed << 13)
  let shifted = shifted ^ (shifted >> 17)
  shifted ^ (shifted << 5)
}

///|
/// The active sequence starts after lead_frames. Sine/sweep phase starts at
/// zero; the sweep frequency reaches its endpoint one sample beyond the
/// active interval. A raised cosine taper applies only to the active edges.
pub fn generate_probe(spec : ProbeSpec) -> Result[Audio, String] {
  let rate = spec.sample_rate
  let active = spec.active_frames
  let lead = spec.lead_frames
  let tail = spec.tail_frames
  let fade = spec.fade_frames
  let full = active.to_int64() + lead.to_int64() + tail.to_int64()
  if !valid_audio_rate(rate) ||
    active < 1 ||
    lead < 0 ||
    tail < 0 ||
    full > 262144L ||
    fade < 0 ||
    fade > (active - 1) / 2 ||
    !(spec.amplitude > 0.0 && spec.amplitude <= 1.0) {
    return Err("invalid probe rate, frame budget, taper or amplitude")
  }
  let mut noise = 0U
  let mut sweep_ratio = 0.0
  let mut sweep_scale = 0.0
  match spec.excitation {
    Impulse =>
      if active != 1 {
        return Err("an impulse has exactly one active frame")
      }
    Sine(hz) =>
      if !valid_tone_frequency(hz, rate) || active < 4 {
        return Err("invalid sine frequency or active duration")
      }
    LogSweep(start, end) => {
      if !valid_tone_frequency(start, rate) ||
        !valid_tone_frequency(end, rate) ||
        end < 1.01 * start ||
        active < 32 {
        return Err("sweep frequencies must increase within 10 Hz..0.45*rate")
      }
      sweep_ratio = @math.ln(end / start)
      sweep_scale = 2.0 *
        PI *
        start *
        active.to_double() /
        (rate.to_double() * sweep_ratio)
    }
    WhiteNoise(seed) => {
      if seed == 0U {
        return Err("white-noise seed must be nonzero")
      }
      noise = seed
    }
  }
  let samples = Array::make(full.to_int(), 0.0)
  let inverse_rate = 1.0 / rate.to_double()
  for i in 0..<active {
    let value = match spec.excitation {
      Impulse => 1.0
      Sine(hz) => @math.sin(2.0 * PI * hz * i.to_double() * inverse_rate)
      LogSweep(_, _) => {
        let progress = i.to_double() / active.to_double()
        @math.sin(sweep_scale * (@math.exp(sweep_ratio * progress) - 1.0))
      }
      WhiteNoise(_) => {
        noise = next_noise_state(noise)
        // The 24-bit fraction is exactly representable on each target.
        (noise >> 8).to_double() / 8388608.0 - 1.0
      }
    }
    samples[lead + i] = spec.amplitude * probe_envelope(i, active, fade) * value
  }
  Ok({ samples: [samples], sample_rate: rate, latency_samples: 0, })
}

///|
/// One-second reference sweep for the local workbench. Its upper frequency is
/// constrained by the selected sample rate so a new scene doesn't need a file.
pub fn default_probe(sample_rate : Int32) -> Result[Audio, String] {
  if !valid_audio_rate(sample_rate) {
    return Err("probe sample rate must be 8000..96000")
  }
  let high_hz = (0.4 * sample_rate.to_double()).min(7200.0)
  generate_probe({
    sample_rate,
    active_frames: sample_rate,
    lead_frames: 0,
    tail_frames: 0,
    fade_frames: sample_rate / 100,
    amplitude: 0.7,
    excitation: LogSweep(60.0, high_hz),
  })
}
