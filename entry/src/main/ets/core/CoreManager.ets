import { vpnExtension } from '@kit.NetworkKit';
import { settings } from '@kit.BasicServicesKit';
import { common, Want } from '@kit.AbilityKit';
import { CoreState, WorkMode, RoutingMode, NodeProfile, AppSettings } from '../common/Types';
import { RuntimeInfo, RuntimeStore } from '../store/RuntimeStore';
import { NodeStore } from '../store/NodeStore';
import { SettingsStore } from '../store/SettingsStore';
import { XrayConfigBuilder } from './XrayConfigBuilder';
import { XrayBridge } from './XrayBridge';
import { GeoAssets } from './GeoAssets';
import BuildProfile from 'BuildProfile';

const BUNDLE_NAME = 'com.fql.goout';
const VPN_ABILITY = 'GoOutVpnExtAbility';

/** UI 侧核心控制器：只负责启停 VPN 扩展，实际内核在扩展进程内运行 */
export class CoreManager {
  private static buildWant(): Want {
    return {
      bundleName: BUNDLE_NAME,
      abilityName: VPN_ABILITY,
    };
  }

  static getRuntime(context: common.Context): RuntimeInfo {
    return RuntimeStore.getState(context);
  }

  /**
   * 预授权：VPN 授权状态存于 settingsdata（key=包名[_userId]，value="1"）。
   * 写入后 startVpnExtensionAbility 会跳过系统授权弹窗。
   * 主要用于模拟器（公共镜像缺 vpndialog 系统组件）。
   */
  private static async preAuthorize(context: common.Context): Promise<void> {
    const keys = [`${BUNDLE_NAME}_100`, BUNDLE_NAME];
    for (const key of keys) {
      try {
        await settings.setValue(context, key, '1');
      } catch (e) {
        console.error(`CoreManager preAuthorize ${key} error: ${(e as Error).message}`);
      }
    }
  }

  /** 连接：先校验选中节点，再启动 VPN 扩展（系统可能弹出授权框） */
  static async connect(context: common.Context): Promise<string> {
    const runtime = RuntimeStore.getState(context);
    if (runtime.state === CoreState.RUNNING || runtime.state === CoreState.STARTING) {
      return '已在运行中';
    }
    const selectedId = NodeStore.getSelectedId(context);
    const node = NodeStore.loadNodes(context).find((n) => n.id === selectedId);
    if (!node) {
      return '请先选择节点';
    }
    const appSettings = SettingsStore.load(context);
    // 绕过大陆模式需要 geo 分流数据，缺失时按需下载
    if (appSettings.routingMode === RoutingMode.BYPASS_CN && !GeoAssets.isReady(context)) {
      RuntimeStore.setState(context, CoreState.STARTING, '正在下载分流数据(约28MB)…');
      const err = await GeoAssets.ensure(context);
      if (err) {
        RuntimeStore.setState(context, CoreState.ERROR, err);
        return err;
      }
    }
    await CoreManager.preAuthorize(context);
    // 仅代理模式只在开发构建(debug)可用；发布包即使设置残留也强制走 VPN 模式
    if (appSettings.workMode === WorkMode.PROXY && BuildProfile.DEBUG) {
      return CoreManager.connectProxyMode(context, node, appSettings);
    }
    try {
      RuntimeStore.setState(context, CoreState.STARTING, '正在启动 VPN');
      // 系统 VPN 授权流程可能挂起（模拟器缺 vpndialog），加超时兜底
      const timeout = new Promise<void>((resolve, reject) => {
        setTimeout(() => reject(new Error('启动超时')), 15000);
      });
      await Promise.race([
        vpnExtension.startVpnExtensionAbility(CoreManager.buildWant()),
        timeout,
      ]);
      return '';
    } catch (e) {
      const err = e as Error;
      RuntimeStore.setState(context, CoreState.ERROR, err.message);
      return `启动失败: ${err.message}`;
    }
  }

  /** 仅代理模式：不建 VPN，直接在 UI 进程跑 xray（模拟器无 TUN 时验证内核全链路） */
  private static connectProxyMode(context: common.Context, node: NodeProfile,
    appSettings: AppSettings): string {
    try {
      RuntimeStore.setState(context, CoreState.STARTING, '内核启动中(代理模式)');
      const config = XrayConfigBuilder.build(node, appSettings);
      const datadir = GeoAssets.dirOf(context);
      if (!XrayBridge.runXray(config, datadir)) {
        RuntimeStore.setState(context, CoreState.ERROR, 'xray 内核启动失败');
        return 'xray 内核启动失败';
      }
      RuntimeStore.setState(context, CoreState.RUNNING, `[代理模式] SOCKS5 127.0.0.1:${appSettings.socksPort}`, node.name);
      return '';
    } catch (e) {
      const err = e as Error;
      RuntimeStore.setState(context, CoreState.ERROR, err.message);
      return `启动失败: ${err.message}`;
    }
  }

  static async disconnect(context: common.Context): Promise<string> {
    const appSettings = SettingsStore.load(context);
    if (appSettings.workMode === WorkMode.PROXY) {
      RuntimeStore.setState(context, CoreState.STOPPING, '');
      XrayBridge.stopXray();
      RuntimeStore.setState(context, CoreState.STOPPED, '');
      return '';
    }
    try {
      RuntimeStore.setState(context, CoreState.STOPPING, '');
      await vpnExtension.stopVpnExtensionAbility(CoreManager.buildWant());
      RuntimeStore.setState(context, CoreState.STOPPED, '');
      return '';
    } catch (e) {
      const err = e as Error;
      return `停止失败: ${err.message}`;
    }
  }

  /** 切换节点：运行中则重启扩展 */
  static async switchNode(context: common.Context, nodeId: string): Promise<string> {
    const runtime = RuntimeStore.getState(context);
    NodeStore.setSelectedId(context, nodeId);
    if (runtime.state === CoreState.RUNNING || runtime.state === CoreState.STARTING) {
      await CoreManager.disconnect(context);
      return await CoreManager.connect(context);
    }
    return '';
  }
}
