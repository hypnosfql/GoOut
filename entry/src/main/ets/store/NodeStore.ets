import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { NodeProfile, SubscriptionItem } from '../common/Types';

const STORE_NAME = 'goout_nodes';
const KEY_NODES = 'nodes';
const KEY_SUBS = 'subscriptions';
const KEY_SELECTED = 'selected_node_id';

/** 节点与订阅持久化 */
export class NodeStore {
  private static pref: preferences.Preferences | null = null;

  private static get(context: common.Context): preferences.Preferences {
    if (!NodeStore.pref) {
      NodeStore.pref = preferences.getPreferencesSync(context, { name: STORE_NAME });
    }
    return NodeStore.pref;
  }

  // ---------- 节点 ----------
  static loadNodes(context: common.Context): NodeProfile[] {
    const raw = NodeStore.get(context).getSync(KEY_NODES, '[]') as string;
    try {
      return JSON.parse(raw) as NodeProfile[];
    } catch (e) {
      console.error(`NodeStore loadNodes parse error: ${e}`);
      return [];
    }
  }

  static saveNodes(context: common.Context, nodes: NodeProfile[]): void {
    const p = NodeStore.get(context);
    p.putSync(KEY_NODES, JSON.stringify(nodes));
    p.flush();
  }

  static addNode(context: common.Context, node: NodeProfile): void {
    const nodes = NodeStore.loadNodes(context);
    nodes.push(node);
    NodeStore.saveNodes(context, nodes);
  }

  static deleteNode(context: common.Context, id: string): void {
    const nodes = NodeStore.loadNodes(context).filter((n) => n.id !== id);
    NodeStore.saveNodes(context, nodes);
    if (NodeStore.getSelectedId(context) === id) {
      NodeStore.setSelectedId(context, '');
    }
  }

  static updateNode(context: common.Context, node: NodeProfile): void {
    const nodes = NodeStore.loadNodes(context);
    const idx = nodes.findIndex((n) => n.id === node.id);
    if (idx >= 0) {
      nodes[idx] = node;
      NodeStore.saveNodes(context, nodes);
    }
  }

  // ---------- 选中节点 ----------
  static getSelectedId(context: common.Context): string {
    return NodeStore.get(context).getSync(KEY_SELECTED, '') as string;
  }

  static setSelectedId(context: common.Context, id: string): void {
    const p = NodeStore.get(context);
    p.putSync(KEY_SELECTED, id);
    p.flush();
  }

  // ---------- 订阅 ----------
  static loadSubs(context: common.Context): SubscriptionItem[] {
    const raw = NodeStore.get(context).getSync(KEY_SUBS, '[]') as string;
    try {
      return JSON.parse(raw) as SubscriptionItem[];
    } catch (e) {
      return [];
    }
  }

  static saveSubs(context: common.Context, subs: SubscriptionItem[]): void {
    const p = NodeStore.get(context);
    p.putSync(KEY_SUBS, JSON.stringify(subs));
    p.flush();
  }

  static newId(): string {
    // 时间戳 + 较长随机串，避免碰撞导致订阅/节点串号
    return `${Date.now()}_${Math.random().toString(36).slice(2, 12)}`;
  }
}
