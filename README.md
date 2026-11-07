# BoxRIR

[![CI](https://github.com/zhangbowen2006/BoxRIR/actions/workflows/ci.yml/badge.svg)](https://github.com/zhangbowen2006/BoxRIR/actions/workflows/ci.yml)

**用 MoonBit 在本地生成房间脉冲响应和多通道模拟录音。** 提供 MoonBit 库、Node CLI、JS/TypeScript SDK 和浏览器 Wasm GC 工作台，生产计算无需 Python、C++ 绑定或声学服务。

[在线工作台](https://zhangbowen2006.github.io/BoxRIR/) · [GitHub 与运行包](https://github.com/zhangbowen2006/BoxRIR/releases) · [运行包说明](docs/RUNTIME.md) · [0.2.0 发布检查](docs/RELEASE-0.2.0.md) · [来源与许可](NOTICE)

本源码版本为 **0.2.0**。Mooncakes 已有版本为 [0.1.1](https://mooncakes.io/docs/zhangbowen2006/boxrir@0.1.1)，不包含本轮扩展；0.2.0 注册表发布状态以实际版本页面为准。

## 三种明确的模型

| 模式 | 能力与输入约定 | 时间轴 |
|---|---|---|
| `audiolabs_v030` | 移植 AudioLabs RIR Generator 0.3.0 数值核；五种麦克风指向性、方位/俯仰、六墙有符号压力反射系数或 T60、二维/三维反射、有限阶/窗口内镜像、可选 100Hz 高通 | 上游 8ms Hann-sinc，固定 `nsample`，无额外延迟；默认长度规则保留上游行为 |
| 原矩形模型 | 全向点源/接收点，六墙能量吸声、有限总反射阶数、归一化 Hann-sinc | 保留到达时间窗，加共同 `half_width` 延迟及完整核尾部 |
| 凸多边形柱体 | 3–8 个逆时针严格凸顶点，0–4 阶；逐有限墙面回溯，导出墙序列与命中点 | 与原模型相同；排除棱边、顶点及擦边退化路径 |

所有模式保持通道间时差和原始线性模型增益，输出 Float32 WAV。**压力反射 `beta` 与能量吸声 `absorption` 不能混填，两套滤波/时间轴不能互换。** 这不是新物理算法，也不是整个 pyroomacoustics 的移植。[数值兼容范围](docs/AUDIOLABS-COMPATIBILITY.md) · [原模型与几何约定](docs/MODEL.md)。

## 直接使用运行包

从 GitHub Releases 下载并解压运行包，使用 Node.js 24 或以上版本；不需要 `npm install`、MoonBit 或 Python：

```sh
node bin/boxrir.mjs --version
node bin/boxrir.mjs rir examples/stereo.json output-stereo
node bin/boxrir.mjs simulate examples/triangle.json examples/probe.wav output-triangle
node bin/boxrir.mjs --backend wasm-gc simulate examples/reference-cardioid.json examples/probe.wav output-cardioid
```

输出目录必须不存在。成功目录包含 `rir.wav`、`report.json`、`paths.csv`、`response.svg`、原始 `scene.json` 和完成清单 `run-manifest.json`；simulate 另含 `wet.wav` 及输入快照 `source.wav`。清单记录输入、核心二进制与各输出的 SHA-256。仅在清单存在且 `.boxrir-incomplete` 不存在时消费结果。普通写入失败会回滚本次创建的文件；停电后的不完整目录须保留标记并换新目录重试。已有目录不覆盖，并发进程不能混写。输入/计算/写入错误退出码为 2。

```js
import {createBoxRIR} from './sdk/client.mjs';
import fs from 'node:fs';
const engine = await createBoxRIR();
const scene = JSON.parse(fs.readFileSync('examples/reference-cardioid.json', 'utf8'));
const result = engine.render(scene, {dryWav: fs.readFileSync('examples/probe.wav')});
fs.writeFileSync('my-rir.wav', result.rirWav);
```

SDK 带 `.d.mts` 类型声明。浏览器可通过 HTTP(S) 加载整个 `sdk` 目录并选择 `backend:'wasm-gc'`；需要 Wasm GC/JS string builtins，不支持时明确报错。Node 的 Wasm 后端传入 `wasmBytes`。初始化后计算同步执行，交互界面应放到 Worker，取消时终止 Worker。没有静默切换后端。

## 从源码开发

验证工具链为 moon 0.1.20261021 / moonc 0.10.17+093cb8f9c，Node.js 24.22.1。CI 固定该 MoonBit 编译器：

```sh
moon update
moon check --target all --deny-warn
moon test --target js --deny-warn
moon test --target wasm --deny-warn
moon test --target wasm-gc --deny-warn
node scripts/build-sdk.mjs
node --test tests/*.test.mjs
node scripts/build-demo.mjs
node scripts/serve-demo.mjs
```

浏览器打开 `http://127.0.0.1:4177`。上传匹配采样率的单声道 WAV 或使用合成扫频；计算和文件都留在浏览器内。切换场景、修改参数或替换声源会清除旧结果，避免下载过期音频。试听增益对所有通道统一调整，下载不应用该增益。浏览器可能下混多通道播放，以下载文件为准。

```sh
node scripts/build-release.mjs
node scripts/test-distribution.mjs
moon package
python scripts/test-moon-package.py
```

构建产物分别位于 `_build/sdk`、`_build/demo`、`_build/distribution`。运行包包含全部许可和 `SHA256SUMS.json`，编译来源在 `sdk/build-info.json`。Mooncakes 本地归档用独立消费工程验证，不等于已经发布到注册表。

## 可运行的完整场景

| 使用者与问题 | 输入与操作 | 输出及验证 |
|---|---|---|
| 浏览器音频工具开发者需要无需 Python 服务的双通道响应 | `stereo.json` 执行 `rir`，或在工作台生成 | 两通道 4032 帧；直接声到达约 7.658/8.090ms，每通道 377 条保留路径。独立镜像参考、延迟和增益测试 |
| 语音/阵列算法开发者需要带方向性差异的可复现模拟录音 | `reference-cardioid.json` + `probe.wav` 执行 `simulate` | 两通道 2048 帧 RIR、18047 帧录音，无额外延迟；原版 AudioLabs C++ 波形和 SciPy 卷积逐样本对照 |
| 声学原型与教学开发者需要非矩形房间反射 | `triangle.json`、`trapezoid.json`、`pentagon.json` 执行 `simulate` | 两通道 WAV、有限面有效路径和卷积尾部；pyroomacoustics 几何/可见性对照，命中点、反射定律和物理路径长度验证 |
| 教学人员对比单墙吸声变化 | `wall-before.json` 与 `wall-after.json` 只改变 x 低墙吸声 | 该墙一阶压力增益变成 1/3，到达时间及其他一阶反射不变；独立公式与输出文件核对 |

这些是可运行的合成使用场景，没有外部客户采用或真实房间校准证据。`examples/probe.wav` 是自制扫频，不是测量录音。

## 接口与资源边界

MoonBit 核心公开 `scene`、`prism_scene`、`trace`、`trace_prism`、`render`、`audiolabs_rir`、`Audio::convolve`；IO 独立。完整签名见 [核心接口](pkg.generated.mbti)、[JSON API](api/pkg.generated.mbti)、[WAV IO](io/pkg.generated.mbti)。

- 一个全向点源、1–8 接收点；长度 0.1–1000m，声速 100–1000m/s，严格内部点、源与各接收点距离至少 0.01m。
- 8–96kHz，最多 100 万 RIR 采样。原模型窗口 1–2000ms、阶数 0–12、核半宽 4–32；凸柱体阶数最多 4。
- AudioLabs 模式 `nsample` 1–192000，阶数 -1..12；最多 200 万候选组合、6400 万插值 tap。`-1` 表示时间窗枚举，仍受资源限制。
- WAV 输入最多 4MiB、262144 帧、单声道，必须同采样率；拒绝 NaN/Inf 和超过 10⁶ 的样本。没有隐式重采样、下混、限幅或峰值归一化。
- 卷积输出每通道最多 262144 帧、合计 200 万采样，保留完整线性卷积尾部。AudioLabs 路径报告上限一万条，截断时显式标记，波形仍包含所有计算贡献。
- 场景 JSON 最多 65536 字符，拒绝未知字段、重复键、错误整数形式及越界几何。

这是离线/批处理计算库，不承诺实时音频回调。一次 Windows/Node 压力测量中，八通道 96kHz、96000 帧 RIR 加 65536 帧输入，Wasm GC 总进程峰值约 478MiB，JS 约 588MiB；普通示例更低，但采样数限制不是通用内存保证。完整测量与环境见 [发布检查](docs/RELEASE-0.2.0.md)，可运行 `node scripts/benchmark-runtime.mjs` 复测。

不实现障碍物、绕射、散射、空气吸收、频率相关材料、移动声源、任意多面体或 HRTF。有限阶与有限窗口不能保证真实 RT60；需要这些物理机制时应采用相应完整模拟器。

## 数值与交付验证

- 24 组 MoonBit 测试：三个本地后端实际通过；Linux CI 另执行 Native。
- 24 组 Node 测试：SDK、CLI、并发、磁盘写入失败、WAV 异常和数值差分。
- AudioLabs 原版二进制生成 103 组、155130 个 Float64 样本，三个后端最大绝对误差 2.665×10⁻¹⁵；不对齐、不归一化、不拟合增益。含 64 组预先指定的随机场景。
- pyroomacoustics：原矩形 32 场景/2330 镜像，凸柱体 20 场景/1687 有效路径；独立六墙 BFS 为 5 场景/225 镜像。几何对照与完整波形对照明确区分。
- Edge 实际 Wasm GC 工作台：六个场景、音频解码、下载、取消后重启、结果失效和手机布局通过。
- 独立运行包与 Mooncakes 本地归档均通过独立消费验证；后者没有冒充注册表安装成功。

[完整工程记录](docs/RELEASE-0.2.0.md) · [结构化证据](docs/evidence/0.2.0.json) · [参考再生成方法](tests/reference/README.md)。Native 的 Linux 结果以对应提交的 CI 为准；本机未安装 MSVC/Windows SDK，不声称完成 Windows Native 运行。

## 来源与许可证

AudioLabs 模式实际移植自 [rir-generator v0.3.0](https://github.com/audiolabs/rir-generator/tree/v0.3.0)，固定 commit `052790faade19074c6921e007fb8972c60e8f0a6`，保留 core/wrapper 两份 MIT 声明。原渲染器和凸几何扩展独立组织实现，不将移植、依赖或生成的参考数据计为原创算法。[来源清单](docs/PROVENANCE.md)。

FFT/IFFT 复用 `chgttyyr/MoonSpectrum@0.2.2`（Apache-2.0），本项目组织共享声源频谱的多通道卷积；WAV 解码复用 `Ridge-Lab/moonwavkit@0.1.3`（MIT），另实现保留增益的窄范围 Float32 写出。BoxRIR 不依赖其他本人参赛项目。代码、测试和文档有 AI 辅助。

项目采用 Apache-2.0；发布时须同时保留 [NOTICE](NOTICE) 及 [第三方许可](docs/licenses)。
