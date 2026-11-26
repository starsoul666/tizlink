import { promptAction } from '@kit.ArkUI';
import {
  APP_VERSION,
  AppSettings,
  AuthSession,
  BackendType,
  DEFAULT_WHMCS_API_URL
} from '../model/Models';
import { I18n } from '../model/I18n';
import { ApiService } from '../service/ApiService';
import { StorageService } from '../service/StorageService';
import { Theme } from './Theme';

type AuthMode = 'login' | 'register' | 'reset';

@Component
export struct AuthView {
  @Link settings: AppSettings;
  @Link auth: AuthSession;
  onAuthSuccess: (subscribeUrl: string) => void = () => {};

  @State mode: AuthMode = 'login';
  @State email: string = '';
  @State password: string = '';
  @State inviteCode: string = '';
  @State verifyCode: string = '';
  @State loading: boolean = false;
  @State sendingCode: boolean = false;
  @State countdown: number = 0;
  @State showServerConfig: boolean = false;
  @State manualSubInput: string = '';

  private countdownTimer: number = -1;

  aboutToAppear(): void {
    this.email = this.auth.email;
    this.manualSubInput = this.settings.manualSubscribeUrl;
  }

  aboutToDisappear(): void {
    if (this.countdownTimer !== -1) {
      clearInterval(this.countdownTimer);
      this.countdownTimer = -1;
    }
  }

  private showToast(msg: string): void {
    try {
      promptAction.showToast({ message: msg, duration: 2200 });
    } catch (_e) {
      // ignore
    }
  }

  private async handleSendCode(): Promise<void> {
    const cleanEmail: string = this.email.trim();
    if (!cleanEmail.includes('@')) {
      this.showToast(I18n.t('请输入有效的邮箱地址', 'Please enter a valid email'));
      return;
    }
    this.sendingCode = true;
    const res = await ApiService.getInstance().sendEmailVerify(this.settings, cleanEmail);
    this.sendingCode = false;
    this.showToast(res.message);
    if (res.ok) {
      this.countdown = 60;
      if (this.countdownTimer !== -1) {
        clearInterval(this.countdownTimer);
      }
      this.countdownTimer = setInterval(() => {
        if (this.countdown > 0) {
          this.countdown--;
        } else {
          clearInterval(this.countdownTimer);
          this.countdownTimer = -1;
        }
      }, 1000);
    }
  }

  private async handleSubmit(): Promise<void> {
    if (this.settings.backendType === 'custom') {
      await this.enterDirectSubscriptionMode();
      return;
    }

    const cleanEmail: string = this.email.trim();
    const cleanPwd: string = this.password;
    if (cleanEmail.length === 0 || !cleanEmail.includes('@')) {
      this.showToast(I18n.t('请输入邮箱', 'Please enter email'));
      return;
    }
    if (this.mode !== 'reset' || this.settings.backendType !== 'whmcs') {
      if (cleanPwd.length < 6) {
        this.showToast(I18n.t('密码长度不能少于 6 位', 'Password must be at least 6 characters'));
        return;
      }
    }

    this.loading = true;
    await StorageService.getInstance().saveSettings(this.settings);
    const api: ApiService = ApiService.getInstance();

    if (this.mode === 'login') {
      const res = await api.login(this.settings, cleanEmail, cleanPwd, this.auth.deviceId);
      this.loading = false;
      if (!res.ok || !res.data) {
        this.showToast(res.message);
        return;
      }
      const nextAuth: AuthSession = {
        loggedIn: true,
        backendType: this.settings.backendType,
        email: res.data.email,
        token: res.data.token,
        authData: res.data.authData,
        savedPassword: cleanPwd,
        deviceId: this.auth.deviceId
      };
      this.auth = nextAuth;
      await StorageService.getInstance().saveAuth(nextAuth);
      this.showToast(I18n.t('登录成功', 'Login successful'));
      this.onAuthSuccess(res.data.subscribeUrl);
      return;
    }

    if (this.mode === 'register') {
      const res = await api.register(
        this.settings,
        cleanEmail,
        cleanPwd,
        this.verifyCode.trim(),
        this.inviteCode.trim()
      );
      this.loading = false;
      if (!res.ok || !res.data) {
        this.showToast(res.message);
        return;
      }
      const nextAuth: AuthSession = {
        loggedIn: true,
        backendType: this.settings.backendType,
        email: res.data.email,
        token: res.data.token,
        authData: res.data.authData,
        savedPassword: cleanPwd,
        deviceId: this.auth.deviceId
      };
      this.auth = nextAuth;
      await StorageService.getInstance().saveAuth(nextAuth);
      this.showToast(I18n.t('注册成功', 'Registration successful'));
      this.onAuthSuccess(res.data.subscribeUrl);
      return;
    }

    const resetRes = await api.resetPassword(this.settings, cleanEmail, this.verifyCode.trim(), cleanPwd);
    this.loading = false;
    this.showToast(resetRes.message);
    if (resetRes.ok) {
      this.mode = 'login';
      this.verifyCode = '';
    }
  }

  private async enterDirectSubscriptionMode(): Promise<void> {
    const subUrl: string = this.manualSubInput.trim();
    const updatedSettings: AppSettings = {
      backendType: 'custom',
      whmcsApiUrl: this.settings.whmcsApiUrl,
      v2boardApiUrl: this.settings.v2boardApiUrl,
      manualSubscribeUrl: subUrl,
      routingMode: this.settings.routingMode,
      relayRegion: this.settings.relayRegion,
      enableIpv6: this.settings.enableIpv6,
      enableFakeIp: this.settings.enableFakeIp,
      mixedPort: this.settings.mixedPort,
      controllerPort: this.settings.controllerPort,
      splitTunnelEnabled: this.settings.splitTunnelEnabled,
      splitTunnelMode: this.settings.splitTunnelMode,
      splitTunnelApps: this.settings.splitTunnelApps,
      chainProxy: this.settings.chainProxy,
      crispWebsiteId: this.settings.crispWebsiteId,
      telegramUrl: this.settings.telegramUrl,
      language: this.settings.language,
      logLevel: this.settings.logLevel
    };
    this.settings = updatedSettings;
    await StorageService.getInstance().saveSettings(updatedSettings);

    const nextAuth: AuthSession = {
      loggedIn: true,
      backendType: 'custom',
      email: I18n.t('本地订阅模式', 'Direct Subscription'),
      token: 'local',
      authData: 'local',
      savedPassword: '',
      deviceId: this.auth.deviceId
    };
    this.auth = nextAuth;
    await StorageService.getInstance().saveAuth(nextAuth);
    this.onAuthSuccess(subUrl);
  }

  private selectBackend(type: BackendType): void {
    this.settings = {
      backendType: type,
      whmcsApiUrl: this.settings.whmcsApiUrl || DEFAULT_WHMCS_API_URL,
      v2boardApiUrl: this.settings.v2boardApiUrl,
      manualSubscribeUrl: this.settings.manualSubscribeUrl,
      routingMode: this.settings.routingMode,
      relayRegion: this.settings.relayRegion,
      enableIpv6: this.settings.enableIpv6,
      enableFakeIp: this.settings.enableFakeIp,
      mixedPort: this.settings.mixedPort,
      controllerPort: this.settings.controllerPort,
      splitTunnelEnabled: this.settings.splitTunnelEnabled,
      splitTunnelMode: this.settings.splitTunnelMode,
      splitTunnelApps: this.settings.splitTunnelApps,
      chainProxy: this.settings.chainProxy,
      crispWebsiteId: this.settings.crispWebsiteId,
      telegramUrl: this.settings.telegramUrl,
      language: this.settings.language,
      logLevel: this.settings.logLevel
    };
  }

  @Builder
  private buildInputRow(
    iconText: string,
    placeholder: string,
    value: string,
    isPassword: boolean,
    onChange: (val: string) => void
  ) {
    Row({ space: 10 }) {
      Text(iconText)
        .fontSize(15)
        .fontColor(Theme.TEXT_SECONDARY)
        .width(22)
        .textAlign(TextAlign.Center)
      TextInput({ text: value, placeholder: placeholder })
        .type(isPassword ? InputType.Password : InputType.Normal)
        .placeholderColor(Theme.TEXT_MUTED)
        .fontColor(Theme.TEXT_PRIMARY)
        .fontSize(15)
        .backgroundColor(Color.Transparent)
        .layoutWeight(1)
        .height(44)
        .onChange((v: string) => onChange(v))
    }
    .width('100%')
    .height(52)
    .padding({ left: 14, right: 14 })
    .backgroundColor(Theme.INPUT_BG)
    .borderRadius(14)
    .border({ width: 1, color: Theme.BORDER })
  }

  build() {
    Scroll() {
      Column() {
        // Brand Header
        Column({ space: 12 }) {
          Image($r('app.media.app_icon'))
            .width(64)
            .height(64)
            .borderRadius(16)
            .shadow({ radius: 24, color: '#3360A5FA', offsetY: 4 })
          Text('TizLink')
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.TEXT_PRIMARY)
            .letterSpacing(1)
          Text(`HarmonyOS NEXT · v${APP_VERSION}`)
            .fontSize(12)
            .fontColor(Theme.TEXT_MUTED)
        }
        .margin({ top: 44, bottom: 28 })

        // Auth Card
        Column({ space: 14 }) {
          Text(
            this.settings.backendType === 'custom'
              ? I18n.t('免登录订阅模式', 'Direct Subscription')
              : this.mode === 'login'
                ? I18n.t('欢迎回来', 'Welcome Back')
                : this.mode === 'register'
                  ? I18n.t('创建账户', 'Create Account')
                  : I18n.t('重置密码', 'Reset Password')
          )
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.TEXT_PRIMARY)
            .margin({ bottom: 6 })

          // Backend Mode Pill Switcher
          Row({ space: 6 }) {
            this.buildBackendChip('whmcs', I18n.t('TizLink 线路', 'TizLink'))
            this.buildBackendChip('v2board', 'V2Board')
            this.buildBackendChip('custom', I18n.t('直连订阅', 'Direct'))
          }
          .width('100%')
          .padding(4)
          .backgroundColor(Theme.INPUT_BG)
          .borderRadius(12)
          .border({ width: 1, color: Theme.BORDER })

          if (this.settings.backendType === 'custom') {
            Text(I18n.t(
              '无需账号登录，可粘贴 Clash/Mihomo 订阅链接或进入后直接导入节点 URI。',
              'Skip account login. Paste a Clash/Mihomo subscription URL or import node URIs directly.'
            ))
              .fontSize(13)
              .fontColor(Theme.TEXT_SECONDARY)
              .lineHeight(20)

            this.buildInputRow('🔗', I18n.t('订阅链接（选填，进入后也可导入）', 'Subscription URL (Optional)'),
              this.manualSubInput, false, (v: string) => {
                this.manualSubInput = v;
              })
          } else {
            this.buildInputRow('✉', I18n.t('邮箱', 'Email'), this.email, false, (v: string) => {
              this.email = v;
            })

            if (this.mode === 'register') {
              this.buildInputRow('🎁', I18n.t('邀请码（选填）', 'Invite Code (Optional)'), this.inviteCode, false,
                (v: string) => {
                  this.inviteCode = v;
                })
            }

            if (this.mode === 'register' || this.mode === 'reset') {
              Row({ space: 10 }) {
                Text('🛡')
                  .fontSize(15)
                  .fontColor(Theme.TEXT_SECONDARY)
                  .width(22)
                  .textAlign(TextAlign.Center)
                TextInput({ text: this.verifyCode, placeholder: I18n.t('验证码', 'Verification Code') })
                  .placeholderColor(Theme.TEXT_MUTED)
                  .fontColor(Theme.TEXT_PRIMARY)
                  .fontSize(15)
                  .backgroundColor(Color.Transparent)
                  .layoutWeight(1)
                  .height(44)
                  .onChange((v: string) => {
                    this.verifyCode = v;
                  })
                Button(
                  this.countdown > 0
                    ? `${this.countdown}s`
                    : this.sendingCode
                      ? I18n.t('发送中', 'Sending')
                      : I18n.t('发送验证码', 'Send Code')
                )
                  .fontSize(13)
                  .fontColor(this.countdown > 0 ? Theme.TEXT_MUTED : Theme.TEXT_PRIMARY)
                  .backgroundColor(Color.Transparent)
                  .enabled(this.countdown === 0 && !this.sendingCode)
                  .onClick(() => {
                    void this.handleSendCode();
                  })
              }
              .width('100%')
              .height(52)
              .padding({ left: 14, right: 8 })
              .backgroundColor(Theme.INPUT_BG)
              .borderRadius(14)
              .border({ width: 1, color: Theme.BORDER })
            }

            this.buildInputRow(
              '🔒',
              this.mode === 'reset' ? I18n.t('新密码', 'New Password') : I18n.t('密码', 'Password'),
              this.password,
              true,
              (v: string) => {
                this.password = v;
              }
            )
          }

          // Primary CTA Button (matching Flux/TizLink silver-white pill button)
          Button(
            this.loading
              ? I18n.t('请稍候...', 'Please wait...')
              : this.settings.backendType === 'custom'
                ? I18n.t('进入 TizLink', 'Enter TizLink')
                : this.mode === 'login'
                  ? I18n.t('立即登录', 'Login')
                  : this.mode === 'register'
                    ? I18n.t('注册账户', 'Register')
                    : I18n.t('重置密码', 'Reset Password')
          )
            .width('100%')
            .height(52)
            .margin({ top: 8 })
            .borderRadius(16)
            .backgroundColor(Theme.PRIMARY_BTN_BG)
            .fontColor(Theme.PRIMARY_BTN_TEXT)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .enabled(!this.loading)
            .onClick(() => {
              void this.handleSubmit();
            })

          // Collapsible API Endpoint Editor
          if (this.settings.backendType !== 'custom') {
            Row() {
              Text(I18n.t('服务器线路设置', 'API Endpoint Settings'))
                .fontSize(13)
                .fontColor(Theme.TEXT_SECONDARY)
              Blank()
              Text(this.showServerConfig ? '▲' : '▼')
                .fontSize(11)
                .fontColor(Theme.TEXT_MUTED)
            }
            .width('100%')
            .padding({ top: 6, bottom: 2 })
            .onClick(() => {
              this.showServerConfig = !this.showServerConfig;
            })

            if (this.showServerConfig) {
              Column({ space: 8 }) {
                if (this.settings.backendType === 'whmcs') {
                  Text(I18n.t('WHMCS API 地址', 'WHMCS API URL'))
                    .fontSize(12)
                    .fontColor(Theme.TEXT_MUTED)
                    .width('100%')
                  TextInput({ text: this.settings.whmcsApiUrl })
                    .fontSize(12)
                    .fontColor(Theme.TEXT_PRIMARY)
                    .backgroundColor(Theme.INPUT_BG)
                    .borderRadius(10)
                    .border({ width: 1, color: Theme.BORDER })
                    .padding({ left: 10, right: 10 })
                    .height(42)
                    .onChange((v: string) => {
                      this.settings.whmcsApiUrl = v;
                    })
                } else {
                  Text(I18n.t('V2Board 后端域名 (例如 https://panel.example.com)', 'V2Board Domain'))
                    .fontSize(12)
                    .fontColor(Theme.TEXT_MUTED)
                    .width('100%')
                  TextInput({ text: this.settings.v2boardApiUrl, placeholder: 'https://your-v2board-domain.com' })
                    .fontSize(12)
                    .fontColor(Theme.TEXT_PRIMARY)
                    .placeholderColor(Theme.TEXT_MUTED)
                    .backgroundColor(Theme.INPUT_BG)
                    .borderRadius(10)
                    .border({ width: 1, color: Theme.BORDER })
                    .padding({ left: 10, right: 10 })
                    .height(42)
                    .onChange((v: string) => {
                      this.settings.v2boardApiUrl = v;
                    })
                }
              }
              .width('100%')
              .padding({ top: 4 })
            }
          }
        }
        .width('90%')
        .constraintSize({ maxWidth: 440 })
        .padding(24)
        .backgroundColor(Theme.SURFACE)
        .borderRadius(24)
        .border({ width: 1, color: Theme.BORDER })

        // Footer Mode Switch Links
        if (this.settings.backendType !== 'custom') {
          Row({ space: 20 }) {
            if (this.mode === 'login') {
              Text(I18n.t('没有账号？去注册', 'No account? Register'))
                .fontSize(14)
                .fontColor(Theme.TEXT_SECONDARY)
                .onClick(() => {
                  this.mode = 'register';
                })
              Text('|')
                .fontSize(14)
                .fontColor(Theme.BORDER_LIGHT)
              Text(I18n.t('忘记密码', 'Forgot Password'))
                .fontSize(14)
                .fontColor(Theme.TEXT_SECONDARY)
                .onClick(() => {
                  this.mode = 'reset';
                })
            } else {
              Text(I18n.t('已有账号？返回登录', 'Already have an account? Login'))
                .fontSize(14)
                .fontColor(Theme.TEXT_SECONDARY)
                .onClick(() => {
                  this.mode = 'login';
                })
            }
          }
          .margin({ top: 24, bottom: 40 })
        } else {
          Blank().height(40)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BG)
    .scrollBar(BarState.Off)
  }

  @Builder
  private buildBackendChip(type: BackendType, label: string) {
    Text(label)
      .fontSize(12)
      .fontWeight(this.settings.backendType === type ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(this.settings.backendType === type ? Theme.TEXT_PRIMARY : Theme.TEXT_SECONDARY)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(34)
      .borderRadius(9)
      .backgroundColor(this.settings.backendType === type ? Theme.PILL_ACTIVE_BG : Color.Transparent)
      .onClick(() => {
        this.selectBackend(type);
      })
  }
}
