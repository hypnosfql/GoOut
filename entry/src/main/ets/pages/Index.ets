import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { NodeProfile, CoreState } from '../common/Types';
import { NodeStore } from '../store/NodeStore';
import { CoreManager } from '../core/CoreManager';
import { RuntimeInfo } from '../store/RuntimeStore';
import { ShareLinkParser } from '../core/ShareLinkParser';
import { PingTester } from '../core/PingTester';
import { XrayBridge } from '../core/XrayBridge';

/** 节点分组（按订阅） */
interface NodeGroup {
  subId: string;      // '' 表示手动添加
  name: string;
  expanded: boolean;
  nodes: NodeProfile[];
}

@Entry
@Component
struct Index {
  @State nodes: NodeProfile[] = [];
  @State groups: NodeGroup[] = [];
  @State selectedId: string = '';
  @State runtime: RuntimeInfo = { state: CoreState.STOPPED, message: '', activeNode: '' };
  @State testing: boolean = false;
  @State coreVersion: string = '';
  importDialog: CustomDialogController = new CustomDialogController({
    builder: ImportDialog({
      onImport: (text: string) => {
        this.importText(text);
      },
      onPaste: (): Promise<string> => this.readClipboard(),
    }),
    customStyle: true,
  });
  private ctx: common.Context = getContext(this);
  private timer: number = -1;

  aboutToAppear(): void {
    this.reload();
    // M0 验证：调用 native Go 桥
    this.coreVersion = XrayBridge.xrayVersion();
    // 页面可见期间每秒同步一次扩展进程状态（轻量轮询，仅前台）
    this.timer = setInterval(() => {
      this.runtime = CoreManager.getRuntime(this.ctx);
    }, 1000);
  }

  aboutToDisappear(): void {
    clearInterval(this.timer);
  }

  onPageShow(): void {
    this.reload();
  }

  private reload(): void {
    this.nodes = NodeStore.loadNodes(this.ctx);
    this.selectedId = NodeStore.getSelectedId(this.ctx);
    this.runtime = CoreManager.getRuntime(this.ctx);
    this.groups = this.buildGroups();
  }

  /** 按订阅分组：手动添加在前，订阅按添加顺序；保留原展开状态，默认折叠 */
  private buildGroups(): NodeGroup[] {
    const subs = NodeStore.loadSubs(this.ctx);
    const subName = new Map<string, string>();
    for (const s of subs) {
      subName.set(s.id, s.name);
    }
    // 保留之前的展开状态
    const prevExpanded = new Map<string, boolean>();
    for (const g of this.groups) {
      prevExpanded.set(g.subId, g.expanded);
    }
    const bySub = new Map<string, NodeProfile[]>();
    for (const n of this.nodes) {
      const key = n.subId ?? '';
      if (!bySub.has(key)) {
        bySub.set(key, []);
      }
      bySub.get(key)!.push(n);
    }
    const groups: NodeGroup[] = [];
    const manual = bySub.get('');
    if (manual && manual.length > 0) {
      groups.push({
        subId: '',
        name: '手动添加',
        expanded: prevExpanded.get('') ?? false,
        nodes: manual,
      });
    }
    for (const s of subs) {
      const nodes = bySub.get(s.id);
      if (nodes && nodes.length > 0) {
        groups.push({
          subId: s.id,
          name: subName.get(s.id) ?? '订阅',
          expanded: prevExpanded.get(s.id) ?? false,
          nodes,
        });
      }
    }
    // 防御：subId 存在但订阅已删除的孤儿节点
    for (const key of bySub.keys()) {
      const nodes = bySub.get(key)!;
      if (key !== '' && !subName.has(key) && nodes.length > 0) {
        groups.push({
          subId: key,
          name: '其他',
          expanded: prevExpanded.get(key) ?? false,
          nodes,
        });
      }
    }
    return groups;
  }

  private toggleGroup(subId: string): void {
    const groups: NodeGroup[] = [];
    for (const g of this.groups) {
      if (g.subId === subId) {
        groups.push({ subId: g.subId, name: g.name, expanded: !g.expanded, nodes: g.nodes });
      } else {
        groups.push(g);
      }
    }
    this.groups = groups;
  }

  private stateText(): string {
    switch (this.runtime.state) {
      case CoreState.RUNNING:
        return `已连接 · ${this.runtime.activeNode}`;
      case CoreState.STARTING:
        return '连接中…';
      case CoreState.STOPPING:
        return '断开中…';
      case CoreState.ERROR:
        return `错误: ${this.runtime.message}`;
      default:
        return '未连接';
    }
  }

  private isRunning(): boolean {
    return this.runtime.state === CoreState.RUNNING;
  }

  build() {
    Column() {
      // ---- 顶部栏 ----
      Row() {
        Text('GoOut')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
        Blank()
        Button('订阅')
          .fontSize(14)
          .backgroundColor(Color.Transparent)
          .fontColor($r('sys.color.ohos_id_color_text_primary_activated'))
          .onClick(() => router.pushUrl({ url: 'pages/SubscriptionPage' }))
        Button('设置')
          .fontSize(14)
          .backgroundColor(Color.Transparent)
          .fontColor($r('sys.color.ohos_id_color_text_primary_activated'))
          .onClick(() => router.pushUrl({ url: 'pages/SettingsPage' }))
      }
      .width('100%')
      .padding({ left: 16, right: 8, top: 12, bottom: 4 })

      // ---- 状态栏 ----
      Row() {
        Circle({ width: 10, height: 10 })
          .fill(this.isRunning() ? '#4CAF50' : '#9E9E9E')
          .margin({ right: 8 })
        Text(this.stateText() + (this.coreVersion ? ` · 内核: ${this.coreVersion}` : ''))
          .fontSize(13)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 4, bottom: 8 })

      // ---- 操作行 ----
      Row({ space: 12 }) {
        Button('导入链接')
          .fontSize(13)
          .height(32)
          .onClick(() => this.showImportDialog())
        Button('测速')
          .fontSize(13)
          .height(32)
          .enabled(!this.testing && this.nodes.length > 0)
          .onClick(() => this.testAll())
        Button('日志')
          .fontSize(13)
          .height(32)
          .onClick(() => router.pushUrl({ url: 'pages/LogPage' }))
      }
      .width('100%')
      .padding({ left: 16, bottom: 8 })

      Divider().strokeWidth(0.5)

      // ---- 节点列表（按订阅分组，默认折叠） ----
      List({ space: 8 }) {
        ForEach(this.groups, (group: NodeGroup) => {
          ListItemGroup() {
            // 组头
            ListItem() {
              this.GroupHeader(group)
            }
            // 展开的节点
            if (group.expanded) {
              ForEach(group.nodes, (node: NodeProfile) => {
                ListItem() {
                  this.NodeItem(node)
                }
                .gesture(
                  LongPressGesture()
                    .onAction(() => this.showNodeOps(node))
                )
              }, (node: NodeProfile) => `${node.id}_${node.delay}`)
            }
          }
        }, (group: NodeGroup) => `${group.subId}_${group.expanded}_${group.nodes.length}`)
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 16, right: 16, top: 8 })
      .cachedCount(4)

      // ---- 连接按钮 ----
      Button(this.isRunning() ? '断开连接' : '连接')
        .width('90%')
        .height(48)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .backgroundColor(this.isRunning() ? '#E53935' : '#0A59F7')
        .margin({ bottom: 24, top: 8 })
        .enabled(this.runtime.state !== CoreState.STARTING && this.runtime.state !== CoreState.STOPPING)
        .onClick(async () => {
          const msg = this.isRunning()
            ? await CoreManager.disconnect(this.ctx)
            : await CoreManager.connect(this.ctx);
          if (msg) {
            promptAction.showToast({ message: msg });
          }
          this.runtime = CoreManager.getRuntime(this.ctx);
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }

  @Builder
  GroupHeader(group: NodeGroup) {
    Row() {
      Text(group.expanded ? '▾' : '▸')
        .fontSize(14)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .margin({ right: 8 })
      Text(group.name)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(`${group.nodes.length} 节点`)
        .fontSize(12)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius(12)
    .backgroundColor($r('sys.color.ohos_id_color_card_bg'))
    .onClick(() => this.toggleGroup(group.subId))
  }

  @Builder
  NodeItem(node: NodeProfile) {
    Row() {
      Column() {
        Text(node.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${node.protocol.toUpperCase()} · ${node.server}:${node.port}`)
          .fontSize(12)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (node.delay !== undefined && node.delay >= 0) {
        Text(`${node.delay}ms`)
          .fontSize(12)
          .fontColor(node.delay < 500 ? '#4CAF50' : '#FF9800')
          .margin({ right: 8 })
      }

      Radio({ group: 'node_select', value: node.id })
        .checked(this.selectedId === node.id)
        .onChange((checked: boolean) => {
          if (checked) {
            this.selectNode(node);
          }
        })
    }
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor(this.selectedId === node.id ? '#E8F0FE' : Color.White)
    .onClick(() => this.selectNode(node))
  }

  private async selectNode(node: NodeProfile): Promise<void> {
    this.selectedId = node.id;
    const msg = await CoreManager.switchNode(this.ctx, node.id);
    if (msg) {
      promptAction.showToast({ message: msg });
    }
  }

  private showImportDialog(): void {
    this.importDialog.open();
  }

  private importText(text: string): void {
    const nodes = ShareLinkParser.parseMulti(text);
    if (nodes.length === 0) {
      promptAction.showToast({ message: '未识别到有效节点链接' });
      return;
    }
    const all = NodeStore.loadNodes(this.ctx);
    for (const n of nodes) {
      all.push(n);
    }
    NodeStore.saveNodes(this.ctx, all);
    if (!this.selectedId && nodes.length > 0) {
      NodeStore.setSelectedId(this.ctx, nodes[0].id);
      this.selectedId = nodes[0].id;
    }
    promptAction.showToast({ message: `导入 ${nodes.length} 个节点` });
    this.reload();
  }

  private async readClipboard(): Promise<string> {
    try {
      const pb = pasteboard.getSystemPasteboard();
      if (!pb.hasDataSync()) {
        return '';
      }
      const data = pb.getDataSync();
      return data.getPrimaryText() ?? '';
    } catch (e) {
      return '';
    }
  }

  private showNodeOps(node: NodeProfile): void {
    promptAction.showDialog({
      title: node.name,
      message: `${node.server}:${node.port}`,
      buttons: [{ text: '删除', color: '#E53935' }, { text: '取消', color: '#888888' }],
    }).then((res) => {
      if (res.index === 0) {
        NodeStore.deleteNode(this.ctx, node.id);
        this.reload();
      }
    });
  }

  private async testAll(): Promise<void> {
    this.testing = true;
    promptAction.showToast({ message: '测速中…' });
    try {
      await PingTester.testNodes(this.ctx, this.nodes);
      this.reload();
      promptAction.showToast({ message: '测速完成' });
    } catch (e) {
      promptAction.showToast({ message: `测速失败: ${(e as Error).message}` });
    } finally {
      this.testing = false;
    }
  }
}


/** 导入分享链接对话框 */
@CustomDialog
struct ImportDialog {
  controller: CustomDialogController;
  onImport: (text: string) => void = () => {};
  onPaste: () => Promise<string> = async () => '';
  @State inputText: string = '';

  build() {
    Column({ space: 12 }) {
      Text('导入分享链接')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
      TextArea({ placeholder: 'vless:// / vmess:// / ss:// / trojan://，多条按行分隔', text: $$this.inputText })
        .width('100%')
        .height(120)
        .fontSize(13)
      Row({ space: 12 }) {
        Button('粘贴')
          .fontSize(14)
          .layoutWeight(1)
          .onClick(async () => {
            const text = await this.onPaste();
            if (text) {
              this.inputText = text;
            }
          })
        Button('导入')
          .fontSize(14)
          .layoutWeight(1)
          .enabled(this.inputText.trim().length > 0)
          .onClick(() => {
            this.onImport(this.inputText);
            this.inputText = '';
            this.controller.close();
          })
        Button('取消')
          .fontSize(14)
          .layoutWeight(1)
          .backgroundColor('#999999')
          .onClick(() => this.controller.close())
      }
      .width('100%')
    }
    .width('85%')
    .padding(20)
    .borderRadius(16)
    .backgroundColor(Color.White)
  }
}
