import { describe, it, expect } from '@ohos/hypium';
import { ShareLinkParser } from '../main/ets/core/ShareLinkParser';
import { Protocol } from '../main/ets/common/Types';

export default function shareLinkParserTest() {
  describe('ShareLinkParser', () => {

    // ---------- vless ----------
    it('parseVless_reality_full', 0, () => {
      const link = 'vless://uuid-1234@1.2.3.4:443?security=reality&flow=xtls-rprx-vision' +
        '&pbk=PUBKEY&sid=abcd&sni=www.microsoft.com&fp=chrome&type=tcp#node1';
      const n = ShareLinkParser.parse(link);
      expect(n !== null).assertTrue();
      expect(n!.protocol).assertEqual(Protocol.VLESS);
      expect(n!.uuid).assertEqual('uuid-1234');
      expect(n!.server).assertEqual('1.2.3.4');
      expect(n!.port).assertEqual(443);
      expect(n!.security).assertEqual('reality');
      expect(n!.flow).assertEqual('xtls-rprx-vision');
      expect(n!.publicKey).assertEqual('PUBKEY');
      expect(n!.shortId).assertEqual('abcd');
      expect(n!.sni).assertEqual('www.microsoft.com');
      expect(n!.fingerprint).assertEqual('chrome');
      expect(n!.network).assertEqual('tcp');
      expect(n!.name).assertEqual('node1');
      expect(n!.delay).assertEqual(-1);
    });

    it('parseVless_ws_grpc_fields', 0, () => {
      const ws = ShareLinkParser.parse('vless://u@h:80?type=ws&path=%2Fapi&host=cdn.example.com#w');
      expect(ws!.network).assertEqual('ws');
      expect(ws!.path).assertEqual('/api');
      expect(ws!.host).assertEqual('cdn.example.com');
      const grpc = ShareLinkParser.parse('vless://u@h:443?type=grpc&serviceName=GunService#g');
      expect(grpc!.network).assertEqual('grpc');
      expect(grpc!.path).assertEqual('GunService');
    });

    it('parseVless_defaults_and_name_fallback', 0, () => {
      const n = ShareLinkParser.parse('vless://u@h:443');
      expect(n!.security).assertEqual('none');
      expect(n!.flow).assertUndefined();
      expect(n!.network).assertEqual('tcp');
      expect(n!.name).assertEqual('h:443');
    });

    it('parseVless_invalid_returns_null', 0, () => {
      expect(ShareLinkParser.parse('vless://')).assertNull();
      expect(ShareLinkParser.parse('vless://u@')).assertNull();
      expect(ShareLinkParser.parse('vless://h:443')).assertNull(); // 缺 @
    });

    // ---------- vmess ----------
    it('parseVmess_full', 0, () => {
      const json = JSON.stringify({
        v: '2', ps: 'vmess-node', add: 'vm.example.com', port: '443',
        id: 'uuid-vm', aid: '0', net: 'ws', path: '/ws', host: 'cdn.com',
        tls: 'tls', sni: 'sni.com',
      });
      // 直接构造 base64 链接
      const link = 'vmess://' + toB64(json);
      const n = ShareLinkParser.parse(link);
      expect(n !== null).assertTrue();
      expect(n!.protocol).assertEqual(Protocol.VMESS);
      expect(n!.name).assertEqual('vmess-node');
      expect(n!.server).assertEqual('vm.example.com');
      expect(n!.port).assertEqual(443);
      expect(n!.uuid).assertEqual('uuid-vm');
      expect(n!.alterId).assertEqual(0);
      expect(n!.network).assertEqual('ws');
      expect(n!.path).assertEqual('/ws');
      expect(n!.host).assertEqual('cdn.com');
      expect(n!.security).assertEqual('tls');
      expect(n!.sni).assertEqual('sni.com');
    });

    it('parseVmess_missing_fields', 0, () => {
      expect(ShareLinkParser.parse('vmess://' + toB64(JSON.stringify({ id: 'x' })))).assertNull();
      expect(ShareLinkParser.parse('vmess://' + toB64(JSON.stringify({ add: 'x' })))).assertNull();
      expect(ShareLinkParser.parse('vmess://!!!badbase64!!!')).assertNull();
    });

    // ---------- ss ----------
    it('parseSs_userinfo_b64', 0, () => {
      const link = 'ss://' + toB64('chacha20-ietf-poly1305:pass123') + '@1.2.3.4:8388#ssnode';
      const n = ShareLinkParser.parse(link);
      expect(n !== null).assertTrue();
      expect(n!.protocol).assertEqual(Protocol.SHADOWSOCKS);
      expect(n!.method).assertEqual('chacha20-ietf-poly1305');
      expect(n!.password).assertEqual('pass123');
      expect(n!.server).assertEqual('1.2.3.4');
      expect(n!.port).assertEqual(8388);
      expect(n!.name).assertEqual('ssnode');
    });

    it('parseSs_full_b64_and_query_stripped', 0, () => {
      const link = 'ss://' + toB64('aes-128-gcm:p@10.0.2.2:8388') + '?plugin=obfs#s2';
      const n = ShareLinkParser.parse(link);
      expect(n !== null).assertTrue();
      expect(n!.method).assertEqual('aes-128-gcm');
      expect(n!.password).assertEqual('p');
      expect(n!.server).assertEqual('10.0.2.2');
      expect(n!.port).assertEqual(8388);
    });

    it('parseSs_ipv6', 0, () => {
      const link = 'ss://' + toB64('aes-256-gcm:pw') + '@[2001:db8::1]:443#v6';
      const n = ShareLinkParser.parse(link);
      expect(n !== null).assertTrue();
      expect(n!.server).assertEqual('2001:db8::1');
      expect(n!.port).assertEqual(443);
    });

    it('parseSs_invalid', 0, () => {
      expect(ShareLinkParser.parse('ss://')).assertNull();
      expect(ShareLinkParser.parse('ss://' + toB64('nocolon') + '@h:1')).assertNull();
    });

    // ---------- trojan ----------
    it('parseTrojan_full', 0, () => {
      const link = 'trojan://p%40ss@tj.example.com:443?security=tls&sni=tj.com&fp=firefox&type=ws&path=%2Ftj#tjnode';
      const n = ShareLinkParser.parse(link);
      expect(n !== null).assertTrue();
      expect(n!.protocol).assertEqual(Protocol.TROJAN);
      expect(n!.password).assertEqual('p@ss');
      expect(n!.server).assertEqual('tj.example.com');
      expect(n!.security).assertEqual('tls');
      expect(n!.sni).assertEqual('tj.com');
      expect(n!.fingerprint).assertEqual('firefox');
      expect(n!.network).assertEqual('ws');
      expect(n!.path).assertEqual('/tj');
    });

    it('parseTrojan_invalid', 0, () => {
      expect(ShareLinkParser.parse('trojan://')).assertNull();
    });

    // ---------- parseMulti / 其他 ----------
    it('parseMulti_mixed_lines', 0, () => {
      const text = 'ss://' + toB64('aes-128-gcm:p@h:1') + '#a\n' +
        'not-a-link\n' +
        'trojan://p@h2:443#b\r\n' +
        '\n' +
        'vmess://' + toB64(JSON.stringify({ add: 'h3', port: '80', id: 'i' }));
      const nodes = ShareLinkParser.parseMulti(text);
      expect(nodes.length).assertEqual(3);
      expect(nodes[0].protocol).assertEqual(Protocol.SHADOWSOCKS);
      expect(nodes[1].protocol).assertEqual(Protocol.TROJAN);
      expect(nodes[2].protocol).assertEqual(Protocol.VMESS);
    });

    it('parse_unknown_scheme_returns_null', 0, () => {
      expect(ShareLinkParser.parse('http://example.com')).assertNull();
      expect(ShareLinkParser.parse('hysteria2://p@h:443')).assertNull();
      expect(ShareLinkParser.parse('')).assertNull();
    });

    it('base64Decode_urlsafe_and_padding', 0, () => {
      // url-safe: '-'→'+', '_'→'/', 无 padding
      const decoded = ShareLinkParser.base64Decode('SGVsbG8tV29ybGRfQQ');
      expect(decoded).assertEqual('Hello-World_A');
      const decoded2 = ShareLinkParser.base64Decode('aGVsbG8');
      expect(decoded2).assertEqual('hello');
    });

    it('unique_ids_generated', 0, () => {
      const a = ShareLinkParser.parse('ss://' + toB64('m:p@h:1'));
      const b = ShareLinkParser.parse('ss://' + toB64('m:p@h:1'));
      expect(a!.id !== b!.id).assertTrue();
    });
  });
}

/** 测试内联的 base64 编码（避免依赖被测模块的解码做编码，保证独立性） */
function toB64(s: string): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  const bytes: number[] = [];
  for (let i = 0; i < s.length; i++) {
    bytes.push(s.charCodeAt(i) & 0xff);
  }
  let out = '';
  for (let i = 0; i < bytes.length; i += 3) {
    const b0 = bytes[i];
    const b1 = i + 1 < bytes.length ? bytes[i + 1] : 0;
    const b2 = i + 2 < bytes.length ? bytes[i + 2] : 0;
    out += chars.charAt(b0 >> 2);
    out += chars.charAt(((b0 & 3) << 4) | (b1 >> 4));
    out += i + 1 < bytes.length ? chars.charAt(((b1 & 15) << 2) | (b2 >> 6)) : '=';
    out += i + 2 < bytes.length ? chars.charAt(b2 & 63) : '=';
  }
  return out;
}
