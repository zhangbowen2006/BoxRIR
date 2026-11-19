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
| Mooncakes 发布 | `zhangbowen2006/boxrir@0.4.0` 可公开下载及安装。全新工程在 JS、Wasm、Wasm GC 各跑通 6 项公开接口测试。注册表源码包和同一 GitHub 发行版的源码附件 SHA-256 一致。[安装与验证](evidence/0.4.0-release.json) |

验收项来自[十一月赛事官网](https://moonbitlang.github.io/Hackathon2026/)和[赛事章程](https://bxup9uklfcb.feishu.cn/wiki/Dx4Bwd6D1i3GfHkajQCcF7SznEd)。本期安排以组委会的十一月通知为准。

## 五分钟检查

1. 浏览器打开[工作台](https://zhangbowen2006.github.io/BoxRIR/)，选择六频段示例，查看双通道响应，下载声源和 WAV。把矩形示例中的 `sample_rate` 改为 `48000`，直接生成，核对下载的 `source.wav` 与录音均为 48 kHz。
2. 打开[多声源工作台](https://zhangbowen2006.github.io/BoxRIR/mix.html)，运行内置两轨示例，再修改第二轨增益或起始帧。下载新的 `report.json` 和 `wet.wav`，核对时间轴与声道顺序。
3. 下载[GitHub 0.4.0 运行包](https://github.com/zhangbowen2006/BoxRIR/releases/tag/v0.4.0)，执行[实验文档](EXPERIMENTS.md)中的两轨流程和 `verify`，再用 `analyze` 读取当前响应。独立数值复现可从仓库运行 `python scripts/verify-experiments.py`。

## 包和验证结果

- `v0.4.0` 固定了运行包的源码修订。可在发行页下载 `SHA256SUMS.txt`，并查看运行包内的 `sdk/build-info.json`。[固定发行版](https://github.com/zhangbowen2006/BoxRIR/releases/tag/v0.4.0) · [发布版 CI](https://github.com/zhangbowen2006/BoxRIR/actions/runs/44424324209)
- 在 MoonBit 工程运行 `moon add zhangbowen2006/boxrir@0.4.0`。库的安装验证可以从仓库运行 `python scripts/test-registry-package.py`，脚本会在新工程安装并执行接口测试。[Mooncakes 0.4.0](https://mooncakes.io/docs/zhangbowen2006/boxrir@0.4.0) · [公开交付验证](evidence/0.4.0-release.json)
- 验证了合成响应、公开参考实现与端到端文件流程。现场测量、设备校准、材料标定和外部采用情况尚未取得证据。[本地验证结果](evidence/0.4.0.json) · [功能边界](EXPERIMENTS.md)
