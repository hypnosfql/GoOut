import { vpnExtension } from '@kit.NetworkKit';
import VpnExtensionAbility from '@ohos.app.ability.VpnExtensionAbility';
import { Want } from '@kit.AbilityKit';
import { GeoAssets } from '../core/GeoAssets';
import { XrayBridge } from '../core/XrayBridge';
import { XrayConfigBuilder } from '../core/XrayConfigBuilder';
import { NodeStore } from '../store/NodeStore';
import { SettingsStore } from '../store/SettingsStore';
import { RuntimeStore } from '../store/RuntimeStore';
import { CoreState } from '../common/Types';

const TAG = 'GoOutVpnExt';

/**
 * VPN 扩展能力：运行在独立进程。
 * 职责：读配置 → 启动 xray 内核 → 创建 tun → 启动 hev 桥接 → protectProcessNet。
 * 注意：xray 必须在本进程内运行，否则出站流量会回环进 tun。
 */
export default class GoOutVpnExtAbility extends VpnExtensionAbility {
  private vpnConn: vpnExtension.VpnConnection | null = null;
  private tunFd: number = -1;

  onCreate(want: Want): void {
    console.info(`${TAG} onCreate`);
    this.startCore().catch((e: Error) => {
      console.error(`${TAG} startCore failed: ${e.message}`);
      console.error(`${TAG} error detail: ${JSON.stringify(e)}`);
      RuntimeStore.setState(this.context, CoreState.ERROR, `启动失败: ${e.message}`);
    });
  }

  onDestroy(): void {
    console.info(`${TAG} onDestroy`);
    this.stopCore();
  }

  private async startCore(): Promise<void> {
    const ctx = this.context;
    RuntimeStore.setState(ctx, CoreState.STARTING, '内核启动中');

    // 1. 读配置
    const settings = SettingsStore.load(ctx);
    const selectedId = NodeStore.getSelectedId(ctx);
    const node = NodeStore.loadNodes(ctx).find((n) => n.id === selectedId);
    if (!node) {
      throw new Error('未选择节点');
    }
    const configJson = XrayConfigBuilder.build(node, settings);
    console.info(`${TAG} config built for node ${node.name}`);

    // 2. 启动 xray 内核（本进程内）
    const datadir = this.ensureGeoAssets(ctx);
    if (!XrayBridge.runXray(configJson, datadir)) {
      throw new Error('xray 内核启动失败');
    }
    console.info(`${TAG} xray started, socks5 127.0.0.1:${settings.socksPort}`);

    try {
      // 3. 创建 VPN 虚拟网卡
      this.vpnConn = vpnExtension.createVpnConnection(ctx);
      const config: vpnExtension.VpnConfig = {
        addresses: [{ address: { address: '10.0.0.2', family: 1 }, prefixLength: 32 }],
        routes: [
          {
            interface: 'tun0',
            destination: { address: { address: '0.0.0.0', family: 1 }, prefixLength: 0 },
            gateway: { address: '0.0.0.0', family: 1 },
            hasGateway: false,
            isDefaultRoute: true,
          },
        ],
        mtu: 1500,
        isIPv4Accepted: true,
        isIPv6Accepted: false,
        isBlocking: false,
        isInternal: true,
      };
      this.tunFd = await this.vpnConn.create(config);
      console.info(`${TAG} vpn created, tunFd=${this.tunFd}`);
      if (this.tunFd < 0) {
        throw new Error(`创建虚拟网卡失败: ${this.tunFd}`);
      }

      // 4. 放行本进程所有 socket（xray 出站直连，防回环）
      // 失败不致命：部分模拟器版本该接口返回 internal error
      try {
        await this.vpnConn.protectProcessNet();
        console.info(`${TAG} protectProcessNet ok`);
      } catch (e) {
        console.error(`${TAG} protectProcessNet failed (non-fatal): ${(e as Error).message}`);
      }

      // 5. 启动 hev-socks5-tunnel：tun fd ⇄ socks5
      const yaml = buildHevYaml(settings.socksPort, settings.ipv6);
      if (!XrayBridge.startHev(yaml, this.tunFd)) {
        throw new Error('hev-socks5-tunnel 启动失败');
      }
      console.info(`${TAG} hev started`);

      RuntimeStore.setState(ctx, CoreState.RUNNING, '', node.name);
    } catch (e) {
      // 失败要回滚内核
      this.stopCore();
      throw e as Error;
    }
  }

  /** geo 数据目录（UI 侧连接前已按需下载；此处仅取路径） */
  private ensureGeoAssets(ctx: vpnExtension.VpnExtensionContext): string {
    return GeoAssets.dirOf(ctx);
  }

  private stopCore(): void {
    const ctx = this.context;
    RuntimeStore.setState(ctx, CoreState.STOPPING, '');
    try {
      XrayBridge.stopHev();
    } catch (e) {
      console.error(`${TAG} stopHev error: ${(e as Error).message}`);
    }
    try {
      XrayBridge.stopXray();
    } catch (e) {
      console.error(`${TAG} stopXray error: ${(e as Error).message}`);
    }
    if (this.vpnConn) {
      this.vpnConn.destroy().catch((e: Error) => {
        console.error(`${TAG} vpn destroy error: ${e.message}`);
      });
      this.vpnConn = null;
    }
    this.tunFd = -1;
    RuntimeStore.setState(ctx, CoreState.STOPPED, '');
    console.info(`${TAG} core stopped`);
  }
}

function buildHevYaml(socksPort: number, ipv6: boolean): string {
  // hev-socks5-tunnel 配置：单线程、低开销
  return [
    'tunnel:',
    '  mtu: 8500',
    `  ipv4: 10.0.0.2`,
    'socks5:',
    `  port: ${socksPort}`,
    '  address: 127.0.0.1',
    '  udp: udp',
    'misc:',
    '  task-stack-size: 24576',
  ].join('\n');
}
