import { promptAction } from '@kit.ArkUI';
import {
  APP_VERSION,
  AppSettings,
  AuthSession
} from '../model/Models';
import { I18n } from '../model/I18n';
import { ApiService } from '../service/ApiService';
import { StorageService } from '../service/StorageService';
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

  private getRegionLabel(): string {
    if (this.settings.relayRegion === 'global') {
      return I18n.t('国际线路', 'Global');
    }
    if (this.settings.relayRegion === 'auto') {
      return I18n.t('自动线路', 'Auto');
    }
    return I18n.t('国内线路', 'Domestic');
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
    Stack() {
      Scroll() {
        Column() {
          // Top Bar with Line Selection Pill (matching APK "点「线路」切换")
          Row() {
            Blank()
            Row({ space: 6 }) {
              Circle()
                .width(7)
                .height(7)
                .fill(Theme.ACCENT_MINT)
              Text(`${I18n.t('线路', 'Line')} · ${this.getRegionLabel()}`)
                .fontSize(12)
                .fontColor(Theme.TEXT_PRIMARY)
              Text('▾')
                .fontSize(11)
                .fontColor(Theme.TEXT_SECONDARY)
            }
            .padding({ left: 12, right: 12, top: 7, bottom: 7 })
            .backgroundColor(Theme.SURFACE)
            .borderRadius(16)
            .border({ width: 1, color: Theme.BORDER })
            .onClick(() => {
              this.showLineSheet = true;
            })
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 14 })

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
          .margin({ top: 28, bottom: 28 })

          // Auth Card (strictly single TizLink mode matching APK)
          Column({ space: 14 }) {
            Text(
              this.mode === 'login'
                ? I18n.t('欢迎回来', 'Welcome Back')
                : this.mode === 'register'
                  ? I18n.t('创建账户', 'Create Account')
                  : I18n.t('重置密码', 'Reset Password')
            )
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.TEXT_PRIMARY)
              .margin({ bottom: 8 })

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
              this.buildInputRow(
                '🔒',
                I18n.t('密码', 'Password'),
                this.password,
                true,
                (v: string) => {
                  this.password = v;
                }
              )
            } else {
              Text(I18n.t('系统将向您的注册邮箱发送重置密码邮件。', 'A password reset email will be sent to your inbox.'))
                .fontSize(12)
                .fontColor(Theme.TEXT_SECONDARY)
                .width('100%')
            }

            Button(
              this.loading
                ? I18n.t('请稍候...', 'Please wait...')
                : this.mode === 'login'
                  ? I18n.t('立即登录', 'Login')
                  : this.mode === 'register'
                    ? I18n.t('注册账户', 'Register')
                    : I18n.t('发送重置邮件', 'Reset Password')
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
          }
          .width('90%')
          .constraintSize({ maxWidth: 440 })
          .padding(24)
          .backgroundColor(Theme.SURFACE)
          .borderRadius(24)
          .border({ width: 1, color: Theme.BORDER })

          // Footer Mode Switch Links
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
              Text(I18n.t('已有账号？返回登录', 'Back to Login'))
                .fontSize(14)
                .fontColor(Theme.TEXT_SECONDARY)
                .onClick(() => {
                  this.mode = 'login';
                })
            }
          }
          .margin({ top: 24, bottom: 40 })
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
    }
    .width('100%')
    .height('100%')
  }
}
