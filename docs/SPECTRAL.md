# 六频带材料与空气衰减

`model: "octave_bands"` 是显式的新渲染模式，支持矩形和严格凸柱体。
它不改变 `audiolabs_v030` 的插值、压力系数、滤波或时间轴。

每墙输入六个**能量吸声**系数，对应125、250、500、1000、2000、4000Hz。
逐条有效路径先按墙命中次数计算压力系数乘积，再按该路径实际长度施加
`10^(-air_db_per_m[band]*distance/20)`。这不同于给最终宽带录音套全局EQ：
不同墙、反射次数、距离的路径具有不同的频谱。

六个分数延迟RIR通过互补Hamming FIR合成（16kHz默认513tap）。五个低通由
MoonSpectrum设计，切点为相邻中心频率的几何均值，中间滤波器为低通之差，
最低/最高频段分别延伸至DC/Nyquist。滤波器之和是一个单位延迟脉冲。
这是有限长度的工程近似，不宣称IEC61260认证；最高频段以4000Hz参数代表
整个高搁架，不进行更高频率的空气衰减外推。推荐16kHz语音/原型实验。

统一延迟为 `half_width + band_filter_half_width`，默认272采样；输出长度为
`ceil(fs*duration_ms/1000) + 2*half_width + 2*band_filter_half_width`，保留完整尾部。
频谱恒定材料、零空气损耗时，结果退化为原RIR按已知FIR延迟平移后的波形。
不会自动对齐、限幅或归一化通道。

可手动指定六个 `air_db_per_m`，或用 `atmosphere` 自动计算，二者互斥：

```json
{"temperature_c":20,"relative_humidity_percent":50,"pressure_kpa":101.325}
```

温度为摄氏度，湿度为百分数（50，不是0.5），压力为kPa。计算按固定
Python Acoustics ISO9613-1方程源码移植/适配，BSD-3-Clause声明和固定SHA见
`licenses/python-acoustics-BSD.txt`、`provenance/python-acoustics.json`。
方程的水汽摩尔浓度使用百分数，验证时调用该上游底层函数并显式传入百分数，
没有混用fraction/percent。范围限-20..50°C、10..100%RH、80..110kPa。
这不是标准合规认证、现场校准或室内测量精度保证。
`atmosphere` 只改变空气损耗；传播声速仍由 `speed` 显式给定，默认343m/s。

资源边界：16..96kHz；band FIR半宽默认及最小为ceil(256*fs/16000)，
上限4096。高采样率自动增加核长度，显式欠分辨组合会失败，避免低频材料频段
严重串扰。另测16/44.1/96kHz每个中心频率的自身频段响应在0.98..1.02内、
其他频段贡献绝对值低于0.02。六频带中间采样预算合计不超过
一百万。其余几何、接收点、输出及卷积预算继续生效。`paths[].gain` 仅表示
几何扩散；材料和空气作用后的有效压力增益见 `band_paths[].band_gains`。
路径明细超过10000时显式截断，直达声另行保留，波形仍使用全部已接纳贡献。

独立验证使用第一阶解析镜像几何、SciPy `firwin`/`fftconvolve` 以及固定上游
大气方程：12份完整Float64波形、29786个样本，另36组气象条件。
三种可移植后端和CI的Native目标执行同一组golden。测试参考数据不计实现规模。
这些仍是合成/数值证据，没有外部采用或真实房间测量证明。
