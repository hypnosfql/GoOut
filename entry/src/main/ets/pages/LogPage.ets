import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { RuntimeInfo, RuntimeStore } from '../store/RuntimeStore';

/**
 * 日志页：显示运行状态与内核日志文件（内核侧写 filesDir/goout.log，M5 完善）
 */
@Entry
@Component
struct LogPage {
  @State logText: string = '';
  @State runtimeText: string = '';
  private ctx: common.Context = getContext(this);
  private timer: number = -1;

  aboutToAppear(): void {
    this.refresh();
    this.timer = setInterval(() => this.refresh(), 2000);
  }

  aboutToDisappear(): void {
    clearInterval(this.timer);
  }

  private refresh(): void {
    const info: RuntimeInfo = RuntimeStore.getState(this.ctx);
    this.runtimeText = `状态: ${info.state}\n节点: ${info.activeNode || '-'}\n消息: ${info.message || '-'}`;
    try {
      const path = `${this.ctx.filesDir}/goout.log`;
      if (fs.accessSync(path)) {
        const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
        const stat = fs.statSync(file.fd);
        const size = Math.min(stat.size, 64 * 1024); // 只读尾部 64KB
        const buf = new ArrayBuffer(size);
        fs.readSync(file.fd, buf, { offset: stat.size - size });
        fs.closeSync(file);
        const decoder = util.TextDecoder.create('utf-8');
        this.logText = decoder.decodeToString(new Uint8Array(buf));
      }
    } catch (e) {
      // 日志文件不存在属于正常情况
      console.debug(`LogPage refresh: ${(e as Error).message}`);
    }
  }

  build() {
    Column() {
      Row() {
        Button('返回')
          .fontSize(14)
          .backgroundColor(Color.Transparent)
          .fontColor($r('sys.color.ohos_id_color_text_primary_activated'))
          .onClick(() => router.back())
        Text('日志')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .margin({ left: 8 })
      }
      .width('100%')
      .padding({ left: 8, right: 16, top: 12, bottom: 12 })

      Text(this.runtimeText)
        .fontSize(13)
        .fontFamily('monospace')
        .width('100%')
        .padding(12)
        .backgroundColor(Color.White)
        .borderRadius(12)
        .margin({ left: 16, right: 16, bottom: 8 })

      Scroll() {
        Text(this.logText || '暂无内核日志')
          .fontSize(11)
          .fontFamily('monospace')
          .fontColor('#D4D4D4')
          .width('100%')
          .padding(12)
      }
      .layoutWeight(1)
      .width('100%')
      .margin({ left: 16, right: 16, bottom: 16 })
      .backgroundColor('#1E1E1E')
      .borderRadius(12)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
