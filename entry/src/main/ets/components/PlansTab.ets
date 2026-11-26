import { promptAction, router } from '@kit.ArkUI';
import {
  AppSettings,
  AuthSession,
  PaymentMethod,
  PlanItem
} from '../model/Models';
import { I18n } from '../model/I18n';
import { ApiService } from '../service/ApiService';
import { Theme } from './Theme';

interface PeriodOption {
  key: string;
  label: string;
  price: number;
}

@Component
export struct PlansTab {
  @Prop plans: PlanItem[] = [];
  @Prop loading: boolean = false;
  @Prop settings: AppSettings | null = null;
  @Prop auth: AuthSession | null = null;

  onRefreshPlans: () => void = () => {};
  onOrderCompleted: () => void = () => {};
  onClose: () => void = () => {};

  @State activePlan: PlanItem | null = null;
  @State selectedPeriodKey: string = 'month_price';
  @State couponCode: string = '';
  @State paymentMethods: PaymentMethod[] = [];
  @State selectedMethodId: string = '';
  @State submitting: boolean = false;

  private showToast(msg: string): void {
    try {
      promptAction.showToast({ message: msg, duration: 2200 });
    } catch (_e) {
      // ignore
    }
  }

  private getPeriodOptions(plan: PlanItem): PeriodOption[] {
    const opts: PeriodOption[] = [];
    if (plan.monthPrice > 0 || (plan.quarterPrice === 0 && plan.yearPrice === 0 && plan.onetimePrice === 0)) {
      opts.push({ key: 'month_price', label: I18n.t('月付', 'Monthly'), price: plan.monthPrice });
    }
    if (plan.quarterPrice > 0) {
      opts.push({ key: 'quarter_price', label: I18n.t('季付', 'Quarterly'), price: plan.quarterPrice });
    }
    if (plan.halfYearPrice > 0) {
      opts.push({ key: 'half_year_price', label: I18n.t('半年付', 'Half-Year'), price: plan.halfYearPrice });
    }
    if (plan.yearPrice > 0) {
      opts.push({ key: 'year_price', label: I18n.t('年付', 'Yearly'), price: plan.yearPrice });
    }
    if (plan.onetimePrice > 0) {
      opts.push({ key: 'onetime_price', label: I18n.t('一次性', 'One-time'), price: plan.onetimePrice });
    }
    if (plan.resetPrice > 0) {
      opts.push({ key: 'reset_price', label: I18n.t('重置流量', 'Reset Traffic'), price: plan.resetPrice });
    }
    return opts;
  }

  private getDisplayPrice(plan: PlanItem): number {
    if (plan.monthPrice > 0) {
      return plan.monthPrice;
    }
    if (plan.quarterPrice > 0) {
      return plan.quarterPrice;
    }
    if (plan.yearPrice > 0) {
      return plan.yearPrice;
    }
    if (plan.onetimePrice > 0) {
      return plan.onetimePrice;
    }
    return 0;
  }

  private async openCheckout(plan: PlanItem): Promise<void> {
    this.activePlan = plan;
    const periods: PeriodOption[] = this.getPeriodOptions(plan);
    this.selectedPeriodKey = periods.length > 0 ? periods[0].key : 'month_price';
    this.couponCode = '';

    if (this.settings && this.auth) {
      const res = await ApiService.getInstance().fetchPaymentMethods(this.settings, this.auth);
      if (res.ok && res.data && res.data.length > 0) {
        this.paymentMethods = res.data;
        this.selectedMethodId = res.data[0].id;
      } else {
        this.paymentMethods = [];
        this.selectedMethodId = '';
      }
    }
  }

  private async submitOrder(): Promise<void> {
    if (!this.activePlan || !this.settings || !this.auth) {
      return;
    }
    this.submitting = true;
    const api: ApiService = ApiService.getInstance();
    const orderRes = await api.createOrder(
      this.settings,
      this.auth,
      this.activePlan.id,
      this.selectedPeriodKey,
      this.couponCode,
      this.selectedMethodId
    );
    if (!orderRes.ok || !orderRes.data) {
      this.submitting = false;
      this.showToast(orderRes.message);
      return;
    }
    const tradeNo: string = orderRes.data;
    const checkoutRes = await api.checkoutOrder(
      this.settings,
      this.auth,
      tradeNo,
      this.selectedMethodId
    );
    this.submitting = false;
    if (!checkoutRes.ok || !checkoutRes.data) {
      this.showToast(checkoutRes.message);
      return;
    }
    if (checkoutRes.data.paid) {
      this.showToast(I18n.t('订阅已激活！', 'Your subscription has been activated!'));
      this.activePlan = null;
      this.onOrderCompleted();
      return;
    }
    if (checkoutRes.data.paymentUrl.length > 0) {
      this.activePlan = null;
      router.pushUrl({
        url: 'pages/WebSupportPage',
        params: {
          title: I18n.t('订单支付', 'Order Checkout'),
          url: checkoutRes.data.paymentUrl
        }
      });
    } else {
      this.showToast(I18n.t(`订单已创建 (${tradeNo})，请在“我的订单”查看`, `Order ${tradeNo} created`));
      this.activePlan = null;
    }
  }

  build() {
    Stack() {
      Column({ space: 14 }) {
        // Header Bar with Back Button
        Row({ space: 8 }) {
          Text('‹')
            .fontSize(28)
            .fontColor(Theme.TEXT_PRIMARY)
            .width(34)
            .height(34)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.onClose();
            })

          Text(I18n.t('订阅套餐', 'Subscription Plans'))
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.TEXT_PRIMARY)
          Blank()
          Text(this.loading ? I18n.t('刷新中...', 'Loading...') : I18n.t('刷新', 'Refresh'))
            .fontSize(14)
            .fontColor(Theme.ACCENT_BLUE)
            .onClick(() => {
              this.onRefreshPlans();
            })
        }
        .width('100%')
        .padding({ left: 12, right: 20, top: 10, bottom: 2 })

        if (this.plans.length === 0) {
          Column({ space: 12 }) {
            Text('📦')
              .fontSize(40)
            Text(I18n.t('暂无可订阅套餐', 'No Plans Available'))
              .fontSize(16)
              .fontColor(Theme.TEXT_PRIMARY)
            Text(I18n.t('点击右上角「刷新」获取最新套餐列表', 'Tap Refresh to load available plans'))
              .fontSize(13)
              .fontColor(Theme.TEXT_SECONDARY)
              .textAlign(TextAlign.Center)
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 14 }) {
            ForEach(this.plans, (plan: PlanItem) => {
              ListItem() {
                Column({ space: 14 }) {
                  Row() {
                    Column({ space: 6 }) {
                      Text(plan.name)
                        .fontSize(18)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(Theme.TEXT_PRIMARY)
                      if (plan.content.length > 0) {
                        Text(plan.content.replace(/<[^>]+>/g, '').trim())
                          .fontSize(13)
                          .fontColor(Theme.TEXT_SECONDARY)
                          .maxLines(3)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                      }
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)

                    if (plan.transferEnableGb > 0) {
                      Text(`${plan.transferEnableGb} GB`)
                        .fontSize(12)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(Theme.ACCENT_BLUE)
                        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                        .backgroundColor(Theme.ACCENT_BLUE_SOFT)
                        .borderRadius(10)
                    }
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Top)

                  Row() {
                    Row({ space: 2 }) {
                      Text('¥')
                        .fontSize(15)
                        .fontColor(Theme.TEXT_SECONDARY)
                        .margin({ top: 8 })
                      Text(`${this.getDisplayPrice(plan)}`)
                        .fontSize(28)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(Theme.TEXT_PRIMARY)
                    }
                    Blank()
                    Button(this.getDisplayPrice(plan) === 0 ? I18n.t('立即体验', 'Try Now') : I18n.t('立即订阅', 'Subscribe'))
                      .height(40)
                      .padding({ left: 22, right: 22 })
                      .borderRadius(12)
                      .backgroundColor(Theme.ACCENT_BLUE)
                      .fontColor(Color.White)
                      .fontSize(14)
                      .fontWeight(FontWeight.Bold)
                      .onClick(() => {
                        void this.openCheckout(plan);
                      })
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Center)
                }
                .width('100%')
                .padding(18)
                .backgroundColor(Theme.SURFACE)
                .borderRadius(18)
                .border({ width: 1, color: Theme.BORDER })
                .shadow({ radius: 10, color: Theme.SHADOW_CARD, offsetY: 2 })
              }
            }, (plan: PlanItem) => `${plan.id}_${plan.name}`)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 20, right: 20, bottom: 20 })
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Theme.BG)

      // Checkout Overlay Modal
      if (this.activePlan !== null) {
        Column() {
          Column({ space: 14 }) {
            Row() {
              Text(this.activePlan.name)
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.TEXT_PRIMARY)
              Blank()
              Text('✕')
                .fontSize(18)
                .fontColor(Theme.TEXT_SECONDARY)
                .onClick(() => {
                  this.activePlan = null;
                })
            }
            .width('100%')

            Text(I18n.t('订阅周期', 'Subscription Period'))
              .fontSize(13)
              .fontColor(Theme.TEXT_SECONDARY)
              .width('100%')

            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.getPeriodOptions(this.activePlan), (opt: PeriodOption) => {
                Column({ space: 2 }) {
                  Text(opt.label)
                    .fontSize(12)
                    .fontColor(this.selectedPeriodKey === opt.key ? Theme.ACCENT_BLUE : Theme.TEXT_SECONDARY)
                  Text(`¥${opt.price}`)
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.selectedPeriodKey === opt.key ? Theme.ACCENT_BLUE : Theme.TEXT_PRIMARY)
                }
                .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                .margin({ right: 8, bottom: 8 })
                .backgroundColor(this.selectedPeriodKey === opt.key ? Theme.ACCENT_BLUE_SOFT : Theme.SURFACE_SOFT)
                .borderRadius(12)
                .border({
                  width: 1,
                  color: this.selectedPeriodKey === opt.key ? Theme.ACCENT_BLUE : Theme.BORDER
                })
                .onClick(() => {
                  this.selectedPeriodKey = opt.key;
                })
              }, (opt: PeriodOption) => opt.key)
            }
            .width('100%')

            TextInput({ text: this.couponCode, placeholder: I18n.t('优惠码（选填）', 'Coupon Code (Optional)') })
              .height(44)
              .fontSize(14)
              .fontColor(Theme.TEXT_PRIMARY)
              .placeholderColor(Theme.TEXT_MUTED)
              .backgroundColor(Theme.SURFACE_SOFT)
              .borderRadius(12)
              .padding({ left: 12, right: 12 })
              .onChange((v: string) => {
                this.couponCode = v;
              })

            if (this.paymentMethods.length > 0) {
              Text(I18n.t('支付方式', 'Payment Method'))
                .fontSize(13)
                .fontColor(Theme.TEXT_SECONDARY)
                .width('100%')
              Row({ space: 8 }) {
                ForEach(this.paymentMethods, (m: PaymentMethod) => {
                  Text(m.name)
                    .fontSize(13)
                    .fontColor(this.selectedMethodId === m.id ? Theme.ACCENT_BLUE : Theme.TEXT_SECONDARY)
                    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                    .backgroundColor(this.selectedMethodId === m.id ? Theme.ACCENT_BLUE_SOFT : Theme.SURFACE_SOFT)
                    .borderRadius(10)
                    .border({
                      width: 1,
                      color: this.selectedMethodId === m.id ? Theme.ACCENT_BLUE : Theme.BORDER
                    })
                    .onClick(() => {
                      this.selectedMethodId = m.id;
                    })
                }, (m: PaymentMethod) => m.id)
              }
              .width('100%')
            }

            Button(this.submitting ? I18n.t('正在提交订单...', 'Submitting...') : I18n.t('确认下单并支付', 'Confirm & Pay'))
              .width('100%')
              .height(46)
              .borderRadius(14)
              .backgroundColor(Theme.ACCENT_BLUE)
              .fontColor(Color.White)
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .enabled(!this.submitting)
              .onClick(() => {
                void this.submitOrder();
              })
          }
          .width('90%')
          .constraintSize({ maxWidth: 440 })
          .padding(20)
          .backgroundColor(Theme.SURFACE)
          .borderRadius(22)
          .shadow({ radius: 24, color: '#26000000', offsetY: 8 })
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
