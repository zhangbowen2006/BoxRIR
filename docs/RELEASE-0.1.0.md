# 0.1.0 发布记录

- 实际账号：zhangbowen2006，GitHub与Mooncakes均经终端核验。
- 仓库：https://github.com/zhangbowen2006/BoxRIR ，PUBLIC，默认main。
- 代码标签：[v0.1.0](https://github.com/zhangbowen2006/BoxRIR/tree/v0.1.0)，对应9523120542a2f4967b915a07e0510a15f3e18267。
- [四目标CI与部署](https://github.com/zhangbowen2006/BoxRIR/actions/runs/41169960989)均成功：Wasm/Wasm GC/JS/Native各12组测试、Node5组、独立SciPy核验和工作台构建。
- 包：https://mooncakes.io/docs/zhangbowen2006/boxrir@0.1.0 。服务端发布时间2026-10-31T04:48:52.483730Z，即北京时间12:48:52。
- SHA256：eff1522eb4e85096123554b7ca4c46c91f7faf190c4d0b5836d64dd373c26d7d；上传归档与注册表元数据一致。
- `moon publish --dry-run`：解压后检查通过，202 Accepted；`moon publish`：200 OK；`moon view ...@0.1.0 --json`：精确版本存在、未撤回。
- 独立临时模块执行 `moon add zhangbowen2006/boxrir@0.1.0`，从注册表下载后调用scene/images/render/convolve；断言7镜像、1632卷积帧、16采样延迟，实际运行通过。
- 在线工作台：https://zhangbowen2006.github.io/BoxRIR/ 。部署作业成功，页面、app、worker、编译核心、场景JSON和示例WAV均HTTP200。

本地浏览器交互已实测，包括Worker计算、结果展示及原始/模拟音频解码加载。线上页面的浏览器自动化访问超时，未将HTTP状态等同于完成线上交互验收；本地下载事件也被浏览器工具取消，未声称自动化下载成功。CLI生成的文件已实际验证，网页中的下载数据由同一核心生成。

随后修复了显式模拟请求的空WAV处理并发布0.1.1，见RELEASE-0.1.1.md；不是为文档另发版本。发布成功不是报名、初审或获奖通知。
