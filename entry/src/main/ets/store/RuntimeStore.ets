import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { CoreState } from '../common/Types';

const STORE_NAME = 'goout_runtime';
const KEY_STATE = 'state';
const KEY_MSG = 'message';
const KEY_NODE = 'active_node';

export interface RuntimeInfo {
  state: CoreState;
  message: string;
  activeNode: string;
}

/**
 * 运行状态跨进程共享（UI 进程读 / VPN 扩展进程写）。
 * 用 Preferences 而非内存，保证 VPN 扩展进程的状态对 UI 可见。
 */
export class RuntimeStore {
  private static pref: preferences.Preferences | null = null;

  private static get(context: common.Context): preferences.Preferences {
    if (!RuntimeStore.pref) {
      RuntimeStore.pref = preferences.getPreferencesSync(context, { name: STORE_NAME });
    }
    return RuntimeStore.pref;
  }

  static setState(context: common.Context, state: CoreState, message: string = '',
    activeNode?: string): void {
    const p = RuntimeStore.get(context);
    p.putSync(KEY_STATE, state);
    p.putSync(KEY_MSG, message);
    if (activeNode !== undefined) {
      p.putSync(KEY_NODE, activeNode);
    }
    p.flush();
  }

  static getState(context: common.Context): RuntimeInfo {
    const p = RuntimeStore.get(context);
    return {
      state: p.getSync(KEY_STATE, CoreState.STOPPED) as CoreState,
      message: p.getSync(KEY_MSG, '') as string,
      activeNode: p.getSync(KEY_NODE, '') as string,
    };
  }
}
