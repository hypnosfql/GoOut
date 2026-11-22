import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';

const TAG = 'GeoAssets';

/** geo 数据下载源（按优先级尝试） */
const MIRRORS: string[][] = [
  // [geoip url, geosite url]
  [
    'https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/geoip.dat',
    'https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/geosite.dat',
  ],
  [
    'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat',
    'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat',
  ],
];

const GEO_FILES: string[] = ['geoip.dat', 'geosite.dat'];
/** 体积下限：小于该值视为下载失败（错误页/截断） */
const MIN_SIZE = 1024 * 1024;

/** geo 数据管理：按需下载（首连 bypass_cn 时），已下载则离线复用 */
export class GeoAssets {
  /** geo 数据目录是否就绪（同步检查，不触发下载） */
  static isReady(context: common.Context): boolean {
    const dir = GeoAssets.dirOf(context);
    try {
      for (const name of GEO_FILES) {
        const target = `${dir}/${name}`;
        if (!fileIo.accessSync(target)) {
          return false;
        }
        if (fileIo.statSync(target).size < MIN_SIZE) {
          return false;
        }
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /** 返回 geo 数据目录（xray 资产目录） */
  static dirOf(context: common.Context): string {
    return `${context.filesDir}/geo`;
  }

  /**
   * 确保 geo 数据就绪：缺失则下载（双源回退）。
   * 返回 '' 成功；否则返回错误信息。
   */
  static async ensure(context: common.Context): Promise<string> {
    if (GeoAssets.isReady(context)) {
      return '';
    }
    const dir = GeoAssets.dirOf(context);
    try {
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir, true);
      }
    } catch (e) {
      console.error(`${TAG} mkdir failed: ${(e as Error).message}`);
    }
    let lastErr = '';
    for (const mirror of MIRRORS) {
      for (let i = 0; i < GEO_FILES.length; i++) {
        try {
          console.info(`${TAG} downloading ${GEO_FILES[i]} from ${mirror[i]}`);
          await GeoAssets.download(mirror[i], `${dir}/${GEO_FILES[i]}`);
        } catch (e) {
          lastErr = (e as Error).message;
          console.error(`${TAG} download failed: ${lastErr}`);
          break; // 换下一个源
        }
      }
      if (GeoAssets.isReady(context)) {
        return '';
      }
    }
    // 失败清理半截文件
    GeoAssets.cleanPartial(context);
    return `分流数据下载失败: ${lastErr}（请检查网络后重试，或在设置中改用全局代理/直连模式）`;
  }

  /** 强制重新下载（设置页手动更新） */
  static async forceUpdate(context: common.Context): Promise<string> {
    const dir = GeoAssets.dirOf(context);
    for (const name of GEO_FILES) {
      const target = `${dir}/${name}`;
      try {
        if (fileIo.accessSync(target)) {
          fileIo.unlinkSync(target);
        }
      } catch (e) {
        // 忽略
      }
    }
    return GeoAssets.ensure(context);
  }

  private static cleanPartial(context: common.Context): void {
    const dir = GeoAssets.dirOf(context);
    for (const name of GEO_FILES) {
      const target = `${dir}/${name}`;
      try {
        if (fileIo.accessSync(target) && fileIo.statSync(target).size < MIN_SIZE) {
          fileIo.unlinkSync(target);
        }
      } catch (e) {
        // 忽略清理失败
      }
    }
  }

  private static download(url: string, filePath: string): Promise<void> {
    return new Promise((resolve, reject) => {
      const req = http.createHttp();
      req.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 15000,
        readTimeout: 120000,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        header: { 'User-Agent': 'GoOut/1.0' },
      }, (err, resp) => {
        req.destroy();
        if (err) {
          reject(new Error(err.message));
          return;
        }
        if (resp.responseCode !== 200) {
          reject(new Error(`HTTP ${resp.responseCode}`));
          return;
        }
        try {
          const buf = resp.result as ArrayBuffer;
          const file = fileIo.openSync(filePath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
          fileIo.writeSync(file.fd, buf);
          fileIo.closeSync(file);
          const size = fileIo.statSync(filePath).size;
          if (size < MIN_SIZE) {
            reject(new Error(`文件不完整(${size}B)`));
            return;
          }
          resolve();
        } catch (e) {
          reject(new Error(`写入失败: ${(e as Error).message}`));
        }
      });
    });
  }
}
