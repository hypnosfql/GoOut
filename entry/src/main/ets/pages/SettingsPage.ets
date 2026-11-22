import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { AppSettings, RoutingMode, WorkMode } from '../common/Types';
import BuildProfile from 'BuildProfile';
import { SettingsStore } from '../store/SettingsStore';
import { GeoAssets } from '../core/GeoAssets';

@Entry
@Component
struct SettingsPage {
  @State settings: AppSettings = {
    workMode: WorkMode.VPN,
    routingMode: RoutingMode.BYPASS_CN,
    socksPort: 10808,
    dnsRemote: '1.1.1.1',
    dnsDirect: '223.5.5.5',
    logLevel: 'warning',
    ipv6: false,
  };
  private ctx: common.Context = getContext(this);

  @State updatingGeo: boolean = false;
  @State geoStatus: string = '';

  aboutToAppear(): void {
    this.settings = SettingsStore.load(this.ctx);
    this.refreshGeoStatus();
  }

  private refreshGeoStatus(): void {
    this.geoStatus = GeoAssets.isReady(this.ctx) ? '已下载（绕过大陆模式可用）' : '未下载（首次连接时自动下载）';
  }

  build() {
    Column() {
      Row() {
        Button('返回')
          .fontSize(14)
          .backgroundColor(Color.Transparent)
          .fontColor($r('sys.color.ohos_id_color_text_primary_activated'))
          .onClick(() => {
            this.save();
            router.back();
          })
        Text('设置')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .margin({ left: 8 })
      }
      .width('100%')
      .padding({ left: 8, right: 16, top: 12, bottom: 12 })

      Scroll() {
        Column({ space: 12 }) {
          // 工作模式
          this.ModeGroup()

          // 路由模式
          this.RoutingGroup()

          // 网络
          this.NetworkGroup()

          // 分流数据
          this.GeoGroup()

          // 日志
          this.LogLevelGroup()
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 24 })
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }

  @Builder
  GroupTitle(title: string) {
    Text(title)
      .fontSize(13)
      .fontColor($r('sys.color.ohos_id_color_text_secondary'))
  }

  @Builder
  ModeGroup() {
    Column({ space: 8 }) {
      this.GroupTitle('工作模式')
      Column() {
        Column({ space: 4 }) {
          this.RadioRow('VPN 模式', this.settings.workMode === WorkMode.VPN, () => {
            this.settings.workMode = WorkMode.VPN;
          })
          if (BuildProfile.DEBUG) {
            this.RadioRow('仅代理模式（模拟器调试）', this.settings.workMode === WorkMode.PROXY, () => {
              this.settings.workMode = WorkMode.PROXY;
            })
          }
        }
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding(12)
      .borderRadius(12)
      .backgroundColor(Color.White)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  GeoGroup() {
    Column({ space: 8 }) {
      this.GroupTitle('分流数据（geoip/geosite）')
      Column() {
        Row() {
          Text(this.geoStatus)
            .fontSize(14)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
            .layoutWeight(1)
          Button(this.updatingGeo ? '下载中…' : '更新')
            .fontSize(13)
            .height(32)
            .enabled(!this.updatingGeo)
            .onClick(async () => {
              this.updatingGeo = true;
              const err = await GeoAssets.forceUpdate(this.ctx);
              this.updatingGeo = false;
              this.refreshGeoStatus();
              promptAction.showToast({ message: err || '分流数据更新成功' });
            })
        }
        .width('100%')
      }
      .width('100%')
      .padding(12)
      .borderRadius(12)
      .backgroundColor(Color.White)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  RoutingGroup() {
    Column({ space: 8 }) {
      this.GroupTitle('路由模式')
      Column() {
        this.RoutingGroupContent()
      }
      .width('100%')
      .padding(12)
      .borderRadius(12)
      .backgroundColor(Color.White)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  NetworkGroup() {
    Column({ space: 8 }) {
      this.GroupTitle('网络')
      Column() {
        this.NetworkGroupContent()
      }
      .width('100%')
      .padding(12)
      .borderRadius(12)
      .backgroundColor(Color.White)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  LogLevelGroup() {
    Column({ space: 8 }) {
      this.GroupTitle('日志等级')
      Column() {
        this.LogLevelGroupContent()
      }
      .width('100%')
      .padding(12)
      .borderRadius(12)
      .backgroundColor(Color.White)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  RadioRow(label: string, checked: boolean, onSelect: () => void) {
    Row() {
      Text(label)
        .fontSize(15)
        .layoutWeight(1)
      Radio({ group: label, value: label })
        .checked(checked)
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 })
    .onClick(onSelect)
  }

  @Builder
  TextRow(label: string, value: string, onChange: (v: string) => void) {
    Row() {
      Text(label)
        .fontSize(15)
        .layoutWeight(1)
      TextInput({ text: value })
        .width(140)
        .height(36)
        .fontSize(14)
        .onChange(onChange)
    }
    .width('100%')
  }

  @Builder
  RoutingGroupContent() {
    Column({ space: 4 }) {
      this.RadioRow('绕过大陆（推荐）', this.settings.routingMode === RoutingMode.BYPASS_CN, () => {
        this.settings.routingMode = RoutingMode.BYPASS_CN;
      })
      this.RadioRow('全局代理', this.settings.routingMode === RoutingMode.GLOBAL, () => {
        this.settings.routingMode = RoutingMode.GLOBAL;
      })
      this.RadioRow('全局直连（调试）', this.settings.routingMode === RoutingMode.DIRECT, () => {
        this.settings.routingMode = RoutingMode.DIRECT;
      })
    }
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  NetworkGroupContent() {
    Column({ space: 8 }) {
      this.TextRow('本地 SOCKS 端口', this.settings.socksPort.toString(), (v: string) => {
        const p = parseInt(v);
        if (p > 1024 && p < 65535) {
          this.settings.socksPort = p;
        }
      })
      this.TextRow('远程 DNS', this.settings.dnsRemote, (v: string) => {
        this.settings.dnsRemote = v;
      })
      this.TextRow('直连 DNS', this.settings.dnsDirect, (v: string) => {
        this.settings.dnsDirect = v;
      })
      Row() {
        Text('IPv6')
          .fontSize(15)
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.settings.ipv6 })
          .onChange((on: boolean) => {
            this.settings.ipv6 = on;
          })
      }
      .width('100%')
    }
  }

  @Builder
  LogLevelGroupContent() {
    Column({ space: 4 }) {
      ForEach(['debug', 'info', 'warning', 'error'], (level: string) => {
        this.RadioRow(level, this.settings.logLevel === level, () => {
          this.settings.logLevel = level;
        })
      }, (level: string) => level)
    }
    .alignItems(HorizontalAlign.Start)
  }

  private save(): void {
    SettingsStore.save(this.ctx, this.settings);
    promptAction.showToast({ message: '设置已保存' });
  }
}
