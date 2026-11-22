import gooutcore from 'libgooutcore.so';

/** invoke 请求/响应类型（ArkTS 严格模式要求显式声明） */
interface InvokeReq {
  action: string;
  payload: object;
}

interface InvokeResp<T> {
  code: number;
  msg?: string;
  data?: T;
}

/** NAPI 桥：对 Go 内核(libgoout/libxray)的薄封装 */
export class XrayBridge {
  static invoke(action: string, payload: object): string {
    const req: InvokeReq = { action, payload };
    return gooutcore.invoke(JSON.stringify(req));
  }

  /** 解析响应，失败时返回 null 并打日志 */
  static invokeData<T>(action: string, payload?: object): T | null {
    try {
      const raw = XrayBridge.invoke(action, payload ?? new InvokeEmpty());
      const resp = JSON.parse(raw) as InvokeResp<T>;
      if (resp.code === 0) {
        return resp.data ?? null;
      }
      console.error(`XrayBridge ${action} error: ${resp.msg ?? 'unknown'}`);
    } catch (e) {
      console.error(`XrayBridge ${action} exception: ${(e as Error).message}`);
    }
    return null;
  }

  /** 启动 xray 内核 */
  static runXray(configJson: string, datadir: string): boolean {
    const payload: RunXrayPayload = { xray: configJson, datadir };
    const data = XrayBridge.invokeData<string>('RunXray', payload);
    return data !== null;
  }

  static stopXray(): boolean {
    const data = XrayBridge.invokeData<string>('StopXray');
    return data !== null;
  }

  static xrayVersion(): string {
    return XrayBridge.invokeData<string>('version') ?? 'unknown';
  }

  /** hev-socks5-tunnel */
  static startHev(configYaml: string, fd: number): boolean {
    return gooutcore.startHev(configYaml, fd);
  }

  static stopHev(): boolean {
    return gooutcore.stopHev();
  }

  static isHevRunning(): boolean {
    return gooutcore.isHevRunning();
  }
}

class InvokeEmpty {
}

interface RunXrayPayload {
  xray: string;
  datadir: string;
}
