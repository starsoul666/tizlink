import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ApiResult,
  APP_VERSION,
  AppSettings,
  AuthSession,
  createEmptySubscription,
  InviteCodeItem,
  InviteSummary,
  NoticeItem,
  OrderItem,
  PaymentMethod,
  PlanItem,
  ProxyNode,
  SubscriptionInfo
} from '../model/Models';
import { SubscriptionParser } from './SubscriptionParser';

const DOMAIN: number = 0x3200;
const TAG: string = 'ApiService';

type JsonMap = Record<string, Object | undefined>;

export interface LoginPayload {
  token: string;
  authData: string;
  email: string;
  subscribeUrl: string;
}

export interface CheckoutResult {
  type: number;
  paymentUrl: string;
  paid: boolean;
}

export class ApiService {
  private static instance: ApiService | null = null;

  static getInstance(): ApiService {
    if (!ApiService.instance) {
      ApiService.instance = new ApiService();
    }
    return ApiService.instance;
  }

  private getV2BoardBase(settings: AppSettings): string {
    const raw: string = settings.v2boardApiUrl.trim().replace(/\/+$/, '');
    if (raw.length === 0) {
      return '';
    }
    if (raw.endsWith('/api/v1')) {
      return raw;
    }
    return `${raw}/api/v1`;
  }

  private async requestJson(
    url: string,
    method: http.RequestMethod,
    headers: Record<string, string>,
    body?: string
  ): Promise<ApiResult<JsonMap>> {
    const req: http.HttpRequest = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: method,
        header: headers,
        connectTimeout: 15000,
        readTimeout: 20000,
        expectDataType: http.HttpDataType.STRING
      };
      if (body !== undefined && body.length > 0) {
        options.extraData = body;
      }
      const res: http.HttpResponse = await req.request(url, options);
      const text: string = typeof res.result === 'string' ? res.result : String(res.result ?? '');
      if (res.responseCode >= 200 && res.responseCode < 300) {
        try {
          const parsed = JSON.parse(text) as JsonMap;
          return { ok: true, message: 'OK', data: parsed };
        } catch (_e) {
          return { ok: false, message: `Invalid JSON response (${res.responseCode})` };
        }
      }
      let errMsg: string = `HTTP ${res.responseCode}`;
      try {
        const errObj = JSON.parse(text) as JsonMap;
        const m = errObj['message'] ?? errObj['msg'] ?? errObj['error'];
        if (typeof m === 'string' && m.length > 0) {
          errMsg = m;
        }
      } catch (_e) {
        // keep HTTP status
      }
      return { ok: false, message: errMsg };
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(DOMAIN, TAG, 'HTTP error %{public}s: %{public}s', url, msg);
      return { ok: false, message: msg };
    } finally {
      req.destroy();
    }
  }

  private async requestText(
    url: string,
    headers: Record<string, string>
  ): Promise<ApiResult<string>> {
    const req: http.HttpRequest = http.createHttp();
    try {
      const res: http.HttpResponse = await req.request(url, {
        method: http.RequestMethod.GET,
        header: headers,
        connectTimeout: 15000,
        readTimeout: 25000,
        expectDataType: http.HttpDataType.STRING
      });
      const text: string = typeof res.result === 'string' ? res.result : String(res.result ?? '');
      if (res.responseCode >= 200 && res.responseCode < 300) {
        return { ok: true, message: 'OK', data: text };
      }
      return { ok: false, message: `HTTP ${res.responseCode}` };
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : JSON.stringify(err);
      return { ok: false, message: msg };
    } finally {
      req.destroy();
    }
  }

  private async whmcsCall(
    settings: AppSettings,
    action: string,
    params: Record<string, string>
  ): Promise<ApiResult<JsonMap>> {
    const apiUrl: string = settings.whmcsApiUrl.trim();
    if (apiUrl.length === 0) {
      return { ok: false, message: '未配置 WHMCS API 地址' };
    }
    const pairs: string[] = [`action=${encodeURIComponent(action)}`];
    const keys: string[] = Object.keys(params);
    for (const k of keys) {
      pairs.push(`${encodeURIComponent(k)}=${encodeURIComponent(params[k])}`);
    }
    const formBody: string = pairs.join('&');
    const headers: Record<string, string> = {
      'Content-Type': 'application/x-www-form-urlencoded',
      'User-Agent': `AegisClient-WHMCS/1.0 AegisClient/${APP_VERSION} (HarmonyOS)`
    };
    const res: ApiResult<JsonMap> = await this.requestJson(apiUrl, http.RequestMethod.POST, headers, formBody);
    if (!res.ok || !res.data) {
      return res;
    }
    const status = res.data['status'];
    const success = res.data['success'];
    const result = res.data['result'];
    if (status === 'error' || success === false || result === 'error') {
      const errMsg = res.data['message'] ?? res.data['msg'] ?? res.data['error'] ?? '请求失败';
      return { ok: false, message: String(errMsg) };
    }
    return res;
  }

  private v2Headers(auth?: AuthSession): Record<string, string> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': `AegisClient/${APP_VERSION} (HarmonyOS)`
    };
    if (auth && auth.authData.length > 0) {
      headers['Authorization'] = auth.authData;
    } else if (auth && auth.token.length > 0) {
      headers['Authorization'] = auth.token;
    }
    return headers;
  }

  // ==================== AUTH ====================

  async login(
    settings: AppSettings,
    email: string,
    password: string,
    deviceId: string
  ): Promise<ApiResult<LoginPayload>> {
    if (settings.backendType === 'whmcs') {
      const res = await this.whmcsCall(settings, 'login', {
        'email': email,
        'password': password,
        'device_id': deviceId
      });
      if (!res.ok || !res.data) {
        return { ok: false, message: res.message };
      }
      const d = (res.data['data'] as JsonMap | undefined) ?? res.data;
      const token: string = String(d['token'] ?? d['auth_data'] ?? `whmcs:${email}`);
      const subUrl: string = String(d['subscribe_url'] ?? d['subscription_url'] ?? '');
      return {
        ok: true,
        message: '登录成功',
        data: {
          token: token,
          authData: token,
          email: email,
          subscribeUrl: subUrl
        }
      };
    }

    const base: string = this.getV2BoardBase(settings);
    if (base.length === 0) {
      return { ok: false, message: '请先在服务器设置中填写 V2Board 后端域名' };
    }
    const res = await this.requestJson(
      `${base}/passport/auth/login`,
      http.RequestMethod.POST,
      this.v2Headers(),
      JSON.stringify({ email: email, password: password })
    );
    if (!res.ok || !res.data) {
      return { ok: false, message: res.message };
    }
    const d = res.data['data'] as JsonMap | undefined;
    if (!d) {
      return { ok: false, message: String(res.data['message'] ?? '登录失败') };
    }
    return {
      ok: true,
      message: '登录成功',
      data: {
        token: String(d['token'] ?? ''),
        authData: String(d['auth_data'] ?? d['token'] ?? ''),
        email: email,
        subscribeUrl: ''
      }
    };
  }

  async sendEmailVerify(settings: AppSettings, email: string): Promise<ApiResult<boolean>> {
    if (settings.backendType === 'whmcs') {
      const res = await this.whmcsCall(settings, 'sendcode', { 'email': email });
      return { ok: res.ok, message: res.ok ? '验证码已发送' : res.message, data: res.ok };
    }
    const base: string = this.getV2BoardBase(settings);
    if (base.length === 0) {
      return { ok: false, message: '未配置后端地址' };
    }
    const res = await this.requestJson(
      `${base}/passport/comm/sendEmailVerify`,
      http.RequestMethod.POST,
      this.v2Headers(),
      JSON.stringify({ email: email })
    );
    return { ok: res.ok, message: res.ok ? '验证码已发送' : res.message, data: res.ok };
  }

  async register(
    settings: AppSettings,
    email: string,
    password: string,
    emailCode: string,
    inviteCode: string
  ): Promise<ApiResult<LoginPayload>> {
    if (settings.backendType === 'whmcs') {
      const params: Record<string, string> = {
        'email': email,
        'password': password
      };
      if (emailCode.length > 0) {
        params['code'] = emailCode;
      }
      if (inviteCode.length > 0) {
        params['invite_code'] = inviteCode;
      }
      const res = await this.whmcsCall(settings, 'register', params);
      if (!res.ok || !res.data) {
        return { ok: false, message: res.message };
      }
      const d = (res.data['data'] as JsonMap | undefined) ?? res.data;
      const token: string = String(d['token'] ?? `whmcs:${email}`);
      return {
        ok: true,
        message: '注册成功',
        data: { token: token, authData: token, email: email, subscribeUrl: '' }
      };
    }

    const base: string = this.getV2BoardBase(settings);
    if (base.length === 0) {
      return { ok: false, message: '未配置后端地址' };
    }
    const payload: Record<string, string> = {
      'email': email,
      'password': password
    };
    if (emailCode.length > 0) {
      payload['email_code'] = emailCode;
    }
    if (inviteCode.length > 0) {
      payload['invite_code'] = inviteCode;
    }
    const res = await this.requestJson(
      `${base}/passport/auth/register`,
      http.RequestMethod.POST,
      this.v2Headers(),
      JSON.stringify(payload)
    );
    if (!res.ok || !res.data) {
      return { ok: false, message: res.message };
    }
    const d = res.data['data'] as JsonMap | undefined;
    if (!d) {
      return { ok: false, message: String(res.data['message'] ?? '注册失败') };
    }
    return {
      ok: true,
      message: '注册成功',
      data: {
        token: String(d['token'] ?? ''),
        authData: String(d['auth_data'] ?? d['token'] ?? ''),
        email: email,
        subscribeUrl: ''
      }
    };
  }

  async resetPassword(
    settings: AppSettings,
    email: string,
    emailCode: string,
    newPassword: string
  ): Promise<ApiResult<boolean>> {
    if (settings.backendType === 'whmcs') {
      const res = await this.whmcsCall(settings, 'resetpassword', {
        'email': email,
        'code': emailCode,
        'password': newPassword
      });
      return { ok: res.ok, message: res.ok ? '密码重置成功' : res.message, data: res.ok };
    }
    const base: string = this.getV2BoardBase(settings);
    if (base.length === 0) {
      return { ok: false, message: '未配置后端地址' };
    }
    const res = await this.requestJson(
      `${base}/passport/auth/forget`,
      http.RequestMethod.POST,
      this.v2Headers(),
      JSON.stringify({ email: email, email_code: emailCode, password: newPassword })
    );
    return { ok: res.ok, message: res.ok ? '密码重置成功' : res.message, data: res.ok };
  }

  async changePassword(
    settings: AppSettings,
    auth: AuthSession,
    oldPassword: string,
    newPassword: string
  ): Promise<ApiResult<boolean>> {
    if (settings.backendType === 'whmcs') {
      const res = await this.whmcsCall(settings, 'changepassword', {
        'email': auth.email,
        'password': oldPassword,
        'new_password': newPassword
      });
      return { ok: res.ok, message: res.ok ? '密码修改成功' : res.message, data: res.ok };
    }
    const base: string = this.getV2BoardBase(settings);
    const res = await this.requestJson(
      `${base}/user/changePassword`,
      http.RequestMethod.POST,
      this.v2Headers(auth),
      JSON.stringify({ old_password: oldPassword, new_password: newPassword })
    );
    return { ok: res.ok, message: res.ok ? '密码修改成功' : res.message, data: res.ok };
  }

  // ==================== SUBSCRIPTION & NODES ====================

  async fetchSubscriptionInfo(
    settings: AppSettings,
    auth: AuthSession
  ): Promise<ApiResult<SubscriptionInfo>> {
    if (settings.backendType === 'custom') {
      const info: SubscriptionInfo = createEmptySubscription();
      info.planName = '自定义订阅';
      info.subscribeUrl = settings.manualSubscribeUrl;
      info.email = auth.email || '本地订阅用户';
      return { ok: true, message: 'OK', data: info };
    }

    if (settings.backendType === 'whmcs') {
      const res = await this.whmcsCall(settings, 'getsubscription', {
        'email': auth.email,
        'password': auth.savedPassword,
        'token': auth.token
      });
      if (!res.ok || !res.data) {
        return { ok: false, message: res.message };
      }
      const d = (res.data['data'] as JsonMap | undefined) ?? res.data;
      const info: SubscriptionInfo = createEmptySubscription();
      info.planName = String(d['plan_name'] ?? d['product_name'] ?? d['name'] ?? 'TizLink 套餐');
      info.subscribeUrl = String(d['subscribe_url'] ?? d['subscription_url'] ?? d['url'] ?? '');
      info.expiredAt = Number(d['expired_at'] ?? d['expire_time'] ?? 0) || 0;
      info.transferEnable = Number(d['transfer_enable'] ?? d['total_traffic'] ?? 0) || 0;
      info.usedUpload = Number(d['u'] ?? d['upload'] ?? 0) || 0;
      info.usedDownload = Number(d['d'] ?? d['download'] ?? d['used_traffic'] ?? 0) || 0;
      info.resetDay = Number(d['reset_day'] ?? 0) || 0;
      info.email = String(d['email'] ?? auth.email);
      info.balance = Number(d['balance'] ?? 0) || 0;
      info.uuid = String(d['uuid'] ?? '');
      return { ok: true, message: 'OK', data: info };
    }

    const base: string = this.getV2BoardBase(settings);
    const subRes = await this.requestJson(
      `${base}/user/getSubscribe`,
      http.RequestMethod.GET,
      this.v2Headers(auth)
    );
    if (!subRes.ok || !subRes.data) {
      return { ok: false, message: subRes.message };
    }
    const d = (subRes.data['data'] as JsonMap | undefined) ?? {};
    const planObj = d['plan'] as JsonMap | undefined;
    const info: SubscriptionInfo = createEmptySubscription();
    info.planName = String(planObj?.['name'] ?? d['plan_name'] ?? '无有效套餐');
    info.subscribeUrl = String(d['subscribe_url'] ?? '');
    info.expiredAt = Number(d['expired_at'] ?? 0) || 0;
    info.transferEnable = Number(d['transfer_enable'] ?? 0) || 0;
    info.usedUpload = Number(d['u'] ?? 0) || 0;
    info.usedDownload = Number(d['d'] ?? 0) || 0;
    info.resetDay = Number(d['reset_day'] ?? 0) || 0;
    info.email = String(d['email'] ?? auth.email);
    info.uuid = String(d['uuid'] ?? '');

    // Also fetch user/info for balance
    const userRes = await this.requestJson(`${base}/user/info`, http.RequestMethod.GET, this.v2Headers(auth));
    if (userRes.ok && userRes.data) {
      const ud = userRes.data['data'] as JsonMap | undefined;
      if (ud) {
        info.balance = (Number(ud['balance'] ?? 0) || 0) / 100.0;
        if (ud['email']) {
          info.email = String(ud['email']);
        }
      }
    }
    return { ok: true, message: 'OK', data: info };
  }

  async downloadAndParseNodes(subscribeUrl: string): Promise<ApiResult<ProxyNode[]>> {
    const cleanUrl: string = subscribeUrl.trim();
    if (cleanUrl.length === 0) {
      return { ok: false, message: '订阅链接为空' };
    }
    const headers: Record<string, string> = {
      'User-Agent': `clash-verge/v2.0.0 AegisClient/${APP_VERSION} (HarmonyOS)`,
      'Accept': '*/*'
    };
    const res: ApiResult<string> = await this.requestText(cleanUrl, headers);
    if (!res.ok || !res.data) {
      return { ok: false, message: `订阅下载失败: ${res.message}` };
    }
    const nodes: ProxyNode[] = SubscriptionParser.parseSubscription(res.data);
    if (nodes.length === 0) {
      return { ok: false, message: '订阅内容中未解析到可用节点' };
    }
    return { ok: true, message: `已更新 ${nodes.length} 个节点`, data: nodes };
  }

  // ==================== PLANS, ORDERS & PAYMENTS ====================

  async fetchPlans(settings: AppSettings, auth: AuthSession): Promise<ApiResult<PlanItem[]>> {
    if (settings.backendType === 'custom') {
      return { ok: true, message: 'OK', data: [] };
    }
    let rawList: Object[] = [];
    if (settings.backendType === 'whmcs') {
      const res = await this.whmcsCall(settings, 'getproducts', {
        'email': auth.email,
        'token': auth.token
      });
      if (!res.ok || !res.data) {
        return { ok: false, message: res.message };
      }
      const d = res.data['data'] ?? res.data['products'];
      if (Array.isArray(d)) {
        rawList = d as Object[];
      }
    } else {
      const base: string = this.getV2BoardBase(settings);
      const res = await this.requestJson(`${base}/user/plan/fetch`, http.RequestMethod.GET, this.v2Headers(auth));
      if (!res.ok || !res.data) {
        return { ok: false, message: res.message };
      }
      const d = res.data['data'];
      if (Array.isArray(d)) {
        rawList = d as Object[];
      }
    }

    const plans: PlanItem[] = [];
    const scale: number = settings.backendType === 'v2board' ? 100.0 : 1.0;
    for (const item of rawList) {
      const m = item as JsonMap;
      plans.push({
        id: Number(m['id'] ?? 0) || 0,
        name: String(m['name'] ?? '套餐'),
        content: String(m['content'] ?? m['description'] ?? ''),
        transferEnableGb: Number(m['transfer_enable'] ?? m['traffic_gb'] ?? 0) || 0,
        monthPrice: (Number(m['month_price'] ?? m['monthly'] ?? 0) || 0) / scale,
        quarterPrice: (Number(m['quarter_price'] ?? m['quarterly'] ?? 0) || 0) / scale,
        halfYearPrice: (Number(m['half_year_price'] ?? m['semiannually'] ?? 0) || 0) / scale,
        yearPrice: (Number(m['year_price'] ?? m['annually'] ?? 0) || 0) / scale,
        onetimePrice: (Number(m['onetime_price'] ?? 0) || 0) / scale,
        resetPrice: (Number(m['reset_price'] ?? 0) || 0) / scale
      });
    }
    return { ok: true, message: 'OK', data: plans };
  }

  async fetchPaymentMethods(settings: AppSettings, auth: AuthSession): Promise<ApiResult<PaymentMethod[]>> {
    let rawList: Object[] = [];
    if (settings.backendType === 'whmcs') {
      const res = await this.whmcsCall(settings, 'getpaymentmethods', {
        'email': auth.email,
        'token': auth.token
      });
      if (!res.ok || !res.data) {
        return { ok: false, message: res.message };
      }
      const d = res.data['data'] ?? res.data['methods'];
      if (Array.isArray(d)) {
        rawList = d as Object[];
      }
    } else {
      const base: string = this.getV2BoardBase(settings);
      const res = await this.requestJson(
        `${base}/user/order/getPaymentMethod`,
        http.RequestMethod.GET,
        this.v2Headers(auth)
      );
      if (!res.ok || !res.data) {
        return { ok: false, message: res.message };
      }
      const d = res.data['data'];
      if (Array.isArray(d)) {
        rawList = d as Object[];
      }
    }

    const methods: PaymentMethod[] = [];
    for (const item of rawList) {
      const m = item as JsonMap;
      methods.push({
        id: String(m['id'] ?? m['module'] ?? ''),
        name: String(m['name'] ?? m['displayname'] ?? '在线支付'),
        payment: String(m['payment'] ?? m['module'] ?? '')
      });
    }
    return { ok: true, message: 'OK', data: methods };
  }

  async createOrder(
    settings: AppSettings,
    auth: AuthSession,
    planId: number,
    period: string,
    couponCode: string
  ): Promise<ApiResult<string>> {
    if (settings.backendType === 'whmcs') {
      const params: Record<string, string> = {
        'email': auth.email,
        'token': auth.token,
        'plan_id': String(planId),
        'period': period
      };
      if (couponCode.trim().length > 0) {
        params['coupon_code'] = couponCode.trim();
      }
      const res = await this.whmcsCall(settings, 'createorder', params);
      if (!res.ok || !res.data) {
        return { ok: false, message: res.message };
      }
      const d = (res.data['data'] as JsonMap | undefined) ?? res.data;
      const tradeNo: string = String(d['trade_no'] ?? d['invoice_id'] ?? d['order_id'] ?? '');
      return tradeNo.length > 0
        ? { ok: true, message: '订单已创建', data: tradeNo }
        : { ok: false, message: '未返回订单号' };
    }

    const base: string = this.getV2BoardBase(settings);
    const body: Record<string, Object> = {
      'plan_id': planId,
      'period': period
    };
    if (couponCode.trim().length > 0) {
      body['coupon_code'] = couponCode.trim();
    }
    const res = await this.requestJson(
      `${base}/user/order/save`,
      http.RequestMethod.POST,
      this.v2Headers(auth),
      JSON.stringify(body)
    );
    if (!res.ok || !res.data) {
      return { ok: false, message: res.message };
    }
    const tradeNo: string = String(res.data['data'] ?? '');
    return tradeNo.length > 0
      ? { ok: true, message: '订单已创建', data: tradeNo }
      : { ok: false, message: String(res.data['message'] ?? '创建订单失败') };
  }

  async checkoutOrder(
    settings: AppSettings,
    auth: AuthSession,
    tradeNo: string,
    methodId: string
  ): Promise<ApiResult<CheckoutResult>> {
    if (settings.backendType === 'whmcs') {
      const res = await this.whmcsCall(settings, 'checkorder', {
        'email': auth.email,
        'token': auth.token,
        'trade_no': tradeNo,
        'paymentmethod': methodId
      });
      if (!res.ok || !res.data) {
        return { ok: false, message: res.message };
      }
      const d = (res.data['data'] as JsonMap | undefined) ?? res.data;
      const payUrl: string = String(d['payment_url'] ?? d['pay_url'] ?? d['url'] ?? '');
      const paid: boolean = d['paid'] === true || String(d['status']) === 'Paid';
      return { ok: true, message: 'OK', data: { type: paid ? -1 : 1, paymentUrl: payUrl, paid: paid } };
    }

    const base: string = this.getV2BoardBase(settings);
    const res = await this.requestJson(
      `${base}/user/order/checkout`,
      http.RequestMethod.POST,
      this.v2Headers(auth),
      JSON.stringify({ trade_no: tradeNo, method: methodId })
    );
    if (!res.ok || !res.data) {
      return { ok: false, message: res.message };
    }
    const typeVal: number = Number(res.data['type'] ?? 1);
    const dataVal = res.data['data'];
    const paid: boolean = typeVal === -1 || dataVal === true;
    const payUrl: string = typeof dataVal === 'string' ? dataVal : '';
    return { ok: true, message: 'OK', data: { type: typeVal, paymentUrl: payUrl, paid: paid } };
  }

  async fetchOrders(settings: AppSettings, auth: AuthSession): Promise<ApiResult<OrderItem[]>> {
    if (settings.backendType === 'custom') {
      return { ok: true, message: 'OK', data: [] };
    }
    let rawList: Object[] = [];
    if (settings.backendType === 'whmcs') {
      const res = await this.whmcsCall(settings, 'getorders', {
        'email': auth.email,
        'token': auth.token
      });
      if (!res.ok || !res.data) {
        return { ok: false, message: res.message };
      }
      const d = res.data['data'] ?? res.data['orders'];
      if (Array.isArray(d)) {
        rawList = d as Object[];
      }
    } else {
      const base: string = this.getV2BoardBase(settings);
      const res = await this.requestJson(`${base}/user/order/fetch`, http.RequestMethod.GET, this.v2Headers(auth));
      if (!res.ok || !res.data) {
        return { ok: false, message: res.message };
      }
      const d = res.data['data'];
      if (Array.isArray(d)) {
        rawList = d as Object[];
      }
    }

    const orders: OrderItem[] = [];
    const scale: number = settings.backendType === 'v2board' ? 100.0 : 1.0;
    for (const item of rawList) {
      const m = item as JsonMap;
      const planObj = m['plan'] as JsonMap | undefined;
      orders.push({
        tradeNo: String(m['trade_no'] ?? m['invoice_id'] ?? m['id'] ?? ''),
        planName: String(planObj?.['name'] ?? m['plan_name'] ?? '订阅订单'),
        period: String(m['period'] ?? 'month_price'),
        totalAmount: (Number(m['total_amount'] ?? m['amount'] ?? 0) || 0) / scale,
        status: Number(m['status'] ?? 0) || 0,
        createdAt: Number(m['created_at'] ?? 0) || 0,
        paymentUrl: String(m['payment_url'] ?? '')
      });
    }
    return { ok: true, message: 'OK', data: orders };
  }

  async cancelOrder(settings: AppSettings, auth: AuthSession, tradeNo: string): Promise<ApiResult<boolean>> {
    if (settings.backendType === 'v2board') {
      const base: string = this.getV2BoardBase(settings);
      const res = await this.requestJson(
        `${base}/user/order/cancel`,
        http.RequestMethod.POST,
        this.v2Headers(auth),
        JSON.stringify({ trade_no: tradeNo })
      );
      return { ok: res.ok, message: res.ok ? '订单已取消' : res.message, data: res.ok };
    }
    return { ok: false, message: '当前后端不支持客户端直接取消订单' };
  }

  // ==================== INVITE & NOTICES ====================

  async fetchInviteSummary(settings: AppSettings, auth: AuthSession): Promise<ApiResult<InviteSummary>> {
    const empty: InviteSummary = {
      codes: [],
      registeredCount: 0,
      commissionRate: 0,
      commissionBalance: 0,
      pendingCommission: 0
    };
    if (settings.backendType === 'custom') {
      return { ok: true, message: 'OK', data: empty };
    }
    if (settings.backendType === 'whmcs') {
      const res = await this.whmcsCall(settings, 'affiliate', {
        'email': auth.email,
        'token': auth.token
      });
      if (!res.ok || !res.data) {
        return { ok: false, message: res.message };
      }
      const d = (res.data['data'] as JsonMap | undefined) ?? res.data;
      const codeStr: string = String(d['invite_code'] ?? d['code'] ?? '');
      if (codeStr.length > 0) {
        empty.codes.push({ code: codeStr, status: 0, createdAt: 0 });
      }
      empty.registeredCount = Number(d['registered_count'] ?? d['signups'] ?? 0) || 0;
      empty.commissionBalance = Number(d['balance'] ?? 0) || 0;
      return { ok: true, message: 'OK', data: empty };
    }

    const base: string = this.getV2BoardBase(settings);
    const res = await this.requestJson(`${base}/user/invite/fetch`, http.RequestMethod.GET, this.v2Headers(auth));
    if (!res.ok || !res.data) {
      return { ok: false, message: res.message };
    }
    const d = (res.data['data'] as JsonMap | undefined) ?? {};
    const codesRaw = d['codes'];
    if (Array.isArray(codesRaw)) {
      for (const c of codesRaw as Object[]) {
        const cm = c as JsonMap;
        empty.codes.push({
          code: String(cm['code'] ?? ''),
          status: Number(cm['status'] ?? 0) || 0,
          createdAt: Number(cm['created_at'] ?? 0) || 0
        });
      }
    }
    const stat = d['stat'];
    if (Array.isArray(stat) && stat.length >= 4) {
      empty.registeredCount = Number(stat[0] ?? 0) || 0;
      empty.commissionBalance = (Number(stat[1] ?? 0) || 0) / 100.0;
      empty.pendingCommission = (Number(stat[2] ?? 0) || 0) / 100.0;
      empty.commissionRate = Number(stat[3] ?? 0) || 0;
    }
    return { ok: true, message: 'OK', data: empty };
  }

  async generateInviteCode(settings: AppSettings, auth: AuthSession): Promise<ApiResult<boolean>> {
    if (settings.backendType !== 'v2board') {
      return { ok: false, message: '当前后端自动分配固定邀请码' };
    }
    const base: string = this.getV2BoardBase(settings);
    const res = await this.requestJson(`${base}/user/invite/save`, http.RequestMethod.GET, this.v2Headers(auth));
    return { ok: res.ok, message: res.ok ? '邀请码已生成' : res.message, data: res.ok };
  }

  async fetchNotices(settings: AppSettings, auth: AuthSession): Promise<ApiResult<NoticeItem[]>> {
    if (settings.backendType === 'custom') {
      return { ok: true, message: 'OK', data: [] };
    }
    let rawList: Object[] = [];
    if (settings.backendType === 'whmcs') {
      const res = await this.whmcsCall(settings, 'getannouncements', {
        'email': auth.email,
        'token': auth.token
      });
      if (!res.ok || !res.data) {
        return { ok: false, message: res.message };
      }
      const d = res.data['data'] ?? res.data['announcements'];
      if (Array.isArray(d)) {
        rawList = d as Object[];
      }
    } else {
      const base: string = this.getV2BoardBase(settings);
      const res = await this.requestJson(`${base}/user/notice/fetch`, http.RequestMethod.GET, this.v2Headers(auth));
      if (!res.ok || !res.data) {
        return { ok: false, message: res.message };
      }
      const d = res.data['data'];
      if (Array.isArray(d)) {
        rawList = d as Object[];
      }
    }

    const notices: NoticeItem[] = [];
    for (const item of rawList) {
      const m = item as JsonMap;
      notices.push({
        id: Number(m['id'] ?? 0) || 0,
        title: String(m['title'] ?? '系统公告'),
        content: String(m['content'] ?? m['announcement'] ?? ''),
        createdAt: Number(m['created_at'] ?? 0) || 0
      });
    }
    return { ok: true, message: 'OK', data: notices };
  }

  // ==================== EXIT IP CHECK ====================

  async fetchExitIp(): Promise<string> {
    const endpoints: string[] = [
      'https://ifconfig.me/ip',
      'https://api.ipify.org',
      'https://icanhazip.com'
    ];
    for (const ep of endpoints) {
      const res: ApiResult<string> = await this.requestText(ep, { 'User-Agent': 'curl/8.0' });
      if (res.ok && res.data) {
        const ip: string = res.data.trim();
        if (ip.length >= 7 && ip.length <= 45) {
          return ip;
        }
      }
    }
    return '--';
  }
}
