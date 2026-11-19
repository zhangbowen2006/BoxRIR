# 8–10 月季度入围作品对照

项目名单来自组委会的 2026 年 8–10 月季度赛入围图片，共 11 项，排名不分先后。下列观察来自各项目公开仓库的文档或工作流。评选理由由组委会掌握。

| 入围项目 | 可查的工程做法 | 对 BoxRIR 的启发 |
|---|---|---|
| native-gui | 把窗口、控件等能力做成可运行的组件示例，CI 区分平台检查。[示例](https://github.com/lb091188/moonbit-native-gui/blob/master/examples/README.md) · [CI](https://github.com/lb091188/moonbit-native-gui/blob/master/.github/workflows/ci.yml) | 让评委用现成的输入获得可下载的 WAV。 |
| moon-heke 工具组 | 通过有类型的接口连接 Web 应用和服务器，协议与框架组件公开。[组件组织](https://github.com/moonbitstack) · [moonasgi](https://github.com/moonbitstack/moonasgi) | 频段、几何和时间轴保持统一核心，CLI 和浏览器共同调用公开接口。 |
| floating | 文档明确数值表示、运算状态与边界。[手册](https://github.com/Luna-Flow/floating/blob/main/doc/manual/index.md) | 把衰减拟合的有效、动态范围不足和拟合偏弱状态写入结果。 |
| qbe.mbt | 独立的目标产物和上游 C 参考进入 CI。[CI](https://github.com/azhzx/qbe.mbt/blob/main/.github/workflows/ci.yml) | 延续上游 AudioLabs 差分，再用 SciPy 验证本版多轨混音和音频数值。 |
| posoco | 独立的核心与使用示例，流水线覆盖不同目标。[示例](https://github.com/colmugx/posoco/tree/main/examples) · [CI](https://github.com/colmugx/posoco/blob/main/.github/workflows/check.yml) | 核心 MoonBit 库可独立调用，运行包和浏览器从正常入口测试。 |
| BioSeqs | 提供库使用入口、示例与多目标检查。[仓库](https://github.com/paipai-Studio/BioSeqs) · [CI](https://github.com/paipai-Studio/BioSeqs/blob/main/.github/workflows/ci.yml) | 把外部用户如何安装、导入和执行列入验收证据。 |
| MoUI | 单独执行下游消费测试，并提供独立示例应用。[外部消费工作流](https://github.com/wzzc-dev/MoUI/blob/main/.github/workflows/external-consumer.yml) · [示例](https://github.com/wzzc-dev/MoUI/tree/main/examples) | 区分源码归档、仓库外使用与注册表实际安装，记录准确版本。 |
| moonav1 | 结合固定解码参考、跨后端测试和可运行用法。[仓库](https://github.com/0717lee/moonav1) · [CI](https://github.com/0717lee/moonav1/blob/main/.github/workflows/ci.yml) | 验证下载 WAV 的采样和误差，避免只验证页面按钮与文件存在。 |
| MoonFrame | 提供可执行文档用例和面向同类库的功能比较。[文档](https://github.com/ihb2032/MoonFrame/blob/main/README.mbt.md) · [功能比较](https://github.com/ihb2032/MoonFrame/blob/main/docs/comparison.md) | 将项目边界与可复现输入输出放在同一页。 |
| MBOpenClacky | 明确测试层级和已知缺口。[测试说明](https://github.com/hnlyxiaobing/MBOpenClacky/blob/main/docs/testing.md) · [已知缺口](https://github.com/hnlyxiaobing/MBOpenClacky/blob/main/docs/known-gaps.md) | 把数值一致性、端到端操作、工具链兼容和现场声学准确性分别用对应证据支持。 |
| fist-mbt | 通过独立证据库追踪实际场景、运行方式与结果。[实现](https://github.com/vicTop-cw/FIST-Mbt) · [证据](https://github.com/vicTop-cw/fist-evidence) | 输出清单保存输入快照和摘要，同一套文件可复算、可核验。 |

## 0.4.0 从对照中落实的改进

0.3.0 已有公开参考波形、四种传播模式、CLI 和浏览器。原先工作台无法在 48 kHz 的场景下直接生成默认输入，单声源入口也无法模拟两路干声在不同位置和时刻的叠加。0.4.0 已针对这两个缺口补上浏览器操作、WAV 下载及真实浏览器回归，并把宽带分析、可追溯对照、重采样接进同一个 `probe`、`mix`、`estimate`、`compare` 工作流。[运行与复现](EXPERIMENTS.md)

MoonBit 社区已有 `roomacoustics` 提供衰减曲线、混响时间和房间模态分析，pyroomacoustics 也有混响时间例程。BoxRIR 此次将宽带响应分析用于模拟和录音的可复现实验，与其他库有方法层面的交集。BoxRIR 的交付包含带位置、频段吸声和传播路径的前向模拟、可输入多轨 WAV 的录音合成、公开 MoonBit 接口和浏览器工作台。[roomacoustics](https://github.com/AYHEY001/roomacoustics) · [pyroomacoustics RT60](https://pyroomacoustics.readthedocs.io/en/stable/pyroomacoustics.experimental.rt60.html)

现场互校需要同一房间、声源、麦克风与设备信息。任意多面体、运动声源和高级物理传播也需要分别设计数值参考和验证数据。0.4.0 的验收证据针对文档列明的静态场景。[验收复现](ACCEPTANCE.md)

## 安装示例复核

2026-11-19 再次核对以上项目的公开文档与工作流。其中 MoonFrame、moonasgi 和 floating 都把导入配置和第一次调用放在安装说明附近。MoUI 另外验证了外部工程安装。0.4.1 据此补上可复制的 `moon.mod`、`moon.pkg` 和双通道示例，源码包验证执行其中的示例，注册表验证还会在新工程逐字执行三个文件。[BoxRIR MoonBit 快速开始](MOONBIT-QUICKSTART.md) · [MoonFrame 可执行文档](https://github.com/ihb2032/MoonFrame/blob/main/README.mbt.md) · [MoUI 外部消费](https://github.com/wzzc-dev/MoUI/blob/main/.github/workflows/external-consumer.yml)

此表对照当前公开仓库。各项目持续演进，截图确认的是季度入围名单，当前能力与入围时的状态可能存在差异。
