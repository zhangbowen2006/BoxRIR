# 身份、来源与复用关系

参赛者张博文，个人项目，实际GitHub/Mooncakes账号为zhangbowen2006。此前提出但未核验的新账号未使用；换账号不代表不同参赛者，也不会重置报名次数。

BoxRIR与本人NeedleRail、AgentCanary、MoonGate、WasmSlim等项目在同一账号下公开。NeedleRail是几何到刺绣针迹编译，AgentCanary是工具历史策略回放；本项目是声学正向模拟，未复制它们的核心算法或提交历史。通用文档排版方式不作为新的实现贡献。没有将AgentCanary描述成已被驳回。

数学基础为经典Allen-Berkley镜像源方法。原渲染器和凸多边形扩展独立以MoonBit组织实现，通过上游公共API和六墙BFS交叉验证。2026-11-07新增的 audiolabs_v030 模式则实际移植了 AudioLabs RIR Generator 0.3.0 的数值核和默认参数处理，不再将这一部分称作完全原创。没有整体移植 pyroomacoustics；不宣称新的反射算法。

| 来源 | 实际使用 | 许可 |
|---|---|---|
| MoonBit core | 标准库及数学运算 | Apache-2.0 |
| chgttyyr/MoonSpectrum 0.2.2 | 调用FFT/IFFT，由本项目组织共享声源频谱的多通道卷积 | Apache-2.0，完整文本见licenses/MoonSpectrum.txt |
| Ridge-Lab/moonwavkit 0.1.3 | WAV解析与PCM/Float32输入解码；本项目先限制块边界并过滤元数据 | MIT，完整文本见licenses/MoonWavKit.txt |
| moonbitlang/x 0.4.45 | MoonSpectrum声明的传递依赖 | Apache-2.0；未计为本项目新增工作 |
| pyroomacoustics 0.10.1 | 开发验证fixture生成器，通过公共API调用；生产库不依赖Python | MIT，文本见licenses/pyroomacoustics.txt |
| audiolabs/rir-generator v0.3.0 | 原模式为参考；新增 audiolabs.mbt 数值核及默认参数处理为实际移植；原始 C++/Python 仅用于开发验证 | MIT，wrapper文本见licenses/rir-generator.txt；core完整声明见licenses/audiolabs-rir-generator-MIT.txt；固定SHA见docs/provenance/audiolabs-source-manifest.json |

roomacoustics和moondsp为相关项目，调查范围和功能交集见RESEARCH.md。未复用其声学分析、Freeverb实现或Python素材生成代码，不隐瞒同领域已有成果。

现有MoonWavKit写出接口仅覆盖整数PCM。BoxRIR为保留原始模型幅度实现了窄范围Float32 WAV输出（fmt/fact/data），不是另起一个通用音频格式项目；独立SciPy读取验证其文件。样例声源是自制一秒合成扫频，没有第三方录音或个人数据。

代码、测试、调研和文档有AI辅助。按参赛者在本会话确认的组委会口径，申报书允许AI辅助；参赛者仍应核对材料并能解释每墙计数、压力与能量、滤波延迟和模型局限。没有伪造实际用户、机器测量、初审通过或获奖。
