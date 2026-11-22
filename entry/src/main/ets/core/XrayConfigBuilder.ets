import { AppSettings, NodeProfile, Protocol, RoutingMode } from '../common/Types';

// ---------- xray 配置显式类型（ArkTS 严格模式要求） ----------
interface XrayLog {
  loglevel: string;
}

interface XraySniffing {
  enabled: boolean;
  destOverride: string[];
  routeOnly: boolean;
}

interface XraySocksSettings {
  auth: string;
  udp: boolean;
  ip: string;
}

interface XrayInbound {
  tag: string;
  listen: string;
  port: number;
  protocol: string;
  settings: XraySocksSettings;
  sniffing: XraySniffing;
}

interface XrayVlessUser {
  id: string;
  encryption: string;
  flow?: string;
  security?: string;
}

interface XrayVmessUser {
  id: string;
  alterId: number;
  security: string;
}

interface XrayVnextVless {
  address: string;
  port: number;
  users: XrayVlessUser[];
}

interface XrayVnextVmess {
  address: string;
  port: number;
  users: XrayVmessUser[];
}

interface XrayServerEntry {
  address: string;
  port: number;
  method?: string;
  password?: string;
}

interface XrayBlackholeSettings {
  response: XrayBlackholeResponse;
}

interface XrayBlackholeResponse {
  type: string;
}

/** 出站 settings 全字段可选并集（按协议取所需字段） */
interface XrayOutboundSettings {
  vnext?: XrayVnextVless[] | XrayVnextVmess[];
  servers?: XrayServerEntry[];
  domainStrategy?: string;
  response?: XrayBlackholeResponse;
}

interface XrayTlsSettings {
  serverName: string;
  fingerprint: string;
  allowInsecure: boolean;
}

interface XrayRealitySettings {
  serverName: string;
  fingerprint: string;
  publicKey: string;
  shortId: string;
  spiderX: string;
}

interface XrayWsSettings {
  path: string;
  headers: XrayWsHeaders;
}

interface XrayWsHeaders {
  Host: string;
}

interface XrayGrpcSettings {
  serviceName: string;
  multiMode: boolean;
}

interface XrayTcpHeaderRequest {
  path: string[];
  headers: XrayTcpHeaders;
}

interface XrayTcpHeaders {
  Host: string[];
}

interface XrayTcpHeader {
  type: string;
  request: XrayTcpHeaderRequest;
}

interface XrayTcpSettings {
  header: XrayTcpHeader;
}

interface XrayStreamSettings {
  network: string;
  security: string;
  tlsSettings?: XrayTlsSettings;
  realitySettings?: XrayRealitySettings;
  wsSettings?: XrayWsSettings;
  grpcSettings?: XrayGrpcSettings;
  tcpSettings?: XrayTcpSettings;
}

interface XrayOutbound {
  tag: string;
  protocol: string;
  settings: XrayOutboundSettings;
  streamSettings?: XrayStreamSettings;
}

interface XrayRoutingRule {
  type: string;
  outboundTag: string;
  ip?: string[];
  domain?: string[];
  network?: string;
}

interface XrayRouting {
  domainStrategy: string;
  rules: XrayRoutingRule[];
}

interface XrayDnsServer {
  address: string;
  domains?: string[];
  skipFallback?: boolean;
}

interface XrayDns {
  servers: XrayDnsServer[];
  queryStrategy: string;
}

interface XrayPolicyLevel {
  handshake: number;
  connIdle: number;
  uplinkOnly: number;
  downlinkOnly: number;
  bufferSize: number;
}

interface XrayPolicyLevels {
  '0': XrayPolicyLevel;
}

interface XrayPolicySystem {
  statsInboundUplink: boolean;
  statsInboundDownlink: boolean;
}

interface XrayPolicy {
  levels: XrayPolicyLevels;
  system: XrayPolicySystem;
}

interface XrayConfig {
  log: XrayLog;
  dns: XrayDns;
  inbounds: XrayInbound[];
  outbounds: XrayOutbound[];
  routing: XrayRouting;
  policy: XrayPolicy;
}

/** 根据节点 + 设置生成 xray JSON 配置 */
export class XrayConfigBuilder {
  static build(node: NodeProfile, settings: AppSettings): string {
    const config: XrayConfig = {
      log: { loglevel: settings.logLevel },
      dns: XrayConfigBuilder.buildDns(settings),
      inbounds: [XrayConfigBuilder.buildSocksInbound(settings.socksPort)],
      outbounds: [
        XrayConfigBuilder.buildOutbound(node),
        { tag: 'direct', protocol: 'freedom', settings: { domainStrategy: 'UseIP' } },
        { tag: 'block', protocol: 'blackhole', settings: { response: { type: 'http' } } },
      ],
      routing: XrayConfigBuilder.buildRouting(settings.routingMode),
      policy: {
        levels: {
          '0': { handshake: 4, connIdle: 300, uplinkOnly: 1, downlinkOnly: 1, bufferSize: 512 },
        },
        system: { statsInboundUplink: true, statsInboundDownlink: true },
      },
    };
    return JSON.stringify(config);
  }

  // ---------------- inbound ----------------
  private static buildSocksInbound(port: number): XrayInbound {
    return {
      tag: 'socks-in',
      listen: '127.0.0.1',
      port,
      protocol: 'socks',
      settings: { auth: 'noauth', udp: true, ip: '127.0.0.1' },
      sniffing: {
        enabled: true,
        destOverride: ['http', 'tls', 'quic'],
        routeOnly: true,
      },
    };
  }

  // ---------------- outbound ----------------
  private static buildOutbound(node: NodeProfile): XrayOutbound {
    switch (node.protocol) {
      case Protocol.VLESS:
        return XrayConfigBuilder.buildVless(node);
      case Protocol.VMESS:
        return XrayConfigBuilder.buildVmess(node);
      case Protocol.SHADOWSOCKS:
        return XrayConfigBuilder.buildSs(node);
      case Protocol.TROJAN:
        return XrayConfigBuilder.buildTrojan(node);
    }
  }

  private static buildVless(node: NodeProfile): XrayOutbound {
    const user: XrayVlessUser = { id: node.uuid ?? '', encryption: 'none' };
    if (node.flow) {
      user.flow = node.flow;
    }
    if (node.security && node.security !== 'none') {
      user.security = node.security;
    }
    const vnext: XrayVnextVless[] = [{
      address: node.server,
      port: node.port,
      users: [user],
    }];
    return {
      tag: 'proxy',
      protocol: 'vless',
      settings: { vnext },
      streamSettings: XrayConfigBuilder.buildStream(node),
    };
  }

  private static buildVmess(node: NodeProfile): XrayOutbound {
    const vnext: XrayVnextVmess[] = [{
      address: node.server,
      port: node.port,
      users: [{
        id: node.uuid ?? '',
        alterId: node.alterId ?? 0,
        security: 'auto',
      }],
    }];
    return {
      tag: 'proxy',
      protocol: 'vmess',
      settings: { vnext },
      streamSettings: XrayConfigBuilder.buildStream(node),
    };
  }

  private static buildSs(node: NodeProfile): XrayOutbound {
    const servers: XrayServerEntry[] = [{
      address: node.server,
      port: node.port,
      method: node.method ?? 'aes-128-gcm',
      password: node.password ?? '',
    }];
    return {
      tag: 'proxy',
      protocol: 'shadowsocks',
      settings: { servers },
    };
  }

  private static buildTrojan(node: NodeProfile): XrayOutbound {
    const servers: XrayServerEntry[] = [{
      address: node.server,
      port: node.port,
      password: node.password ?? '',
    }];
    return {
      tag: 'proxy',
      protocol: 'trojan',
      settings: { servers },
      streamSettings: XrayConfigBuilder.buildStream(node),
    };
  }

  // ---------------- streamSettings ----------------
  private static buildStream(node: NodeProfile): XrayStreamSettings {
    const network = node.network ?? 'tcp';
    const security = node.security ?? 'none';
    const stream: XrayStreamSettings = { network, security };
    if (security === 'tls') {
      stream.tlsSettings = {
        serverName: node.sni || node.host || node.server,
        fingerprint: node.fingerprint || 'chrome',
        allowInsecure: false,
      };
    } else if (security === 'reality') {
      stream.realitySettings = {
        serverName: node.sni || 'www.microsoft.com',
        fingerprint: node.fingerprint || 'chrome',
        publicKey: node.publicKey ?? '',
        shortId: node.shortId ?? '',
        spiderX: node.spiderX ?? '',
      };
    }
    if (network === 'ws') {
      stream.wsSettings = {
        path: node.path || '/',
        headers: { Host: node.host || node.sni || node.server },
      };
    } else if (network === 'grpc') {
      stream.grpcSettings = {
        serviceName: node.path ?? '',
        multiMode: false,
      };
    } else if (network === 'tcp' && node.host) {
      stream.tcpSettings = {
        header: {
          type: 'http',
          request: {
            path: [node.path || '/'],
            headers: { Host: [node.host] },
          },
        },
      };
    }
    return stream;
  }

  // ---------------- routing ----------------
  private static buildRouting(mode: RoutingMode): XrayRouting {
    if (mode === RoutingMode.GLOBAL) {
      return {
        domainStrategy: 'AsIs',
        rules: [{ type: 'field', network: 'tcp,udp', outboundTag: 'proxy' }],
      };
    }
    if (mode === RoutingMode.DIRECT) {
      return {
        domainStrategy: 'AsIs',
        rules: [{ type: 'field', network: 'tcp,udp', outboundTag: 'direct' }],
      };
    }
    // bypass_cn：私网/大陆直连，其余代理
    return {
      domainStrategy: 'IPIfNonMatch',
      rules: [
        { type: 'field', ip: ['geoip:private'], outboundTag: 'direct' },
        { type: 'field', domain: ['geosite:cn'], outboundTag: 'direct' },
        { type: 'field', ip: ['geoip:cn'], outboundTag: 'direct' },
        { type: 'field', network: 'tcp,udp', outboundTag: 'proxy' },
      ],
    };
  }

  // ---------------- dns ----------------
  private static buildDns(settings: AppSettings): XrayDns {
    const queryStrategy = settings.ipv6 ? 'UseIP' : 'UseIPv4';
    if (settings.routingMode === RoutingMode.BYPASS_CN) {
      const servers: XrayDnsServer[] = [
        { address: settings.dnsDirect, domains: ['geosite:cn'], skipFallback: true },
        { address: settings.dnsRemote },
      ];
      return { servers, queryStrategy };
    }
    const servers: XrayDnsServer[] = [
      { address: settings.dnsRemote },
      { address: settings.dnsDirect },
    ];
    return { servers, queryStrategy };
  }
}
