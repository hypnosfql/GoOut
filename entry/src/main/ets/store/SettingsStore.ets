import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { AppSettings, DEFAULT_SETTINGS, RoutingMode, WorkMode } from '../common/Types';

const STORE_NAME = 'goout_settings';
const KEY_SETTINGS = 'settings';

/** 部分设置（反序列化用） */
interface PartialSettings {
  workMode?: WorkMode;
  routingMode?: RoutingMode;
  socksPort?: number;
  dnsRemote?: string;
  dnsDirect?: string;
  logLevel?: string;
  ipv6?: boolean;
}

/** 应用设置持久化（Preferences KV，轻量） */
export class SettingsStore {
  private static pref: preferences.Preferences | null = null;

  private static get(context: common.Context): preferences.Preferences {
    if (!SettingsStore.pref) {
      SettingsStore.pref = preferences.getPreferencesSync(context, { name: STORE_NAME });
    }
    return SettingsStore.pref;
  }

  static load(context: common.Context): AppSettings {
    const raw = SettingsStore.get(context).getSync(KEY_SETTINGS, '') as string;
    const result: AppSettings = {
      workMode: DEFAULT_SETTINGS.workMode,
      routingMode: DEFAULT_SETTINGS.routingMode,
      socksPort: DEFAULT_SETTINGS.socksPort,
      dnsRemote: DEFAULT_SETTINGS.dnsRemote,
      dnsDirect: DEFAULT_SETTINGS.dnsDirect,
      logLevel: DEFAULT_SETTINGS.logLevel,
      ipv6: DEFAULT_SETTINGS.ipv6,
    };
    if (raw) {
      try {
        const parsed = JSON.parse(raw) as PartialSettings;
        // 手动合并，兼容后续新增字段
        if (parsed.routingMode !== undefined) {
          result.routingMode = parsed.routingMode;
        }
        if (parsed.workMode !== undefined) {
          result.workMode = parsed.workMode;
        }
        if (parsed.socksPort !== undefined) {
          result.socksPort = parsed.socksPort;
        }
        if (parsed.dnsRemote !== undefined) {
          result.dnsRemote = parsed.dnsRemote;
        }
        if (parsed.dnsDirect !== undefined) {
          result.dnsDirect = parsed.dnsDirect;
        }
        if (parsed.logLevel !== undefined) {
          result.logLevel = parsed.logLevel;
        }
        if (parsed.ipv6 !== undefined) {
          result.ipv6 = parsed.ipv6;
        }
      } catch (e) {
        console.error(`SettingsStore load parse error: ${(e as Error).message}`);
      }
    }
    return result;
  }

  static save(context: common.Context, settings: AppSettings): void {
    const p = SettingsStore.get(context);
    p.putSync(KEY_SETTINGS, JSON.stringify(settings));
    p.flush();
  }
}
