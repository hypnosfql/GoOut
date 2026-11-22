import { NodeProfile, Protocol } from '../common/Types';
import { NodeStore } from '../store/NodeStore';

/**
 * 简版 Clash YAML 订阅解析器。
 * 只解析 proxies: 段中 ss/vmess/trojan/vless 的常用字段（缩进结构、不处理 flow/anchors）。
 * 覆盖绝大多数机场 Clash 订阅。
 */
export class ClashYamlParser {
  static isClashYaml(text: string): boolean {
    return text.includes('proxies:') || text.includes('Proxy:');
  }

  static parse(text: string): NodeProfile[] {
    const nodes: NodeProfile[] = [];
    const lines = text.split(/\r?\n/);
    let inProxies = false;
    let current: YamlProxy | null = null;
    let subKey = ''; // ws-opts / grpc-opts / reality-opts 的二级键上下文

    for (const rawLine of lines) {
      // 定位 proxies: 段（兼容 "proxies:" 顶格写法）
      if (!inProxies) {
        if (/^proxies\s*:/.test(rawLine)) {
          inProxies = true;
        }
        continue;
      }
      // proxy-groups: 等下一个顶格键 → 结束
      if (/^[a-zA-Z_-]+\s*:/.test(rawLine) && !/^proxies\s*:/.test(rawLine)) {
        break;
      }
      // flow 风格列表项："  - {name: x, server: y, ...}"
      if (/^\s+-\s+\{/.test(rawLine)) {
        const proxy = ClashYamlParser.parseFlowLine(rawLine);
        if (proxy) {
          const node = ClashYamlParser.toNode(proxy);
          if (node) {
            nodes.push(node);
          }
        }
        continue;
      }
      // 列表项起始："  - name: xxx"（允许任意缩进）
      const itemMatch = rawLine.match(/^\s+-\s+name\s*:\s*(.+)$/);
      if (itemMatch) {
        if (current) {
          const node = ClashYamlParser.toNode(current);
          if (node) {
            nodes.push(node);
          }
        }
        current = new YamlProxy();
        current.map.set('name', ClashYamlParser.stripQuote(itemMatch[1].trim()));
        subKey = '';
        continue;
      }
      if (!current) {
        continue;
      }
      // 二级段标记：ws-opts: / grpc-opts: / reality-opts:
      const sectionMatch = rawLine.match(/^\s{4}(ws-opts|grpc-opts|reality-opts)\s*:\s*$/);
      if (sectionMatch) {
        subKey = sectionMatch[1];
        continue;
      }
      // headers: 归入 ws-opts 上下文
      if (/^\s{6}headers\s*:\s*$/.test(rawLine)) {
        subKey = 'ws-headers';
        continue;
      }
      // 键值对
      const kvMatch = rawLine.match(/^\s+([a-zA-Z0-9_-]+)\s*:\s*(.*)$/);
      if (kvMatch) {
        const key = kvMatch[1];
        const value = ClashYamlParser.stripQuote(kvMatch[2].trim());
        if (subKey === 'ws-headers') {
          current.map.set(`ws-header-${key}`, value);
        } else if (subKey !== '') {
          current.map.set(`${subKey}.${key}`, value);
        } else {
          current.map.set(key, value);
        }
      }
    }
    if (current) {
      const node = ClashYamlParser.toNode(current);
      if (node) {
        nodes.push(node);
      }
    }
    return nodes;
  }

  /** flow 风格单行：{name: x, server: y, port: 443, type: ss, ...} */
  private static parseFlowLine(line: string): YamlProxy | null {
    const m = line.match(/^\s*-\s*\{(.+)\}\s*,?\s*$/);
    if (!m) {
      return null;
    }
    const proxy = new YamlProxy();
    for (const pair of ClashYamlParser.splitPairs(m[1])) {
      const idx = pair.indexOf(':');
      if (idx > 0) {
        proxy.map.set(pair.substring(0, idx).trim(), ClashYamlParser.stripQuote(pair.substring(idx + 1).trim()));
      }
    }
    return proxy;
  }

  /** 按逗号拆分，忽略引号内的逗号 */
  private static splitPairs(s: string): string[] {
    const parts: string[] = [];
    let current = '';
    let quote = '';
    for (let i = 0; i < s.length; i++) {
      const ch = s.charAt(i);
      if (quote === '' && (ch === '\'' || ch === '"')) {
        quote = ch;
        current += ch;
      } else if (quote !== '' && ch === quote) {
        quote = '';
        current += ch;
      } else if (quote === '' && ch === ',') {
        parts.push(current);
        current = '';
      } else {
        current += ch;
      }
    }
    if (current.trim() !== '') {
      parts.push(current);
    }
    return parts;
  }

  private static stripQuote(v: string): string {
    if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith('\'') && v.endsWith('\''))) {
      return v.substring(1, v.length - 1);
    }
    return v;
  }

  private static toNode(p: YamlProxy): NodeProfile | null {
    const m = p.map;
    const type = (m.get('type') ?? '').toLowerCase();
    const server = m.get('server') ?? '';
    const port = parseInt(m.get('port') ?? '0');
    const name = m.get('name') ?? `${server}:${port}`;
    if (!server || !port) {
      return null;
    }
    const node: NodeProfile = {
      id: NodeStore.newId(),
      name,
      protocol: Protocol.SHADOWSOCKS,
      server,
      port,
      delay: -1,
    };
    switch (type) {
      case 'ss':
        node.protocol = Protocol.SHADOWSOCKS;
        node.method = m.get('cipher') ?? 'aes-128-gcm';
        node.password = m.get('password') ?? '';
        break;
      case 'vmess':
        node.protocol = Protocol.VMESS;
        node.uuid = m.get('uuid') ?? '';
        node.alterId = parseInt(m.get('alterId') ?? '0');
        node.sni = m.get('servername') ?? (m.get('sni') ?? '');
        ClashYamlParser.fillStream(node, m);
        break;
      case 'trojan':
        node.protocol = Protocol.TROJAN;
        node.password = m.get('password') ?? '';
        node.security = 'tls';
        node.sni = m.get('sni') ?? (m.get('servername') ?? '');
        ClashYamlParser.fillStream(node, m);
        break;
      case 'vless':
        node.protocol = Protocol.VLESS;
        node.uuid = m.get('uuid') ?? '';
        node.flow = m.get('flow') || undefined;
        const security = m.get('security') ?? '';
        if (security === 'reality' || m.has('reality-opts.public-key')) {
          node.security = 'reality';
        } else if (security === 'tls' || m.get('tls') === 'true') {
          node.security = 'tls';
        } else {
          node.security = 'none';
        }
        node.sni = m.get('servername') ?? (m.get('sni') ?? '');
        node.fingerprint = m.get('client-fingerprint') ?? '';
        node.publicKey = m.get('reality-opts.public-key') ?? '';
        node.shortId = m.get('reality-opts.short-id') ?? '';
        ClashYamlParser.fillStream(node, m);
        break;
      default:
        return null; // hysteria2/tuic 等一期不支持
    }
    if (!node.name) {
      node.name = `${server}:${port}`;
    }
    return node;
  }

  /** 填充传输层字段（network/ws/grpc/tls） */
  private static fillStream(node: NodeProfile, m: Map<string, string>): void {
    node.network = m.get('network') ?? 'tcp';
    if (m.get('tls') === 'true' && node.protocol !== Protocol.VLESS) {
      node.security = 'tls';
    }
    if (node.network === 'ws') {
      node.path = m.get('ws-opts.path') ?? '/';
      node.host = m.get('ws-opts.headers.Host') ?? (m.get('ws-header-Host') ?? '');
    } else if (node.network === 'grpc') {
      node.path = m.get('grpc-opts.grpc-service-name') ?? (m.get('grpc-opts.serviceName') ?? '');
    }
  }
}

class YamlProxy {
  map: Map<string, string> = new Map();
}
