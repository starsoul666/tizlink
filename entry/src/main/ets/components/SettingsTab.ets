import { promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import {
  APP_VERSION,
  AppSettings
} from '../model/Models';
import { I18n } from '../model/I18n';
import { StorageService } from '../service/StorageService';
import { VpnManager } from '../service/VpnManager';
import { Theme } from './Theme';

type SettingsSubView = 'none' | 'dns' | 'chain_proxy' | 'split_tunnel' | 'custom_rules' | 'yaml' | 'logs';

@Component
export struct SettingsTab {
  @Link settings: AppSettings;
  onOpenLineSelector: () => void = () => {};
  onSettingsChanged: () => void = () => {};

  @State subView: SettingsSubView = 'none';
  @State dnsInput: string = '';
  @State ruleInput: string = '';
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
      this.showToast(I18n.t(`已复制: ${text}`, `Copied: ${text}`));
    } catch (_e) {
      this.showToast(I18n.t('复制失败', 'Copy failed'));
    }
  }

  private async saveAndNotify(): Promise<void> {
    I18n.lang = this.settings.language;
    await StorageService.getInstance().saveSettings(this.settings);
    this.onSettingsChanged();
  }

  private async openYamlViewer(): Promise<void> {
    this.cachedYaml = await StorageService.getInstance().loadLastConfigYaml();
    if (this.cachedYaml.length === 0) {
      this.cachedYaml = I18n.t('# 暂无缓存配置，请先连接一次节点', '# No cached config yet');
    }
    this.subView = 'yaml';
  }

  private openLogsViewer(): void {
    this.nativeLogs = VpnManager.getInstance().getNativeLogs();
    if (this.nativeLogs.length === 0) {
      this.nativeLogs = I18n.t('暂无 Mihomo 内核运行日志', 'No native logs yet');
    }
    this.subView = 'logs';
  }

  private formatApiHost(url: string): string {
    return url.replace(/^https?:\/\//, '').split('/')[0];
  }

  build() {
    if (this.subView !== 'none') {
      this.buildSubView()
    } else {
      this.buildMainSettings()
    }
  }

  @Builder
  private buildMainSettings() {
    Scroll() {
      Column({ space: 16 }) {
        // Page Title: 设置 (exact match to APK Screenshot #4)
        Text(I18n.t('设置', 'Settings'))
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT_PRIMARY)
          .width('100%')
          .margin({ top: 10, bottom: 2 })

        // Card 1: 网络设置 + 代理端口 (exact match to APK Screenshot #4)
        Column() {
          // Sub-header: 网络设置
          Row({ space: 8 }) {
            Text('▤')
              .fontSize(16)
              .fontColor(Theme.ACCENT_BLUE)
            Text(I18n.t('网络设置', 'Network Settings'))
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.TEXT_PRIMARY)
          }
          .width('100%')
          .padding({ left: 18, right: 18, top: 18, bottom: 12 })

          // Row: DNS 设置
          this.buildNavRow(
            '▤',
            I18n.t('DNS 设置', 'DNS Settings'),
            I18n.t('点击配置 DNS 覆写（解决部分网络连上不能上网）', 'Configure DNS override'),
            () => {
              this.subView = 'dns';
            }
          )

          // Row: IPv6
          this.buildToggleRow(
            '🌐',
            'IPv6',
            I18n.t('启用 IPv6 连接（部分网络环境可能不支持）', 'Enable IPv6 tunnel'),
            this.settings.enableIpv6,
            (val: boolean) => {
              this.settings.enableIpv6 = val;
              void this.saveAndNotify();
            }
          )

          // Row: 链式代理
          this.buildToggleRow(
            '⛓',
            I18n.t('链式代理', 'Chain Proxy'),
            I18n.t('流量经过节点后再转发到您的代理', 'Forward traffic through secondary proxy'),
            this.settings.chainProxy.enabled,
            (val: boolean) => {
              this.settings.chainProxy.enabled = val;
              void this.saveAndNotify();
            },
            () => {
              this.subView = 'chain_proxy';
            }
          )

          // Row: 分应用代理
          this.buildToggleRow(
            '⊞',
            I18n.t('分应用代理', 'Split Tunneling'),
            I18n.t('选择哪些应用走 VPN', 'Choose apps routed via VPN'),
            this.settings.splitTunnelEnabled,
            (val: boolean) => {
              this.settings.splitTunnelEnabled = val;
              void this.saveAndNotify();
            },
            () => {
              this.subView = 'split_tunnel';
            }
          )

          // Row: 自定义规则
          this.buildNavRow(
            '📁',
            I18n.t('自定义规则', 'Custom Rules'),
            I18n.t('添加自己的分流规则（最高优先级生效）', 'Add custom routing rules (highest priority)'),
            () => {
              this.subView = 'custom_rules';
            }
          )

          Divider().color(Theme.BORDER).margin({ left: 18, right: 18, top: 8, bottom: 12 })

          // Sub-header: 代理端口
          Row({ space: 8 }) {
            Text('<>')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.ACCENT_BLUE)
            Text(I18n.t('代理端口', 'Proxy Ports'))
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.TEXT_PRIMARY)
          }
          .width('100%')
          .padding({ left: 18, right: 18, bottom: 10 })

          // HTTP/SOCKS5 混合 7890
          Row() {
            Text(I18n.t('HTTP/SOCKS5 混合', 'HTTP/SOCKS5 Mixed'))
              .fontSize(14)
              .fontColor(Theme.TEXT_SECONDARY)
            Blank()
            Text(`${this.settings.mixedPort || 7890}`)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.TEXT_PRIMARY)
              .margin({ right: 8 })
            Text('❐')
              .fontSize(15)
              .fontColor(Theme.TEXT_MUTED)
          }
          .width('100%')
          .padding({ left: 18, right: 18, top: 8, bottom: 8 })
          .onClick(() => {
            this.copyText(`127.0.0.1:${this.settings.mixedPort || 7890}`);
          })

          // SOCKS5 专用 7891
          Row() {
            Text(I18n.t('SOCKS5 专用', 'SOCKS5 Port'))
              .fontSize(14)
              .fontColor(Theme.TEXT_SECONDARY)
            Blank()
            Text(`${this.settings.socksPort || 7891}`)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.TEXT_PRIMARY)
              .margin({ right: 8 })
            Text('❐')
              .fontSize(15)
              .fontColor(Theme.TEXT_MUTED)
          }
          .width('100%')
          .padding({ left: 18, right: 18, top: 8, bottom: 12 })
          .onClick(() => {
            this.copyText(`127.0.0.1:${this.settings.socksPort || 7891}`);
          })

          // Blue LAN Sharing Banner (exact match to APK Screenshot #4)
          Row({ space: 10 }) {
            Text('📶')
              .fontSize(16)
              .fontColor(Theme.ACCENT_BLUE)
            Text(
              this.settings.allowLan
                ? I18n.t(`局域网共享已启用 - 其他设备可连接 127.0.0.1:${this.settings.mixedPort || 7890}`, `LAN sharing enabled on port ${this.settings.mixedPort || 7890}`)
                : I18n.t('局域网共享已关闭 - 点击开启局域网共享', 'LAN sharing disabled - tap to enable')
            )
              .fontSize(13)
              .fontColor(Theme.ACCENT_BLUE)
              .lineHeight(19)
              .layoutWeight(1)
          }
          .width('calc(100% - 36vp)')
          .padding(14)
          .backgroundColor('#EBF3FF')
          .borderRadius(12)
          .border({ width: 1, color: '#D6E6FF' })
          .onClick(() => {
            this.settings.allowLan = !this.settings.allowLan;
            void this.saveAndNotify();
          })

          // 内网 IP Row
          Row() {
            Text(I18n.t('本机代理地址', 'Local Proxy'))
              .fontSize(14)
              .fontColor(Theme.TEXT_SECONDARY)
            Blank()
            Text(`127.0.0.1`)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.TEXT_PRIMARY)
              .margin({ right: 8 })
            Text('❐')
              .fontSize(15)
              .fontColor(Theme.TEXT_MUTED)
          }
          .width('100%')
          .padding({ left: 18, right: 18, top: 14, bottom: 18 })
          .onClick(() => {
            this.copyText('127.0.0.1');
          })
        }
        .width('100%')
        .backgroundColor(Theme.SURFACE)
        .borderRadius(20)
        .border({ width: 1, color: Theme.BORDER })
        .shadow({ radius: 12, color: Theme.SHADOW_CARD, offsetY: 3 })

        // Card 2: API 节点 (exact match to APK Screenshot #4 bottom)
        Column() {
          Row({ space: 8 }) {
            Text('☁')
              .fontSize(17)
              .fontColor(Theme.ACCENT_BLUE)
            Text(I18n.t('API 节点', 'API Nodes'))
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.TEXT_PRIMARY)
            Blank()
            Text('›')
              .fontSize(20)
              .fontColor(Theme.TEXT_MUTED)
          }
          .width('100%')
          .padding({ left: 18, right: 18, top: 16, bottom: 8 })

          Text(this.formatApiHost(this.settings.whmcsApiUrl))
            .fontSize(13)
            .fontColor(Theme.TEXT_SECONDARY)
            .width('100%')
            .padding({ left: 18, right: 18, bottom: 16 })
        }
        .width('100%')
        .backgroundColor(Theme.SURFACE)
        .borderRadius(20)
        .border({ width: 1, color: Theme.BORDER })
        .shadow({ radius: 10, color: Theme.SHADOW_CARD, offsetY: 2 })
        .onClick(() => {
          this.onOpenLineSelector();
        })

        // Card 3: 诊断与系统
        Column() {
          Row() {
            Column({ space: 2 }) {
              Text(I18n.t('语言 / Language', 'Language')).fontSize(15).fontColor(Theme.TEXT_PRIMARY)
              Text(this.settings.language === 'zh' ? '简体中文' : 'English').fontSize(12).fontColor(Theme.TEXT_SECONDARY)
            }.alignItems(HorizontalAlign.Start)
            Blank()
            Button(this.settings.language === 'zh' ? 'English' : '中文')
              .height(32)
              .fontSize(12)
              .backgroundColor(Theme.SURFACE_SOFT)
              .fontColor(Theme.ACCENT_BLUE)
              .onClick(() => {
                this.settings.language = this.settings.language === 'zh' ? 'en' : 'zh';
                void this.saveAndNotify();
              })
          }
          .width('100%')
          .padding({ left: 18, right: 18, top: 14, bottom: 14 })

          Divider().color(Theme.BORDER).margin({ left: 18, right: 18 })

          this.buildNavRow(
            '📝',
            I18n.t('查看生成配置 (YAML)', 'Generated Mihomo YAML'),
            I18n.t('检查当前生效的代理与分流配置', 'Inspect active Mihomo config'),
            () => {
              void this.openYamlViewer();
            }
          )

          Divider().color(Theme.BORDER).margin({ left: 18, right: 18 })

          this.buildNavRow(
            '📋',
            I18n.t('查看运行日志', 'View Core Logs'),
            VpnManager.getInstance().getCoreVersion(),
            () => {
              this.openLogsViewer();
            }
          )
        }
        .width('100%')
        .backgroundColor(Theme.SURFACE)
        .borderRadius(20)
        .border({ width: 1, color: Theme.BORDER })
        .shadow({ radius: 10, color: Theme.SHADOW_CARD, offsetY: 2 })

        Text(`TizLink v${APP_VERSION}`)
          .fontSize(12)
          .fontColor(Theme.TEXT_MUTED)
          .margin({ top: 4, bottom: 96 })
      }
      .width('100%')
      .constraintSize({ maxWidth: 640 })
      .padding({ left: 20, right: 20, bottom: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BG)
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
  }

  @Builder
  private buildNavRow(icon: string, title: string, subtitle: string, onClick: () => void) {
    Row({ space: 12 }) {
      Text(icon)
        .fontSize(16)
        .fontColor(Theme.TEXT_SECONDARY)
        .width(24)
        .textAlign(TextAlign.Center)
      Column({ space: 3 }) {
        Text(title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TEXT_PRIMARY)
        Text(subtitle)
          .fontSize(12)
          .fontColor(Theme.TEXT_SECONDARY)
          .lineHeight(17)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text('›')
        .fontSize(20)
        .fontColor(Theme.TEXT_MUTED)
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 12, bottom: 12 })
    .onClick(onClick)
  }

  @Builder
  private buildToggleRow(
    icon: string,
    title: string,
    subtitle: string,
    isOn: boolean,
    onChange: (val: boolean) => void,
    onTapRow?: () => void
  ) {
    Row({ space: 12 }) {
      Text(icon)
        .fontSize(16)
        .fontColor(Theme.TEXT_SECONDARY)
        .width(24)
        .textAlign(TextAlign.Center)
      Column({ space: 3 }) {
        Text(title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TEXT_PRIMARY)
        Text(subtitle)
          .fontSize(12)
          .fontColor(Theme.TEXT_SECONDARY)
          .lineHeight(17)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .onClick(() => {
        if (onTapRow) {
          onTapRow();
        }
      })

      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .selectedColor(Theme.ACCENT_BLUE)
        .onChange((val: boolean) => onChange(val))
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 12, bottom: 12 })
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
      if (this.subView === 'dns') {
        this.buildSubHeader(I18n.t('DNS 设置', 'DNS Settings'))
        Scroll() {
          Column({ space: 14 }) {
            Column() {
              this.buildToggleRow(
                '⚡',
                I18n.t('Fake-IP DNS 加速', 'Fake-IP DNS Mode'),
                I18n.t('推荐开启，减少 DNS 解析延迟与污染', 'Recommended for faster resolution'),
                this.settings.enableFakeIp,
                (val: boolean) => {
                  this.settings.enableFakeIp = val;
                  void this.saveAndNotify();
                }
              )
            }
            .backgroundColor(Theme.SURFACE)
            .borderRadius(16)
            .border({ width: 1, color: Theme.BORDER })

            Row({ space: 8 }) {
              TextInput({ text: this.dnsInput, placeholder: '例如 223.5.5.5 或 https://doh.pub/dns-query' })
                .layoutWeight(1)
                .height(44)
                .fontSize(13)
                .fontColor(Theme.TEXT_PRIMARY)
                .placeholderColor(Theme.TEXT_MUTED)
                .backgroundColor(Theme.SURFACE_SOFT)
                .borderRadius(12)
                .padding({ left: 12, right: 12 })
                .onChange((v: string) => {
                  this.dnsInput = v;
                })
              Button(I18n.t('添加', 'Add'))
                .height(44)
                .borderRadius(12)
                .backgroundColor(Theme.ACCENT_BLUE)
                .fontColor(Color.White)
                .onClick(() => {
                  const s: string = this.dnsInput.trim();
                  if (s.length > 0 && !this.settings.customDns.includes(s)) {
                    this.settings.customDns = [...this.settings.customDns, s];
                    this.dnsInput = '';
                    void this.saveAndNotify();
                  }
                })
            }

            if (this.settings.customDns.length === 0) {
              Text(I18n.t('当前使用默认优化 DNS（223.5.5.5 / 119.29.29.29）', 'Using default optimized DNS'))
                .fontSize(12)
                .fontColor(Theme.TEXT_SECONDARY)
                .width('100%')
            } else {
              ForEach(this.settings.customDns, (dns: string) => {
                Row() {
                  Text(dns).fontSize(14).fontColor(Theme.TEXT_PRIMARY).layoutWeight(1)
                  Text(I18n.t('移除', 'Remove'))
                    .fontSize(12)
                    .fontColor(Theme.ACCENT_RED)
                    .onClick(() => {
                      this.settings.customDns = this.settings.customDns.filter((x: string) => x !== dns);
                      void this.saveAndNotify();
                    })
                }
                .width('100%')
                .padding(14)
                .backgroundColor(Theme.SURFACE_SOFT)
                .borderRadius(12)
              }, (dns: string) => dns)
            }
          }
          .padding({ left: 20, right: 20, bottom: 96 })
        }.layoutWeight(1)
      } else if (this.subView === 'custom_rules') {
        this.buildSubHeader(I18n.t('自定义规则', 'Custom Rules'))
        Scroll() {
          Column({ space: 14 }) {
            Text(I18n.t('格式示例：DOMAIN-SUFFIX,openai.com,PROXY 或 DOMAIN-SUFFIX,baidu.com,DIRECT', 'Example: DOMAIN-SUFFIX,example.com,PROXY'))
              .fontSize(12)
              .fontColor(Theme.TEXT_SECONDARY)
              .width('100%')

            Row({ space: 8 }) {
              TextInput({ text: this.ruleInput, placeholder: 'DOMAIN-SUFFIX,example.com,PROXY' })
                .layoutWeight(1)
                .height(44)
                .fontSize(13)
                .fontColor(Theme.TEXT_PRIMARY)
                .placeholderColor(Theme.TEXT_MUTED)
                .backgroundColor(Theme.SURFACE_SOFT)
                .borderRadius(12)
                .padding({ left: 12, right: 12 })
                .onChange((v: string) => {
                  this.ruleInput = v;
                })
              Button(I18n.t('添加', 'Add'))
                .height(44)
                .borderRadius(12)
                .backgroundColor(Theme.ACCENT_BLUE)
                .fontColor(Color.White)
                .onClick(() => {
                  const r: string = this.ruleInput.trim();
                  if (r.length > 0 && !this.settings.customRules.includes(r)) {
                    this.settings.customRules = [...this.settings.customRules, r];
                    this.ruleInput = '';
                    void this.saveAndNotify();
                  }
                })
            }

            ForEach(this.settings.customRules, (rule: string) => {
              Row() {
                Text(rule).fontSize(13).fontColor(Theme.TEXT_PRIMARY).layoutWeight(1)
                Text(I18n.t('删除', 'Delete'))
                  .fontSize(12)
                  .fontColor(Theme.ACCENT_RED)
                  .onClick(() => {
                    this.settings.customRules = this.settings.customRules.filter((x: string) => x !== rule);
                    void this.saveAndNotify();
                  })
              }
              .width('100%')
              .padding(14)
              .backgroundColor(Theme.SURFACE_SOFT)
              .borderRadius(12)
            }, (rule: string) => rule)
          }
          .padding({ left: 20, right: 20, bottom: 96 })
        }.layoutWeight(1)
      } else if (this.subView === 'split_tunnel') {
        this.buildSubHeader(I18n.t('分应用代理', 'Split Tunneling'))
        Scroll() {
          Column({ space: 14 }) {
            Row({ space: 8 }) {
              Button(I18n.t('绕过以下应用 (Bypass)', 'Bypass Listed'))
                .layoutWeight(1)
                .height(40)
                .fontSize(12)
                .borderRadius(12)
                .backgroundColor(this.settings.splitTunnelMode === 'bypass' ? Theme.ACCENT_BLUE_SOFT : Theme.SURFACE_SOFT)
                .fontColor(this.settings.splitTunnelMode === 'bypass' ? Theme.ACCENT_BLUE : Theme.TEXT_SECONDARY)
                .onClick(() => {
                  this.settings.splitTunnelMode = 'bypass';
                  void this.saveAndNotify();
                })
              Button(I18n.t('仅以下应用代理 (Only)', 'Only Listed'))
                .layoutWeight(1)
                .height(40)
                .fontSize(12)
                .borderRadius(12)
                .backgroundColor(this.settings.splitTunnelMode === 'only' ? Theme.ACCENT_BLUE_SOFT : Theme.SURFACE_SOFT)
                .fontColor(this.settings.splitTunnelMode === 'only' ? Theme.ACCENT_BLUE : Theme.TEXT_SECONDARY)
                .onClick(() => {
                  this.settings.splitTunnelMode = 'only';
                  void this.saveAndNotify();
                })
            }

            Row({ space: 8 }) {
              TextInput({ text: this.splitAppInput, placeholder: '例如 com.tencent.mm / com.huawei.browser' })
                .layoutWeight(1)
                .height(44)
                .fontSize(13)
                .fontColor(Theme.TEXT_PRIMARY)
                .placeholderColor(Theme.TEXT_MUTED)
                .backgroundColor(Theme.SURFACE_SOFT)
                .borderRadius(12)
                .padding({ left: 12, right: 12 })
                .onChange((v: string) => {
                  this.splitAppInput = v;
                })
              Button(I18n.t('添加', 'Add'))
                .height(44)
                .borderRadius(12)
                .backgroundColor(Theme.ACCENT_BLUE)
                .fontColor(Color.White)
                .onClick(() => {
                  const pkg: string = this.splitAppInput.trim();
                  if (pkg.length > 0 && !this.settings.splitTunnelApps.includes(pkg)) {
                    this.settings.splitTunnelApps = [...this.settings.splitTunnelApps, pkg];
                    this.splitAppInput = '';
                    void this.saveAndNotify();
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
                    void this.saveAndNotify();
                  })
              }
              .width('100%')
              .padding(14)
              .backgroundColor(Theme.SURFACE_SOFT)
              .borderRadius(12)
            }, (pkg: string) => pkg)
          }
          .padding({ left: 20, right: 20, bottom: 96 })
        }.layoutWeight(1)
      } else if (this.subView === 'chain_proxy') {
        this.buildSubHeader(I18n.t('链式代理', 'Chain Proxy'))
        Scroll() {
          Column({ space: 12 }) {
            Text(I18n.t('二级代理服务器', 'Secondary Proxy Server')).fontSize(12).fontColor(Theme.TEXT_SECONDARY)
            TextInput({ text: this.settings.chainProxy.server, placeholder: '1.2.3.4' })
              .height(46)
              .fontColor(Theme.TEXT_PRIMARY)
              .backgroundColor(Theme.SURFACE_SOFT)
              .borderRadius(12)
              .padding({ left: 12, right: 12 })
              .onChange((v: string) => {
                this.settings.chainProxy.server = v;
              })

            Text(I18n.t('端口', 'Port')).fontSize(12).fontColor(Theme.TEXT_SECONDARY)
            TextInput({ text: String(this.settings.chainProxy.port), placeholder: '1080' })
              .type(InputType.Number)
              .height(46)
              .fontColor(Theme.TEXT_PRIMARY)
              .backgroundColor(Theme.SURFACE_SOFT)
              .borderRadius(12)
              .padding({ left: 12, right: 12 })
              .onChange((v: string) => {
                this.settings.chainProxy.port = Number(v) || 1080;
              })

            Text(I18n.t('用户名（选填）', 'Username (Optional)')).fontSize(12).fontColor(Theme.TEXT_SECONDARY)
            TextInput({ text: this.settings.chainProxy.username })
              .height(46)
              .fontColor(Theme.TEXT_PRIMARY)
              .backgroundColor(Theme.SURFACE_SOFT)
              .borderRadius(12)
              .padding({ left: 12, right: 12 })
              .onChange((v: string) => {
                this.settings.chainProxy.username = v;
              })

            Text(I18n.t('密码（选填）', 'Password (Optional)')).fontSize(12).fontColor(Theme.TEXT_SECONDARY)
            TextInput({ text: this.settings.chainProxy.password })
              .type(InputType.Password)
              .height(46)
              .fontColor(Theme.TEXT_PRIMARY)
              .backgroundColor(Theme.SURFACE_SOFT)
              .borderRadius(12)
              .padding({ left: 12, right: 12 })
              .onChange((v: string) => {
                this.settings.chainProxy.password = v;
              })

            Button(I18n.t('保存配置', 'Save'))
              .width('100%')
              .height(46)
              .margin({ top: 6 })
              .borderRadius(12)
              .backgroundColor(Theme.ACCENT_BLUE)
              .fontColor(Color.White)
              .onClick(async () => {
                await this.saveAndNotify();
                this.showToast(I18n.t('链式代理配置已保存，重新连接后生效', 'Saved'));
              })
          }
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 20, right: 20, bottom: 96 })
        }.layoutWeight(1)
      } else if (this.subView === 'yaml') {
        this.buildSubHeader(I18n.t('Mihomo 生成配置 (YAML)', 'Generated Mihomo YAML'))
        Row({ space: 10 }) {
          Button(I18n.t('复制配置', 'Copy YAML'))
            .height(34)
            .fontSize(12)
            .backgroundColor(Theme.ACCENT_BLUE_SOFT)
            .fontColor(Theme.ACCENT_BLUE)
            .onClick(() => this.copyText(this.cachedYaml))
        }
        .width('100%')
        .padding({ left: 20, right: 20, bottom: 8 })
        Scroll() {
          Text(this.cachedYaml)
            .fontSize(11)
            .fontColor(Theme.TEXT_SECONDARY)
            .fontFamily('monospace')
            .width('100%')
            .padding(14)
            .backgroundColor(Theme.SURFACE_SOFT)
            .borderRadius(12)
        }
        .layoutWeight(1)
        .padding({ left: 20, right: 20, bottom: 96 })
      } else if (this.subView === 'logs') {
        this.buildSubHeader(I18n.t('Mihomo 运行日志', 'Core Logs'))
        Row({ space: 10 }) {
          Button(I18n.t('刷新', 'Refresh'))
            .height(34)
            .fontSize(12)
            .backgroundColor(Theme.SURFACE_SOFT)
            .fontColor(Theme.TEXT_PRIMARY)
            .onClick(() => this.openLogsViewer())
          Button(I18n.t('复制日志', 'Copy'))
            .height(34)
            .fontSize(12)
            .backgroundColor(Theme.ACCENT_BLUE_SOFT)
            .fontColor(Theme.ACCENT_BLUE)
            .onClick(() => this.copyText(this.nativeLogs))
          Button(I18n.t('清空', 'Clear'))
            .height(34)
            .fontSize(12)
            .backgroundColor(Theme.ACCENT_RED_SOFT)
            .fontColor(Theme.ACCENT_RED)
            .onClick(() => {
              VpnManager.getInstance().clearNativeLogs();
              this.nativeLogs = I18n.t('日志已清空', 'Logs cleared');
            })
        }
        .width('100%')
        .padding({ left: 20, right: 20, bottom: 8 })
        Scroll() {
          Text(this.nativeLogs)
            .fontSize(11)
            .fontColor(Theme.TEXT_SECONDARY)
            .fontFamily('monospace')
            .width('100%')
            .padding(14)
            .backgroundColor(Theme.SURFACE_SOFT)
            .borderRadius(12)
        }
        .layoutWeight(1)
        .padding({ left: 20, right: 20, bottom: 96 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BG)
  }
}
