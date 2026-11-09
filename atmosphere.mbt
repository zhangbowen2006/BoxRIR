// Formula port/adaptation from Python Acoustics, commit
// 99d79206159b822ea2f4e9d27c8b2fbfeb704d38, BSD-3-Clause.
// Copyright (c) 2013, Python Acoustics; full notice in docs/licenses/.

///|
/// ISO 9613-1 equation profile for the six octave centres, in dB/metre.
/// RH is a PERCENTAGE (50 means 50%), not a fraction; temperature is Celsius,
/// pressure kPa. No certification or measured-room accuracy is implied.
pub fn atmospheric_air_loss(
  temperature_c : Double,
  relative_humidity_percent : Double,
  pressure_kpa~ : Double = 101.325,
) -> Result[Array[Double], String] {
  if !(temperature_c >= -20.0 &&
    temperature_c <= 50.0 &&
    relative_humidity_percent >= 10.0 &&
    relative_humidity_percent <= 100.0 &&
    pressure_kpa >= 80.0 &&
    pressure_kpa <= 110.0) {
    return Err("atmosphere needs -20..50 C, 10..100 percent RH, 80..110 kPa")
  }
  let temperature = temperature_c + 273.15
  let ratio = temperature / 293.15
  let pressure = pressure_kpa / 101.325
  let saturated = 101.325 *
    @math.pow(10.0, -6.8346 * @math.pow(273.16 / temperature, 1.261) + 4.6151)
  // h is percentage molar concentration. Passing fractional RH here changes
  // the relaxation frequencies by orders of magnitude; keep the unit explicit.
  let h = relative_humidity_percent * saturated / pressure_kpa
  let oxygen = pressure * (24.0 + 40400.0 * h * (0.02 + h) / (0.391 + h))
  let nitrogen = pressure *
    @math.pow(ratio, -0.5) *
    (9.0 + 280.0 * h * @math.exp(-4.170 * (@math.pow(ratio, -1.0 / 3.0) - 1.0)))
  Ok(
    octave_centers().map(fn(frequency) {
      let square = frequency * frequency
      8.686 *
      square *
      (
        1.84e-11 / pressure * ratio.sqrt() +
        @math.pow(ratio, -2.5) *
        (
          0.01275 *
          @math.exp(-2239.1 / temperature) /
          (oxygen + square / oxygen) +
          0.1068 *
          @math.exp(-3352.0 / temperature) /
          (nitrogen + square / nitrogen)
        )
      )
    }),
  )
}
