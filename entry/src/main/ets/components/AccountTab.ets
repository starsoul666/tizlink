import { promptAction, router } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import {
  APP_VERSION,
  AppSettings,
  AuthSession,
  formatBytes,
  formatDate,
  InviteCodeItem,
  InviteSummary,
  NoticeItem,
  OrderItem,
  SubscriptionInfo,
  VpnState
} from '../model/Models';
import { I18n } from '../model/I18n';
import { ApiService } from '../service/ApiService';
import { Theme } from './Theme';

type AccountSubView = 'none' | 'orders' | 'invite' | 'notices' | 'password' | 'terms';

@Component
export struct AccountTab {
  @Prop vpnState: VpnState = 'disconnected';
  @Prop subscription: SubscriptionInfo = {
    planName: '',
    subscribeUrl: '',
    expiredAt: 0,
    transferEnable: 0,
    usedUpload: 0,
    usedDownload: 0,
    resetDay: 0,
    email: '',
    balance: 0,
    uuid: ''
  };
  @Link settings: AppSettings;
  @Link auth: AuthSession;

  onRefreshAccount: () => void = () => {};
  onOpenPlans: () => void = () => {};
  onLogout: () => void = () => {};

  @State subView: AccountSubView = 'none';
  @State orders: OrderItem[] = [];
  @State inviteSummary: InviteSummary = {
    codes: [],
    registeredCount: 0,
    commissionRate: 0,
    commissionBalance: 0,
    pendingCommission: 0
  };
  @State notices: NoticeItem[] = [];
  @State loadingSub: boolean = false;
  @State oldPassword: string = '';
  @State newPassword: string = '';

  private showToast(msg: string): void {
    try {
      promptAction.showToast({ message: msg, duration: 2000 });
    } catch (_e) {
      // ignore
    }
  }

  private copyText(text: string): void {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      pasteboard.getSystemPasteboard().setDataSync(data);
      this.showToast(I18n.t('已复制到剪贴板', 'Copied to clipboard'));
    } catch (_e) {
      this.showToast(I18n.t('复制失败', 'Copy failed'));
    }
  }

  private getUsedTraffic(): number {
    return (this.subscription.usedUpload || 0) + (this.subscription.usedDownload || 0);
  }

  private getTrafficProgress(): number {
    const total: number = this.subscription.transferEnable || 0;
    if (total <= 0) {
      return 0;
    }
    return Math.min(100, Math.max(2, (this.getUsedTraffic() / total) * 100));
  }

  private async openOrders(): Promise<void> {
    this.subView = 'orders';
    this.loadingSub = true;
    const res = await ApiService.getInstance().fetchOrders(this.settings, this.auth);
    this.loadingSub = false;
    if (res.ok && res.data) {
      this.orders = res.data;
    } else {
      this.showToast(res.message);
    }
  }

  private async openInvite(): Promise<void> {
    this.subView = 'invite';
    this.loadingSub = true;
    const res = await ApiService.getInstance().fetchInviteSummary(this.settings, this.auth);
    this.loadingSub = false;
    if (res.ok && res.data) {
      this.inviteSummary = res.data;
    } else {
      this.showToast(res.message);
    }
  }

  private async openNotices(): Promise<void> {
    this.subView = 'notices';
    this.loadingSub = true;
    const res = await ApiService.getInstance().fetchNotices(this.settings, this.auth);
    this.loadingSub = false;
    if (res.ok && res.data) {
      this.notices = res.data;
    } else {
      this.showToast(res.message);
    }
  }

  private openCrispSupport(): void {
    const id: string = this.settings.crispWebsiteId.trim();
    if (id.length === 0) {
      this.showToast(I18n.t('暂无在线客服配置', 'Support widget not configured'));
      return;
    }
    router.pushUrl({
      url: 'pages/WebSupportPage',
      params: {
        title: I18n.t('在线客服', 'Customer Support'),
        url: `https://go.crisp.chat/chat/embed/?website_id=${encodeURIComponent(id)}`
      }
    });
  }

  build() {
    if (this.subView !== 'none') {
      this.buildSubView()
    } else {
      this.buildMainAccountView()
    }
  }

  @Builder
  private buildMainAccountView() {
    Scroll() {
      Column({ space: 14 }) {
        // Section 1: 连接状态 (exact match to APK Screenshot #2)
        Text(I18n.t('连接状态', 'Connection Status'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT_PRIMARY)
          .width('100%')
          .margin({ top: 6 })

        Row({ space: 10 }) {
          Circle()
            .width(10)
            .height(10)
            .fill(this.vpnState === 'connected' ? Theme.ACCENT_GREEN : Theme.TEXT_SECONDARY)
          Text(
            this.vpnState === 'connected'
              ? I18n.t('已连接', 'Connected')
              : this.vpnState === 'connecting'
                ? I18n.t('连接中...', 'Connecting...')
                : I18n.t('未连接', 'Disconnected')
          )
            .fontSize(15)
            .fontColor(Theme.TEXT_PRIMARY)
          Blank()
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 16, bottom: 16 })
        .backgroundColor(Theme.SURFACE)
        .borderRadius(16)
        .border({ width: 1, color: Theme.BORDER })
        .shadow({ radius: 10, color: Theme.SHADOW_CARD, offsetY: 2 })

        // Section 2: 订阅 (exact match to APK Screenshot #2)
        Row() {
          Text(I18n.t('订阅', 'Subscription'))
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.TEXT_PRIMARY)
          Blank()
          Text(I18n.t('刷新', 'Refresh'))
            .fontSize(13)
            .fontColor(Theme.ACCENT_BLUE)
            .onClick(() => {
              this.onRefreshAccount();
            })
        }
        .width('100%')
        .margin({ top: 4 })

        Column({ space: 14 }) {
          Row({ space: 14 }) {
            Column() {
              Text('★')
                .fontSize(20)
                .fontColor(Theme.ACCENT_BLUE)
            }
            .width(46)
            .height(46)
            .borderRadius(23)
            .backgroundColor(Theme.ACCENT_BLUE_SOFT)
            .justifyContent(FlexAlign.Center)

            Column({ space: 4 }) {
              Text(this.subscription.planName || I18n.t('暂无有效订阅', 'No Active Subscription'))
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.TEXT_PRIMARY)
              Text(
                this.subscription.expiredAt > 0
                  ? `${I18n.t('过期时间', 'Expires')}: ${formatDate(this.subscription.expiredAt)}`
                  : I18n.t('长期有效 / 未到期限制', 'No expiration')
              )
                .fontSize(13)
                .fontColor(Theme.TEXT_MUTED)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')

          Progress({ value: this.getTrafficProgress(), total: 100, type: ProgressType.Linear })
            .width('100%')
            .height(6)
            .color(Theme.ACCENT_BLUE)
            .backgroundColor('#E5E7EB')

          Row() {
            Text(`${I18n.t('已用流量', 'Used')}: ${formatBytes(this.getUsedTraffic())}`)
              .fontSize(12)
              .fontColor(Theme.TEXT_SECONDARY)
            Blank()
            Text(`${I18n.t('总流量', 'Total')}: ${formatBytes(this.subscription.transferEnable)}`)
              .fontSize(12)
              .fontColor(Theme.TEXT_SECONDARY)
          }
          .width('100%')

          if (this.subscription.resetDay > 0) {
            Row({ space: 8 }) {
              Text('↻')
                .fontSize(14)
                .fontColor(Theme.TEXT_SECONDARY)
              Text(I18n.t(`流量重置还剩 ${this.subscription.resetDay} 天`, `Traffic resets in ${this.subscription.resetDay} days`))
                .fontSize(13)
                .fontColor(Theme.TEXT_SECONDARY)
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 11, bottom: 11 })
            .backgroundColor(Theme.SURFACE_SOFT)
            .borderRadius(12)
          }

          // Outlined Blue Button: 续费订阅
          Row({ space: 6 }) {
            Text('↻')
              .fontSize(15)
              .fontColor(Theme.ACCENT_BLUE)
            Text(I18n.t('续费订阅', 'Renew Subscription'))
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.ACCENT_BLUE)
          }
          .width('100%')
          .height(46)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(Theme.SURFACE)
          .borderRadius(12)
          .border({ width: 1, color: '#BFDBFE' })
          .onClick(() => {
            this.onOpenPlans();
          })

          // Outlined Teal Button: 升级套餐
          Row({ space: 6 }) {
            Text('↑')
              .fontSize(15)
              .fontColor(Theme.ACCENT_TEAL)
            Text(I18n.t('升级套餐', 'Upgrade Plan'))
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.ACCENT_TEAL)
          }
          .width('100%')
          .height(46)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(Theme.SURFACE)
          .borderRadius(12)
          .border({ width: 1, color: '#CCFBF1' })
          .onClick(() => {
            this.onOpenPlans();
          })
        }
        .width('100%')
        .padding(18)
        .backgroundColor(Theme.SURFACE)
        .borderRadius(20)
        .border({ width: 1, color: Theme.BORDER })
        .shadow({ radius: 12, color: Theme.SHADOW_CARD, offsetY: 3 })

        // Section 3: 基本资料 (exact match to APK Screenshot #2)
        Text(I18n.t('基本资料', 'Profile'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT_PRIMARY)
          .width('100%')
          .margin({ top: 4 })

        Column({ space: 14 }) {
          Row({ space: 10 }) {
            Text('✉')
              .fontSize(16)
              .fontColor(Theme.ACCENT_BLUE)
            Text(`${I18n.t('邮箱', 'Email')}:`)
              .fontSize(14)
              .fontColor(Theme.TEXT_SECONDARY)
            Blank()
            Text(this.subscription.email || this.auth.email || '--')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.TEXT_PRIMARY)
          }
          .width('100%')

          Row({ space: 10 }) {
            Text('💳')
              .fontSize(16)
              .fontColor(Theme.ACCENT_BLUE)
            Text(`${I18n.t('余额', 'Balance')}:`)
              .fontSize(14)
              .fontColor(Theme.TEXT_SECONDARY)
            Blank()
            Text(`${this.subscription.balance}`)
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.TEXT_PRIMARY)
          }
          .width('100%')
        }
        .width('100%')
        .padding(18)
        .backgroundColor(Theme.SURFACE)
        .borderRadius(18)
        .border({ width: 1, color: Theme.BORDER })
        .shadow({ radius: 10, color: Theme.SHADOW_CARD, offsetY: 2 })

        // Section 4: 功能 (exact match to APK Screenshot #2 bottom)
        Text(I18n.t('功能', 'Features'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT_PRIMARY)
          .width('100%')
          .margin({ top: 4 })

        Column() {
          this.buildMenuRow('🧾', I18n.t('我的订单', 'My Orders'), () => {
            void this.openOrders();
          })
          Divider().color(Theme.BORDER)
          this.buildMenuRow('🎁', I18n.t('邀请好友', 'Invite Friends'), () => {
            void this.openInvite();
          })
          Divider().color(Theme.BORDER)
          this.buildMenuRow('📢', I18n.t('系统公告', 'Announcements'), () => {
            void this.openNotices();
          })
          Divider().color(Theme.BORDER)
          this.buildMenuRow('🔑', I18n.t('修改密码', 'Change Password'), () => {
            this.subView = 'password';
          })
          Divider().color(Theme.BORDER)
          this.buildMenuRow('💬', I18n.t('在线客服', 'Online Support'), () => {
            this.openCrispSupport();
          })
          Divider().color(Theme.BORDER)
          this.buildMenuRow('📄', I18n.t('服务条款', 'Terms of Service'), () => {
            this.subView = 'terms';
          })
        }
        .width('100%')
        .backgroundColor(Theme.SURFACE)
        .borderRadius(18)
        .border({ width: 1, color: Theme.BORDER })
        .shadow({ radius: 10, color: Theme.SHADOW_CARD, offsetY: 2 })

        // Logout Button
        Button(I18n.t('退出登录', 'Sign Out'))
          .width('100%')
          .height(48)
          .borderRadius(14)
          .backgroundColor(Theme.ACCENT_RED_SOFT)
          .fontColor(Theme.ACCENT_RED)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .border({ width: 1, color: '#FECACA' })
          .onClick(() => {
            this.onLogout();
          })

        Text(`TizLink HarmonyOS NEXT v${APP_VERSION}`)
          .fontSize(12)
          .fontColor(Theme.TEXT_MUTED)
          .margin({ top: 4, bottom: 96 })
      }
      .width('100%')
      .constraintSize({ maxWidth: 640 })
      .padding({ left: 20, right: 20, top: 8, bottom: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BG)
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
  }

  @Builder
  private buildMenuRow(icon: string, title: string, onClick: () => void) {
    Row({ space: 12 }) {
      Text(icon)
        .fontSize(16)
        .width(24)
        .textAlign(TextAlign.Center)
      Text(title)
        .fontSize(15)
        .fontColor(Theme.TEXT_PRIMARY)
        .layoutWeight(1)
      Text('›')
        .fontSize(20)
        .fontColor(Theme.TEXT_MUTED)
    }
    .width('100%')
    .height(54)
    .padding({ left: 16, right: 16 })
    .onClick(onClick)
  }

  @Builder
  private buildSubHeader(title: string) {
    Row({ space: 10 }) {
      Text('‹')
        .fontSize(28)
        .fontColor(Theme.TEXT_PRIMARY)
        .width(34)
        .height(34)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.subView = 'none';
        })
      Text(title)
        .fontSize(19)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TEXT_PRIMARY)
      Blank()
    }
    .width('100%')
    .padding({ left: 12, right: 20, top: 10, bottom: 10 })
  }

  @Builder
  private buildSubView() {
    Column() {
      if (this.subView === 'orders') {
        this.buildSubHeader(I18n.t('我的订单', 'My Orders'))
        if (this.loadingSub) {
          LoadingProgress().width(36).height(36).color(Theme.ACCENT_BLUE).margin({ top: 60 })
        } else if (this.orders.length === 0) {
          Text(I18n.t('暂无订单记录', 'No orders yet')).fontSize(14).fontColor(Theme.TEXT_SECONDARY).margin({ top: 60 })
        } else {
          List({ space: 10 }) {
            ForEach(this.orders, (o: OrderItem) => {
              ListItem() {
                Column({ space: 8 }) {
                  Row() {
                    Text(o.planName).fontSize(15).fontWeight(FontWeight.Bold).fontColor(Theme.TEXT_PRIMARY)
                    Blank()
                    Text(o.status === 3 ? I18n.t('已完成', 'Paid') : o.status === 2 ? I18n.t('已取消', 'Canceled') : I18n.t('待支付', 'Pending'))
                      .fontSize(12)
                      .fontColor(o.status === 3 ? Theme.ACCENT_GREEN : o.status === 2 ? Theme.TEXT_MUTED : Theme.ACCENT_AMBER)
                  }.width('100%')
                  Row() {
                    Text(`#${o.tradeNo}`).fontSize(12).fontColor(Theme.TEXT_MUTED)
                    Blank()
                    Text(`¥ ${o.totalAmount.toFixed(2)}`).fontSize(15).fontWeight(FontWeight.Bold).fontColor(Theme.TEXT_PRIMARY)
                  }.width('100%')
                }
                .width('100%')
                .padding(16)
                .backgroundColor(Theme.SURFACE)
                .borderRadius(16)
                .border({ width: 1, color: Theme.BORDER })
              }
            }, (o: OrderItem) => o.tradeNo)
            ListItem() {
              Column().height(86)
            }
          }
          .layoutWeight(1)
          .padding({ left: 20, right: 20 })
        }
      } else if (this.subView === 'invite') {
        this.buildSubHeader(I18n.t('邀请好友', 'Invite Friends'))
        Scroll() {
          Column({ space: 14 }) {
            Row({ space: 10 }) {
              this.buildStatBox(I18n.t('已邀请人数', 'Invites'), `${this.inviteSummary.registeredCount}`)
              this.buildStatBox(I18n.t('返利比例', 'Rate'), `${this.inviteSummary.commissionRate}%`)
              this.buildStatBox(I18n.t('可用佣金', 'Commission'), `¥${this.inviteSummary.commissionBalance.toFixed(2)}`)
            }.width('100%')

            if (this.inviteSummary.codes.length === 0) {
              Text(I18n.t('暂无邀请码', 'No invite codes')).fontSize(13).fontColor(Theme.TEXT_SECONDARY).margin({ top: 12 })
            } else {
              ForEach(this.inviteSummary.codes, (item: InviteCodeItem) => {
                Row() {
                  Text(item.code).fontSize(15).fontWeight(FontWeight.Medium).fontColor(Theme.TEXT_PRIMARY)
                  Blank()
                  Text(I18n.t('复制', 'Copy'))
                    .fontSize(13)
                    .fontColor(Theme.ACCENT_BLUE)
                    .onClick(() => this.copyText(item.code))
                }
                .width('100%')
                .padding(14)
                .backgroundColor(Theme.SURFACE_SOFT)
                .borderRadius(14)
              })
            }
          }
          .padding({ left: 20, right: 20, bottom: 96 })
        }.layoutWeight(1)
      } else if (this.subView === 'notices') {
        this.buildSubHeader(I18n.t('系统公告', 'Announcements'))
        if (this.loadingSub) {
          LoadingProgress().width(36).height(36).color(Theme.ACCENT_BLUE).margin({ top: 60 })
        } else if (this.notices.length === 0) {
          Text(I18n.t('暂无系统公告', 'No announcements')).fontSize(14).fontColor(Theme.TEXT_SECONDARY).margin({ top: 60 })
        } else {
          List({ space: 12 }) {
            ForEach(this.notices, (n: NoticeItem) => {
              ListItem() {
                Column({ space: 8 }) {
                  Row() {
                    Text(n.title).fontSize(15).fontWeight(FontWeight.Bold).fontColor(Theme.TEXT_PRIMARY).layoutWeight(1)
                    Text(formatDate(n.createdAt)).fontSize(11).fontColor(Theme.TEXT_MUTED)
                  }.width('100%')
                  Text(n.content.replace(/<[^>]+>/g, '').trim())
                    .fontSize(13)
                    .fontColor(Theme.TEXT_SECONDARY)
                    .lineHeight(20)
                }
                .width('100%')
                .padding(16)
                .backgroundColor(Theme.SURFACE)
                .borderRadius(16)
                .border({ width: 1, color: Theme.BORDER })
                .alignItems(HorizontalAlign.Start)
              }
            }, (n: NoticeItem) => `${n.id}_${n.title}`)
            ListItem() {
              Column().height(86)
            }
          }
          .layoutWeight(1)
          .padding({ left: 20, right: 20 })
        }
      } else if (this.subView === 'password') {
        this.buildSubHeader(I18n.t('修改密码', 'Change Password'))
        Column({ space: 14 }) {
          TextInput({ text: this.oldPassword, placeholder: I18n.t('当前密码', 'Current Password') })
            .type(InputType.Password)
            .height(50)
            .fontColor(Theme.TEXT_PRIMARY)
            .placeholderColor(Theme.TEXT_MUTED)
            .backgroundColor(Theme.SURFACE_SOFT)
            .borderRadius(14)
            .padding({ left: 14, right: 14 })
            .onChange((v: string) => {
              this.oldPassword = v;
            })

          TextInput({ text: this.newPassword, placeholder: I18n.t('新密码（至少 6 位）', 'New Password (min 6 chars)') })
            .type(InputType.Password)
            .height(50)
            .fontColor(Theme.TEXT_PRIMARY)
            .placeholderColor(Theme.TEXT_MUTED)
            .backgroundColor(Theme.SURFACE_SOFT)
            .borderRadius(14)
            .padding({ left: 14, right: 14 })
            .onChange((v: string) => {
              this.newPassword = v;
            })

          Button(I18n.t('保存新密码', 'Update Password'))
            .width('100%')
            .height(48)
            .borderRadius(14)
            .backgroundColor(Theme.ACCENT_BLUE)
            .fontColor(Color.White)
            .onClick(async () => {
              if (this.newPassword.length < 6) {
                this.showToast(I18n.t('新密码不能少于 6 位', 'New password too short'));
                return;
              }
              const res = await ApiService.getInstance().changePassword(
                this.settings, this.auth, this.oldPassword, this.newPassword
              );
              this.showToast(res.message);
              if (res.ok) {
                this.oldPassword = '';
                this.newPassword = '';
                this.subView = 'none';
              }
            })
        }
        .padding(20)
      } else if (this.subView === 'terms') {
        this.buildSubHeader(I18n.t('服务条款与隐私声明', 'Terms of Service'))
        Scroll() {
          Text(
            I18n.t(
              '1. 本应用为 TizLink 纯血鸿蒙版（HarmonyOS NEXT 原生 ArkTS + Mihomo 内核）。\n\n' +
              '2. 本应用仅作为网络代理与加密隧道客户端，不主动收集用户浏览历史或 DNS 明文记录。\n\n' +
              '3. 请严格遵守您所在国家或地区的相关法律法规合法合规使用网络工具。\n\n' +
              '4. VPN 隧道基于 HarmonyOS NEXT VpnExtensionAbility 与原生 Mihomo sing-tun (gVisor) 实现，所有流量加密均在设备本地完成。',
              '1. TizLink HarmonyOS NEXT edition is built with native ArkTS + Mihomo core.\n\n' +
              '2. Zero browsing logs are collected by the client.\n\n' +
              '3. Please comply with applicable local laws and regulations.'
            )
          )
            .fontSize(14)
            .fontColor(Theme.TEXT_SECONDARY)
            .lineHeight(24)
            .padding({ left: 20, right: 20, bottom: 96 })
        }.layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BG)
  }

  @Builder
  private buildStatBox(label: string, val: string) {
    Column({ space: 4 }) {
      Text(val).fontSize(18).fontWeight(FontWeight.Bold).fontColor(Theme.TEXT_PRIMARY)
      Text(label).fontSize(11).fontColor(Theme.TEXT_SECONDARY)
    }
    .layoutWeight(1)
    .padding(14)
    .backgroundColor(Theme.SURFACE_SOFT)
    .borderRadius(14)
  }
}
