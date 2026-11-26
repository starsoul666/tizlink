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
import { StorageService } from '../service/StorageService';
import { VpnManager } from '../service/VpnManager';
import { Theme } from './Theme';

type AccountSubView =
  'none' | 'orders' | 'invite' | 'notices' | 'password' | 'settings' | 'split_tunnel' | 'chain_proxy' | 'yaml' | 'logs' | 'terms';

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
  onOpenLineSelector: () => void = () => {};
  onSettingsChanged: () => void = () => {};
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
  @State splitAppInput: string = '';
  @State cachedYaml: string = '';
  @State nativeLogs: string = '';

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
    return Math.min(100, Math.max(0, (this.getUsedTraffic() / total) * 100));
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

  private async openYamlViewer(): Promise<void> {
    this.cachedYaml = await StorageService.getInstance().loadLastConfigYaml();
    if (this.cachedYaml.length === 0) {
      this.cachedYaml = I18n.t('# 暂无缓存配置，请先连接一次节点', '# No cached config yet (connect once first)');
    }
    this.subView = 'yaml';
  }

  private openLogsViewer(): void {
    this.nativeLogs = VpnManager.getInstance().getNativeLogs();
    if (this.nativeLogs.length === 0) {
      this.nativeLogs = I18n.t('暂无 Mihomo 内核运行日志', 'No native Mihomo logs yet');
    }
    this.subView = 'logs';
  }

  private openCrispSupport(): void {
    const id: string = this.settings.crispWebsiteId.trim();
    if (id.length === 0) {
      this.showToast(I18n.t('请先在“高级设置”中填写 Crisp Website ID', 'Configure Crisp Website ID in Settings first'));
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

  private async saveAndNotifySettings(): Promise<void> {
    I18n.lang = this.settings.language;
    await StorageService.getInstance().saveSettings(this.settings);
    this.onSettingsChanged();
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
      Column({ space: 16 }) {
        // Section: Connection Status (exact match to APK screenshot 8)
        Text(I18n.t('连接状态', 'Connection Status'))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT_PRIMARY)
          .width('100%')

        Row({ space: 10 }) {
          Circle()
            .width(10)
            .height(10)
            .fill(this.vpnState === 'connected' ? Theme.ACCENT_MINT : Theme.TEXT_SECONDARY)
          Text(
            this.vpnState === 'connected'
              ? I18n.t('已连接 · Mihomo 安全隧道运行中', 'Connected · Mihomo Tunnel Active')
              : I18n.t('未连接', 'Disconnected')
          )
            .fontSize(14)
            .fontColor(Theme.TEXT_PRIMARY)
          Blank()
          Text(VpnManager.getInstance().isCoreAvailable() ? 'Core OK' : 'Core')
            .fontSize(11)
            .fontColor(Theme.ACCENT_MINT)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .backgroundColor('#162B2E')
            .borderRadius(6)
        }
        .width('100%')
        .padding(16)
        .backgroundColor(Theme.SURFACE)
        .borderRadius(16)
        .border({ width: 1, color: Theme.BORDER })

        // Section: My Subscription (exact match to APK screenshot 8)
        Row() {
          Text(I18n.t('我的订阅', 'My Subscription'))
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.TEXT_PRIMARY)
          Blank()
          Text(I18n.t('刷新', 'Refresh'))
            .fontSize(13)
            .fontColor(Theme.ACCENT_MINT)
            .onClick(() => {
              this.onRefreshAccount();
            })
        }
        .width('100%')

        Column({ space: 14 }) {
          Row({ space: 12 }) {
            Column() {
              Text('★')
                .fontSize(18)
                .fontColor(Theme.TEXT_PRIMARY)
            }
            .width(42)
            .height(42)
            .borderRadius(21)
            .backgroundColor(Theme.SURFACE_ELEVATED)
            .justifyContent(FlexAlign.Center)

            Column({ space: 3 }) {
              Text(this.subscription.planName || I18n.t('暂无有效订阅', 'No Active Subscription'))
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.TEXT_PRIMARY)
              Text(
                this.subscription.expiredAt > 0
                  ? `${I18n.t('有效期至', 'Expires')}: ${formatDate(this.subscription.expiredAt)}`
                  : I18n.t('长期有效 / 未到期限制', 'No expiration')
              )
                .fontSize(12)
                .fontColor(Theme.TEXT_SECONDARY)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')

          Progress({ value: this.getTrafficProgress(), total: 100, type: ProgressType.Linear })
            .width('100%')
            .height(6)
            .color(Theme.PRIMARY_BTN_BG)
            .backgroundColor('#232836')

          Row() {
            Text(`${I18n.t('已用', 'Used')}: ${formatBytes(this.getUsedTraffic())}`)
              .fontSize(12)
              .fontColor(Theme.TEXT_SECONDARY)
            Blank()
            Text(`${I18n.t('总量', 'Total')}: ${formatBytes(this.subscription.transferEnable)}`)
              .fontSize(12)
              .fontColor(Theme.TEXT_SECONDARY)
          }
          .width('100%')

          if (this.subscription.resetDay > 0) {
            Row({ space: 8 }) {
              Text('↻')
                .fontSize(14)
                .fontColor(Theme.TEXT_SECONDARY)
              Text(I18n.t(`每月 ${this.subscription.resetDay} 日重置流量`, `Resets on day ${this.subscription.resetDay} monthly`))
                .fontSize(13)
                .fontColor(Theme.TEXT_SECONDARY)
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .backgroundColor(Theme.INPUT_BG)
            .borderRadius(12)
            .border({ width: 1, color: Theme.BORDER })
          }
        }
        .width('100%')
        .padding(18)
        .backgroundColor(Theme.SURFACE)
        .borderRadius(18)
        .border({ width: 1, color: Theme.BORDER })

        // Section: Basic Info
        Text(I18n.t('基本资料', 'Profile'))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT_PRIMARY)
          .width('100%')

        Column({ space: 12 }) {
          Row() {
            Text(`✉  ${I18n.t('邮箱', 'Email')}`)
              .fontSize(14)
              .fontColor(Theme.TEXT_SECONDARY)
            Blank()
            Text(this.subscription.email || this.auth.email || '--')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.TEXT_PRIMARY)
          }
          .width('100%')

          Divider().color(Theme.BORDER)

          Row() {
            Text(`💳  ${I18n.t('余额', 'Balance')}`)
              .fontSize(14)
              .fontColor(Theme.TEXT_SECONDARY)
            Blank()
            Text(`¥ ${this.subscription.balance.toFixed(2)}`)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.TEXT_PRIMARY)
          }
          .width('100%')

          Divider().color(Theme.BORDER)

          Row() {
            Text(`📱  ${I18n.t('设备标识', 'Device ID')}`)
              .fontSize(14)
              .fontColor(Theme.TEXT_SECONDARY)
            Blank()
            Text(this.auth.deviceId)
              .fontSize(12)
              .fontColor(Theme.TEXT_MUTED)
              .onClick(() => {
                this.copyText(this.auth.deviceId);
              })
          }
          .width('100%')
        }
        .width('100%')
        .padding(16)
        .backgroundColor(Theme.SURFACE)
        .borderRadius(16)
        .border({ width: 1, color: Theme.BORDER })

        // Action Menu List
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
          this.buildMenuRow('⚙', I18n.t('高级设置 · 分流与代理', 'Advanced Settings'), () => {
            this.subView = 'settings';
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
        .borderRadius(16)
        .border({ width: 1, color: Theme.BORDER })

        // Logout Button
        Button(I18n.t('退出登录', 'Sign Out'))
          .width('100%')
          .height(48)
          .borderRadius(14)
          .backgroundColor('#2A181B')
          .fontColor(Theme.ACCENT_RED)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .border({ width: 1, color: '#44F87171' })
          .onClick(() => {
            this.onLogout();
          })

        Text(`TizLink HarmonyOS NEXT v${APP_VERSION}`)
          .fontSize(12)
          .fontColor(Theme.TEXT_MUTED)
          .margin({ top: 4, bottom: 24 })
      }
      .width('100%')
      .constraintSize({ maxWidth: 820 })
      .padding({ left: 18, right: 18, top: 8, bottom: 16 })
    }
    .width('100%')
    .height('100%')
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
        .fontSize(14)
        .fontColor(Theme.TEXT_PRIMARY)
        .layoutWeight(1)
      Text('›')
        .fontSize(18)
        .fontColor(Theme.TEXT_MUTED)
    }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 16 })
    .onClick(onClick)
  }

  @Builder
  private buildSubHeader(title: string) {
    Row({ space: 12 }) {
      Text('‹')
        .fontSize(26)
        .fontColor(Theme.TEXT_PRIMARY)
        .width(34)
        .height(34)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          if (this.subView === 'split_tunnel' || this.subView === 'chain_proxy' || this.subView === 'yaml' || this.subView === 'logs') {
            this.subView = 'settings';
          } else {
            this.subView = 'none';
          }
        })
      Text(title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TEXT_PRIMARY)
      Blank()
    }
    .width('100%')
    .padding({ left: 12, right: 18, top: 8, bottom: 8 })
  }

  @Builder
  private buildSubView() {
    Column() {
      if (this.subView === 'orders') {
        this.buildSubHeader(I18n.t('我的订单', 'My Orders'))
        if (this.loadingSub) {
          LoadingProgress().width(36).height(36).color(Theme.ACCENT_MINT).margin({ top: 60 })
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
                  if (o.status === 0) {
                    Row({ space: 8 }) {
                      Button(I18n.t('取消订单', 'Cancel'))
                        .height(32)
                        .fontSize(12)
                        .backgroundColor('#2A181B')
                        .fontColor(Theme.ACCENT_RED)
                        .onClick(async () => {
                          const res = await ApiService.getInstance().cancelOrder(this.settings, this.auth, o.tradeNo);
                          this.showToast(res.message);
                          if (res.ok) {
                            void this.openOrders();
                          }
                        })
                    }.width('100%').justifyContent(FlexAlign.End)
                  }
                }
                .width('100%')
                .padding(16)
                .backgroundColor(Theme.SURFACE)
                .borderRadius(16)
                .border({ width: 1, color: Theme.BORDER })
              }
            }, (o: OrderItem) => o.tradeNo)
          }
          .layoutWeight(1)
          .padding({ left: 18, right: 18 })
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

            Button(I18n.t('生成新邀请码', 'Generate Invite Code'))
              .width('100%')
              .height(44)
              .borderRadius(12)
              .backgroundColor(Theme.PRIMARY_BTN_BG)
              .fontColor(Theme.PRIMARY_BTN_TEXT)
              .onClick(async () => {
                const res = await ApiService.getInstance().generateInviteCode(this.settings, this.auth);
                this.showToast(res.message);
                if (res.ok) {
                  void this.openInvite();
                }
              })

            if (this.inviteSummary.codes.length === 0) {
              Text(I18n.t('暂无邀请码', 'No invite codes')).fontSize(13).fontColor(Theme.TEXT_SECONDARY).margin({ top: 12 })
            } else {
              ForEach(this.inviteSummary.codes, (item: InviteCodeItem) => {
                Row() {
                  Text(item.code).fontSize(15).fontWeight(FontWeight.Medium).fontColor(Theme.TEXT_PRIMARY)
                  Blank()
                  Text(I18n.t('复制', 'Copy'))
                    .fontSize(13)
                    .fontColor(Theme.ACCENT_MINT)
                    .onClick(() => this.copyText(item.code))
                }
                .width('100%')
                .padding(14)
                .backgroundColor(Theme.SURFACE)
                .borderRadius(14)
                .border({ width: 1, color: Theme.BORDER })
              })
            }
          }
          .padding({ left: 18, right: 18, bottom: 24 })
        }.layoutWeight(1)
      } else if (this.subView === 'notices') {
        this.buildSubHeader(I18n.t('系统公告', 'Announcements'))
        if (this.loadingSub) {
          LoadingProgress().width(36).height(36).color(Theme.ACCENT_MINT).margin({ top: 60 })
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
          }
          .layoutWeight(1)
          .padding({ left: 18, right: 18 })
        }
      } else if (this.subView === 'password') {
        this.buildSubHeader(I18n.t('修改密码', 'Change Password'))
        Column({ space: 14 }) {
          TextInput({ text: this.oldPassword, placeholder: I18n.t('当前密码', 'Current Password') })
            .type(InputType.Password)
            .height(48)
            .fontColor(Theme.TEXT_PRIMARY)
            .placeholderColor(Theme.TEXT_MUTED)
            .backgroundColor(Theme.SURFACE)
            .borderRadius(14)
            .border({ width: 1, color: Theme.BORDER })
            .padding({ left: 14, right: 14 })
            .onChange((v: string) => {
              this.oldPassword = v;
            })

          TextInput({ text: this.newPassword, placeholder: I18n.t('新密码（至少 6 位）', 'New Password (min 6 chars)') })
            .type(InputType.Password)
            .height(48)
            .fontColor(Theme.TEXT_PRIMARY)
            .placeholderColor(Theme.TEXT_MUTED)
            .backgroundColor(Theme.SURFACE)
            .borderRadius(14)
            .border({ width: 1, color: Theme.BORDER })
            .padding({ left: 14, right: 14 })
            .onChange((v: string) => {
              this.newPassword = v;
            })

          Button(I18n.t('保存新密码', 'Update Password'))
            .width('100%')
            .height(48)
            .borderRadius(14)
            .backgroundColor(Theme.PRIMARY_BTN_BG)
            .fontColor(Theme.PRIMARY_BTN_TEXT)
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
        .padding(18)
      } else if (this.subView === 'settings') {
        this.buildSettingsSubView()
      } else if (this.subView === 'split_tunnel') {
        this.buildSplitTunnelSubView()
      } else if (this.subView === 'chain_proxy') {
        this.buildChainProxySubView()
      } else if (this.subView === 'yaml') {
        this.buildSubHeader(I18n.t('Mihomo 生成配置 (YAML)', 'Generated Mihomo YAML'))
        Row({ space: 10 }) {
          Button(I18n.t('复制配置', 'Copy YAML'))
            .height(34)
            .fontSize(12)
            .backgroundColor(Theme.SURFACE_ELEVATED)
            .fontColor(Theme.ACCENT_MINT)
            .onClick(() => this.copyText(this.cachedYaml))
        }
        .width('100%')
        .padding({ left: 18, right: 18, bottom: 8 })
        Scroll() {
          Text(this.cachedYaml)
            .fontSize(11)
            .fontColor(Theme.TEXT_SECONDARY)
            .fontFamily('monospace')
            .width('100%')
            .padding(14)
            .backgroundColor(Theme.INPUT_BG)
            .borderRadius(12)
        }
        .layoutWeight(1)
        .padding({ left: 18, right: 18, bottom: 18 })
      } else if (this.subView === 'logs') {
        this.buildSubHeader(I18n.t('Mihomo 内核运行日志', 'Mihomo Core Logs'))
        Row({ space: 10 }) {
          Button(I18n.t('刷新', 'Refresh'))
            .height(34)
            .fontSize(12)
            .backgroundColor(Theme.SURFACE_ELEVATED)
            .fontColor(Theme.TEXT_PRIMARY)
            .onClick(() => this.openLogsViewer())
          Button(I18n.t('复制日志', 'Copy'))
            .height(34)
            .fontSize(12)
            .backgroundColor(Theme.SURFACE_ELEVATED)
            .fontColor(Theme.ACCENT_MINT)
            .onClick(() => this.copyText(this.nativeLogs))
          Button(I18n.t('清空', 'Clear'))
            .height(34)
            .fontSize(12)
            .backgroundColor('#2A181B')
            .fontColor(Theme.ACCENT_RED)
            .onClick(() => {
              VpnManager.getInstance().clearNativeLogs();
              this.nativeLogs = I18n.t('日志已清空', 'Logs cleared');
            })
        }
        .width('100%')
        .padding({ left: 18, right: 18, bottom: 8 })
        Scroll() {
          Text(this.nativeLogs)
            .fontSize(11)
            .fontColor(Theme.TEXT_SECONDARY)
            .fontFamily('monospace')
            .width('100%')
            .padding(14)
            .backgroundColor(Theme.INPUT_BG)
            .borderRadius(12)
        }
        .layoutWeight(1)
        .padding({ left: 18, right: 18, bottom: 18 })
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
            .padding(18)
        }.layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildSettingsSubView() {
    this.buildSubHeader(I18n.t('高级设置', 'Advanced Settings'))
    Scroll() {
      Column({ space: 14 }) {
        // Core & DNS Toggles
        Column() {
          this.buildToggleRow(
            I18n.t('Fake-IP DNS 加速', 'Fake-IP DNS Mode'),
            I18n.t('推荐开启，减少 DNS 解析延迟与污染', 'Recommended for lower DNS latency'),
            this.settings.enableFakeIp,
            (val: boolean) => {
              this.settings.enableFakeIp = val;
              void this.saveAndNotifySettings();
            }
          )
          Divider().color(Theme.BORDER)
          this.buildToggleRow(
            I18n.t('启用 IPv6 隧道', 'Enable IPv6 Tunnel'),
            I18n.t('仅在运营商与节点均支持 IPv6 时开启', 'Enable only when ISP & node support IPv6'),
            this.settings.enableIpv6,
            (val: boolean) => {
              this.settings.enableIpv6 = val;
              void this.saveAndNotifySettings();
            }
          )
          Divider().color(Theme.BORDER)
          Row() {
            Column({ space: 2 }) {
              Text(I18n.t('界面语言', 'Language')).fontSize(14).fontColor(Theme.TEXT_PRIMARY)
              Text(this.settings.language === 'zh' ? '简体中文' : 'English').fontSize(12).fontColor(Theme.TEXT_SECONDARY)
            }.alignItems(HorizontalAlign.Start)
            Blank()
            Button(this.settings.language === 'zh' ? '切换 English' : '切换中文')
              .height(32)
              .fontSize(12)
              .backgroundColor(Theme.SURFACE_ELEVATED)
              .fontColor(Theme.ACCENT_MINT)
              .onClick(() => {
                this.settings.language = this.settings.language === 'zh' ? 'en' : 'zh';
                void this.saveAndNotifySettings();
              })
          }
          .width('100%')
          .padding(16)
        }
        .backgroundColor(Theme.SURFACE)
        .borderRadius(16)
        .border({ width: 1, color: Theme.BORDER })

        // Split Tunneling & Chain Proxy & Diagnostics
        Column() {
          this.buildMenuRow('📡', I18n.t('线路选择 (国内/国际与 API 测速)', 'Line Selection (CN/Global & API)'), () => {
            this.onOpenLineSelector();
          })
          Divider().color(Theme.BORDER)
          this.buildMenuRow('📱', I18n.t('分应用代理 (Split Tunneling)', 'Per-App Split Tunneling'), () => {
            this.subView = 'split_tunnel';
          })
          Divider().color(Theme.BORDER)
          this.buildMenuRow('⛓', I18n.t('链式代理 / 二级代理 (Chain Proxy)', 'Chain Proxy (dialer-proxy)'), () => {
            this.subView = 'chain_proxy';
          })
          Divider().color(Theme.BORDER)
          this.buildMenuRow('📝', I18n.t('查看生成的 Mihomo YAML 配置', 'View Generated Mihomo YAML'), () => {
            void this.openYamlViewer();
          })
          Divider().color(Theme.BORDER)
          this.buildMenuRow('📋', I18n.t('查看 Mihomo 内核运行日志', 'View Mihomo Core Logs'), () => {
            this.openLogsViewer();
          })
        }
        .backgroundColor(Theme.SURFACE)
        .borderRadius(16)
        .border({ width: 1, color: Theme.BORDER })

        // Crisp Website ID & Ports
        Column({ space: 10 }) {
          Text(I18n.t('Crisp 客服 Website ID（选填）', 'Crisp Website ID (Optional)'))
            .fontSize(12)
            .fontColor(Theme.TEXT_SECONDARY)
          TextInput({ text: this.settings.crispWebsiteId, placeholder: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' })
            .height(42)
            .fontSize(13)
            .fontColor(Theme.TEXT_PRIMARY)
            .placeholderColor(Theme.TEXT_MUTED)
            .backgroundColor(Theme.INPUT_BG)
            .borderRadius(10)
            .border({ width: 1, color: Theme.BORDER })
            .padding({ left: 10, right: 10 })
            .onChange((v: string) => {
              this.settings.crispWebsiteId = v;
              void this.saveAndNotifySettings();
            })

          Text(`${I18n.t('内核版本', 'Core Version')}: ${VpnManager.getInstance().getCoreVersion()}`)
            .fontSize(12)
            .fontColor(Theme.TEXT_MUTED)
            .margin({ top: 4 })
        }
        .width('100%')
        .padding(16)
        .backgroundColor(Theme.SURFACE)
        .borderRadius(16)
        .border({ width: 1, color: Theme.BORDER })
        .alignItems(HorizontalAlign.Start)
      }
      .padding({ left: 18, right: 18, bottom: 24 })
    }.layoutWeight(1)
  }

  @Builder
  private buildSplitTunnelSubView() {
    this.buildSubHeader(I18n.t('分应用代理', 'Split Tunneling'))
    Scroll() {
      Column({ space: 14 }) {
        Column() {
          this.buildToggleRow(
            I18n.t('启用分应用代理', 'Enable Split Tunneling'),
            I18n.t('按 HarmonyOS 应用包名控制是否走 VPN', 'Control VPN routing per HarmonyOS bundleName'),
            this.settings.splitTunnelEnabled,
            (val: boolean) => {
              this.settings.splitTunnelEnabled = val;
              void this.saveAndNotifySettings();
            }
          )
        }
        .backgroundColor(Theme.SURFACE)
        .borderRadius(16)
        .border({ width: 1, color: Theme.BORDER })

        Row({ space: 8 }) {
          Button(I18n.t('绕过以下应用 (Bypass)', 'Bypass Listed Apps'))
            .layoutWeight(1)
            .height(40)
            .fontSize(12)
            .borderRadius(12)
            .backgroundColor(this.settings.splitTunnelMode === 'bypass' ? Theme.PILL_ACTIVE_BG : Theme.SURFACE)
            .fontColor(this.settings.splitTunnelMode === 'bypass' ? Theme.ACCENT_MINT : Theme.TEXT_SECONDARY)
            .onClick(() => {
              this.settings.splitTunnelMode = 'bypass';
              void this.saveAndNotifySettings();
            })
          Button(I18n.t('仅以下应用代理 (Only)', 'Only Listed Apps'))
            .layoutWeight(1)
            .height(40)
            .fontSize(12)
            .borderRadius(12)
            .backgroundColor(this.settings.splitTunnelMode === 'only' ? Theme.PILL_ACTIVE_BG : Theme.SURFACE)
            .fontColor(this.settings.splitTunnelMode === 'only' ? Theme.ACCENT_MINT : Theme.TEXT_SECONDARY)
            .onClick(() => {
              this.settings.splitTunnelMode = 'only';
              void this.saveAndNotifySettings();
            })
        }

        Row({ space: 8 }) {
          TextInput({ text: this.splitAppInput, placeholder: '例如 com.tencent.mm / com.huawei.browser' })
            .layoutWeight(1)
            .height(44)
            .fontSize(13)
            .fontColor(Theme.TEXT_PRIMARY)
            .placeholderColor(Theme.TEXT_MUTED)
            .backgroundColor(Theme.SURFACE)
            .borderRadius(12)
            .border({ width: 1, color: Theme.BORDER })
            .padding({ left: 12, right: 12 })
            .onChange((v: string) => {
              this.splitAppInput = v;
            })
          Button(I18n.t('添加', 'Add'))
            .height(44)
            .borderRadius(12)
            .backgroundColor(Theme.PRIMARY_BTN_BG)
            .fontColor(Theme.PRIMARY_BTN_TEXT)
            .onClick(() => {
              const pkg: string = this.splitAppInput.trim();
              if (pkg.length > 0 && !this.settings.splitTunnelApps.includes(pkg)) {
                this.settings.splitTunnelApps = [...this.settings.splitTunnelApps, pkg];
                this.splitAppInput = '';
                void this.saveAndNotifySettings();
              }
            })
        }

        ForEach(this.settings.splitTunnelApps, (pkg: string) => {
          Row() {
            Text(pkg).fontSize(13).fontColor(Theme.TEXT_PRIMARY).layoutWeight(1)
            Text(I18n.t('移除', 'Remove'))
              .fontSize(12)
              .fontColor(Theme.ACCENT_RED)
              .onClick(() => {
                this.settings.splitTunnelApps = this.settings.splitTunnelApps.filter((x: string) => x !== pkg);
                void this.saveAndNotifySettings();
              })
          }
          .width('100%')
          .padding(14)
          .backgroundColor(Theme.SURFACE)
          .borderRadius(12)
          .border({ width: 1, color: Theme.BORDER })
        }, (pkg: string) => pkg)
      }
      .padding({ left: 18, right: 18, bottom: 24 })
    }.layoutWeight(1)
  }

  @Builder
  private buildChainProxySubView() {
    this.buildSubHeader(I18n.t('链式代理 (Chain Proxy)', 'Chain Proxy'))
    Scroll() {
      Column({ space: 14 }) {
        Column() {
          this.buildToggleRow(
            I18n.t('启用链式代理', 'Enable Chain Proxy'),
            I18n.t('流量经由当前节点后，再通过下方二级代理出口', 'Route traffic through your proxy after our node'),
            this.settings.chainProxy.enabled,
            (val: boolean) => {
              this.settings.chainProxy.enabled = val;
              void this.saveAndNotifySettings();
            }
          )
        }
        .backgroundColor(Theme.SURFACE)
        .borderRadius(16)
        .border({ width: 1, color: Theme.BORDER })

        Column({ space: 10 }) {
          Text(I18n.t('二级代理服务器', 'Secondary Proxy Server')).fontSize(12).fontColor(Theme.TEXT_SECONDARY)
          TextInput({ text: this.settings.chainProxy.server, placeholder: '1.2.3.4' })
            .height(44)
            .fontColor(Theme.TEXT_PRIMARY)
            .placeholderColor(Theme.TEXT_MUTED)
            .backgroundColor(Theme.INPUT_BG)
            .borderRadius(10)
            .border({ width: 1, color: Theme.BORDER })
            .padding({ left: 12, right: 12 })
            .onChange((v: string) => {
              this.settings.chainProxy.server = v;
            })

          Text(I18n.t('端口', 'Port')).fontSize(12).fontColor(Theme.TEXT_SECONDARY)
          TextInput({ text: String(this.settings.chainProxy.port), placeholder: '1080' })
            .type(InputType.Number)
            .height(44)
            .fontColor(Theme.TEXT_PRIMARY)
            .backgroundColor(Theme.INPUT_BG)
            .borderRadius(10)
            .border({ width: 1, color: Theme.BORDER })
            .padding({ left: 12, right: 12 })
            .onChange((v: string) => {
              this.settings.chainProxy.port = Number(v) || 1080;
            })

          Text(I18n.t('用户名（选填）', 'Username (Optional)')).fontSize(12).fontColor(Theme.TEXT_SECONDARY)
          TextInput({ text: this.settings.chainProxy.username })
            .height(44)
            .fontColor(Theme.TEXT_PRIMARY)
            .backgroundColor(Theme.INPUT_BG)
            .borderRadius(10)
            .border({ width: 1, color: Theme.BORDER })
            .padding({ left: 12, right: 12 })
            .onChange((v: string) => {
              this.settings.chainProxy.username = v;
            })

          Text(I18n.t('密码（选填）', 'Password (Optional)')).fontSize(12).fontColor(Theme.TEXT_SECONDARY)
          TextInput({ text: this.settings.chainProxy.password })
            .type(InputType.Password)
            .height(44)
            .fontColor(Theme.TEXT_PRIMARY)
            .backgroundColor(Theme.INPUT_BG)
            .borderRadius(10)
            .border({ width: 1, color: Theme.BORDER })
            .padding({ left: 12, right: 12 })
            .onChange((v: string) => {
              this.settings.chainProxy.password = v;
            })

          Button(I18n.t('保存链式代理配置', 'Save Chain Proxy'))
            .width('100%')
            .height(44)
            .margin({ top: 6 })
            .borderRadius(12)
            .backgroundColor(Theme.PRIMARY_BTN_BG)
            .fontColor(Theme.PRIMARY_BTN_TEXT)
            .onClick(async () => {
              await this.saveAndNotifySettings();
              this.showToast(I18n.t('链式代理配置已保存，重新连接后生效', 'Saved. Reconnect to apply.'));
            })
        }
        .width('100%')
        .padding(16)
        .backgroundColor(Theme.SURFACE)
        .borderRadius(16)
        .border({ width: 1, color: Theme.BORDER })
        .alignItems(HorizontalAlign.Start)
      }
      .padding({ left: 18, right: 18, bottom: 24 })
    }.layoutWeight(1)
  }

  @Builder
  private buildToggleRow(title: string, subtitle: string, isOn: boolean, onChange: (val: boolean) => void) {
    Row({ space: 12 }) {
      Column({ space: 3 }) {
        Text(title).fontSize(14).fontColor(Theme.TEXT_PRIMARY)
        Text(subtitle).fontSize(11).fontColor(Theme.TEXT_SECONDARY)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .selectedColor(Theme.ACCENT_MINT)
        .onChange((val: boolean) => onChange(val))
    }
    .width('100%')
    .padding(16)
  }

  @Builder
  private buildStatBox(label: string, val: string) {
    Column({ space: 4 }) {
      Text(val).fontSize(18).fontWeight(FontWeight.Bold).fontColor(Theme.TEXT_PRIMARY)
      Text(label).fontSize(11).fontColor(Theme.TEXT_SECONDARY)
    }
    .layoutWeight(1)
    .padding(14)
    .backgroundColor(Theme.SURFACE)
    .borderRadius(14)
    .border({ width: 1, color: Theme.BORDER })
  }
}
