# GoOut — 鸿蒙原生 Xray 客户端方案

> 目标：HarmonyOS NEXT 原生（ArkTS/ArkUI）VPN 客户端，内核 xray-core，
> 交互参考 v2rayNG 但只保留常用功能，资源占用尽可能小。

## 1. 总体架构

```
┌─────────────────────────────────────────────────────┐
│ ArkTS UI 层（Index/节点列表/添加/订阅/设置/日志）      │
├─────────────────────────────────────────────────────┤
│ 服务层（ArkTS）                                      │
│  ├─ GoOutVpnExtensionAbility (vpnExtension)          │
│  │    ├─ 创建 VpnConnection（tun fd、路由、DNS）       │
│  │    └─ protect(fd) 放行内核出网 socket              │
│  └─ CoreManager（启停内核、状态机、事件上报 UI）        │
├─────────────────────────────────────────────────────┤
│ Native 层（C/C++，OHOS NDK，NAPI 桥接）               │
│  ├─ libxray.so   ← libXray cgo 封装（xray-core）      │
│  │    入口: CGoInvoke(json) → json                   │
│  │    开 SOCKS5 入站 127.0.0.1:10808                  │
│  └─ libhev.so    ← hev-socks5-tunnel                 │
│         tun fd ⇄ socks5，单线程、极轻量               │
└─────────────────────────────────────────────────────┘
```

数据流：
`App 流量 → VPN tun fd → libhev(hev-socks5-tunnel) → xray SOCKS5 入站 → xray 出站(VLESS/REALITY 等) → protect() 后的真实网卡`

这是 v2rayNG 验证过的模式：xray 不直接处理 tun，桥接交给约几百 KB 的 C 库，省内存且稳定。

## 2. 功能范围（做 / 不做）

### 做（v2rayNG 常用功能子集）

| 模块 | 功能 |
|------|------|
| 节点管理 | 节点列表、URL/剪贴板导入（vless/vmess/ss/trojan）、二维码扫描、编辑、删除 |
| 订阅 | 订阅链接添加、手动更新、节点列表合并 |
| 连接 | 一键连接/断开、连接状态/流量显示、节点切换自动重连 |
| 测速 | 真连接延迟测试（libXray Ping）、结果排序 |
| 路由 | 三选一：全局 / 绕过大陆(geoip+geosite) / 仅代理浏览器类（可选） |
| 协议出站 | VLESS(+REALITY/XTLS Vision)、VMess、Shadowsocks、Trojan |
| 日志 | 内核日志查看（等级可调） |
| 设置 | 本地端口、路由模式、DNS、日志等级 |

### 不做（明确裁剪，控制体积与内存）

- 自定义完整 JSON 配置编辑器、多入站
- 负载均衡 / fallback 策略组
- WebDAV 备份、局域网共享、root 模式、TProxy
- 多用户/流量统计售卖功能
- Hysteria2/TUIC/WireGuard 出站（xray 本身支持有限，后续按需再加）
- 桌面端/平板多窗口适配（一期只做手机）

## 3. 关键技术点

### 3.1 xray-core → libxray.so（本项目最大风险项）

- 采用官方封装 **libXray**（`CGoInvoke(json)` 单入口），不自己造 FFI。
- Go 官方不支持 openharmony 目标，需用社区移植工具链
  （OpenHarmony-SIG 的 Go fork / 或 `GOOS=android` + OHOS NDK clang 链接的方案，
  ClashBox(mihomo) 已验证 Go 内核可在鸿蒙 NEXT 运行）。
- 产物：`lib/arm64-v8a/libxray.so`，经 NAPI 薄封装给 ArkTS 调用。
- **M0 必须先做 PoC**：hello-cgo .so → ArkTS NAPI 加载调用，再编 libXray。
  若工具链不通，方案整体降级为「内置 sing-box/其他已适配鸿蒙的内核」再评估。

### 3.2 VPN 通道

- 使用 `@kit.NetworkKit` 的 **VpnExtensionAbility**：
  `createVpnConnection()` 拿 tun fd，`protect(fd)` 放行内核 socket，防回环。
- VPN 配置：地址 10.0.0.2/32（或 26.26.26.1/30），MTU 1500，路由 0.0.0.0/0，
  DNS 223.5.5.5 / 1.1.1.1。
- tun fd 通过 NAPI 传给 libhev 启动桥接。

### 3.3 hev-socks5-tunnel

- v2rayNG 同款（其仓库自带 `compile-hevtun.sh`），C 实现、单线程 epoll，
  内存常驻约 1–2 MB，直接用 OHOS NDK 编译。

### 3.4 配置生成

- ArkTS 侧解析分享链接 → 生成 xray JSON（入站 socks5 10808 + 单出站 + 路由规则），
  参考 v2rayNG 的 `core/CoreOutboundBuilder.kt` 逻辑，只保留三种路由模式模板。
- geo 数据：用社区精简版 geoip/geosite（Loyalsoldier），放 rawfile，
  路由选「绕过大陆」时才加载（xray 侧按需 include，降低内存）。

## 4. 资源占用优化（对应要求 1）

| 层面 | 措施 |
|------|------|
| Go 运行时 | 启用 libXray 的 `InitForceFree`（定期 FreeOSMemory）；`debug.SetGCPercent(50)` + `debug.SetMemoryLimit(~64MB)` |
| 内核 | 用 libXray 的 nodep 精简依赖路径编译；只保留所需协议 |
| tun 桥 | hev-socks5-tunnel（C，单线程），不用 Go 版 tun2socks |
| geo 数据 | 精简版 geosite（仅 cn 分类相关），绕过大陆模式才全量生效 |
| UI | 列表用 LazyForEach；延迟测试并发限流；无后台轮询，事件驱动（Emitter/NSNotification） |
| 进程 | VPN 扩展能力运行在独立 extension 进程，UI 被杀不影响代理 |
| 包体 | release 开启混淆/裁剪；.so 仅保留 arm64-v8a |

## 5. 模块划分（在现有工程上落地）

```
entry/src/main/ets/
├─ pages/
│  ├─ Index.ets            # 主界面：连接按钮 + 节点列表（参考 v2rayNG 主界面）
│  ├─ NodeEditPage.ets     # 添加/编辑节点
│  ├─ SubscriptionPage.ets # 订阅管理
│  ├─ LogPage.ets          # 日志
│  └─ SettingsPage.ets     # 设置
├─ core/
│  ├─ CoreManager.ets      # 内核启停、状态机
│  ├─ XrayConfigBuilder.ets# 分享链接 → xray JSON
│  ├─ ShareLinkParser.ets  # vless:// vmess:// ss:// trojan:// 解析
│  └─ PingTester.ets       # 延迟测试
├─ vpnext/
│  └─ GoOutVpnExtAbility.ets
├─ store/
│  ├─ NodeStore.ets        # 节点持久化（Preferences）
│  └─ SettingsStore.ets
└─ common/                 # 常量、类型、工具

entry/src/main/cpp/
├─ napi_init.cpp           # NAPI 注册：startXray/stopXray/ping/startHev/stopHev
├─ third_party/libxray.so  # 预编译产物（M1 输出）
└─ third_party/hev/        # hev-socks5-tunnel 源码编译
```

## 6. 里程碑

| 阶段 | 内容 | 验收 | 状态 |
|------|------|------|------|
| M0 | Go→OHOS .so 工具链 PoC | ArkTS 通过 NAPI 调到 cgo 导出函数 | ✅ 完成（clang argv[0] 推导 target + cfg sysroot + android stub） |
| M1 | 编译 libxray.so + NAPI 封装 | ArkTS 调用 RunXray 成功，日志输出版本号 | ✅ 完成（libXray 后端，UI 显示 xray 26.11.9） |
| M2 | libhev + VpnExtensionAbility 打通 | 连上节点后浏览器可访问外网 | ⚠️ 模拟器无 TUN/无 vpndialog，代理模式验证内核全链路通过，VPN 待真机 |
| M3 | 主界面 + 节点管理（导入/编辑/连接） | 完整手动节点使用闭环 | ✅ 完成（模拟器 uitest 自动化验证） |
| M4 | 订阅更新 + 测速 + 三种路由模式 | 订阅用户全流程可用 | ✅ 完成（订阅 2 节点入库、测速显示、路由模式实现） |
| M5 | 内存/包体优化、日志页、稳定性打磨 | 后台 1h 内存稳定，无泄漏增长 | 🔶 部分（GC 调优已内建；裁剪/日志待续） |

## 模拟器环境限制（M2 关键结论）

公共模拟器镜像**无 TUN 设备、无 vpndialog 系统组件**，VPN 模式无法端到端跑通。
解决方案：① settingsdata 预授权跳过弹窗（MANAGE_SETTINGS ACL）；② 增加“仅代理模式”
在模拟器验证内核全链路；③ VPN 链路留真机验证。

## 7. 依赖与来源

| 组件 | 来源 | 用途 |
|------|------|------|
| xray-core | github.com/XTLS/Xray-core | 代理内核 |
| libXray | github.com/XTLS/libXray | cgo 封装（CGoInvoke） |
| hev-socks5-tunnel | github.com/heiher/hev-socks5-tunnel | tun→socks5 桥 |
| geoip/geosite | Loyalsoldier 精简版 | 分流规则 |
| Go for OHOS 工具链 | OpenHarmony-SIG 移植 | M0 验证重点 |
