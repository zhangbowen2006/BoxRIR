# 在 MoonBit 工程中使用 BoxRIR

本例从 Mooncakes 安装 `zhangbowen2006/boxrir@0.4.1`，生成一个房间的双通道响应，将两帧干声卷积成模拟录音，再写入和读回 Float32 WAV 字节。使用已验证的 moon 0.1.20261021 / moonc 0.10.17+093cb8f9c 工具链。

在一个新的空文件夹中保存下面三个文件。库的安装由 `moon test` 自动解析依赖完成。

`moon.mod`

```moonbit
name = "boxrir_example/demo"

import {
  "zhangbowen2006/boxrir@0.4.1",
}
```

`moon.pkg`

```moonbit
import {
  "zhangbowen2006/boxrir" @boxrir,
  "zhangbowen2006/boxrir/io" @wav,
} for "test"
```

`quickstart_test.mbt`

```moonbit
///|
test "render a room and round-trip a stereo recording" {
  let room = @boxrir.scene(
    { x: 5.0, y: 4.0, z: 3.0 },
    { x: 1.0, y: 1.0, z: 1.0 },
    [{ x: 3.0, y: 1.0, z: 1.0 }, { x: 3.2, y: 1.0, z: 1.0 }],
    [0.2, 0.2, 0.2, 0.2, 0.2, 0.2],
    16000, 1, 100,
  ).unwrap()
  let response = @boxrir.render(room)
  assert_eq(response.channel_count(), 2)
  assert_eq(response.channel(0).unwrap().length(), 1632)

  let recording = @boxrir.convolve(response, [1.0, 0.5]).unwrap()
  assert_eq(recording.frames(), 1633)
  assert_eq(recording.latency_samples, 16)

  let encoded = @wav.write_float32(
    [recording.channel(0).unwrap(), recording.channel(1).unwrap()],
    recording.sample_rate,
  ).unwrap()
  let decoded = @wav.read_multichannel(encoded).unwrap()
  assert_eq(decoded.sample_rate, 16000)
  assert_eq(decoded.channels.length(), 2)
  assert_eq(decoded.channels[0].length(), 1633)
}
```

在该文件夹运行以下命令。

```sh
moon test --target js --deny-warn
moon test --target wasm --deny-warn
moon test --target wasm-gc --deny-warn
```

三个命令应各显示 `Total tests: 1, passed: 1, failed: 0.`。WAV 在本例中以字节传递，便于嵌入调用者自己的文件或网络接口。需要直接保存 WAV 时可使用[文件 CLI](https://github.com/zhangbowen2006/BoxRIR/blob/main/docs/EXPERIMENTS.md)。

房间尺寸单位为米，采样率为 Hz，干声为线性幅度。`scene` 参数按房间、声源、接收点、六墙能量吸声、采样率、总反射阶数和响应窗毫秒传入。本例每通道 1,632 帧响应包括共同 16 帧滤波延迟和核尾部。两帧干声卷积得到 1,633 帧，两个接收点保留各自的幅度和到达时间。

该用例同时由本仓库的本地源码包与注册表安装脚本逐字执行。[安装验证脚本](https://github.com/zhangbowen2006/BoxRIR/blob/main/scripts/test-registry-package.py) · [接口签名](https://github.com/zhangbowen2006/BoxRIR/blob/main/pkg.generated.mbti)
