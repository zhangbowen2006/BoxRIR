# BoxRIR 0.3.0 发布检查

日期：2026-11-09。本轮只完善 BoxRIR，不改写正式申报书，不操作报名表或替主办方作审核结论。

## 针对反馈的实质变化

截图指出原项目仅基础矩形传播，评委建议证明技术路线、成熟实现移植价值与部署约束。
0.2.0 已移植固定 AudioLabs 数值核；0.3.0 增加逐路径六频带墙材料与空气损耗，支持原矩形和凸柱体。
各路径按命中墙及次数分别计算频段压力，再按真实路径距离衰减，之后合成RIR；没有用最终全局EQ冒充路径声学。
温湿度/压力方程适配固定 Python Acoustics 源码，BSD-3-Clause完整保留，来源哈希随源码/运行包分发。
详细定义及近似见 [SPECTRAL.md](SPECTRAL.md)。

子代理只读审查，主代理实现及修复；以下发现已处理：

| 发现 | 修复与核对 |
|---|---|
| AudioLabs 镜像数混用筛选前循环次数 | 分离 evaluated_candidates 与筛选后镜像数，测试0/1/2阶1/7/25个镜像及每麦分类计数 |
| raw JSON 样本预算在计算之后判断 | 显式窗口先拒绝不可能输出的请求 |
| 新频段短FIR在96kHz下低频串扰严重 | 默认及最小半宽ceil(256*fs/16000)，不足的显式配置拒绝；16/44.1/96kHz各频段中心自身响应0.98..1.02、其他档低于0.02 |
| 凸柱体多麦可见路径数不能取平均当镜像数 | 使用闭式候选反射词数，保留每麦路径计数；梯形63/61和五边形64/65用例验证 |
| spectralSamples类型声明与wet字段不一致 | 报告默认wet:null，生成音频时覆盖，加入运行时和TypeScript检查 |
| 最大柱体反射树重复枚举 | 渲染与报告共享已验证路径；镜像计数不再分配整个树；返回路径的可变次数数组深复制 |
| 构建来源可能误用祖先仓库、unknown当clean | 校验Git顶层，未知记null，发布门禁要求确知git且dirty严格等于false |
| 消费脚本固定旧版、来源hash被排除 | 动态读取moon.mod；公共来源清单迁至docs/provenance并随各类包分发 |

## 实际验证与复现

- MoonBit JS、Wasm、Wasm GC 各31项测试通过；Linux Native由对应提交CI执行，不宣称本机Windows Native已运行。
- Node测试涵盖原数值对照、SDK、独占目录、磁盘中断、畸形WAV、频段波形和声明一致性；完整结果以该提交运行输出为准。
- 原AudioLabs 103场景、155130个Float64样本仍通过，同一采样索引、无归一化/拟合。
- 新模式12份独立SciPy完整波形、29786样本，本地三个后端最大误差4.164e-17以下；另36组气象输入对照。
- 频段中心响应检验独立于“同一滤波设计波形一致”检验，避免把共同设计缺陷藏在参考对照中。
- 三个真实CLI流程：频段处理前、处理后、凸梯形。Float32 RIR与报告驱动的独立重建最大误差约3.320e-9，模拟录音与SciPy卷积约1.859e-9。
- 上述文件重建使用报告路径几何；不冒充独立高阶几何预言机。几何另由既有pyroomacoustics/BFS/反射定律/矩形闭式检查。
- 实际Edge Wasm GC工作台九场景通过，包含解码、下载、输入变更失效、取消重启、Blob回收及手机布局；不是全程人工听审。
- 独立运行包含源码版本、来源SHA、许可证和文件校验值；真实CLI与SDK消费通过后再用于发布。

```sh
moon check --target all --deny-warn
moon test --target js --deny-warn
moon test --target wasm --deny-warn
moon test --target wasm-gc --deny-warn
moon run cmd/reference-parity --target wasm-gc --deny-warn
node scripts/build-sdk.mjs
node --test tests/*.test.mjs
node scripts/build-release.mjs --require-clean
node scripts/test-distribution.mjs
moon package
python scripts/test-moon-package.py
```

本地归档用moon.work验证；正式注册表发布后另运行
`python scripts/test-registry-package.py`：新工程无workspace、精确版本安装、匿名官方ZIP和缓存ZIP对注册表SHA256、安装目录与ZIP逐文件比较，再运行四个公开消费测试。
此项只能在实际注册表安装成功后宣称完成。测试输出留在generated/registry-consumer，公开发布说明记录结果。

工具链 moon 0.1.20261021 / moonc 0.10.17+093cb8f9c，Node24；服务端发布预检返回202和“Dry run completed successfully”，当前CLI仍异常退出1。该退出码不当成实际发布成功证据，发布后以注册表真实下载及安装校验确认。

## 尚未关闭的边界

没有外部客户采用或真实房间测量证据，没有障碍物、散射/绕射、多声源时序调度、移动声源、任意多面体或HRTF。
六频段首末为搁架、中心频率近似，不是标准认证滤波器或连续频率精确材料；温度只影响空气损耗，声速单独设置。
长音频仍需按目标设备实测内存，采样预算不等于固定内存上限；FFT库和运行时GC仍有开销。

是否已覆盖评委认为必要的核心范围，以及旧项目补正后的申报类别/季度资格，需要主办方确认。
当前官网支持未通过项目修改原表、按有效提交/修改时间归属；首页未明确“本月必须10次”数字要求，表单相关口径仍待核对。
所有提交按实际功能/修复形成，不以空提交或无意义拆分补数量。申报书仍需同步这次新增能力与移植来源，不能沿用旧范围宣称新版已经获批。
