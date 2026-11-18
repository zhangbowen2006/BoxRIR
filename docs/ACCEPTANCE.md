# BoxRIR 十一月验收复现

BoxRIR 已通过 2026 年十一月黑客松报名初审，依据为参赛者保存的组委会通知。评审材料以此仓库的实际提交和可运行结果为准，最终验收由组委会决定。此前的十月初审和 0.1.1 记录见[历史版本](https://github.com/zhangbowen2006/BoxRIR/blob/6949c70/docs/ACCEPTANCE.md)。

| 官方验收项 | 0.4.0 对应证据 |
|---|---|
| MoonBit 为主要实现语言 | 传播路径、卷积与叠加、探针、衰减分析、传递响应估计、比较与重采样均由 MoonBit 执行。`scripts/report-source-scale.py` 统计自研运行源码 5,018 行，其中 MoonBit 4,258 行、宿主 JavaScript 760 行，移植与公式适配另列 375 行。 |
| 仓库公开，开发过程可追踪 | [Git 提交](https://github.com/zhangbowen2006/BoxRIR/commits/main/)和[持续集成](https://github.com/zhangbowen2006/BoxRIR/actions/workflows/ci.yml)可查。 |
| README、可运行示例、必要测试 | [快速运行](../README.md)、[实验步骤](EXPERIMENTS.md)、[验证方法](VALIDATION.md)覆盖单声源、多声源、数值对照和浏览器下载。 |
| 本期有实质开发 | 0.4.0 实现共享场景的静态多声源录音、可控探针生成、多通道响应分析、带诊断的传递响应估计与对比、显式重采样、产物核验；修复了浏览器默认输入在非 16 kHz 场景的采样率问题。 |
| 开源合规 | [Apache-2.0](../LICENSE)、[NOTICE](../NOTICE)、[来源](PROVENANCE.md)及[第三方许可](licenses)与运行包同步。 |
| 可解释的实现 | 参赛者可以用下方的步骤重跑示例并说明混音时间轴、阈值与拟合状态、源信号频谱与正则化、设备时钟对结果的影响。代码、测试和文档有 AI 辅助。 |

以上六项见[十一月赛事官网](https://moonbitlang.github.io/Hackathon2026/)和[官方页面源码](https://github.com/moonbitlang/Hackathon2026/blob/main/src/App.tsx#L204-L229)。具体截止时间和提交入口以组委会的十一月通知为准。

## 五分钟检查

1. 浏览器打开[工作台](https://zhangbowen2006.github.io/BoxRIR/)，选择六频段示例，查看双通道响应，下载声源和 WAV。把矩形示例中的 `sample_rate` 改为 `48000`，直接生成，核对下载的 `source.wav` 与录音均为 48 kHz。
2. 打开[多声源工作台](https://zhangbowen2006.github.io/BoxRIR/mix.html)，运行内置两轨示例，再修改第二轨增益或起始帧。下载新的 `report.json` 和 `wet.wav`，核对时间轴与声道顺序。
3. 下载[GitHub 运行包](https://github.com/zhangbowen2006/BoxRIR/releases)，执行[实验文档](EXPERIMENTS.md)中的两轨流程和 `verify`，再用 `analyze` 读取当前响应。独立数值复现可从仓库运行 `python scripts/verify-experiments.py`。

## 包和验证结果

- 0.4.0 的源码、前端和运行包版本由对应提交的 CI、运行包内 `sdk/build-info.json` 和下载清单确认。[发布历史](https://github.com/zhangbowen2006/BoxRIR/releases)
- Mooncakes 已核验的注册表版本为 `0.3.0`。0.4.0 本地 Mooncakes 格式归档可用 `moon package` 和 `python scripts/test-moon-package.py` 验证，安装状态以[版本列表](https://mooncakes.io/docs/zhangbowen2006/boxrir)为准。[0.3.0 精确版本](https://mooncakes.io/docs/zhangbowen2006/boxrir@0.3.0)
- 验证了合成响应、公开参考实现与端到端文件流程。现场测量、设备校准、材料标定和外部采用情况尚未取得证据。[本地验证结果](evidence/0.4.0.json) · [功能边界](EXPERIMENTS.md)
