# 录音与响应实验

BoxRIR 0.4.0 提供共享场景的多声源录音、探针、宽带衰减分析、传递响应估计、响应比较和显式重采样。独立运行包使用 Node.js 24。源码用户先执行 `node scripts/build-sdk.mjs`。[运行包](https://github.com/zhangbowen2006/BoxRIR/releases)

## 双声源与双麦克风录音

```sh
node bin/boxrir.mjs probe examples/probe-foreground.json probe-a
node bin/boxrir.mjs probe examples/probe-background.json probe-b
node bin/boxrir.mjs --backend wasm-gc mix examples/mixed-recording.json mix-out probe-a/probe.wav probe-b/probe.wav
node bin/boxrir.mjs verify mix-out
```

用两路输入在不同位置和帧起点合成同一对接收点的录音。CLI 示例为 16 kHz、2 通道、15,631 帧。`probe-*.wav` 由探针命令生成，`mix-out/track-1.wav` 和 `track-2.wav` 是输入快照。`report.json` 记录每轨起始帧、线性增益、路径数量、响应长度和尾部位置。第二轨在 4,000 帧处进入。混音在共享时间轴上依次应用各轨卷积，保留整段尾部及原始线性幅度。[浏览器多声源入口](https://zhangbowen2006.github.io/BoxRIR/mix.html)

浏览器的内置探针长度与上述 CLI 配置不同，16 kHz 默认输出为双通道 17,631 帧。浏览器可替换各轨单声道 WAV，采样率应和场景相同。单声源页面根据当前设置生成默认信号，已在 48 kHz 下验证。录制文件导出保留原采样，试听可能经浏览器下混或播放增益调整。[工作台](https://zhangbowen2006.github.io/BoxRIR/)

## 从响应读取宽带衰减

```sh
node bin/boxrir.mjs rir examples/spectral-before.json before-rir
node bin/boxrir.mjs analyze before-rir/rir.wav before-analysis
node bin/boxrir.mjs verify before-analysis
```

`before-analysis/report.json` 逐通道给出反向能量曲线、EDT、T20、T30、C50/C80、D50 和中心时间。默认起点为分析窗内最早达到该通道峰值幅度 1% 的帧，可通过 `onset_frames` 显式指定。可用 `end_exclusive` 截取尾部，或用 `curve_points` 限制输出点数。拟合需要对应的衰减范围、至少 8 个点、5 ms 的拟合区间以及 R² ≥ 0.9。静音、动态范围不足和偏弱拟合都有单独的状态；使用时检查 `status`。有限响应窗、背景噪声和时零选择会影响数值。当前报告按宽带计算，现场测量规范与分频分析仍需另行验证。[pyroomacoustics 的 Schroeder 方法说明](https://pyroomacoustics.readthedocs.io/en/stable/pyroomacoustics.experimental.rt60.html)

## 将探针录音估计为响应并比较

```sh
node bin/boxrir.mjs estimate probe.wav recorded.wav estimate-options.json estimated
node bin/boxrir.mjs compare reference.wav estimated/estimated-rir.wav compare-options.json compared
node bin/boxrir.mjs verify estimated
```

`estimate-options.json` 可用 `{"response_frames":1024,"regularization_db":-80}`。传递响应估计以 `Y × conj(X) / (|X|² + λ)` 计算，要求已知的单声道探针与多声道录音同采样率、同时间起点，录音窗口足够长。报告给出频谱中达到可靠阈值的频点数，以及窗外能量、重建误差比例。声卡往返延迟、双设备时钟漂移、削波及缺失频段会影响估计；提供真实 WAV 时由操作者确认这些前提。

`compare-options.json` 可用 `{"frames":1024,"lag_radius":0}` 逐声道对照同格式的两个响应。可另提供 `reference_starts` 和 `observed_starts`，以及小范围整数 `lag_radius`。有对齐搜索时保留原起点、选中的位移和比较后的样本误差。增益拟合前后的误差值同时保留，便于识别幅度变化。若两路采样率不同，先显式转换。

```sh
node bin/boxrir.mjs resample input-48k.wav 16000 resampled
```

`resampled/resampled.wav` 保留声道顺序，输出帧数为 `ceil(输入帧数 × 输出采样率 / 输入采样率)`。采用 Blackman 窗化 sinc 低通和常量边界延拓，支持 8–96 kHz。用于离线准备输入和分析，支持的采样率与文件大小受接口预算限制。

`verify` 校验完成清单中列出的文件长度和 SHA-256，并检查不完整标记。需要追溯文件来源时，应从自己认可的运行目录或独立发布校验和开始。

## 独立数值验证

从仓库根目录在 Python 环境安装 NumPy 和 SciPy，构建 SDK 后运行以下命令。脚本在新目录生成合成输入，调用生产 CLI，使用 SciPy 读取 WAV 并独立计算参考结果。

```sh
node scripts/build-sdk.mjs
python scripts/verify-experiments.py
```

| 实验 | Windows 本地 JS 与 Wasm GC 实测 |
|---|---|
| 双声源叠加 | 2 通道、15,631 帧。用分别导出的每轨 RIR 做独立卷积与叠加，最大绝对差约 5.45×10⁻⁹。 |
| 已知响应反推 | 两个 1,024 帧的已知响应，最大绝对差约 2.22×10⁻⁸。 |
| 衰减拟合 | 目标 0.42 s 的合成衰减，T30 返回约 0.42000000006 s。 |
| 重采样 | 48→16 kHz，1 kHz 信号的稳态最大误差约 7.15×10⁻⁸，12 kHz 信号的稳态峰值约 2.66×10⁻⁷。两项均去掉两端各 100 帧。 |

上述数值只支持在列出的输入和容差下复现结果。物理房间、设备和材料参数的校准仍待取得数据。可复现的参考与许可见[来源说明](https://github.com/zhangbowen2006/BoxRIR/blob/main/docs/PROVENANCE.md)。
