# AudioLabs 数值兼容模式：能力、来源与证据

源码版本：0.2.0。此模式是有明确目标域的源码移植，不是“全新声学算法”，也没有整体移植 pyroomacoustics。原矩形和凸多边形渲染器仍是不同模式。发布与验证见 RELEASE-0.2.0.md。

## 为什么值得迁移

目标是让 MoonBit 应用、浏览器音频工具和 Wasm 工作流直接生成可重复的多通道 RIR，同一数值核编译为 JS/Wasm/Wasm GC，不需要部署 Python 声学计算服务或绑定 AudioLabs 的 C++ 库。已把原程序的完整波形作为独立对照，而不只比较镜像位置或几张图。

这证明目标平台上的数值行为和本地文件流程；尚无外部用户采用、真实房间测量或性能领先证据。是否足以复审仍由组委会判断。

## 固定上游与移植范围

- 上游：[audiolabs/rir-generator v0.3.0](https://github.com/audiolabs/rir-generator/tree/v0.3.0)，SHA：052790faade19074c6921e007fb8972c60e8f0a6。
- 核：src/rir_generator/_cffi/rir_generator_core.cpp，内部版本 2.2.20201022；默认参数处理来自同版本 Python wrapper。实际转写为 audiolabs.mbt，接口适配位于 api/audiolabs.mbt。
- 保留 core 与 wrapper 两份 MIT 声明，见 docs/licenses 和 NOTICE。上游源码哈希见 tests/reference/audiolabs-source-manifest.json。
- 没有移植 Python/CFFI 绑定、NumPy API、安装打包或绘图库。BoxRIR 增加类型化接口、明确资源预算、结构化错误、WAV/卷积/浏览器接入。

## 能力对照

| 上游数值参数/行为 | 当前实现与证据 |
| --- | --- |
| c、fs、L、s、多接收点 r | 支持；单位 m、m/s、Hz，API显式命名为 speed/sample_rate/room/source/receivers |
| 六墙压力反射 beta，平坦/3×2 数组 | 支持含负号与零的系数；不混淆能量吸声 alpha |
| reverberation_time 推导均匀反射系数 | 支持，过小到不可能实现的参数明确失败；不把输入 T60 当成实测混响时间 |
| 自动 nsample，或固定输出窗口 | 支持；匹配 v0.3.0 的默认长度规则，固定窗口严格输出 nsample 帧 |
| order=-1 或有限总反射阶数 | 支持；-1 表示时间窗范围内的镜像枚举，有限阶在目标域内最多 12 |
| 全向、双向、心形、亚心形、超心形 | 五种均支持；保留双向/超心形背瓣的负压力响应 |
| azimuth/elevation，弧度 | 支持默认、单角度和双角度；当前一次调用所有接收点共用模式和朝向，与该上游接口一致 |
| dim=2 / dim=3 | 支持上游语义：dim=2 关闭地板/天花板反射，仍保留输入 z 坐标的直达距离，不冒称任意二维房间模型 |
| 8ms Hann-sinc 分数延迟核 | 按原实现移植；不额外归一化；核的首尾按原输出窗口裁剪 |
| 可选 100Hz Allen–Berkley 高通滤波 | 支持，默认开启；每个接收通道独立初始状态 |
| 波形时间轴、线性增益、通道协调 | 兼容模式没有原渲染器的额外 half_width 延迟；不逐通道归一化、不拟合增益 |
| Python/NumPy 绑定与无限资源 | 不提供；使用 MoonBit 类型、JSON 适配及下列明确预算 |

## 核心技术路线

1. 验证几何和参数；beta 与 T60 二选一。先按上游规则计算默认长度，再处理 dim=2，保留运算顺序。
2. 用 c/fs 将长度变换为采样单位；根据时间窗确定每轴镜像索引范围。有限阶与全零反射轴可裁去无贡献项，但保留其余项的参考累加次序。
3. 每个镜像计算六墙压力反射乘积、到达采样位置和球面扩散增益。麦克风方向由接收点指向展开镜像，包含方位和俯仰，不只处理直接声方向。
4. 在同一采样索引累加原版 8ms Hann-sinc，再按通道执行原版高通递推；不移动波形以掩盖时序差异。
5. Float64 核结果可直接用于卷积；WAV 明确转换为 Float32。Python 仅产生参考和验证输出，生产链路不调用它。

## 目标域与已知差异

- 矩形房间尺寸 0.1–1000m，声速 100–1000m/s，严格内部声源/接收点、间距至少 0.01m；1–8 接收点。上游允许的边界/奇异位置不作兼容承诺。
- fs 为 8000–96000 整数 Hz；nsample 为 1–192000，总输出不超过一百万采样。beta 限 -1..1，输入 T60 限 0–30s，最终输出仍受采样数预算控制。
- 最多两百万个实际候选组合、六千四百万个插值 tap 工作量，超限明确失败。order=-1 不是无限计算承诺。
- 路径明细最多一万条；截断时显式 paths_truncated=true，WAV 仍包含所有已完成的数值贡献。直接声信息独立保留，CLI/界面提示明细上限。
- 原生库只返回波形；BoxRIR 附加的路径诊断、压力符号和资源统计不属于 Python API 等价范围。
- v0.3.0 wrapper 的 beta→默认输出长度公式按原版保留，不能当作新的物理 RT60 估计。无耗散 beta 且指定 nsample 时，波形有效；上游会发除零警告。本实现将不可用的估计表示为 null；未给 nsample 时明确报错。
- 凸多边形属于另一套渲染器，未把其几何偷偷加入本兼容模式。频率相关材料、空气吸收、散射/绕射、多声源混合、移动声源、任意多面体尚未支持。

## 验证结果与复现

103 组独立原版参考、155,130 个 Float64 样本，在 JS/Wasm GC/Wasm 三后端逐索引对照；本次最大绝对误差为 2.665e-15 以下。39 组命名边界/基准场景外，增加 64 组预先指定、固定种子 20261107 的随机场景，不根据本实现结果筛选输入。判定容差为 1e-10 + 1e-9×abs(reference)，没有对齐、归一化、相关性拟合或挑选局部峰值。覆盖五种指向性、两种维度、高通开关、-1..12 阶中的多组边界、负/零/无耗散系数、T60/自动窗口、8/11.025/16/22.05/44.1/48/96kHz，以及边缘裁剪和极短输出窗口。

```sh
moon run cmd/reference-parity --target js --deny-warn
moon run cmd/reference-parity --target wasm-gc --deny-warn
moon run cmd/reference-parity --target wasm --deny-warn
node --test tests/audiolabs.test.mjs
```

固定参考保存为 tests/reference/audiolabs-0.3.0.json，包含每组原始 Float64 字节和 SHA-256；cmd/reference-parity/fixtures.mbt 是同一参考数据的自动生成嵌入形式，不计为有效实现代码。Node 同时检查两份表示一致。普通运行无需安装上游。

实际 CLI 输出的三个场景另与原始 C++ binary 和 SciPy 核对：Float32 RIR 最大误差约 1.51e-9，录音最大误差约 1.87e-9；6 个新旧浏览器场景的音频解码、下载、手机布局通过。详见 LOCAL-20261107.md。

重新生成参考需 rir-generator==0.3.0，执行 tests/reference/generate_audiolabs.py。参考是合成的开发数据，参与过实现验证，不能称作盲测或现实声学精度认证。Windows native 运行仍待 MSVC/SDK；Linux Native 由对应提交的 CI 实际运行，状态以该 CI 为准。
