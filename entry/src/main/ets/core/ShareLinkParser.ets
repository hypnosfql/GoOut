import { NodeProfile, Protocol } from '../common/Types';
import { NodeStore } from '../store/NodeStore';

/** splitCommon 的返回结构 */
class SplitResult {
  userInfo: string = '';
  host: string = '';
  port: number = 0;
  query: Map<string, string> = new Map();
  name: string = '';
}

/** 分享链接解析：vless:// vmess:// ss:// trojan:// */
export class ShareLinkParser {
  /** 解析多条（按行分割），返回成功解析的节点列表 */
  static parseMulti(text: string): NodeProfile[] {
    const nodes: NodeProfile[] = [];
    const lines = text.split(/[\r\n]+/);
    for (const raw of lines) {
      const line = raw.trim();
      if (!line) {
        continue;
      }
      const node = ShareLinkParser.parse(line);
      if (node) {
        nodes.push(node);
      }
    }
    return nodes;
  }

  static parse(link: string): NodeProfile | null {
    try {
      if (link.startsWith('vless://')) {
        return ShareLinkParser.parseVless(link);
      }
      if (link.startsWith('vmess://')) {
        return ShareLinkParser.parseVmess(link);
      }
      if (link.startsWith('ss://')) {
        return ShareLinkParser.parseSs(link);
      }
      if (link.startsWith('trojan://')) {
        return ShareLinkParser.parseTrojan(link);
      }
    } catch (e) {
      console.error(`ShareLinkParser parse error: ${(e as Error).message}`);
    }
    return null;
  }

  // ---------------- vless ----------------
  private static parseVless(link: string): NodeProfile | null {
    const parts = ShareLinkParser.splitCommon(link, 'vless://');
    if (!parts.userInfo || !parts.host) {
      return null;
    }
    const node = ShareLinkParser.baseNode(Protocol.VLESS, parts.host, parts.port, parts.name);
    node.uuid = parts.userInfo;
    node.flow = parts.query.get('flow') ?? undefined;
    node.security = parts.query.get('security') ?? 'none';
    node.sni = parts.query.get('sni') ?? '';
    node.fingerprint = parts.query.get('fp') ?? '';
    node.publicKey = parts.query.get('pbk') ?? '';
    node.shortId = parts.query.get('sid') ?? '';
    node.spiderX = parts.query.get('spx') ?? '';
    node.network = parts.query.get('type') ?? 'tcp';
    node.path = parts.query.get('path') ?? (parts.query.get('serviceName') ?? '');
    node.host = parts.query.get('host') ?? '';
    return node;
  }

  // ---------------- vmess ----------------
  private static parseVmess(link: string): NodeProfile | null {
    const b64 = link.substring('vmess://'.length);
    const jsonStr = ShareLinkParser.base64Decode(b64);
    const obj = JSON.parse(jsonStr) as Record<string, string>;
    const add = obj['add'] ?? '';
    const id = obj['id'] ?? '';
    if (!add || !id) {
      return null;
    }
    const node = ShareLinkParser.baseNode(Protocol.VMESS, add,
      parseInt(obj['port'] ?? '443'), obj['ps'] ?? add);
    node.uuid = id;
    node.alterId = parseInt(obj['aid'] ?? '0');
    node.security = obj['tls'] === 'tls' ? 'tls' : 'none';
    node.sni = obj['sni'] ?? '';
    node.network = obj['net'] ?? 'tcp';
    node.path = obj['path'] ?? '';
    node.host = obj['host'] ?? '';
    return node;
  }

  // ---------------- ss ----------------
  private static parseSs(link: string): NodeProfile | null {
    let body = link.substring('ss://'.length);
    let name = '';
    const hashIdx = body.indexOf('#');
    if (hashIdx >= 0) {
      name = decodeURIComponent(body.substring(hashIdx + 1));
      body = body.substring(0, hashIdx);
    }
    const qIdx = body.indexOf('?');
    if (qIdx >= 0) {
      body = body.substring(0, qIdx);
    }

    let method = '';
    let password = '';
    let host = '';
    let port = 0;

    if (body.includes('@')) {
      const atIdx = body.lastIndexOf('@');
      const userB64 = body.substring(0, atIdx);
      const serverPart = body.substring(atIdx + 1);
      const decoded = ShareLinkParser.base64Decode(userB64);
      const colonIdx = decoded.indexOf(':');
      if (colonIdx < 0) {
        return null;
      }
      method = decoded.substring(0, colonIdx);
      password = decoded.substring(colonIdx + 1);
      const parsed = ShareLinkParser.splitHostPort(serverPart);
      if (!parsed) {
        return null;
      }
      host = parsed.host;
      port = parsed.port;
    } else {
      const decoded = ShareLinkParser.base64Decode(body);
      const atIdx = decoded.lastIndexOf('@');
      const colonIdx = decoded.indexOf(':');
      if (atIdx < 0 || colonIdx < 0) {
        return null;
      }
      method = decoded.substring(0, colonIdx);
      password = decoded.substring(colonIdx + 1, atIdx);
      const parsed = ShareLinkParser.splitHostPort(decoded.substring(atIdx + 1));
      if (!parsed) {
        return null;
      }
      host = parsed.host;
      port = parsed.port;
    }

    const node = ShareLinkParser.baseNode(Protocol.SHADOWSOCKS, host, port, name || host);
    node.method = method;
    node.password = password;
    return node;
  }

  // ---------------- trojan ----------------
  private static parseTrojan(link: string): NodeProfile | null {
    const parts = ShareLinkParser.splitCommon(link, 'trojan://');
    if (!parts.userInfo || !parts.host) {
      return null;
    }
    const node = ShareLinkParser.baseNode(Protocol.TROJAN, parts.host, parts.port, parts.name);
    node.password = decodeURIComponent(parts.userInfo);
    node.security = parts.query.get('security') ?? 'tls';
    node.sni = parts.query.get('sni') ?? '';
    node.fingerprint = parts.query.get('fp') ?? '';
    node.network = parts.query.get('type') ?? 'tcp';
    node.path = parts.query.get('path') ?? (parts.query.get('serviceName') ?? '');
    node.host = parts.query.get('host') ?? '';
    return node;
  }

  // ---------------- helpers ----------------
  private static baseNode(protocol: Protocol, server: string, port: number, name: string): NodeProfile {
    const node: NodeProfile = {
      id: NodeStore.newId(),
      name: name || `${server}:${port}`,
      protocol,
      server,
      port,
      delay: -1,
    };
    return node;
  }

  /** 拆分 scheme://userInfo@host:port?query#name */
  private static splitCommon(link: string, scheme: string): SplitResult {
    const result = new SplitResult();
    let body = link.substring(scheme.length);
    const hashIdx = body.indexOf('#');
    if (hashIdx >= 0) {
      result.name = decodeURIComponent(body.substring(hashIdx + 1));
      body = body.substring(0, hashIdx);
    }
    const qIdx = body.indexOf('?');
    if (qIdx >= 0) {
      const qs = body.substring(qIdx + 1);
      body = body.substring(0, qIdx);
      for (const pair of qs.split('&')) {
        const eq = pair.indexOf('=');
        if (eq > 0) {
          result.query.set(pair.substring(0, eq), decodeURIComponent(pair.substring(eq + 1)));
        }
      }
    }
    const atIdx = body.lastIndexOf('@');
    if (atIdx < 0) {
      return result;
    }
    result.userInfo = body.substring(0, atIdx);
    const hp = ShareLinkParser.splitHostPort(body.substring(atIdx + 1));
    if (hp) {
      result.host = hp.host;
      result.port = hp.port;
    }
    return result;
  }

  private static splitHostPort(s: string): SplitResult | null {
    const r = new SplitResult();
    // 支持 IPv6 [::1]:443
    if (s.startsWith('[')) {
      const end = s.indexOf(']');
      if (end < 0 || end + 2 >= s.length) {
        return null;
      }
      r.host = s.substring(1, end);
      r.port = parseInt(s.substring(end + 2));
      return r;
    }
    const idx = s.lastIndexOf(':');
    if (idx <= 0) {
      return null;
    }
    r.host = s.substring(0, idx);
    r.port = parseInt(s.substring(idx + 1));
    return r;
  }

  static base64Decode(b64: string): string {
    const bytes = ShareLinkParser.base64ToBytes(b64);
    return ShareLinkParser.utf8Decode(bytes);
  }

  /** 纯 ArkTS UTF-8 解码，不依赖宿主 TextDecoder */
  private static utf8Decode(bytes: Uint8Array): string {
    let out = '';
    let i = 0;
    while (i < bytes.length) {
      const b0 = bytes[i];
      let cp = 0;
      let len = 0;
      if (b0 < 0x80) {
        cp = b0;
        len = 1;
      } else if ((b0 & 0xe0) === 0xc0) {
        cp = b0 & 0x1f;
        len = 2;
      } else if ((b0 & 0xf0) === 0xe0) {
        cp = b0 & 0x0f;
        len = 3;
      } else if ((b0 & 0xf8) === 0xf0) {
        cp = b0 & 0x07;
        len = 4;
      } else {
        cp = 0xfffd;
        len = 1;
      }
      if (i + len > bytes.length) {
        break;
      }
      for (let j = 1; j < len; j++) {
        cp = (cp << 6) | (bytes[i + j] & 0x3f);
      }
      out += String.fromCharCode(cp);
      i += len;
    }
    return out;
  }

  /** 纯 ArkTS base64 解码（支持 url-safe、无 padding），不依赖宿主 Base64Helper */
  private static base64ToBytes(b64: string): Uint8Array {
    let normalized = b64.replace(/-/g, '+').replace(/_/g, '/');
    while (normalized.length % 4 !== 0) {
      normalized += '=';
    }
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    const table = new Map<string, number>();
    for (let i = 0; i < alphabet.length; i++) {
      table.set(alphabet.charAt(i), i);
    }
    const out: number[] = [];
    let acc = 0;
    let bits = 0;
    for (let i = 0; i < normalized.length; i++) {
      const ch = normalized.charAt(i);
      if (ch === '=') {
        break;
      }
      const v = table.get(ch);
      if (v === undefined) {
        continue; // 忽略空白等非法字符
      }
      acc = (acc << 6) | v;
      bits += 6;
      if (bits >= 8) {
        bits -= 8;
        out.push((acc >> bits) & 0xff);
      }
    }
    return new Uint8Array(out);
  }
}
