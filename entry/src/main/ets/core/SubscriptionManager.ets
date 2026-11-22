import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { NodeProfile, SubscriptionItem } from '../common/Types';
import { NodeStore } from '../store/NodeStore';
import { ShareLinkParser } from './ShareLinkParser';
import { ClashYamlParser } from './ClashYamlParser';

/** 订阅更新 */
export class SubscriptionManager {
  /** 更新单个订阅：拉取 → base64 解码 → 解析 → 替换该订阅名下旧节点 */
  static async update(context: common.Context, sub: SubscriptionItem): Promise<number> {
    const content = await SubscriptionManager.fetch(sub.url);
    let text = content;
    // 格式识别：Clash YAML / base64 链接列表 / 纯文本链接列表
    let nodes: NodeProfile[];
    if (ClashYamlParser.isClashYaml(text)) {
      nodes = ClashYamlParser.parse(text);
      console.info(`SubscriptionManager: clash yaml parsed ${nodes.length} nodes`);
    } else {
      if (!text.includes('://')) {
        try {
          text = ShareLinkParser.base64Decode(text.trim());
        } catch (e) {
          console.error(`SubscriptionManager base64 decode failed: ${(e as Error).message}`);
        }
      }
      nodes = ShareLinkParser.parseMulti(text);
    }
    for (const n of nodes) {
      n.subId = sub.id;
    }
    // 替换该订阅的旧节点，保留其他订阅和手动添加的节点（按 subId 严格隔离）
    const before = NodeStore.loadNodes(context);
    const all = before.filter((n) => n.subId !== sub.id);
    console.info(`SubscriptionManager update: subId=${sub.id}, parsed=${nodes.length}, before=${before.length}, kept=${all.length}`);
    const merged = all.concat(nodes);
    NodeStore.saveNodes(context, merged);
    return nodes.length;
  }

  private static fetch(url: string): Promise<string> {
    return new Promise((resolve, reject) => {
      const req = http.createHttp();
      req.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 15000,
        readTimeout: 30000,
        header: { 'User-Agent': 'v2rayNG/1.8.5' },
      }, (err, resp) => {
        req.destroy();
        if (err) {
          console.error(`SubscriptionManager fetch error: ${err.message}, code=${err.code}, url=${url.substring(0, 40)}`);
          reject(new Error(`订阅拉取失败: ${err.message}`));
          return;
        }
        if (resp.responseCode !== 200) {
          reject(new Error(`订阅返回 ${resp.responseCode}`));
          return;
        }
        // octet-stream 等类型时 result 可能是 ArrayBuffer，统一转 string
        const result = resp.result;
        if (typeof result === 'string') {
          resolve(result);
        } else if (result instanceof ArrayBuffer) {
          const decoder = util.TextDecoder.create('utf-8');
          resolve(decoder.decodeToString(new Uint8Array(result)));
        } else {
          reject(new Error('订阅内容类型不支持'));
        }
      });
    });
  }
}
