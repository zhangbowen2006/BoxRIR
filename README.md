# BoxRIR

[在线工作台](https://zhangbowen2006.github.io/BoxRIR/) · [公开仓库](https://github.com/zhangbowen2006/BoxRIR) · [Mooncakes 0.1.1](https://mooncakes.io/docs/zhangbowen2006/boxrir@0.1.1) · [正式申报书](docs/SUBMISSION.md) · [一页PDF](output/pdf/BoxRIR-项目申报书-20261031.pdf) · [验收对照](docs/ACCEPTANCE.md)

**把三维房间和声源位置转换为多通道脉冲响应及模拟录音。** 核心由 MoonBit 实现，提供类型化 API、JSON CLI 和浏览器工作台。生产计算不运行 Python 或调用外部声学模拟程序。

输入房间尺寸、六面墙的能量吸声系数、一个声源和 1–8 个接收点；输出可直接使用的 Float32 WAV、逐路径传播报告、CSV 与响应图。适用于游戏音频原型、麦克风阵列算法、声学教学和可复现语音数据增强。

镜像声源法是已有物理模型。本项目的贡献是 MoonBit 原生、有明确时间和增益约定的独立生成/仿真工具，不是新物理算法，也不承诺现实房间测量精度。[模型语义](docs/MODEL.md) · [选题对比](docs/RESEARCH.md) · [来源与许可](docs/PROVENANCE.md)。

## 立即运行

需要 MoonBit 0.1.20261028 和 Node.js 22+。Windows 本机没有全局命令时：

```powershell
$env:MOON_HOME='D:\CodexProjects\.tools\moon'
$env:PATH="$env:MOON_HOME\bin;$env:PATH"
```

在项目目录运行：

```sh
moon update
moon check --deny-warn
moon test --deny-warn
moon run cmd/main
moon build --target js --release --deny-warn
node bin/boxrir.mjs rir examples/stereo.json generated/stereo
node bin/boxrir.mjs rir examples/wall-before.json generated/wall-before
node bin/boxrir.mjs rir examples/wall-after.json generated/wall-after
node bin/boxrir.mjs simulate examples/array.json examples/probe.wav generated/array
```

输出目录必须不存在。成功后得到 `rir.wav`、`report.json`、`paths.csv` 和 `response.svg`；simulate 额外生成 `wet.wav`。输入或计算错误退出 2。文件写入失败时可能保留部分产物和 `.boxrir-incomplete` 标记，不能将其当成完成结果；不会覆盖已有输出目录。`inspect scene.json` 可仅输出几何模型。

## 在浏览器中试用

```sh
node scripts/build-demo.mjs
node scripts/serve-demo.mjs
```

打开 `http://127.0.0.1:4177`。选择四个预设之一，修改参数，生成并试听。可上传本地单声道 WAV，也可使用自带的一秒合成扫频。计算在 Web Worker 中执行，可取消；文件不上传服务器。试听音量按整份多通道录音统一调整，下载文件保留原始增益，不悄悄逐通道归一化。

浏览器可将多于两通道的声音下混播放，阵列实验应使用下载的原始文件。页面显示所有麦克风的直接声到达时间、共同滤波延迟、保留和越窗路径数量。

## 三个完整工作流

| 使用者与问题 | 输入和操作 | 真实输出与验证 |
|---|---|---|
| 游戏音频开发者需要与位置对应的双接收点空间响应 | `stereo.json`，6×4×3 m房间，两接收点，6阶反射；执行rir或浏览器生成 | 每通道377条保留路径，4032帧RIR；直接声分别约7.658和8.090 ms。检查到达时间差、球面扩散增益和共享时间轴 |
| 声学教学人员比较单面墙处理前后变化 | `wall-before.json`、`wall-after.json`，只将x低墙能量吸声系数从0.1改为0.9 | 两份2912帧响应；该墙一阶反射的压力增益变为1/3，到达时间和其他一阶反射不变。独立脚本计算核对，不从有限窗口宣称准确RT60 |
| 语音/阵列算法开发者需要可复现的多通道模拟录音 | `array.json` 与16000 Hz单声道 `probe.wav`，执行simulate | 三通道1952帧RIR和17951帧模拟录音，包含完整卷积尾部。SciPy独立卷积和WAV读取对照，报告误差与通道数量 |

这些是完整可运行的合成实验，没有外部用户采用或现场测量证据。提交的 [outputs](outputs) 可直接查看和播放。

## 输入与 API

已验证注册表安装：`moon add zhangbowen2006/boxrir@0.1.1`。精确版本、源码标签、校验值和独立消费结果见 [发布记录](docs/RELEASE-0.1.1.md)。

```json
{"room":[6,4,3],"source":[1.5,1,1.5],"receivers":[[4,1.8,1.4],[4,2.2,1.4]],"absorption":[0.15,0.3,0.25,0.4,0.35,0.2],"sample_rate":16000,"max_order":6,"duration_ms":250,"speed":343,"half_width":16}
```

- `room/source/receivers`：米；声源与接收点严格位于房间内部，彼此距离至少0.01 m。
- `absorption`：六个**能量**吸声系数，顺序为x低、x高、y低、y高、z低、z高；压力反射系数使用 `sqrt(1-alpha)`。
- `max_order`：六面墙反射次数之和上限，不是每轴单独上限。
- `duration_ms`：保留物理到达时间窗；超过窗口的有限阶路径被统计为late。
- `half_width`：窗化sinc半宽，默认16；所有通道增加同样的16采样延迟。输出额外保留2×half_width帧，以免截掉已经接纳路径的FIR尾部。
- `speed`：声速m/s，默认343。整数控制字段必须为整数字面量；拒绝未知字段、重复键及越界值。

公开接口见 [pkg.generated.mbti](pkg.generated.mbti)、[api](api/pkg.generated.mbti) 和 [io](io/pkg.generated.mbti)。核心调用链为 `scene → images/trace → render → convolve`。IO模块独立，接收器数据均保持原始时间差和线性模型增益。

## 实现和依赖

每轴镜像为 `(1-2p)*s+2*n*L`，低/高墙次数分别为 `abs(n-p)`、`abs(n)`；路径压力增益为六面墙反射系数乘积除以 `4*pi*distance`。不同镜像即使同时到达也累加。分数延迟使用完整的归一化Hann窗sinc核，先归一化后放置，不对截断片段补增益。

- 房间模型、镜像/路径枚举、时间窗、分数延迟RIR、通道协调和仿真流程由本项目实现。
- FFT线性卷积复用 `chgttyyr/MoonSpectrum@0.2.2`（Apache-2.0）。
- 输入WAV解析复用 `Ridge-Lab/moonwavkit@0.1.3`（MIT），先做宽整数RIFF块边界检查并过滤无关元数据；不执行隐式下混或重采样。PCM只按位深换算到标准浮点单位，不按峰值归一化。
- 该版本MoonWavKit仅提供整数PCM写出，故本项目提供窄范围IEEE Float32 WAV输出，以保留模型增益和超过±1的浮点样本；没有另造通用WAV库。

依赖表示复用成熟底层能力。BoxRIR 不需要 `roomacoustics`、`moondsp`、NeedleRail或任何先前参赛项目才能运行。

## 资源与物理边界

矩形房间0.1–1000 m；一个全向点源、1–8个全向点接收器；声速100–1000 m/s；频率无关吸声0–1。采样率8000–96000 Hz；总阶0–12；整数窗口1–2000 ms；sinc半宽4–32；总RIR最多1,000,000采样。卷积输出每通道最多262144帧、合计最多2,000,000采样。场景文本最多65536字符，单声道源WAV最多4 MiB和262144帧，采样率须匹配。

不实现障碍物、绕射、散射、空气吸收、频率相关材料或头部传递函数。没有现场校准、工程声级认证或精确RT60保证。有限阶模型可能存在规则镜像的梳状/扫频回声；提高阶数也不能弥补缺少的物理过程。Float32输出只进行数值精度转换，不限幅，播放设备可能自行限幅。

## 验证

```sh
moon check --target all --deny-warn
moon test --target wasm --deny-warn
moon test --target wasm-gc --deny-warn
moon test --target js --deny-warn
moon build --target js --release --deny-warn
node --test tests/*.test.mjs
python -m pip install numpy==2.5.4 scipy==1.18.1
python scripts/verify_artifacts.py
```

已完成12组MoonBit测试、6组Node测试；独立六墙BFS覆盖5场景/225镜像，pyroomacoustics 0.10.1覆盖32场景/2330镜像。外部实现内部有float32，因此比较使用明确尺度相关容差，未伪称逐位一致。WAV及卷积由SciPy独立核对，详见 [验证记录](docs/VALIDATION.md)。`tests/reference` 保存参考生成器及版本元数据。

Windows Native需要MSVC C++工具与Windows SDK；Linux CI负责原生实际运行。浏览器已验证计算完成、结果展示和音频解码加载，不将其描述成连续全程听审。

本项目采用Apache-2.0；第三方完整许可见 [NOTICE](NOTICE)。AI参与了代码、测试与文档，参赛者须理解模型和边界。发布和报名状态以实际链接及官方结果为准。
