# BoxRIR 0.2.0：工程发布检查

检查日期：2026-11-07。范围只包括 BoxRIR 的代码、运行包和工程文档；没有修改参赛申报书。源代码和实际 CI 是最终依据，不把以下记录当作初审结论。

## 对照此前反馈

| 原有不足/评委关注点 | 本版实际交付 | 仍有边界 |
|---|---|---|
| 仅静态矩形的基础传播 | 增加严格凸柱体有限墙面可见性；移植 AudioLabs RIR Generator 0.3.0 完整数值参数链路 | 仍是静态离线镜像法，未实现整个 pyroomacoustics；没有障碍物、散射、绕射、动态几何或频率相关材料 |
| 只有合成几何与自制 demo，不足以说明核心正确性 | 原版 C++ binary 生成完整 Float64 波形，103 场景/155130 样本；三个后端逐点比较；另与 SciPy 核对实际 WAV/卷积文件 | 合成参考不是测量精度、外部用户采用或生产现场可靠性认证 |
| 重写成熟工具需证明迁移价值和平台约束 | 同一 MoonBit 核可编译为 JS/Wasm/Wasm GC；实际 Node SDK/CLI 和浏览器 Wasm GC；独立包在不调用 MoonBit/Python/C++ 的环境运行 | Wasm SDK 要求 GC 和 JS string builtins；不支持的运行时明确失败。Windows Native 缺少 MSVC/SDK，不能声称本机通过 |
| 宣称通用能力但只有局部场景 | 明确三种模型的系数、滤波、窗口、延迟、资源和错误契约；保留原接口；给出完整输入到文件的工作流 | 一源、1–8 接收点及显式预算；不会把有限模型宣传为通用建筑声学平台 |
| 交付质量和可复现性 | SDK 类型检查、输入快照、输出哈希清单、无覆盖/并发/失败回滚、依赖许可、独立运行包和源码包消费测试 | 断电无法跨文件系统保证事务；标记未清理的输出不能消费 |

评委是否认可该范围，需要其复审。任何“全部必要功能都达标”“必过初审”或“生产实测认证”的结论均超出这些证据。

## 数值证据

- AudioLabs 上游固定 v0.3.0 / `052790faade19074c6921e007fb8972c60e8f0a6`，MIT core/wrapper 声明完整保留。这是源码移植，不将其当作原创算法。
- 39 组命名边界/基准 + 64 组固定种子随机场景，涵盖五种模式、方位/俯仰、高通开关、二维/三维反射、有限/窗口阶数、正负/零/无耗散系数、默认窗口与极短窗口等。
- 逐采样判定容差 `1e-10 + 1e-9*abs(reference)`；不移动时间轴、不归一化、不拟合增益。本地 JS、Wasm、Wasm GC 最大绝对误差均为 `2.6645352591003757e-15`。
- pyroomacoustics 0.10.1 凸柱体对照扩展到四阶：20 场景、1687 条有效路径。其 Float32 几何最大偏差约 4.09e-5m；采用 5e-5m 容差，并另用精确矩形闭式、反射角、命中面和物理长度检查，保留 1e-8m 检验。
- 原矩形参考仍为 32 场景/2330 镜像，独立六墙 BFS 为 5 场景/225 镜像。几何与波形证据不混称。
- 新 CLI 实际导出的三个 AudioLabs 流程：RIR Float32 最大误差 `1.5079616860758094e-9`；模拟录音相对原版 + SciPy 最大误差 `1.8607459878472454e-9`。凸柱体录音相对 SciPy 卷积最大误差约 `2.744e-9`。

上游在显式窗口的无耗散系数案例发出默认长度估计除零警告；输出有限，BoxRIR 将不可用估计记为 null。省略显式窗口时拒绝该输入。这一差异已公开，未隐藏失败或改变比较窗口。

## 软件与部署检查

Windows x64，Node 24.22.1，moon 0.1.20261021 / moonc 0.10.17+093cb8f9c：

| 检查 | 本地结果 |
|---|---|
| `moon fmt --check`、`moon check --target all --deny-warn` | 通过 |
| `moon test --target js/wasm/wasm-gc --deny-warn` | 各 24/24 |
| `moon run cmd/reference-parity --target js/wasm/wasm-gc --deny-warn` | 各 103 场景/155130 样本通过 |
| `node --test tests/*.test.mjs` | 24/24；包括磁盘部分写入、并发目录竞争、UTF-8 错误和 SDK 异常 |
| SDK JS/Wasm GC 实际消费 | 完整参考波形、WAV 和卷积通过；Wasm 无非 builtin host imports |
| 192 份固定种子 RIFF 变异输入，每个 SDK 后端 | 各 47 份合法/允许输入、145 份错误拒绝，无未捕获 panic；空输入按 API 契约表示仅生成 RIR |
| TypeScript 5.9.3 严格 NodeNext 检查 | `tests/sdk-types.mts` 通过，使用真实 `.d.mts` 声明 |
| Edge 156.0.4314.58 headless | 6 场景实际 Wasm GC、音频解码、下载对照、取消后重启、旧结果失效、试听 Blob 回收、手机无横向溢出 |
| 独立运行包 | 37 文件，SHA256 全通过；移入独立目录，JS/Wasm GC 的 SDK 和 CLI 均通过；子进程 PATH 中没有 MoonBit/Python/C++ |
| 本地 Mooncakes 归档 | 解压到独立 workspace，三个公开消费测试 + 归档内 24 测试，各后端 27/27；缓存、私人目录及申报材料不在包内 |

Linux CI 固定编译器和 Node 24，执行四个目标（包括 Native）、文件工作流、原版参考、独立消费、TypeScript 和 Chromium 工作台；结果以对应 commit 的 Actions 页面为准。本地未假冒运行 Windows Native。Mooncakes 本地归档通过不等于已发布 0.2.0 到注册表。

## 资源测量和运维契约

运行 `node scripts/benchmark-runtime.mjs`，每例新进程，Node JS heap 上限设为 768MiB。下面是这台 Windows 机器上的一次记录，时间和 RSS 都不是跨设备保证：

| 场景 | JS 计算/进程峰值 RSS | Wasm GC 计算/进程峰值 RSS |
|---|---|---|
| 两通道参考示例，4096 帧 RIR | 约 502ms / 202MiB | 约 499ms / 161MiB |
| 八边形、四阶反射，一通道 | 约 134ms / 134MiB | 约 86ms / 94MiB |
| 八通道 96kHz、96000 帧 RIR + 65536 帧声源 | 约 4.76s / 588MiB | 约 3.51s / 478MiB |

长音频不是实时工作负载；并发运行前应按目标机器实测内存。没有将简单采样数预算等同于通用内存上限。共享干声 FFT、单次 WAV 字节缓冲和紧凑音频传输减少重复计算/分配，但仍依赖 FFT 库和运行时 GC。未宣称性能优于上游。

CLI 首先检查输入与已有输出目录，计算后独占创建目录；每个文件 exclusive 写入、flush，再写输入/核心/输出哈希清单，最后移除 incomplete 标记。正常异常仅回滚本次创建的文件，测试验证不会删除意外出现的第三方文件。断电/强制终止可能保留不完整目录，不能当完成结果。

## 复现入口

```sh
node scripts/build-sdk.mjs
node --test tests/*.test.mjs
moon run cmd/reference-parity --target wasm-gc --deny-warn
node scripts/build-release.mjs
node scripts/test-distribution.mjs
moon package
python scripts/test-moon-package.py
```

原始结果位于 ignored `generated/`：`sdk-verification`、`robustness`、`runtime-benchmark`、`prism-browser`、`distribution-verification`、`package-consumer` 和 `final-workflows-20261107`。可公开的精简副本见 [evidence/0.2.0.json](evidence/0.2.0.json)。完整 Float64 golden 和生成器在 tests/reference；自动生成的 MoonBit 嵌入文件是测试数据，不是实现规模。

发布包包含 LICENSE、NOTICE 和所有依赖许可证；GitHub 推送前核对真实账号 zhangbowen2006、默认分支 main、工作区状态及输入隐私。没有把电话、个人邮箱或身份材料写入本轮产物。
