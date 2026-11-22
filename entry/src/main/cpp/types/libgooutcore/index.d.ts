/**
 * gooutcore native module
 * - invoke: JSON 单入口，对接 Go 桥（M0 stub / M1 libXray 后端）
 * - startHev/stopHev: hev-socks5-tunnel（M2）
 */
export interface GoResponse {
  code: number;
  msg?: string;
  data?: object | string | number | boolean | null;
}

export const invoke: (req: string) => string;
export const startHev: (configYaml: string, fd: number) => boolean;
export const stopHev: () => boolean;
export const isHevRunning: () => boolean;
