///|
pub(all) struct TransferChannel {
  peak : Double
  outside_window_energy_fraction : Double?
  reconstruction_error_fraction : Double?
}

///|
/// A linear estimate of the sampled transfer from a known dry excitation to a
/// recorded signal. Diagnostics describe these inputs only.
pub struct TransferEstimate {
  audio : Audio
  transform_frames : Int32
  recording_frames : Int32
  probe_frames : Int32
  regularization_db : Double
  reliable_bins : Int32
  unique_bins : Int32
  channels : Array[TransferChannel]
}

///|
fn pad_spectrum(
  data : Array[Double],
  length : Int32,
) -> Result[Array[@spectrum.Complex], String] {
  let time = Array::make(length, @spectrum.Complex::zero())
  for i, value in data {
    time[i] = @spectrum.complex(re=value, im=0.0)
  }
  Ok(@spectrum.fft(time[:])) catch {
    _ => Err("transfer FFT failed")
  }
}

///|
fn bin_power(bin : @spectrum.Complex) -> Double {
  bin.re * bin.re + bin.im * bin.im
}

///|
fn transfer_reconstruction_error(
  estimate : Array[Double],
  source_fft : Array[@spectrum.Complex],
  observed_fft : Array[@spectrum.Complex],
) -> Result[Double?, String] {
  let restored = match pad_spectrum(estimate, source_fft.length()) {
    Ok(values) => values
    Err(reason) => return Err(reason)
  }
  let mut residual = 0.0
  let mut total = 0.0
  for index, measured in observed_fft {
    let predicted = restored[index].mul(source_fft[index])
    let re = predicted.re - measured.re
    let im = predicted.im - measured.im
    residual += re * re + im * im
    total += bin_power(measured)
  }
  Ok(if total > 0.0 { Some(residual / total) } else { None })
}

///|
fn transfer_channel(
  recording : Array[Double],
  source_fft : Array[@spectrum.Complex],
  regularization : Double,
  frames : Int32,
) -> Result[(Array[Double], TransferChannel), String] {
  let fft_len = source_fft.length()
  let observed_fft = match pad_spectrum(recording, fft_len) {
    Ok(values) => values
    Err(reason) => return Err(reason)
  }
  let response_fft = Array::makei(fft_len, fn(index) {
    let x = source_fft[index]
    let y = observed_fft[index]
    let divisor = bin_power(x) + regularization
    @spectrum.complex(
      re=(y.re * x.re + y.im * x.im) / divisor,
      im=(y.im * x.re - y.re * x.im) / divisor,
    )
  })
  let response = @spectrum.ifft(response_fft[:]) catch {
    _ => return Err("transfer inverse FFT failed")
  }
  let estimated = Array::make(frames, 0.0)
  let mut outside = 0.0
  let mut total = 0.0
  let mut peak = 0.0
  for i, value in response {
    let sample = value.re
    if !(sample >= -1.0e20 && sample <= 1.0e20) {
      return Err("estimated impulse response exceeds sample magnitude budget")
    }
    let energy = sample * sample
    total += energy
    if i < frames {
      estimated[i] = sample
      peak = peak.max(sample.abs())
    } else {
      outside += energy
    }
  }
  let reconstruction_error_fraction = match
    transfer_reconstruction_error(estimated, source_fft, observed_fft) {
    Ok(value) => value
    Err(reason) => return Err(reason)
  }
  Ok(
    (
      estimated,
      {
        peak,
        outside_window_energy_fraction: if total == 0.0 {
          None
        } else {
          Some(outside / total)
        },
        reconstruction_error_fraction,
      },
    ),
  )
}

///|
/// Frequency-domain Tikhonov estimate H = Y*conj(X)/(|X|²+lambda).
/// The recorded signal and probe must have a common origin and sample rate.
/// The recording must include probe_frames + response_frames - 1 samples.
/// The returned impulse starts at recording frame zero, including any delay.
pub fn estimate_transfer(
  probe : Array[Double],
  recording : Array[Array[Double]],
  sample_rate : Int32,
  response_frames : Int32,
  regularization_db~ : Double = -80.0,
) -> Result[TransferEstimate, String] {
  let recording_frames = match
    checked_audio_frames(recording, sample_rate, 262144, 2000000, 1.0e20) {
    Err(reason) => return Err(reason)
    Ok(frames) => frames
  }
  if probe.is_empty() ||
    !probe.all(v => v >= -1.0e6 && v <= 1.0e6) ||
    response_frames <= 0 ||
    response_frames > 131072 ||
    probe.length().to_int64() + response_frames.to_int64() - 1L >
    recording_frames.to_int64() ||
    !(regularization_db >= -140.0 && regularization_db <= -20.0) {
    return Err("invalid probe, regularization or insufficient recorded tail")
  }
  let fft_len = @spectrum.next_power_of_two(recording_frames) catch {
    _ => return Err("transfer FFT size selection failed")
  }
  if fft_len * recording.length() > 1048576 {
    return Err("transfer transform budget exceeded: 1048576 channel bins")
  }
  let source_fft = match pad_spectrum(probe, fft_len) {
    Ok(values) => values
    Err(reason) => return Err(reason)
  }
  let mut max_power = 0.0
  let unique_bins = fft_len / 2 + 1
  for i in 0..<unique_bins {
    max_power = max_power.max(bin_power(source_fft[i]))
  }
  if max_power < 1.0e-20 {
    return Err("excitation has no usable energy")
  }
  let regularization = max_power *
    @math.exp(@math.ln(10.0) * regularization_db / 10.0)
  let mut reliable_bins = 0
  for i in 0..<unique_bins {
    // At this threshold the regularized estimate preserves at least half of
    // the component's noiseless magnitude. It is not an SNR measurement.
    if bin_power(source_fft[i]) >= regularization {
      reliable_bins += 1
    }
  }
  let samples : Array[Array[Double]] = []
  let channels : Array[TransferChannel] = []
  for input in recording {
    match transfer_channel(input, source_fft, regularization, response_frames) {
      Err(reason) => return Err(reason)
      Ok((response, diagnostic)) => {
        samples.push(response)
        channels.push(diagnostic)
      }
    }
  }
  Ok({
    audio: { samples, sample_rate, latency_samples: 0, },
    transform_frames: fft_len,
    recording_frames,
    probe_frames: probe.length(),
    regularization_db,
    reliable_bins,
    unique_bins,
    channels,
  })
}
