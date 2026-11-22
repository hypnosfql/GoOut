# GoOut

HarmonyOS 原生代理客户端，内核基于 [Xray-core](https://github.com/XTLS/xray-core)

## 特性

- **协议**：VLESS（含 REALITY / XTLS Vision）、VMess、Shadowsocks、Trojan
- **订阅**：链接列表（base64）与 **Clash YAML**（block / flow 两种风格）双格式，按订阅分组展示节点，默认折叠、可展开
- **导入**：分享链接（vless:// vmess:// ss:// trojan://）文本 / 剪贴板导入
- **路由**：绕过大陆（geoip/geosite 精简分流）、全局代理、全局直连
- **测速**：真连接延迟测试（libXray pingBatch，并发限流）
- **双工作模式**：
  - **VPN 模式**：VpnExtensionAbility + hev-socks5-tunnel 全系统代理（真机）
  - **代理模式**：本机 SOCKS5 入站（开发/模拟器调试）
- **低资源占用**：Go 侧 GC 调优（SetGCPercent 50 / SetMemoryLimit 96MB / 定期 FreeOSMemory），tun 桥用 C 实现单线程 hev-socks5-tunnel

## 架构

```
ArkTS UI ── CoreManager ─┬─ VPN 模式 → GoOutVpnExtAbility(独立进程)
                         └─ 代理模式 → XrayBridge(NAPI)
NAPI(libgooutcore.so) ──┬─ invoke → CGoInvoke → libgoout.so(libXray + xray-core)
                        └─ startHev → hev-socks5-tunnel(tun ⇄ socks5)
```

详细设计见 `docs/plan.md`。

## 构建

前置：DevEco Studio 26（含 HarmonyOS SDK / NDK）。Go 工具链由脚本自动准备。

### 1. 环境准备（二次开发第一步）

```bash
bash native/scripts/setup.sh
```

该脚本自动完成：
- 下载 Go 1.27.4 工具链（项目内 `.tmp/`，不污染系统）
- 应用 OHOS 移植补丁（Go 官方不支持 openharmony 目标，以 GOOS=android 交叉编译，需修补两处标准库源码，脚本幂等处理）
- 下载 Go 依赖（libXray / xray-core）

加 `--build` 参数可在准备环境后直接编译全部 ABI 内核：

```bash
bash native/scripts/setup.sh --build
```

### 2. 编译内核 libgoout.so

```bash
bash native/scripts/build-go-so.sh x86_64    # 模拟器
bash native/scripts/build-go-so.sh aarch64   # 真机
bash native/scripts/build-go-so.sh all       # 全部 ABI
```

### 3. 构建 HAP + 签名 + 安装到模拟器 + 启动

```bash
bash native/scripts/deploy.sh --start
```

签名使用 SDK 自带 OpenHarmony 调试证书（仅开发调试用）。

## 测试

```bash
# 运行单元测试（Hypium LocalUnit，宿主机执行，生成覆盖率报告）
hvigorw test --mode module -p product=default
# 覆盖率报告: entry/.test/default/outputs/test/reports/index.html
```

当前 41 个用例 100% 通过；核心业务模块覆盖率：
XrayConfigBuilder 100% / ClashYamlParser 93.7% / ShareLinkParser 90.5%。

## 提交规范

采用 [Conventional Commits](https://www.conventionalcommits.org/)：

```
feat: 新功能        fix: 缺陷修复      refactor: 重构
perf: 性能优化      test: 测试相关      docs: 文档
build: 构建/依赖    ci: 持续集成        chore: 杂项
```

**提交前必须通过全部单元测试**。安装 pre-commit 钩子（自动执行 `hvigorw test`，失败即拒绝提交）：

```bash
bash scripts/install-hooks.sh
```

## 目录

```
entry/src/main/ets/     ArkTS 源码（pages / core / store / vpnext）
entry/src/main/cpp/     NAPI 模块与 hev-socks5-tunnel
entry/src/test/         单元测试（Hypium LocalUnit）
native/gooutbridge/     Go 桥接（libXray cgo 封装）
native/scripts/         交叉编译与部署脚本
docs/                   方案与开发记录
```

## License

GPL-3.0
