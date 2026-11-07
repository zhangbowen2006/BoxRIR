# 选题调查与独立价值

2026-10-31 11:42–11:55（北京时间）同时查询Mooncakes CLI、GitHub repository API、MoonBit社区域名及成熟跨语言项目；先调查再实现。关键词搜索不是全生态审计，未命中不证明没有竞争项目。

## 三个候选方向

| 方向 | 实际需求与可复用性 | 调查结论 |
|---|---|---|
| 接收方签名驱动的文件增量同步 | 更新程序传输新版资源；离线字典更新；缓存刷新。均以旧文件签名、新文件为输入，生成补丁并逐字节复原验证 | [MoonSyncDelta](https://github.com/niuniu513-ask/moon-sync-delta) 已覆盖，且明确作为 [moon-vcdiff](https://github.com/yangxixi00/moon-vcdiff) 扩展披露重叠；[librsync](https://github.com/librsync/librsync)（LGPL-2.1）也已有成熟签名/差量实现。放弃，不改名重复 |
| 整数配额/资源分配 | 预算分成整数单位；任务槽按权重分配；二维报表保留行列总数。输入权重/总额/边界，输出满足约束的整数表，用守恒和穷举小例验证 | [MoonMoney](https://github.com/haol-05/moonmoney)（Apache-2.0）已有金额精确分配；[MoonOpt](https://github.com/Freon793/moonopt)（Apache-2.0）与图算法包覆盖优化/流算法；Python [apportionment](https://github.com/martinlackner/apportionment)（MIT）已有多种成熟配额方法。二维专用应用仍可探索，但本期难在有限时间拿出比现有优化能力更明确的独立贡献，未开发 |
| 由三维房间生成多通道声传播响应 | 游戏/音频原型需要位置相关响应，阵列算法需要共享时间轴的数据，教学需要单墙参数的可控实验 | 选择BoxRIR，完成从场景到RIR及模拟录音的独立工作流；真实产物和上游模型/独立波形对照可验证，不以检查报告为主要功能 |

## 必须披露的相邻MoonBit项目

| 项目 | 已有能力 | BoxRIR的实际差异与边界 |
|---|---|---|
| [AYHEY001/roomacoustics](https://github.com/AYHEY001/roomacoustics)（Apache-2.0） | MoonBit核心从已有IR计算衰减、混响时间和模态，含Sabine估算；仓库也有Python镜像源测试素材生成脚本 | BoxRIR提供MoonBit原生的场景→镜像/每墙次数→多接收点RIR→模拟录音接口。已知其Python脚本存在，不宣称该仓库完全没有IR生成代码。未复制其脚本或使用其库；用户可独立生成训练/音频数据，无须调用分析项目 |
| [dowdiness/moondsp](https://github.com/dowdiness/moondsp)（Apache-2.0） | 已有基于Freeverb调谐的反馈梳状/全通滤波混响 | 两者都有混响音频用途；该模块采用固定延迟网络与衰减/阻尼参数。BoxRIR根据三维位置与六面墙计算几何路径和接收点时差，不以更好听或更准确为未经验证的卖点 |
| [MoonSpectrum](https://github.com/chgttyyr/MoonSpectrum) / [MoonWavKit](https://github.com/Ridge-Lab/MoonWavKit) | FFT、卷积及WAV读取等通用能力 | 本项目直接依赖并注明许可，不将FFT和通用WAV解析重复包装为自己的创新 |

实际检索：Mooncakes `room acoustics`、`shoebox`、`rir`、`reverberation` 未返回直接对应生成模块；`reverb` 检出moondsp，`impulse response`检出通用DSP。GitHub `room impulse MoonBit`发现roomacoustics；`room simulator language:MoonBit`、`RIR generator language:MoonBit`、`shoebox language:MoonBit`当时均为0。检索`image-source`另有不相关图像项目。这里如实保留相邻能力，不把0条结果当成唯一性证明。

## 成熟跨语言参考与对照

- [pyroomacoustics](https://github.com/LCAV/pyroomacoustics)，MIT：[官方Room Simulation文档](https://pyroomacoustics.readthedocs.io/en/pypi-release/pyroomacoustics.room.html)覆盖矩形/多面体房间、镜像源、射线追踪、指向性及阵列。其功能远多于BoxRIR；本项目不调用它进行生产计算，使用0.10.1公共API产生独立对照数据，明示float32容差。
- [AudioLabs RIR Generator](https://www.audiolabs-erlangen.de/fau/professor/habets/resources/simulation)及[Python实现](https://github.com/audiolabs/rir-generator)，MIT：成熟的多通道镜像源模拟。用于核对既有模型和墙面计数约定；没有把它的C++运行时包装成MoonBit项目。
- 基础理论：Allen与Berkley的Image Source Method（1979），链接见AudioLabs参考列表。本项目不主张算法发明、行业唯一或性能领先。

## 为什么是独立项目

BoxRIR的输入是场景和原始声音，核心任务是正向传播模拟，主要输出是能被使用的RIR/多通道录音。它不要求现有声学分析项目、先前参赛项目或第三方服务器集成。可通过类型化库、CLI和浏览器完成同一工作流；依赖FFT/WAV库属于通用底层复用。

工程贡献集中在六墙计数、压力/能量语义、有限阶枚举、共同时间轴、完整分数延迟尾部、多通道卷积和明确的数据交换/资源边界。这个范围有独立可调用价值，但是否足够进入比赛评选由组委会判断。尚无真实房间测量或外部用户采用证据，不能将参考模拟器对照当作现场精度认证。

## 2026-11-07 本地续做决定

按主办方关于成熟实现、迁移价值和完整证据的反馈，新增固定 AudioLabs RIR Generator 0.3.0 的数值核移植模式。原 C++ 内核及 Python 默认参数处理实际转写为 MoonBit，MIT 来源已经披露。此模式与独立凸多边形渲染器分别选择，不声称实现整个 pyroomacoustics。具体能力、迁移价值与目标域限制见 AUDIOLABS-COMPATIBILITY.md；三后端完整波形和实际文件对照见 LOCAL-20261107.md。该决定是对既有 BoxRIR 的实质续做，不冒充新仓库，也未推送或重新申报。
