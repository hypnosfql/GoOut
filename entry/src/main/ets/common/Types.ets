/** 协议类型（一期支持的出站协议） */
export enum Protocol {
  VLESS = 'vless',
  VMESS = 'vmess',
  SHADOWSOCKS = 'ss',
  TROJAN = 'trojan',
}

/** 路由模式 */
export enum RoutingMode {
  GLOBAL = 'global',       // 全局代理
  BYPASS_CN = 'bypass_cn', // 绕过大陆
  DIRECT = 'direct',       // 全局直连（调试用）
}

/** 内核运行状态 */
export enum CoreState {
  STOPPED = 'stopped',
  STARTING = 'starting',
  RUNNING = 'running',
  STOPPING = 'stopping',
  ERROR = 'error',
}

/** 节点配置（分享链接解析后的统一模型） */
export interface NodeProfile {
  id: string;              // 唯一 id（时间戳+随机）
  name: string;            // 显示名（remarks）
  protocol: Protocol;
  server: string;
  port: number;
  // 通用安全/传输参数（按需使用）
  uuid?: string;           // vless/vmess 用户 id
  password?: string;       // trojan/ss 密码
  flow?: string;           // vless flow: xtls-rprx-vision
  security?: string;       // tls | reality | none
  sni?: string;
  fingerprint?: string;    // uTLS 指纹
  publicKey?: string;      // reality publicKey
  shortId?: string;        // reality shortId
  spiderX?: string;        // reality spiderX
  network?: string;        // tcp | ws | grpc
  path?: string;           // ws path / grpc serviceName
  host?: string;           // ws host
  method?: string;         // ss 加密方式
  alterId?: number;        // vmess alterId (默认 0, AEAD)
  subId?: string;          // 来源订阅 id（手动添加为空）
  delay?: number;          // 最近测速结果 ms，-1 未测/失败
}

/** 订阅 */
export interface SubscriptionItem {
  id: string;
  name: string;
  url: string;
  updatedAt: number;       // 最近更新时间戳，0 未更新
  nodeCount: number;
}

/** 工作模式 */
export enum WorkMode {
  VPN = 'vpn',     // VPN 全代理（需要系统 TUN 支持，真机）
  PROXY = 'proxy', // 仅本地代理（调试用，模拟器可跑通内核全链路）
}

/** 应用设置 */
export interface AppSettings {
  workMode: WorkMode;
  routingMode: RoutingMode;
  socksPort: number;       // 本地 socks5 入站端口，默认 10808
  dnsRemote: string;       // 远端 DNS，默认 1.1.1.1
  dnsDirect: string;       // 直连 DNS，默认 223.5.5.5
  logLevel: string;        // debug/info/warning/error
  ipv6: boolean;           // 是否启用 IPv6（默认关，省资源）
}

export const DEFAULT_SETTINGS: AppSettings = {
  workMode: WorkMode.VPN,
  routingMode: RoutingMode.BYPASS_CN,
  socksPort: 10808,
  dnsRemote: '1.1.1.1',
  dnsDirect: '223.5.5.5',
  logLevel: 'warning',
  ipv6: false,
};
