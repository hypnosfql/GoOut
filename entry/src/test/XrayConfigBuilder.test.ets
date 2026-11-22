import { describe, it, expect } from '@ohos/hypium';
import { XrayConfigBuilder } from '../main/ets/core/XrayConfigBuilder';
import { AppSettings, DEFAULT_SETTINGS, NodeProfile, Protocol, RoutingMode, WorkMode } from '../main/ets/common/Types';

// 与产物 JSON 结构对齐的最小类型（只声明测试关心的字段）
interface CfgLog { loglevel: string }
interface CfgDnsServer { address: string; domains?: string[]; skipFallback?: boolean }
interface CfgDns { servers: CfgDnsServer[]; queryStrategy: string }
interface CfgSniffing { enabled: boolean }
interface CfgInbound { tag: string; listen: string; port: number; protocol: string; sniffing: CfgSniffing }
interface CfgVnextUser { id: string; encryption?: string; flow?: string; security?: string; alterId?: number }
interface CfgVnext { address: string; port: number; users: CfgVnextUser[] }
interface CfgServer { address: string; port: number; method?: string; password?: string }
interface CfgSettings {
  vnext?: CfgVnext[];
  servers?: CfgServer[];
  domainStrategy?: string;
}
interface CfgTls { serverName: string; fingerprint: string }
interface CfgReality { serverName: string; publicKey: string; shortId: string }
interface CfgWsHeaders { Host: string }
interface CfgWs { path: string; headers: CfgWsHeaders }
interface CfgGrpc { serviceName: string }
interface CfgTcpHeader { type: string }
interface CfgTcp { header: CfgTcpHeader }
interface CfgStream {
  network: string;
  security: string;
  tlsSettings?: CfgTls;
  realitySettings?: CfgReality;
  wsSettings?: CfgWs;
  grpcSettings?: CfgGrpc;
  tcpSettings?: CfgTcp;
}
interface CfgOutbound { tag: string; protocol: string; settings: CfgSettings; streamSettings?: CfgStream }
interface CfgRule { type: string; outboundTag: string; ip?: string[]; domain?: string[]; network?: string }
interface CfgRouting { domainStrategy: string; rules: CfgRule[] }
interface Cfg {
  log: CfgLog;
  dns: CfgDns;
  inbounds: CfgInbound[];
  outbounds: CfgOutbound[];
  routing: CfgRouting;
}

function mkNode(protocol: Protocol): NodeProfile {
  return {
    id: 'test1',
    name: 'n1',
    protocol,
    server: 'srv.example.com',
    port: 443,
    delay: -1,
  };
}

function mkSettings(mode: RoutingMode): AppSettings {
  return {
    workMode: WorkMode.PROXY,
    routingMode: mode,
    socksPort: 10808,
    dnsRemote: '1.1.1.1',
    dnsDirect: '223.5.5.5',
    logLevel: 'warning',
    ipv6: false,
  };
}

function parseCfg(json: string): Cfg {
  return JSON.parse(json) as Cfg;
}

export default function xrayConfigBuilderTest() {
  describe('XrayConfigBuilder', () => {

    // ---------- 公共骨架 ----------
    it('skeleton_common_parts', 0, () => {
      const cfg = parseCfg(XrayConfigBuilder.build(mkNode(Protocol.SHADOWSOCKS), mkSettings(RoutingMode.GLOBAL)));
      expect(cfg.log.loglevel).assertEqual('warning');
      expect(cfg.inbounds.length).assertEqual(1);
      expect(cfg.inbounds[0].protocol).assertEqual('socks');
      expect(cfg.inbounds[0].listen).assertEqual('127.0.0.1');
      expect(cfg.inbounds[0].port).assertEqual(10808);
      expect(cfg.inbounds[0].sniffing.enabled).assertTrue();
      expect(cfg.outbounds.length).assertEqual(3);
      expect(cfg.outbounds[0].tag).assertEqual('proxy');
      expect(cfg.outbounds[1].protocol).assertEqual('freedom');
      expect(cfg.outbounds[2].protocol).assertEqual('blackhole');
    });

    // ---------- 四种协议出站 ----------
    it('outbound_vless_reality_flow', 0, () => {
      const node = mkNode(Protocol.VLESS);
      node.uuid = 'uuid-1';
      node.flow = 'xtls-rprx-vision';
      node.security = 'reality';
      node.sni = 'www.microsoft.com';
      node.fingerprint = 'chrome';
      node.publicKey = 'PK';
      node.shortId = 'ab';
      const cfg = parseCfg(XrayConfigBuilder.build(node, mkSettings(RoutingMode.GLOBAL)));
      const out = cfg.outbounds[0];
      expect(out.protocol).assertEqual('vless');
      const vnext: CfgVnext[] = out.settings.vnext!;
      expect(vnext[0].address).assertEqual('srv.example.com');
      expect(vnext[0].port).assertEqual(443);
      expect(vnext[0].users[0].id).assertEqual('uuid-1');
      expect(vnext[0].users[0].encryption).assertEqual('none');
      expect(vnext[0].users[0].flow).assertEqual('xtls-rprx-vision');
      expect(vnext[0].users[0].security).assertEqual('reality');
      expect(out.streamSettings!.security).assertEqual('reality');
      expect(out.streamSettings!.realitySettings!.serverName).assertEqual('www.microsoft.com');
      expect(out.streamSettings!.realitySettings!.publicKey).assertEqual('PK');
      expect(out.streamSettings!.realitySettings!.shortId).assertEqual('ab');
    });

    it('outbound_vless_no_flow_no_security', 0, () => {
      const node = mkNode(Protocol.VLESS);
      node.uuid = 'u';
      const cfg = parseCfg(XrayConfigBuilder.build(node, mkSettings(RoutingMode.GLOBAL)));
      const vnext: CfgVnext[] = cfg.outbounds[0].settings.vnext!;
      expect(vnext[0].users[0].flow).assertUndefined();
      expect(vnext[0].users[0].security).assertUndefined();
      // security=none 时不应有 tls/reality settings
      expect(cfg.outbounds[0].streamSettings!.tlsSettings).assertUndefined();
      expect(cfg.outbounds[0].streamSettings!.realitySettings).assertUndefined();
    });

    it('outbound_vmess_defaults', 0, () => {
      const node = mkNode(Protocol.VMESS);
      node.uuid = 'uuid-vm';
      const cfg = parseCfg(XrayConfigBuilder.build(node, mkSettings(RoutingMode.GLOBAL)));
      const vnext: CfgVnext[] = cfg.outbounds[0].settings.vnext!;
      expect(cfg.outbounds[0].protocol).assertEqual('vmess');
      expect(vnext[0].users[0].id).assertEqual('uuid-vm');
      expect(vnext[0].users[0].alterId).assertEqual(0);
    });

    it('outbound_ss_and_trojan', 0, () => {
      const ss = mkNode(Protocol.SHADOWSOCKS);
      ss.method = 'chacha20-ietf-poly1305';
      ss.password = 'pw';
      let cfg = parseCfg(XrayConfigBuilder.build(ss, mkSettings(RoutingMode.GLOBAL)));
      const servers = cfg.outbounds[0].settings.servers as CfgServer[];
      expect(cfg.outbounds[0].protocol).assertEqual('shadowsocks');
      expect(servers[0].method).assertEqual('chacha20-ietf-poly1305');
      expect(servers[0].password).assertEqual('pw');

      const tj = mkNode(Protocol.TROJAN);
      tj.password = 'tpw';
      tj.security = 'tls';
      cfg = parseCfg(XrayConfigBuilder.build(tj, mkSettings(RoutingMode.GLOBAL)));
      expect(cfg.outbounds[0].protocol).assertEqual('trojan');
      expect((cfg.outbounds[0].settings.servers as CfgServer[])[0].password).assertEqual('tpw');
      expect(cfg.outbounds[0].streamSettings!.tlsSettings!.serverName).assertEqual('srv.example.com');
    });

    it('ss_method_default', 0, () => {
      const ss = mkNode(Protocol.SHADOWSOCKS);
      const cfg = parseCfg(XrayConfigBuilder.build(ss, mkSettings(RoutingMode.GLOBAL)));
      expect((cfg.outbounds[0].settings.servers as CfgServer[])[0].method).assertEqual('aes-128-gcm');
    });

    // ---------- 传输层 ----------
    it('stream_tls_sni_fallback_and_ws', 0, () => {
      const node = mkNode(Protocol.VMESS);
      node.uuid = 'u';
      node.security = 'tls';
      node.network = 'ws';
      node.path = '/api';
      node.host = 'cdn.com';
      const cfg = parseCfg(XrayConfigBuilder.build(node, mkSettings(RoutingMode.GLOBAL)));
      const stream = cfg.outbounds[0].streamSettings!;
      expect(stream.tlsSettings!.serverName).assertEqual('cdn.com'); // host 优先
      expect(stream.wsSettings!.path).assertEqual('/api');
      expect(stream.wsSettings!.headers.Host).assertEqual('cdn.com');
    });

    it('stream_grpc_and_tcp_http_header', 0, () => {
      const grpc = mkNode(Protocol.VLESS);
      grpc.uuid = 'u';
      grpc.network = 'grpc';
      grpc.path = 'Svc';
      let cfg = parseCfg(XrayConfigBuilder.build(grpc, mkSettings(RoutingMode.GLOBAL)));
      expect(cfg.outbounds[0].streamSettings!.grpcSettings!.serviceName).assertEqual('Svc');

      const tcp = mkNode(Protocol.VMESS);
      tcp.uuid = 'u';
      tcp.network = 'tcp';
      tcp.host = 'fake.com';
      cfg = parseCfg(XrayConfigBuilder.build(tcp, mkSettings(RoutingMode.GLOBAL)));
      expect(cfg.outbounds[0].streamSettings!.tcpSettings !== undefined).assertTrue();
    });

    // ---------- 路由模式 ----------
    it('routing_global', 0, () => {
      const cfg = parseCfg(XrayConfigBuilder.build(mkNode(Protocol.SHADOWSOCKS), mkSettings(RoutingMode.GLOBAL)));
      expect(cfg.routing.domainStrategy).assertEqual('AsIs');
      expect(cfg.routing.rules.length).assertEqual(1);
      expect(cfg.routing.rules[0].outboundTag).assertEqual('proxy');
    });

    it('routing_direct', 0, () => {
      const cfg = parseCfg(XrayConfigBuilder.build(mkNode(Protocol.SHADOWSOCKS), mkSettings(RoutingMode.DIRECT)));
      expect(cfg.routing.rules[0].outboundTag).assertEqual('direct');
    });

    it('routing_bypass_cn', 0, () => {
      const cfg = parseCfg(XrayConfigBuilder.build(mkNode(Protocol.SHADOWSOCKS), mkSettings(RoutingMode.BYPASS_CN)));
      expect(cfg.routing.domainStrategy).assertEqual('IPIfNonMatch');
      expect(cfg.routing.rules.length).assertEqual(4);
      expect(cfg.routing.rules[0].outboundTag).assertEqual('direct');
      expect(cfg.routing.rules[0].ip![0]).assertEqual('geoip:private');
      expect(cfg.routing.rules[1].domain![0]).assertEqual('geosite:cn');
      expect(cfg.routing.rules[2].ip![0]).assertEqual('geoip:cn');
      expect(cfg.routing.rules[3].outboundTag).assertEqual('proxy');
    });

    // ---------- DNS ----------
    it('dns_bypass_cn_vs_global', 0, () => {
      let cfg = parseCfg(XrayConfigBuilder.build(mkNode(Protocol.SHADOWSOCKS), mkSettings(RoutingMode.BYPASS_CN)));
      expect(cfg.dns.servers.length).assertEqual(2);
      expect(cfg.dns.servers[0].address).assertEqual('223.5.5.5');
      expect(cfg.dns.servers[0].domains![0]).assertEqual('geosite:cn');
      expect(cfg.dns.servers[0].skipFallback).assertTrue();
      expect(cfg.dns.queryStrategy).assertEqual('UseIPv4');

      cfg = parseCfg(XrayConfigBuilder.build(mkNode(Protocol.SHADOWSOCKS), mkSettings(RoutingMode.GLOBAL)));
      expect(cfg.dns.servers[0].address).assertEqual('1.1.1.1');
      expect(cfg.dns.servers[0].domains).assertUndefined();
    });

    it('dns_ipv6_enabled', 0, () => {
      const s = mkSettings(RoutingMode.GLOBAL);
      s.ipv6 = true;
      const cfg = parseCfg(XrayConfigBuilder.build(mkNode(Protocol.SHADOWSOCKS), s));
      expect(cfg.dns.queryStrategy).assertEqual('UseIP');
    });

    // ---------- 设置默认值（Types） ----------
    it('default_settings_sane', 0, () => {
      expect(DEFAULT_SETTINGS.workMode).assertEqual(WorkMode.VPN);
      expect(DEFAULT_SETTINGS.routingMode).assertEqual(RoutingMode.BYPASS_CN);
      expect(DEFAULT_SETTINGS.socksPort).assertEqual(10808);
      expect(DEFAULT_SETTINGS.logLevel).assertEqual('warning');
      expect(DEFAULT_SETTINGS.ipv6).assertFalse();
    });
  });
}
