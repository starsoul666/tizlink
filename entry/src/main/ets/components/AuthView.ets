import { promptAction } from '@kit.ArkUI';
import {
  APP_VERSION,
  AppSettings,
  AuthSession,
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
  @State loading: boolean = false;
  @State showServerConfig: boolean = false;

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
    Scroll() {
      Column() {
        // Brand Header (matching APK screenshot 1-3)
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
        .margin({ top: 52, bottom: 32 })

        // Auth Card (matches original APK login layout)
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

          // Primary CTA Button (matching APK silver-white pill button)
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

          // Optional collapsible API address override
          Row() {
            Text(I18n.t('线路地址设置', 'API Endpoint'))
              .fontSize(12)
              .fontColor(Theme.TEXT_MUTED)
            Blank()
            Text(this.showServerConfig ? '▲' : '▼')
              .fontSize(10)
              .fontColor(Theme.TEXT_MUTED)
          }
          .width('100%')
          .padding({ top: 6, bottom: 2 })
          .onClick(() => {
            this.showServerConfig = !this.showServerConfig;
          })

          if (this.showServerConfig) {
            Column({ space: 8 }) {
              Row() {
                Text(I18n.t('TizLink API 地址', 'TizLink API URL'))
                  .fontSize(12)
                  .fontColor(Theme.TEXT_MUTED)
                Blank()
                Text(I18n.t('恢复默认', 'Reset Default'))
                  .fontSize(12)
                  .fontColor(Theme.ACCENT_MINT)
                  .onClick(() => {
                    this.settings.whmcsApiUrl = DEFAULT_WHMCS_API_URL;
                    this.showToast(I18n.t('已恢复默认 API 地址', 'Restored default API URL'));
                  })
              }
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
            }
            .width('100%')
            .padding({ top: 4 })
          }
        }
        .width('90%')
        .constraintSize({ maxWidth: 440 })
        .padding(24)
        .backgroundColor(Theme.SURFACE)
        .borderRadius(24)
        .border({ width: 1, color: Theme.BORDER })

        // Footer Mode Switch Links (matching APK screenshot 1-3)
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
  }
}
