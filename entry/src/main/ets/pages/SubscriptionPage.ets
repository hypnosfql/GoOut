import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { SubscriptionItem } from '../common/Types';
import { NodeStore } from '../store/NodeStore';
import { SubscriptionManager } from '../core/SubscriptionManager';

@Entry
@Component
struct SubscriptionPage {
  @State subs: SubscriptionItem[] = [];
  @State newName: string = '';
  @State newUrl: string = '';
  @State updatingId: string = '';
  private ctx: common.Context = getContext(this);

  aboutToAppear(): void {
    this.subs = NodeStore.loadSubs(this.ctx);
  }

  build() {
    Column() {
      // 顶部
      Row() {
        Button('返回')
          .fontSize(14)
          .backgroundColor(Color.Transparent)
          .fontColor($r('sys.color.ohos_id_color_text_primary_activated'))
          .onClick(() => router.back())
        Text('订阅管理')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .margin({ left: 8 })
      }
      .width('100%')
      .padding({ left: 8, right: 16, top: 12, bottom: 12 })

      // 添加订阅
      Column({ space: 8 }) {
        TextInput({ placeholder: '订阅名称', text: $$this.newName })
          .height(40)
        TextInput({ placeholder: '订阅地址 https://...', text: $$this.newUrl })
          .height(40)
        Button('添加并更新')
          .width('100%')
          .height(40)
          .enabled(this.newUrl.trim().startsWith('http'))
          .onClick(() => this.addSub())
      }
      .padding(16)
      .backgroundColor(Color.White)
      .borderRadius(12)
      .margin({ left: 16, right: 16, bottom: 16 })

      // 订阅列表
      List({ space: 8 }) {
        ForEach(this.subs, (sub: SubscriptionItem) => {
          ListItem() {
            Row() {
              Column() {
                Text(sub.name)
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                Text(sub.updatedAt > 0
                  ? `${sub.nodeCount} 节点 · ${new Date(sub.updatedAt).toLocaleString()}`
                  : '未更新')
                  .fontSize(12)
                  .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Button(this.updatingId === sub.id ? '更新中' : '更新')
                .fontSize(13)
                .height(32)
                .enabled(this.updatingId === '')
                .onClick(() => this.updateSub(sub))
              Button('删除')
                .fontSize(13)
                .height(32)
                .backgroundColor('#E53935')
                .margin({ left: 8 })
                .onClick(() => this.deleteSub(sub))
            }
            .width('100%')
            .padding(12)
            .borderRadius(12)
            .backgroundColor(Color.White)
          }
        }, (sub: SubscriptionItem) => `${sub.id}_${sub.updatedAt}`)
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }

  private async addSub(): Promise<void> {
    const sub: SubscriptionItem = {
      id: NodeStore.newId(),
      name: this.newName.trim() || this.hostOf(this.newUrl.trim()),
      url: this.newUrl.trim(),
      updatedAt: 0,
      nodeCount: 0,
    };
    // 先更新，成功才入库；失败不允许添加（问题 1 修复）
    this.updatingId = sub.id;
    try {
      const count = await SubscriptionManager.update(this.ctx, sub);
      if (count <= 0) {
        throw new Error('订阅内容为空或格式不支持（未解析到节点链接）');
      }
      sub.updatedAt = Date.now();
      sub.nodeCount = count;
      const subs = NodeStore.loadSubs(this.ctx);
      subs.push(sub);
      NodeStore.saveSubs(this.ctx, subs);
      this.subs = subs;
      this.newName = '';
      this.newUrl = '';
      promptAction.showToast({ message: `添加成功: ${count} 个节点` });
    } catch (e) {
      promptAction.showToast({ message: `添加失败: ${(e as Error).message}` });
      // 失败不入库
    } finally {
      this.updatingId = '';
    }
  }

  private hostOf(url: string): string {
    let s = url;
    const schemeIdx = s.indexOf('://');
    if (schemeIdx >= 0) {
      s = s.substring(schemeIdx + 3);
    }
    const slashIdx = s.indexOf('/');
    if (slashIdx >= 0) {
      s = s.substring(0, slashIdx);
    }
    const colonIdx = s.indexOf(':');
    if (colonIdx >= 0) {
      s = s.substring(0, colonIdx);
    }
    return s || 'subscription';
  }

  private async updateSub(sub: SubscriptionItem): Promise<void> {
    this.updatingId = sub.id;
    console.info(`SubscriptionPage updateSub click: ${JSON.stringify(sub)}`);
    try {
      const count = await SubscriptionManager.update(this.ctx, sub);
      if (count <= 0) {
        // 0 节点视为失败：不清空该订阅原有节点、不刷新时间
        throw new Error('订阅内容为空或格式不支持（未解析到节点链接）');
      }
      const subs = NodeStore.loadSubs(this.ctx);
      const idx = subs.findIndex((s) => s.id === sub.id);
      if (idx >= 0) {
        // 生成新对象，避免共享引用带来的交叉显示问题
        const updated: SubscriptionItem = {
          id: sub.id,
          name: sub.name,
          url: sub.url,
          updatedAt: Date.now(),
          nodeCount: count,
        };
        subs[idx] = updated;
        NodeStore.saveSubs(this.ctx, subs);
        this.subs = subs;
      }
      promptAction.showToast({ message: `更新成功: ${count} 个节点` });
    } catch (e) {
      console.error(`SubscriptionPage updateSub failed: ${(e as Error).message} ${(e as Error).stack}`);
      promptAction.showToast({ message: `更新失败: ${(e as Error).message}` });
    } finally {
      this.updatingId = '';
    }
  }

  private deleteSub(sub: SubscriptionItem): void {
    // 删除订阅同时删除其节点
    const nodes = NodeStore.loadNodes(this.ctx).filter((n) => n.subId !== sub.id);
    NodeStore.saveNodes(this.ctx, nodes);
    const subs = NodeStore.loadSubs(this.ctx).filter((s) => s.id !== sub.id);
    NodeStore.saveSubs(this.ctx, subs);
    this.subs = subs;
  }
}
