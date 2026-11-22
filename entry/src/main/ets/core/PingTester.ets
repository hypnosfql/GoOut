import { common } from '@kit.AbilityKit';
import { NodeProfile } from '../common/Types';
import { XrayConfigBuilder } from './XrayConfigBuilder';
import { XrayBridge } from './XrayBridge';
import { SettingsStore } from '../store/SettingsStore';
import { NodeStore } from '../store/NodeStore';

interface PingResult {
  delay: number; // ms，-1 失败
}

interface PingPayload {
  xray: string;
  datadir: string;
  url: string;
  timeout: number;
}

/** 真连接延迟测试：经 libXray 的 Ping（内部起临时实例） */
export class PingTester {
  /** 并发限制 4，避免瞬间把内存拉爆 */
  private static readonly CONCURRENCY = 4;

  static async testNodes(context: common.Context, nodes: NodeProfile[]): Promise<void> {
    const settings = SettingsStore.load(context);
    const queue = [...nodes];
    const workers: Promise<void>[] = [];
    for (let i = 0; i < PingTester.CONCURRENCY; i++) {
      workers.push((async () => {
        while (queue.length > 0) {
          const node = queue.shift();
          if (!node) {
            break;
          }
          node.delay = await PingTester.pingOne(context, node, settings.socksPort);
          NodeStore.updateNode(context, node);
        }
      })());
    }
    await Promise.all(workers);
  }

  private static async pingOne(context: common.Context, node: NodeProfile, socksPort: number): Promise<number> {
    try {
      const config = XrayConfigBuilder.build(node, SettingsStore.load(context));
      const payload: PingPayload = {
        xray: config,
        datadir: context.filesDir,
        url: 'https://www.gstatic.com/generate_204',
        timeout: 8,
      };
      const result = XrayBridge.invokeData<PingResult>('Ping', payload);
      console.info(`PingTester ${node.name} result: ${JSON.stringify(result)}`);
      return result?.delay ?? -1;
    } catch (e) {
      console.error(`PingTester pingOne error: ${(e as Error).message}`);
      return -1;
    }
  }
}
