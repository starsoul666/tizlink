import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ApiResult,
  APP_VERSION,
  AppSettings,
  AuthSession,
  createEmptySubscription,
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
  subscription?: SubscriptionInfo;
  nodes?: ProxyNode[];
  inviteSummary?: InviteSummary;
}

export interface WhmcsSyncBundle {
  subscription: SubscriptionInfo;
  nodes: ProxyNode[];
  inviteSummary: InviteSummary;
}

export interface CheckoutResult {
  type: number;
  paymentUrl: string;
  paid: boolean;
}

export class ApiService {
  private static instance: ApiService | null = null;
  private cachedWhmcsInvite: InviteSummary | null = null;

  static getInstance(): ApiService {
    if (!ApiService.instance) {
      ApiService.instance = new ApiService();
    }
    return ApiService.instance;
  }

  private formatHttpError(err: Object, url: string): string {
    const raw: string = err instanceof Error ? err.message : JSON.stringify(err);
    if (raw.includes('2300006')) {
      return `域名/主机解析失败 (2300006): 无法访问 ${url}。请确认 API 地址拼写正确且设备网络正常。`;
    }
    if (raw.includes('2300007')) {
      return `连接服务器失败 (2300007): 请检查设备网络连接或服务器地址。`;
    }
    if (raw.includes('2300028')) {
      return `请求超时 (2300028): 服务器响应缓慢或网络不稳定。`;
    }
    return raw;
  }

  private async executeHttpOnce(
    url: string,
    method: http.RequestMethod,
    headers: Record<string, string>,
    body: string | undefined,
    useDirectDns: boolean
  ): Promise<http.HttpResponse> {
    const req: http.HttpRequest = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: method,
        header: headers,
        connectTimeout: 15000,
        readTimeout: 20000,
        usingCache: false,
        usingProtocol: http.HttpProtocol.HTTP1_1,
        expectDataType: http.HttpDataType.STRING
      };
      if (useDirectDns) {
        options.usingProxy = false;
        options.dnsServers = ['223.5.5.5', '119.29.29.29'];
      } else {
        options.usingProxy = true;
      }
      if (body !== undefined && body.length > 0) {
        options.extraData = body;
      }
      return await req.request(url, options);
    } finally {
      req.destroy();
    }
  }

  private async requestWithRetry(
    url: string,
    method: http.RequestMethod,
    headers: Record<string, string>,
    body?: string
  ): Promise<http.HttpResponse> {
    try {
      return await this.executeHttpOnce(url, method, headers, body, true);
    } catch (firstErr) {
      const firstMsg: string = firstErr instanceof Error ? firstErr.message : JSON.stringify(firstErr);
      hilog.warn(DOMAIN, TAG, 'Primary HTTP attempt failed (%{public}s): %{public}s, retrying with system proxy/DNS', url, firstMsg);
      if (firstMsg.includes('2300006') || firstMsg.includes('2300007') || firstMsg.includes('2300028')) {
        return await this.executeHttpOnce(url, method, headers, body, false);
      }
      throw new Error(firstMsg);
    }
  }

  private async requestJson(
    url: string,
    method: http.RequestMethod,
    headers: Record<string, string>,
    body?: string
  ): Promise<ApiResult<JsonMap>> {
    try {
      const res: http.HttpResponse = await this.requestWithRetry(url, method, headers, body);
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
      const friendly: string = this.formatHttpError(err as Object, url);
      hilog.error(DOMAIN, TAG, 'HTTP error %{public}s: %{public}s', url, friendly);
      return { ok: false, message: friendly };
    }
  }

  private async requestText(
    url: string,
    headers: Record<string, string>
  ): Promise<ApiResult<string>> {
    try {
      const res: http.HttpResponse = await this.requestWithRetry(url, http.RequestMethod.GET, headers);
      const text: string = typeof res.result === 'string' ? res.result : String(res.result ?? '');
      if (res.responseCode >= 200 && res.responseCode < 300) {
        return { ok: true, message: 'OK', data: text };
      }
      return { ok: false, message: `HTTP ${res.responseCode}` };
    } catch (err) {
      return { ok: false, message: this.formatHttpError(err as Object, url) };
    }
  }

  private async whmcsCall(
    settings: AppSettings,
    action: string,
    extraHeaders: Record<string, string>,
    formParams?: Record<string, string>
  ): Promise<ApiResult<JsonMap>> {
    const apiUrl: string = settings.whmcsApiUrl.trim();
    if (apiUrl.length === 0) {
      return { ok: false, message: '未配置 TizLink API 地址' };
    }
    const headers: Record<string, string> = {
      'User-Agent': 'AegisClient-WHMCS/1.0',
      'Accept': 'application/json',
      'X-User-Act': action
    };
    const hKeys: string[] = Object.keys(extraHeaders);
    for (const k of hKeys) {
      if (extraHeaders[k].length > 0) {
        headers[k] = extraHeaders[k];
      }
    }

    let formBody: string | undefined = undefined;
    if (formParams) {
      const pKeys: string[] = Object.keys(formParams);
      if (pKeys.length > 0) {
        headers['Content-Type'] = 'application/x-www-form-urlencoded';
        const pairs: string[] = [];
        for (const k of pKeys) {
          pairs.push(`${encodeURIComponent(k)}=${encodeURIComponent(formParams[k])}`);
        }
        formBody = pairs.join('&');
      }
    }

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

  private parseTimestamp(raw: Object | undefined): number {
    if (raw === undefined || raw === null) {
      return 0;
    }
    if (typeof raw === 'number') {
      return raw;
    }
    const str: string = String(raw).trim();
    if (str.length === 0) {
      return 0;
    }
    const num: number = Number(str);
    if (!Number.isNaN(num) && num > 0) {
      return num;
    }
    const ms: number = Date.parse(str.replace(' ', 'T'));
    return Number.isNaN(ms) ? 0 : Math.floor(ms / 1000);
  }

  private parsePositivePrice(raw: Object | undefined): number {
    if (raw === undefined || raw === null) {
      return 0;
    }
    const n: number = Number(raw);
    if (Number.isNaN(n) || n < 0) {
      return 0;
    }
    return n;
  }

  private parseWhmcsLoginData(root: JsonMap, fallbackEmail: string): WhmcsSyncBundle {
    const info: SubscriptionInfo = createEmptySubscription();
    info.email = String(root['email'] ?? fallbackEmail);
    info.balance = Number(root['balance'] ?? 0) || 0;

    const invite: InviteSummary = {
      codes: [],
      registeredCount: 0,
      commissionRate: 0,
      commissionBalance: 0,
      pendingCommission: 0
    };
    const aff = root['affiliate'] as JsonMap | undefined;
    if (aff) {
      const affId: string = String(aff['id'] ?? '');
      if (affId.length > 0) {
        invite.codes.push({ code: `AFF-${affId}`, status: 0, createdAt: this.parseTimestamp(aff['date']) });
      }
      invite.registeredCount = Number(aff['visitors'] ?? 0) || 0;
      invite.commissionBalance = Number(aff['balance'] ?? 0) || 0;
    }
    this.cachedWhmcsInvite = invite;

    const nodes: ProxyNode[] = [];
    const pkgsRaw = root['package'];
    if (Array.isArray(pkgsRaw) && pkgsRaw.length > 0) {
      const pkg = pkgsRaw[0] as JsonMap;
      info.planName = String(pkg['package_name'] ?? pkg['plan_name'] ?? 'TizLink 套餐');
      info.uuid = String(pkg['uuid'] ?? '');
      info.transferEnable = Number(pkg['transfer_enable'] ?? 0) || 0;
      info.usedUpload = Number(pkg['upload'] ?? 0) || 0;
      info.usedDownload = Number(pkg['download'] ?? 0) || 0;
      info.expiredAt = this.parseTimestamp(pkg['next_due_date'] ?? pkg['expired_at']);
      info.resetDay = Number(pkg['days_to_traffic_reset'] ?? pkg['reset_day'] ?? 0) || 0;
      info.subscribeUrl = String(pkg['subscribe_url'] ?? pkg['subscription_url'] ?? '');

      const rawNodes = pkg['node'];
      if (Array.isArray(rawNodes)) {
        const usedNames: Set<string> = new Set<string>();
        for (let i: number = 0; i < rawNodes.length; i++) {
          const parsed: ProxyNode | null = this.convertWhmcsNodeToProxy(
            rawNodes[i] as JsonMap,
            info.uuid,
            i,
            usedNames
          );
          if (parsed) {
            nodes.push(parsed);
          }
        }
      }
    }

    return {
      subscription: info,
      nodes: nodes,
      inviteSummary: invite
    };
  }

  private convertWhmcsNodeToProxy(
    n: JsonMap,
    pkgUuid: string,
    index: number,
    usedNames: Set<string>
  ): ProxyNode | null {
    const rawName: string = String(n['name'] ?? '').trim();
    const server: string = String(n['address'] ?? n['server'] ?? '').trim();
    const port: number = Number(n['client_port'] ?? n['port'] ?? 443) || 443;
    const lastOnline: number = Number(n['last_online'] ?? 1) || 0;

    if (server.length === 0 || (lastOnline === 0 && (rawName.includes('官网') || rawName.includes('通知')))) {
      return null;
    }

    let uniqueName: string = rawName.length > 0 ? rawName : `Node-${index + 1}`;
    if (usedNames.has(uniqueName)) {
      let suffix: number = 2;
      while (usedNames.has(`${uniqueName} #${suffix}`)) {
        suffix++;
      }
      uniqueName = `${uniqueName} #${suffix}`;
    }
    usedNames.add(uniqueName);

    const type: string = String(n['type'] ?? 'trojan').toLowerCase();
    const uuidOrPwd: string = String(n['uuid'] ?? n['password'] ?? pkgUuid);
    const sni: string = String(n['snidomain'] ?? n['sni'] ?? '');
    const network: string = String(n['network'] ?? 'tcp').toLowerCase();
    const tlsMode: string = String(n['tls'] ?? '').toLowerCase();
    const netJson = n['network_settings_json'] as JsonMap | undefined;
    const allowInsecure: boolean =
      n['allow_insecure'] === true ||
      n['allow_insecure'] === 1 ||
      String(netJson?.['allowInsecure'] ?? '').toLowerCase() === 'true';

    const countryFromApi: string = String(n['country'] ?? '').toUpperCase();
    const detected = SubscriptionParser.detectCountry(uniqueName);
    const countryCode: string = countryFromApi.length >= 2 ? countryFromApi : detected.code;
    const regionLabel: string = detected.label;

    const yaml: string[] = [
      `  - name: ${SubscriptionParser.yamlQuote(uniqueName)}`,
      `    type: ${type === 'shadowsocks' ? 'ss' : type}`,
      `    server: ${SubscriptionParser.yamlQuote(server)}`,
      `    port: ${port}`
    ];

    if (type === 'trojan') {
      yaml.push(`    password: ${SubscriptionParser.yamlQuote(uuidOrPwd)}`);
      if (sni.length > 0) {
        yaml.push(`    sni: ${SubscriptionParser.yamlQuote(sni)}`);
      }
      yaml.push(`    skip-cert-verify: ${allowInsecure}`);
      yaml.push(`    udp: true`);
      if (network === 'ws') {
        yaml.push(`    network: ws`);
        yaml.push(`    ws-opts:`);
        yaml.push(`      path: ${SubscriptionParser.yamlQuote(String(netJson?.['path'] ?? '/'))}`);
      } else if (network === 'grpc') {
        yaml.push(`    network: grpc`);
        yaml.push(`    grpc-opts:`);
        yaml.push(`      grpc-service-name: ${SubscriptionParser.yamlQuote(String(netJson?.['serviceName'] ?? ''))}`);
      }
    } else if (type === 'vless') {
      yaml.push(`    uuid: ${SubscriptionParser.yamlQuote(uuidOrPwd)}`);
      yaml.push(`    udp: true`);
      yaml.push(`    tls: ${tlsMode === 'tls' || tlsMode === 'reality'}`);
      yaml.push(`    network: ${SubscriptionParser.yamlQuote(network)}`);
      if (sni.length > 0) {
        yaml.push(`    servername: ${SubscriptionParser.yamlQuote(sni)}`);
      }
      if (allowInsecure) {
        yaml.push(`    skip-cert-verify: true`);
      }
    } else if (type === 'vmess') {
      yaml.push(`    uuid: ${SubscriptionParser.yamlQuote(uuidOrPwd)}`);
      yaml.push(`    alterId: 0`);
      yaml.push(`    cipher: auto`);
      yaml.push(`    udp: true`);
      yaml.push(`    tls: ${tlsMode === 'tls'}`);
      yaml.push(`    network: ${SubscriptionParser.yamlQuote(network)}`);
      if (sni.length > 0 && tlsMode === 'tls') {
        yaml.push(`    servername: ${SubscriptionParser.yamlQuote(sni)}`);
      }
      if (allowInsecure) {
        yaml.push(`    skip-cert-verify: true`);
      }
    } else if (type === 'aegis') {
      yaml.push(`    password: ${SubscriptionParser.yamlQuote(uuidOrPwd)}`);
      yaml.push(`    server-pubkey-b64: ${SubscriptionParser.yamlQuote(String(n['server_pubkey_b64'] ?? n['pubkey_b64'] ?? ''))}`);
      yaml.push(`    sni: ${SubscriptionParser.yamlQuote(sni || server)}`);
      yaml.push(`    host: ${SubscriptionParser.yamlQuote(String(n['host'] ?? (sni || server)))}`);
      yaml.push(`    path: ${SubscriptionParser.yamlQuote(String(n['path'] ?? '/chat'))}`);
      yaml.push(`    client-fingerprint: chrome`);
      yaml.push(`    skip-cert-verify: ${allowInsecure}`);
      yaml.push(`    udp: true`);
    } else if (type === 'hysteria2' || type === 'hy2') {
      yaml[1] = `    type: hysteria2`;
      yaml.push(`    password: ${SubscriptionParser.yamlQuote(uuidOrPwd)}`);
      if (sni.length > 0) {
        yaml.push(`    sni: ${SubscriptionParser.yamlQuote(sni)}`);
      }
      yaml.push(`    skip-cert-verify: ${allowInsecure}`);
    } else if (type === 'ss' || type === 'shadowsocks') {
      yaml.push(`    cipher: ${SubscriptionParser.yamlQuote(String(n['cipher'] ?? n['method'] ?? 'aes-256-gcm'))}`);
      yaml.push(`    password: ${SubscriptionParser.yamlQuote(uuidOrPwd)}`);
      yaml.push(`    udp: true`);
    } else {
      yaml.push(`    password: ${SubscriptionParser.yamlQuote(uuidOrPwd)}`);
      yaml.push(`    udp: true`);
    }

    const nodeId: string = String(n['id'] ?? `whmcs_${index}_${server}_${port}`);
    return {
      id: nodeId,
      name: uniqueName,
      type: type,
      server: server,
      port: port,
      countryCode: countryCode,
      regionLabel: regionLabel,
      latencyMs: -1,
      rawYamlLines: yaml,
      rawUri: ''
    };
  }

  // ==================== AUTH ====================

  async login(
    settings: AppSettings,
    email: string,
    password: string,
    deviceId: string
  ): Promise<ApiResult<LoginPayload>> {
    const res = await this.whmcsCall(settings, 'login', {
      'X-User-Email': email,
      'X-User-Password': password
    }, {
      'device_id': deviceId
    });
    if (!res.ok || !res.data) {
      return { ok: false, message: res.message };
    }
    const token: string = String(res.data['token'] ?? `whmcs:${email}`);
    const bundle: WhmcsSyncBundle = this.parseWhmcsLoginData(res.data, email);
    return {
      ok: true,
      message: `登录成功，已获取 ${bundle.nodes.length} 个节点`,
      data: {
        token: token,
        authData: token,
        email: bundle.subscription.email || email,
        subscribeUrl: bundle.subscription.subscribeUrl,
        subscription: bundle.subscription,
        nodes: bundle.nodes,
        inviteSummary: bundle.inviteSummary
      }
    };
  }

  async syncWhmcsSession(
    settings: AppSettings,
    auth: AuthSession
  ): Promise<ApiResult<WhmcsSyncBundle>> {
    const res = await this.whmcsCall(settings, 'login', {
      'X-User-Email': auth.email,
      'X-User-Password': auth.savedPassword,
      'X-User-Token': auth.token
    }, {
      'device_id': auth.deviceId
    });
    if (!res.ok || !res.data) {
      return { ok: false, message: res.message };
    }
    const bundle: WhmcsSyncBundle = this.parseWhmcsLoginData(res.data, auth.email);
    return {
      ok: true,
      message: `已同步 ${bundle.nodes.length} 个节点`,
      data: bundle
    };
  }

  async register(
    settings: AppSettings,
    email: string,
    password: string,
    inviteCode: string
  ): Promise<ApiResult<LoginPayload>> {
    const prefix: string = email.split('@')[0] || 'User';
    const form: Record<string, string> = {};
    if (inviteCode.length > 0) {
      form['invite_code'] = inviteCode;
    }
    const res = await this.whmcsCall(settings, 'signup', {
      'X-User-Email': email,
      'X-User-Password': password,
      'X-User-Firstname': prefix,
      'X-User-Lastname': 'TizLink'
    }, form);
    if (!res.ok || !res.data) {
      return { ok: false, message: res.message };
    }
    const token: string = String(res.data['token'] ?? `whmcs:${email}`);
    const bundle: WhmcsSyncBundle = this.parseWhmcsLoginData(res.data, email);
    return {
      ok: true,
      message: '注册成功',
      data: {
        token: token,
        authData: token,
        email: email,
        subscribeUrl: bundle.subscription.subscribeUrl,
        subscription: bundle.subscription,
        nodes: bundle.nodes,
        inviteSummary: bundle.inviteSummary
      }
    };
  }

  async resetPassword(
    settings: AppSettings,
    email: string
  ): Promise<ApiResult<boolean>> {
    const res = await this.whmcsCall(settings, 'resetpassword', {
      'X-User-Email': email
    });
    const msg: string = res.ok
      ? String(res.data?.['message'] ?? '重置密码邮件已发送至您的邮箱')
      : res.message;
    return { ok: res.ok, message: msg, data: res.ok };
  }

  async changePassword(
    settings: AppSettings,
    auth: AuthSession,
    oldPassword: string,
    newPassword: string
  ): Promise<ApiResult<boolean>> {
    const res = await this.whmcsCall(settings, 'changepassword', {
      'X-User-Email': auth.email,
      'X-User-Password': oldPassword,
      'X-User-Token': auth.token
    }, {
      'new_password': newPassword,
      'newpassword': newPassword
    });
    return { ok: res.ok, message: res.ok ? '密码修改成功' : res.message, data: res.ok };
  }

  // ==================== SUBSCRIPTION DOWNLOAD ====================

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
    const res = await this.whmcsCall(settings, 'getproducts', {
      'X-User-Email': auth.email,
      'X-User-Password': auth.savedPassword,
      'X-User-Token': auth.token
    });
    if (!res.ok || !res.data) {
      return { ok: false, message: res.message };
    }
    const d = res.data['products'] ?? res.data['data'];
    const rawList: Object[] = Array.isArray(d) ? (d as Object[]) : [];

    const plans: PlanItem[] = [];
    for (const item of rawList) {
      const m = item as JsonMap;
      const pricingObj = m['pricing'] as JsonMap | undefined;
      const cnyObj = pricingObj ? (pricingObj['CNY'] as JsonMap | undefined) : undefined;
      const rawDesc: string = String(m['content'] ?? m['description'] ?? '');
      const cleanDesc: string = rawDesc.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
      const nameStr: string = String(m['name'] ?? '套餐');

      let gb: number = Number(m['transfer_enable'] ?? m['traffic_gb'] ?? 0) || 0;
      if (gb === 0) {
        const gbMatch = `${nameStr} ${cleanDesc}`.match(/(\d+)\s*(?:GB|G)\b/i);
        if (gbMatch) {
          gb = Number(gbMatch[1]) || 0;
        }
      }

      plans.push({
        id: Number(m['pid'] ?? m['id'] ?? 0) || 0,
        name: nameStr,
        content: cleanDesc,
        transferEnableGb: gb,
        monthPrice: this.parsePositivePrice(cnyObj ? cnyObj['monthly'] : (m['month_price'] ?? m['monthly'])),
        quarterPrice: this.parsePositivePrice(cnyObj ? cnyObj['quarterly'] : (m['quarter_price'] ?? m['quarterly'])),
        halfYearPrice: this.parsePositivePrice(cnyObj ? cnyObj['semiannually'] : (m['half_year_price'] ?? m['semiannually'])),
        yearPrice: this.parsePositivePrice(cnyObj ? cnyObj['annually'] : (m['year_price'] ?? m['annually'])),
        onetimePrice: this.parsePositivePrice(m['onetime_price']),
        resetPrice: this.parsePositivePrice(m['reset_price'])
      });
    }
    return { ok: true, message: 'OK', data: plans };
  }

  async fetchPaymentMethods(settings: AppSettings, auth: AuthSession): Promise<ApiResult<PaymentMethod[]>> {
    const res = await this.whmcsCall(settings, 'getpaymentmethods', {
      'X-User-Email': auth.email,
      'X-User-Password': auth.savedPassword,
      'X-User-Token': auth.token
    });
    if (!res.ok || !res.data) {
      return { ok: false, message: res.message };
    }
    const d = res.data['payment_methods'] ?? res.data['data'] ?? res.data['methods'];
    const rawList: Object[] = Array.isArray(d) ? (d as Object[]) : [];

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

  private mapPeriodToWhmcsCycle(period: string): string {
    if (period === 'quarter_price') {
      return 'quarterly';
    }
    if (period === 'half_year_price') {
      return 'semiannually';
    }
    if (period === 'year_price') {
      return 'annually';
    }
    return 'monthly';
  }

  async createOrder(
    settings: AppSettings,
    auth: AuthSession,
    planId: number,
    period: string,
    couponCode: string,
    paymentMethodId: string = ''
  ): Promise<ApiResult<string>> {
    const params: Record<string, string> = {
      'pid': String(planId),
      'billingcycle': this.mapPeriodToWhmcsCycle(period)
    };
    if (paymentMethodId.length > 0) {
      params['paymentmethod'] = paymentMethodId;
    }
    if (couponCode.trim().length > 0) {
      params['promocode'] = couponCode.trim();
    }
    const res = await this.whmcsCall(settings, 'createorder', {
      'X-User-Email': auth.email,
      'X-User-Password': auth.savedPassword,
      'X-User-Token': auth.token
    }, params);
    if (!res.ok || !res.data) {
      return { ok: false, message: res.message };
    }
    const d = (res.data['data'] as JsonMap | undefined) ?? res.data;
    const tradeNo: string = String(d['invoice_id'] ?? d['invoiceid'] ?? d['trade_no'] ?? d['order_id'] ?? '');
    return tradeNo.length > 0
      ? { ok: true, message: '订单已创建', data: tradeNo }
      : { ok: false, message: '未返回订单号' };
  }

  async checkoutOrder(
    settings: AppSettings,
    auth: AuthSession,
    tradeNo: string,
    methodId: string
  ): Promise<ApiResult<CheckoutResult>> {
    const res = await this.whmcsCall(settings, 'checkorder', {
      'X-User-Email': auth.email,
      'X-User-Password': auth.savedPassword,
      'X-User-Token': auth.token
    }, {
      'invoice_id': tradeNo,
      'paymentmethod': methodId
    });
    if (!res.ok || !res.data) {
      return { ok: false, message: res.message };
    }
    const d = (res.data['data'] as JsonMap | undefined) ?? res.data;
    const payUrl: string = String(d['invoice_url'] ?? d['payment_url'] ?? d['pay_url'] ?? d['url'] ?? '');
    const paid: boolean = d['paid'] === true || String(d['status']) === 'Paid';
    return { ok: true, message: 'OK', data: { type: paid ? -1 : 1, paymentUrl: payUrl, paid: paid } };
  }

  async fetchOrders(settings: AppSettings, auth: AuthSession): Promise<ApiResult<OrderItem[]>> {
    const res = await this.whmcsCall(settings, 'getorders', {
      'X-User-Email': auth.email,
      'X-User-Password': auth.savedPassword,
      'X-User-Token': auth.token
    });
    if (!res.ok || !res.data) {
      return { ok: false, message: res.message };
    }
    const d = res.data['orders'] ?? res.data['data'];
    const rawList: Object[] = Array.isArray(d) ? (d as Object[]) : [];

    const orders: OrderItem[] = [];
    for (const item of rawList) {
      const m = item as JsonMap;
      const productsArr = m['products'];
      let whmcsPlanName: string = '';
      let whmcsPeriod: string = '';
      if (Array.isArray(productsArr) && productsArr.length > 0) {
        const firstProd = productsArr[0] as JsonMap;
        whmcsPlanName = String(firstProd['name'] ?? '');
        whmcsPeriod = String(firstProd['billing_cycle'] ?? '');
      }
      const rawStatus = m['invoice_status'] ?? m['status'];
      let statusNum: number = Number(rawStatus ?? 0) || 0;
      if (typeof rawStatus === 'string') {
        const sLower: string = rawStatus.toLowerCase();
        if (sLower === 'paid' || sLower === 'active' || sLower === 'completed') {
          statusNum = 3;
        } else if (sLower === 'cancelled' || sLower === 'canceled') {
          statusNum = 2;
        } else {
          statusNum = 0;
        }
      }
      orders.push({
        tradeNo: String(m['order_num'] ?? m['trade_no'] ?? m['invoice_id'] ?? m['order_id'] ?? m['id'] ?? ''),
        planName: whmcsPlanName || String(m['plan_name'] ?? '订阅订单'),
        period: whmcsPeriod || String(m['period'] ?? m['billingcycle'] ?? 'monthly'),
        totalAmount: Number(m['total_amount'] ?? m['amount'] ?? m['total'] ?? 0) || 0,
        status: statusNum,
        createdAt: this.parseTimestamp(m['created_at'] ?? m['date']),
        paymentUrl: String(m['invoice_url'] ?? m['payment_url'] ?? '')
      });
    }
    return { ok: true, message: 'OK', data: orders };
  }

  async cancelOrder(_settings: AppSettings, _auth: AuthSession, _tradeNo: string): Promise<ApiResult<boolean>> {
    return { ok: false, message: '请在官网个人中心管理待支付账单' };
  }

  // ==================== INVITE & NOTICES ====================

  async fetchInviteSummary(_settings: AppSettings, _auth: AuthSession): Promise<ApiResult<InviteSummary>> {
    if (this.cachedWhmcsInvite) {
      return { ok: true, message: 'OK', data: this.cachedWhmcsInvite };
    }
    return {
      ok: true,
      message: 'OK',
      data: {
        codes: [],
        registeredCount: 0,
        commissionRate: 0,
        commissionBalance: 0,
        pendingCommission: 0
      }
    };
  }

  async generateInviteCode(_settings: AppSettings, _auth: AuthSession): Promise<ApiResult<boolean>> {
    return { ok: false, message: 'TizLink 推广邀请码由账户自动分配' };
  }

  async fetchNotices(settings: AppSettings, auth: AuthSession): Promise<ApiResult<NoticeItem[]>> {
    const res = await this.whmcsCall(settings, 'getannouncements', {
      'X-User-Email': auth.email,
      'X-User-Password': auth.savedPassword,
      'X-User-Token': auth.token
    });
    if (!res.ok || !res.data) {
      return { ok: false, message: res.message };
    }
    const d = res.data['announcements'] ?? res.data['data'];
    const rawList: Object[] = Array.isArray(d) ? (d as Object[]) : [];

    const notices: NoticeItem[] = [];
    for (const item of rawList) {
      const m = item as JsonMap;
      notices.push({
        id: Number(m['id'] ?? 0) || 0,
        title: String(m['title'] ?? '系统公告'),
        content: String(m['content'] ?? m['announcement'] ?? ''),
        createdAt: this.parseTimestamp(m['created_at'] ?? m['date'])
      });
    }
    return { ok: true, message: 'OK', data: notices };
  }

  // ==================== LINE DIAGNOSTICS & REGION DETECT ====================

  async testApiLineLatency(apiUrl: string): Promise<number> {
    const cleanUrl: string = apiUrl.trim();
    if (cleanUrl.length === 0) {
      return -2;
    }
    const start: number = Date.now();
    try {
      const res: http.HttpResponse = await this.requestWithRetry(
        cleanUrl,
        http.RequestMethod.POST,
        {
          'User-Agent': 'AegisClient-WHMCS/1.0',
          'Accept': 'application/json',
          'X-User-Act': 'getpaymentmethods'
        }
      );
      if (res.responseCode >= 200 && res.responseCode < 300) {
        return Math.max(1, Date.now() - start);
      }
      return -2;
    } catch (_e) {
      return -2;
    }
  }

  async detectUserRegion(): Promise<'cn' | 'global'> {
    try {
      const res: ApiResult<string> = await this.requestText(
        'http://ip-api.com/json?fields=countryCode',
        { 'User-Agent': 'AegisClient-WHMCS/1.0' }
      );
      if (res.ok && res.data) {
        const parsed = JSON.parse(res.data) as JsonMap;
        const cc: string = String(parsed['countryCode'] ?? '').toUpperCase();
        if (cc.length === 2) {
          return cc === 'CN' ? 'cn' : 'global';
        }
      }
    } catch (_e) {
      // Fallback to timezone offset
    }
    const tzOffsetHours: number = -new Date().getTimezoneOffset() / 60;
    return tzOffsetHours === 8 ? 'cn' : 'global';
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
