import { promptAction } from '@kit.ArkUI';
import {
  AppSettings,
  AuthSession
} from '../model/Models';
import { I18n } from '../model/I18n';
import { ApiService } from '../service/ApiService';
import { StorageService } from '../service/StorageService';
import { VpnManager } from '../service/VpnManager';
import { LineSelectorSheet } from './LineSelectorSheet';
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
  @State loading: boolean = false;
  @State showLineSheet: boolean = false;
  @State showLogsModal: boolean = false;
  @State nativeLogs: string = '';

  aboutToAppear(): void {
    this.email = this.auth.email;
  }

  private showToast(msg: string): void {
    try {
      promptAction.showToast({ message: msg, duration: 2200 });
    } catch (_e) {
      // ignore
    }
  }

  private getLineDisplayLabel(): string {
    if (this.settings.relayRegion === 'global') {
      return I18n.t('国际线路', 'Global Line');
    }
    if (this.settings.relayRegion === 'cn') {
      return I18n.t('国内线路', 'Domestic Line');
    }
    return I18n.t('自动选择（推荐）', 'Auto Select (Recommended)');
  }

  private async handleToggleLanguage(): Promise<void> {
    this.settings.language = this.settings.language === 'zh' ? 'en' : 'zh';
    I18n.lang = this.settings.language;
    await StorageService.getInstance().saveSettings(this.settings);
    this.showToast(this.settings.language === 'zh' ? '已切换为简体中文' : 'Switched to English');
  }

  private openLogs(): void {
    this.nativeLogs = VpnManager.getInstance().getNativeLogs();
    if (this.nativeLogs.trim().length === 0) {
      this.nativeLogs = I18n.t('暂无内核运行日志', 'No logs available yet');
    }
    this.showLogsModal = true;
  }

  private async handleSubmit(): Promise<void> {
    const cleanEmail: string = this.email.trim();
    const cleanPwd: string = this.password;
    if (cleanEmail.length === 0 || !cleanEmail.includes('@')) {
      this.showToast(I18n.t('请输入有效的邮箱地址', 'Please enter a valid email'));
      return;
    }
    if (this.mode !== 'reset' && cleanPwd.length < 6) {
      this.showToast(I18n.t('密码长度不能少于 6 位', 'Password must be at least 6 characters'));
      return;
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
        email: res.data.email,
        token: res.data.token,
        authData: res.data.authData,
        savedPassword: cleanPwd,
        deviceId: this.auth.deviceId
      };
      this.auth = nextAuth;
      await StorageService.getInstance().saveAuth(nextAuth);
      if (res.data.subscription) {
        await StorageService.getInstance().saveSubscription(res.data.subscription);
      }
      if (res.data.nodes && res.data.nodes.length > 0) {
        await StorageService.getInstance().saveNodes(res.data.nodes);
      }
      this.showToast(res.message);
      this.onAuthSuccess(res.data.subscribeUrl);
      return;
    }

    if (this.mode === 'register') {
      const res = await api.register(
        this.settings,
        cleanEmail,
        cleanPwd,
        this.inviteCode.trim()
      );
      this.loading = false;
      if (!res.ok || !res.data) {
        this.showToast(res.message);
        return;
      }
      const nextAuth: AuthSession = {
        loggedIn: true,
        email: res.data.email,
        token: res.data.token,
        authData: res.data.authData,
        savedPassword: cleanPwd,
        deviceId: this.auth.deviceId
      };
      this.auth = nextAuth;
      await StorageService.getInstance().saveAuth(nextAuth);
      if (res.data.subscription) {
        await StorageService.getInstance().saveSubscription(res.data.subscription);
      }
      if (res.data.nodes && res.data.nodes.length > 0) {
        await StorageService.getInstance().saveNodes(res.data.nodes);
      }
      this.showToast(I18n.t('注册成功', 'Registration successful'));
      this.onAuthSuccess(res.data.subscribeUrl);
      return;
    }

    const resetRes = await api.resetPassword(this.settings, cleanEmail);
    this.loading = false;
    this.showToast(resetRes.message);
    if (resetRes.ok) {
      this.mode = 'login';
    }
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
        .fontSize(16)
        .fontColor(Theme.TEXT_SECONDARY)
        .width(24)
        .textAlign(TextAlign.Center)
      TextInput({ text: value, placeholder: placeholder })
        .type(isPassword ? InputType.Password : InputType.Normal)
        .placeholderColor(Theme.TEXT_MUTED)
        .fontColor(Theme.TEXT_PRIMARY)
        .fontSize(15)
        .backgroundColor(Color.Transparent)
        .layoutWeight(1)
        .height(46)
        .onChange((v: string) => onChange(v))
    }
    .width('100%')
    .height(54)
    .padding({ left: 14, right: 14 })
    .backgroundColor(Theme.INPUT_BG)
    .borderRadius(14)
    .border({ width: 1, color: Theme.BORDER })
  }

  build() {
    Stack() {
      Scroll() {
        Column() {
          // Brand Title (exact match to real APK login screenshot)
          Text('TizLink')
            .fontSize(32)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.TEXT_PRIMARY)
            .margin({ top: 44, bottom: 38 })

          // White Elevated Login Card
          Column({ space: 16 }) {
            Text(
              this.mode === 'login'
                ? I18n.t('欢迎回来', 'Welcome Back')
                : this.mode === 'register'
                  ? I18n.t('创建账号', 'Create Account')
                  : I18n.t('忘记密码', 'Reset Password')
            )
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.TEXT_PRIMARY)
              .margin({ top: 4, bottom: 10 })

            this.buildInputRow('✉', I18n.t('邮箱', 'Email'), this.email, false, (v: string) => {
              this.email = v;
            })

            if (this.mode === 'register') {
              this.buildInputRow('🎁', I18n.t('邀请码（选填）', 'Invite Code (Optional)'), this.inviteCode, false,
                (v: string) => {
                  this.inviteCode = v;
                })
            }

            if (this.mode !== 'reset') {
              this.buildInputRow('🔒', I18n.t('密码', 'Password'), this.password, true, (v: string) => {
                this.password = v;
              })
            } else {
              Text(I18n.t('系统将向您的注册邮箱发送重置密码邮件。', 'A reset link will be sent to your email.'))
                .fontSize(12)
                .fontColor(Theme.TEXT_SECONDARY)
                .width('100%')
            }

            Button(
              this.loading
                ? I18n.t('请稍候...', 'Please wait...')
                : this.mode === 'login'
                  ? I18n.t('登录', 'Login')
                  : this.mode === 'register'
                    ? I18n.t('注册', 'Register')
                    : I18n.t('发送重置邮件', 'Send Reset Email')
            )
              .width('100%')
              .height(50)
              .margin({ top: 10 })
              .borderRadius(14)
              .backgroundColor(Theme.ACCENT_BLUE)
              .fontColor(Color.White)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .enabled(!this.loading)
              .onClick(() => {
                void this.handleSubmit();
              })
          }
          .width('88%')
          .constraintSize({ maxWidth: 420 })
          .padding({ left: 22, right: 22, top: 28, bottom: 28 })
          .backgroundColor(Theme.SURFACE)
          .borderRadius(22)
          .border({ width: 1, color: '#F0F2F7' })
          .shadow({ radius: 24, color: '#14000000', offsetY: 6 })

          // Links Row 1: 没有账号? 注册 | 忘记密码?
          Row({ space: 18 }) {
            if (this.mode === 'login') {
              Text(I18n.t('没有账号? 注册', 'No account? Register'))
                .fontSize(14)
                .fontColor(Theme.ACCENT_BLUE)
                .onClick(() => {
                  this.mode = 'register';
                })
              Text('|')
                .fontSize(13)
                .fontColor(Theme.BORDER_LIGHT)
              Text(I18n.t('忘记密码?', 'Forgot password?'))
                .fontSize(14)
                .fontColor(Theme.TEXT_SECONDARY)
                .onClick(() => {
                  this.mode = 'reset';
                })
            } else {
              Text(I18n.t('已有账号? 返回登录', 'Back to Login'))
                .fontSize(14)
                .fontColor(Theme.ACCENT_BLUE)
                .onClick(() => {
                  this.mode = 'login';
                })
            }
          }
          .margin({ top: 34 })

          // Links Row 2: 跟随系统 / System | 查看日志
          Row({ space: 18 }) {
            Row({ space: 6 }) {
              Text('🌐')
                .fontSize(14)
                .fontColor(Theme.TEXT_SECONDARY)
              Text(this.settings.language === 'zh' ? '跟随系统 / System' : 'English / 中文')
                .fontSize(13)
                .fontColor(Theme.TEXT_SECONDARY)
            }
            .onClick(() => {
              void this.handleToggleLanguage();
            })

            Text('|')
              .fontSize(13)
              .fontColor(Theme.BORDER_LIGHT)

            Row({ space: 6 }) {
              Text('📄')
                .fontSize(14)
                .fontColor(Theme.TEXT_SECONDARY)
              Text(I18n.t('查看日志', 'View Logs'))
                .fontSize(13)
                .fontColor(Theme.TEXT_SECONDARY)
            }
            .onClick(() => {
              this.openLogs();
            })
          }
          .margin({ top: 24 })

          // Line Selector Section (exact match to real APK login bottom)
          Row({ space: 6 }) {
            Text('⇄')
              .fontSize(13)
              .fontColor(Theme.TEXT_SECONDARY)
            Text(I18n.t('线路', 'Line'))
              .fontSize(13)
              .fontColor(Theme.TEXT_SECONDARY)
          }
          .margin({ top: 24, bottom: 12 })

          Row({ space: 10 }) {
            Text('✦')
              .fontSize(15)
              .fontColor(Theme.ACCENT_TEAL)
            Text(this.getLineDisplayLabel())
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.TEXT_PRIMARY)
              .layoutWeight(1)
            Text('⌄')
              .fontSize(16)
              .fontColor(Theme.TEXT_SECONDARY)
          }
          .width('88%')
          .constraintSize({ maxWidth: 420 })
          .height(50)
          .padding({ left: 16, right: 16 })
          .backgroundColor(Theme.SURFACE_SOFT)
          .borderRadius(14)
          .border({ width: 1, color: Theme.BORDER })
          .margin({ bottom: 36 })
          .onClick(() => {
            this.showLineSheet = true;
          })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Theme.BG)
      .scrollBar(BarState.Off)

      if (this.showLineSheet) {
        LineSelectorSheet({
          settings: $settings,
          onClose: () => {
            this.showLineSheet = false;
          }
        })
      }

      if (this.showLogsModal) {
        Column() {
          Column({ space: 12 }) {
            Row() {
              Text(I18n.t('运行日志', 'Core Logs'))
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.TEXT_PRIMARY)
              Blank()
              Text('✕')
                .fontSize(18)
                .fontColor(Theme.TEXT_SECONDARY)
                .onClick(() => {
                  this.showLogsModal = false;
                })
            }
            .width('100%')

            Scroll() {
              Text(this.nativeLogs)
                .fontSize(11)
                .fontColor(Theme.TEXT_SECONDARY)
                .fontFamily('monospace')
                .width('100%')
            }
            .width('100%')
            .height(340)
            .padding(12)
            .backgroundColor(Theme.SURFACE_SOFT)
            .borderRadius(12)
          }
          .width('90%')
          .constraintSize({ maxWidth: 440 })
          .padding(18)
          .backgroundColor(Theme.SURFACE)
          .borderRadius(20)
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BG)
  }
}
