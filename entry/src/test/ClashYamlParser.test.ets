import { describe, it, expect } from '@ohos/hypium';
import { ClashYamlParser } from '../main/ets/core/ClashYamlParser';
import { Protocol } from '../main/ets/common/Types';

export default function clashYamlParserTest() {
  describe('ClashYamlParser', () => {

    // ---------- 格式识别 ----------
    it('isClashYaml', 0, () => {
      expect(ClashYamlParser.isClashYaml('proxies:\n  - {name: a}')).assertTrue();
      expect(ClashYamlParser.isClashYaml('ss://abc@h:1')).assertFalse();
      expect(ClashYamlParser.isClashYaml('')).assertFalse();
    });

    // ---------- flow 风格 ----------
    it('flow_style_ss', 0, () => {
      const yaml = 'port: 7890\n' +
        'proxies:\n' +
        '  - {name: HK-A01, server: hk.example.com, port: 19275, type: ss, cipher: aes-256-gcm, password: pw123, udp: true}\n' +
        '  - {name: JP-A01, server: jp.example.com, port: 476, type: ss, cipher: chacha20-ietf-poly1305, password: pw456}\n' +
        'proxy-groups:\n' +
        '  - {name: PROXY, type: select}\n';
      const nodes = ClashYamlParser.parse(yaml);
      expect(nodes.length).assertEqual(2);
      expect(nodes[0].name).assertEqual('HK-A01');
      expect(nodes[0].protocol).assertEqual(Protocol.SHADOWSOCKS);
      expect(nodes[0].server).assertEqual('hk.example.com');
      expect(nodes[0].port).assertEqual(19275);
      expect(nodes[0].method).assertEqual('aes-256-gcm');
      expect(nodes[0].password).assertEqual('pw123');
      expect(nodes[1].name).assertEqual('JP-A01');
      expect(nodes[1].method).assertEqual('chacha20-ietf-poly1305');
    });

    it('flow_style_quoted_values_with_comma', 0, () => {
      const yaml = 'proxies:\n' +
        '  - {name: "node, with comma", server: h.com, port: 443, type: trojan, password: "p,1", sni: s.com}\n';
      const nodes = ClashYamlParser.parse(yaml);
      expect(nodes.length).assertEqual(1);
      expect(nodes[0].name).assertEqual('node, with comma');
      expect(nodes[0].password).assertEqual('p,1');
      expect(nodes[0].protocol).assertEqual(Protocol.TROJAN);
      expect(nodes[0].security).assertEqual('tls');
      expect(nodes[0].sni).assertEqual('s.com');
    });

    // ---------- block 风格 ----------
    it('block_style_vmess_ws', 0, () => {
      const yaml = 'proxies:\n' +
        '  - name: vm-node\n' +
        '    type: vmess\n' +
        '    server: vm.example.com\n' +
        '    port: 443\n' +
        '    uuid: uuid-1\n' +
        '    alterId: 0\n' +
        '    cipher: auto\n' +
        '    tls: true\n' +
        '    servername: tls.example.com\n' +
        '    network: ws\n' +
        '    ws-opts:\n' +
        '      path: /api\n' +
        '      headers:\n' +
        '        Host: cdn.example.com\n';
      const nodes = ClashYamlParser.parse(yaml);
      expect(nodes.length).assertEqual(1);
      const n = nodes[0];
      expect(n.protocol).assertEqual(Protocol.VMESS);
      expect(n.uuid).assertEqual('uuid-1');
      expect(n.alterId).assertEqual(0);
      expect(n.security).assertEqual('tls');
      expect(n.sni).assertEqual('tls.example.com');
      expect(n.network).assertEqual('ws');
      expect(n.path).assertEqual('/api');
      expect(n.host).assertEqual('cdn.example.com');
    });

    it('block_style_vless_reality', 0, () => {
      const yaml = 'proxies:\n' +
        '  - name: vless-node\n' +
        '    type: vless\n' +
        '    server: vl.example.com\n' +
        '    port: 443\n' +
        '    uuid: uuid-vl\n' +
        '    flow: xtls-rprx-vision\n' +
        '    security: reality\n' +
        '    servername: www.yahoo.com\n' +
        '    client-fingerprint: chrome\n' +
        '    reality-opts:\n' +
        '      public-key: PUBKEY123\n' +
        '      short-id: ab12\n' +
        '    network: tcp\n';
      const nodes = ClashYamlParser.parse(yaml);
      expect(nodes.length).assertEqual(1);
      const n = nodes[0];
      expect(n.protocol).assertEqual(Protocol.VLESS);
      expect(n.uuid).assertEqual('uuid-vl');
      expect(n.flow).assertEqual('xtls-rprx-vision');
      expect(n.security).assertEqual('reality');
      expect(n.sni).assertEqual('www.yahoo.com');
      expect(n.fingerprint).assertEqual('chrome');
      expect(n.publicKey).assertEqual('PUBKEY123');
      expect(n.shortId).assertEqual('ab12');
    });

    it('block_style_grpc', 0, () => {
      const yaml = 'proxies:\n' +
        '  - name: grpc-node\n' +
        '    type: vmess\n' +
        '    server: g.example.com\n' +
        '    port: 443\n' +
        '    uuid: u\n' +
        '    network: grpc\n' +
        '    grpc-opts:\n' +
        '      grpc-service-name: GunSvc\n';
      const nodes = ClashYamlParser.parse(yaml);
      expect(nodes.length).assertEqual(1);
      expect(nodes[0].network).assertEqual('grpc');
      expect(nodes[0].path).assertEqual('GunSvc');
    });

    // ---------- 边界 ----------
    it('skip_unsupported_type_and_invalid', 0, () => {
      const yaml = 'proxies:\n' +
        '  - {name: hy2, server: h.com, port: 443, type: hysteria2, password: x}\n' +
        '  - {name: no-server, port: 443, type: ss, cipher: aes-128-gcm, password: x}\n' +
        '  - {name: ok, server: ok.com, port: 443, type: ss, cipher: aes-128-gcm, password: x}\n';
      const nodes = ClashYamlParser.parse(yaml);
      expect(nodes.length).assertEqual(1);
      expect(nodes[0].name).assertEqual('ok');
    });

    it('empty_and_no_proxies', 0, () => {
      expect(ClashYamlParser.parse('').length).assertEqual(0);
      expect(ClashYamlParser.parse('port: 7890\nmode: Rule\n').length).assertEqual(0);
    });

    it('defaults_applied', 0, () => {
      const yaml = 'proxies:\n' +
        '  - {server: h.com, port: 80, type: ss, password: x}\n';
      const nodes = ClashYamlParser.parse(yaml);
      expect(nodes[0].method).assertEqual('aes-128-gcm'); // 默认加密方式
      expect(nodes[0].name).assertEqual('h.com:80'); // 无名时回退 server:port
      expect(nodes[0].delay).assertEqual(-1);
      expect(nodes[0].network).assertUndefined(); // 传输层不设默认，由 XrayConfigBuilder 兜底为 tcp
      const vm = ClashYamlParser.parse(
        'proxies:\n  - {name: v, server: h.com, port: 443, type: vmess, uuid: u}\n');
      expect(vm[0].alterId).assertEqual(0);
      expect(vm[0].security).assertUndefined(); // vmess 无 tls 字段时 security 不设置
    });

    it('vless_tls_and_none_security', 0, () => {
      const tls = ClashYamlParser.parse(
        'proxies:\n  - {name: a, server: h, port: 443, type: vless, uuid: u, tls: true, servername: s.com}\n');
      expect(tls[0].security).assertEqual('tls');
      expect(tls[0].sni).assertEqual('s.com');
      const none = ClashYamlParser.parse(
        'proxies:\n  - {name: b, server: h, port: 80, type: vless, uuid: u}\n');
      expect(none[0].security).assertEqual('none');
      expect(none[0].flow).assertUndefined();
    });

    it('trojan_default_tls', 0, () => {
      const nodes = ClashYamlParser.parse(
        'proxies:\n  - {name: t, server: h, port: 443, type: trojan, password: p}\n');
      expect(nodes[0].security).assertEqual('tls');
      expect(nodes[0].sni).assertEqual('');
    });
  });
}
