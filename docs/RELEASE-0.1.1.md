# 0.1.1 发布记录

本版本修复显式模拟请求的空WAV文件处理：此前零字节文件会触发API的“仅生成RIR”分支；CLI和网页现在明确拒绝空文件。核心物理模型、API和正常示例数值未变化。这是实际行为修复，不是文档占位版本。

- GitHub与Mooncakes实际账号：zhangbowen2006。
- 源码标签：[v0.1.1](https://github.com/zhangbowen2006/BoxRIR/tree/v0.1.1)，对应1298d7d3fb0b11f8ebf4a26996a78eea3eccf5dd。
- [CI及在线部署](https://github.com/zhangbowen2006/BoxRIR/actions/runs/41171050128)全部通过，仍为四目标各12组、Node5组及SciPy新产物验证；CLI回归增加空文件必须报错且不生成目录的断言。
- 包：[zhangbowen2006/boxrir@0.1.1](https://mooncakes.io/docs/zhangbowen2006/boxrir@0.1.1)。服务端时间2026-10-31T05:05:10.508043Z，即北京时间13:05:10。
- 发布包SHA256：8c228be3810fd08843e68a818381950d483419b60663a2cc6efe1f63ae0ee41d，上传归档与注册表元数据一致。
- 发布前工作树保持干净；`moon publish --dry-run`解压检查通过/202，实际`moon publish`返回200，`moon view`确认未撤回。
- 独立临时模块升级到0.1.1后从注册表下载，公开API再次通过7镜像、1632帧、16采样延迟断言；发布归档中的CLI确实包含空文件拒绝逻辑。

在线静态资源已HTTP核验，本地浏览器交互与音频加载已实测；线上自动化访问的超时边界仍按0.1.0发布记录保留，不将其写成线上互动全部通过。未代提交报名或获得官方审核结论。
