# TizLink for HarmonyOS NEXT (纯血鸿蒙版)

基于 `docs/TizLink-v2.0.20-android.apk` 深度逆向分析与原生重构的 **纯血鸿蒙 (HarmonyOS NEXT / API 12+)** 客户端，使用 **原生 ArkTS / ArkUI (Stage Model)** + **HarmonyOS `VpnExtensionAbility`** + **C++ N-API** + **交叉编译原生 Mihomo 内核 (`arm64-v8a` musl)** 实现。

## 核心架构

```
ArkUI (Index / Auth / Connect / Nodes / Plans / Account / WebSupport)
  │
  ├── ApiService (WHMCS v2raysocks_client.php + V2Board /api/v1 + 订阅下载)
  ├── SubscriptionParser (aegis://, vless://, vmess://, trojan://, ss://, hy2://, tuic://, anytls://, socks5://, Clash YAML)
  ├── MihomoConfigBuilder (自动生成 DNS Fake-IP / 分流规则 / 链式代理 dialer-proxy YAML)
  ├── MihomoControllerService (127.0.0.1:9090 节点热切换 / 延迟测速 / 模式切换 + TCP Ping)
  │
  └── VpnManager ──► TizLinkVpnExtensionAbility (@kit.NetworkKit vpnExtension)
                         │  TUN fd (172.19.0.1/30, DNS 172.19.0.2, MTU 1500)
                         │  Socket protect(fd) 回调桥接 + 分应用代理 (blocked/trustedApplications)
                         ▼
                   libtizlink_native.so (C++ N-API, entry/src/main/cpp/napi_init.cpp)
                         │  dlopen + napi_threadsafe_function protect 同步桥
                         ▼
                   libmihomo.so (Go c-shared, github.com/yeeeku/mihomo@v1.19.25-aegis-mux2, aarch64-linux-ohos)
                         │  with_gvisor + sing-tun + Aegis-Stream Mux2 + GeoData (country.mmdb/geoip.dat/geosite.dat)
```

## 已复刻功能清单

- **账户体系**：支持 **TizLink 默认 WHMCS 线路** (`v2raysocks_client.php`)、**V2Board 后端** (`/api/v1/...`)、以及**免登录直连订阅模式**；包含登录、注册（邮箱验证码 + 邀请码）、重置密码、修改密码、退出登录。
- **连接控制**：深色暗夜玻璃拟态 UI（响应式适配手机底部胶囊栏 & 平板/折叠屏/2in1 左侧边栏），一键启停系统 VPN 隧道、实时上下行速率与累计流量统计、出口 IP 检测、智能分流 (`rule`) / 全局代理 (`global`) 一键切换。
- **节点管理**：自动最优节点 (`AUTO` url-test)、国家/地区识别、协议标签 (`AEGIS` / `VLESS` / `VMESS` / `TROJAN` / `SS` / `HY2` / `TUIC` / `ANYTLS` / `SOCKS5`)、批量与单节点延迟测速、节点热切换、手动导入订阅链接/Clash YAML/节点 URI。
- **订阅与商店**：套餐方案展示、多周期（月付/季付/半年/年付/一次性/重置流量）选择、优惠码、支付方式获取、下单并通过 ArkWeb 跳转支付、我的订单查询与取消。
- **账户与高级设置**：订阅到期日与流量进度条、每月重置日、余额、设备 ID、邀请好友（邀请码与返利统计）、系统公告、Crisp 在线客服 (ArkWeb)、分应用代理 (Split Tunneling)、链式代理 (Chain Proxy `dialer-proxy`)、Fake-IP / IPv6 开关、中英双语切换、生成的 Mihomo YAML 配置查看器、Mihomo 内核实时日志查看器。

## 构建与运行

### 1. 重新编译 HarmonyOS 原生 `libmihomo.so`（已预编译内置于 `entry/libs/arm64-v8a/libmihomo.so`）

```bash
./mihomo-core/build_ohos.sh
```

### 2. 使用 DevEco Studio 构建与签名安装

1. 使用 **DevEco Studio** 打开本项目根目录 `/Users/jwli/workspace/github/tizlink`。
2. 在 **File -> Project Structure -> Signing Configs** 中勾选 **Automatically generate signature**（或在 `build-profile.json5` 配置您的 HarmonyOS 开发者签名证书与 Profile，注意申请真机 VPN 权限）。
3. 连接 HarmonyOS NEXT 真机后点击 **Run**，或使用命令行编译 HAP：

```bash
export DEVECO_SDK_HOME="/Applications/DevEco-Studio.app/Contents/sdk"
export PATH="/Applications/DevEco-Studio.app/Contents/tools/node/bin:/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin:/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin:$PATH"
ohpm install --all
hvigorw assembleHap --mode module -p product=default -p buildMode=debug
```
