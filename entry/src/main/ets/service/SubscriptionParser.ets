import { util } from '@kit.ArkTS';
import { ProxyNode } from '../model/Models';

interface CountryPattern {
  code: string;
  label: string;
  keywords: string[];
}

const COUNTRY_PATTERNS: CountryPattern[] = [
  { code: 'HK', label: '香港', keywords: ['香港', 'hk', 'hong kong', 'hongkong', '🇭🇰'] },
  { code: 'TW', label: '台湾', keywords: ['台湾', '台灣', 'tw', 'taiwan', '台北', '🇹🇼'] },
  { code: 'JP', label: '日本', keywords: ['日本', 'jp', 'japan', 'tokyo', 'osaka', '东京', '大阪', '🇯🇵'] },
  { code: 'SG', label: '新加坡', keywords: ['新加坡', '狮城', 'sg', 'singapore', '🇸🇬'] },
  { code: 'US', label: '美国', keywords: ['美国', '美國', 'us', 'usa', 'united states', 'los angeles', 'san jose', 'seattle', 'new york', '洛杉矶', '圣何塞', '西雅图', '🇺🇸'] },
  { code: 'KR', label: '韩国', keywords: ['韩国', '韓國', 'kr', 'korea', 'seoul', '首尔', '🇰🇷'] },
  { code: 'UK', label: '英国', keywords: ['英国', '英國', 'uk', 'gb', 'london', '伦敦', '🇬🇧'] },
  { code: 'DE', label: '德国', keywords: ['德国', '德國', 'de', 'germany', 'frankfurt', '法兰克福', '🇩🇪'] },
  { code: 'FR', label: '法国', keywords: ['法国', '法國', 'fr', 'france', 'paris', '🇫🇷'] },
  { code: 'NL', label: '荷兰', keywords: ['荷兰', '荷蘭', 'nl', 'netherlands', 'amsterdam', '🇳🇱'] },
  { code: 'AU', label: '澳大利亚', keywords: ['澳洲', '澳大利亚', 'au', 'australia', 'sydney', '🇦🇺'] },
  { code: 'CA', label: '加拿大', keywords: ['加拿大', 'ca', 'canada', 'toronto', '🇨🇦'] },
  { code: 'TR', label: '土耳其', keywords: ['土耳其', 'tr', 'turkey', '🇹🇷'] },
  { code: 'IN', label: '印度', keywords: ['印度', 'in', 'india', 'mumbai', '🇮🇳'] },
  { code: 'MY', label: '马来西亚', keywords: ['马来', '馬來', 'my', 'malaysia', '🇲🇾'] },
  { code: 'TH', label: '泰国', keywords: ['泰国', '泰國', 'th', 'thailand', '🇹🇭'] },
  { code: 'VN', label: '越南', keywords: ['越南', 'vn', 'vietnam', '🇻🇳'] },
  { code: 'RU', label: '俄罗斯', keywords: ['俄罗', '俄羅', 'ru', 'russia', '🇷🇺'] }
];

interface VmessJson {
  ps?: string;
  add?: string;
  port?: string | number;
  id?: string;
  aid?: string | number;
  scy?: string;
  net?: string;
  type?: string;
  host?: string;
  path?: string;
  tls?: string;
  sni?: string;
  alpn?: string;
  fp?: string;
}

export class SubscriptionParser {
  static parseSubscription(rawContent: string): ProxyNode[] {
    const trimmed: string = rawContent.trim();
    if (trimmed.length === 0) {
      return [];
    }

    // 1. Check if it's already Clash/Mihomo YAML (contains "proxies:")
    if (/^\s*proxies\s*:/m.test(trimmed)) {
      const yamlNodes: ProxyNode[] = SubscriptionParser.parseClashYamlProxies(trimmed);
      if (yamlNodes.length > 0) {
        return yamlNodes;
      }
    }

    // 2. Try Base64 decoding if no scheme found directly
    let contentToParse: string = trimmed;
    if (!SubscriptionParser.containsUriScheme(trimmed)) {
      const decoded: string = SubscriptionParser.decodeBase64(trimmed);
      if (decoded.length > 0) {
        if (/^\s*proxies\s*:/m.test(decoded)) {
          const yamlNodes: ProxyNode[] = SubscriptionParser.parseClashYamlProxies(decoded);
          if (yamlNodes.length > 0) {
            return yamlNodes;
          }
        }
        contentToParse = decoded;
      }
    }

    // 3. Line-by-line URI parsing
    const lines: string[] = contentToParse.split(/\r?\n/);
    const nodes: ProxyNode[] = [];
    const usedNames: Set<string> = new Set<string>();

    for (const rawLine of lines) {
      const line: string = rawLine.trim();
      if (line.length === 0 || line.startsWith('#')) {
        continue;
      }
      const parsed: ProxyNode | null = SubscriptionParser.parseUri(line, nodes.length);
      if (parsed) {
        parsed.name = SubscriptionParser.ensureUniqueName(parsed.name, usedNames);
        // Update name line in rawYamlLines
        if (parsed.rawYamlLines.length > 0) {
          parsed.rawYamlLines[0] = `  - name: ${SubscriptionParser.yamlQuote(parsed.name)}`;
        }
        nodes.push(parsed);
      }
    }
    return nodes;
  }

  private static containsUriScheme(text: string): boolean {
    return /(aegis|vless|vmess|trojan|ss|hysteria2|hy2|tuic|anytls|wireguard|wg|socks5):\/\//i.test(text);
  }

  private static decodeBase64(input: string): string {
    try {
      const cleaned: string = input.replace(/\s+/g, '').replace(/-/g, '+').replace(/_/g, '/');
      const padLen: number = (4 - (cleaned.length % 4)) % 4;
      const padded: string = cleaned + '='.repeat(padLen);
      const helper: util.Base64Helper = new util.Base64Helper();
      const bytes: Uint8Array = helper.decodeSync(padded);
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
      return decoder.decodeToString(bytes);
    } catch (_e) {
      return '';
    }
  }

  private static parseClashYamlProxies(yaml: string): ProxyNode[] {
    const lines: string[] = yaml.split(/\r?\n/);
    const nodes: ProxyNode[] = [];
    const usedNames: Set<string> = new Set<string>();

    let inProxies: boolean = false;
    let currentLines: string[] = [];

    const flushCurrent = (): void => {
      if (currentLines.length === 0) {
        return;
      }
      const node: ProxyNode | null = SubscriptionParser.buildNodeFromYamlLines(currentLines, nodes.length, usedNames);
      if (node) {
        nodes.push(node);
      }
      currentLines = [];
    };

    for (const line of lines) {
      if (/^proxies\s*:\s*$/.test(line)) {
        inProxies = true;
        continue;
      }
      if (inProxies && /^[a-zA-Z0-9_-]+\s*:/.test(line)) {
        flushCurrent();
        inProxies = false;
        break;
      }
      if (!inProxies) {
        continue;
      }

      const trimmed: string = line.trim();
      if (trimmed.length === 0 || trimmed.startsWith('#')) {
        continue;
      }

      if (/^\s*-\s+/.test(line) && (line.indexOf('- ') <= 4)) {
        flushCurrent();
        // Handle inline JSON-like Clash proxy entry: - {name: ..., type: ..., server: ..., port: ...}
        if (trimmed.startsWith('- {') && trimmed.endsWith('}')) {
          const inlineNode: ProxyNode | null = SubscriptionParser.parseInlineFlowYaml(trimmed.substring(2), nodes.length, usedNames);
          if (inlineNode) {
            nodes.push(inlineNode);
          }
          continue;
        }
        currentLines.push(line);
      } else if (currentLines.length > 0) {
        currentLines.push(line);
      }
    }
    flushCurrent();
    return nodes;
  }

  private static parseInlineFlowYaml(flowText: string, index: number, usedNames: Set<string>): ProxyNode | null {
    const nameMatch = flowText.match(/name\s*:\s*["']?([^,"'}]+)["']?/);
    const typeMatch = flowText.match(/type\s*:\s*["']?([^,"'}]+)["']?/);
    const serverMatch = flowText.match(/server\s*:\s*["']?([^,"'}]+)["']?/);
    const portMatch = flowText.match(/port\s*:\s*["']?(\d+)["']?/);
    if (!serverMatch || !portMatch) {
      return null;
    }
    const rawName: string = nameMatch ? nameMatch[1].trim() : `Node-${index + 1}`;
    const name: string = SubscriptionParser.ensureUniqueName(rawName, usedNames);
    const type: string = typeMatch ? typeMatch[1].trim().toLowerCase() : 'proxy';
    const server: string = serverMatch[1].trim();
    const port: number = Number(portMatch[1]);
    const region = SubscriptionParser.detectCountry(name);

    return {
      id: `yaml_${index}_${server}_${port}`,
      name: name,
      type: type,
      server: server,
      port: port,
      countryCode: region.code,
      regionLabel: region.label,
      latencyMs: -1,
      rawYamlLines: [`  - ${flowText}`],
      rawUri: ''
    };
  }

  private static buildNodeFromYamlLines(rawLines: string[], index: number, usedNames: Set<string>): ProxyNode | null {
    let name: string = `Node-${index + 1}`;
    let type: string = 'proxy';
    let server: string = '';
    let port: number = 443;

    // Normalize indentation to 2 spaces for list item
    const baseIndent: number = rawLines[0].search(/\S/);
    const normalized: string[] = [];

    for (let i: number = 0; i < rawLines.length; i++) {
      const line: string = rawLines[i];
      const stripped: string = baseIndent > 0 && line.length >= baseIndent ? line.substring(baseIndent) : line.trimStart();
      normalized.push(`  ${stripped}`);

      const clean: string = line.trim().replace(/^-\s*/, '');
      const colonIdx: number = clean.indexOf(':');
      if (colonIdx > 0) {
        const key: string = clean.substring(0, colonIdx).trim();
        const val: string = clean.substring(colonIdx + 1).trim().replace(/^["']|["']$/g, '');
        if (key === 'name' && val.length > 0) {
          name = val;
        } else if (key === 'type' && val.length > 0) {
          type = val.toLowerCase();
        } else if (key === 'server' && val.length > 0) {
          server = val;
        } else if (key === 'port' && val.length > 0) {
          const p: number = Number(val);
          if (!Number.isNaN(p)) {
            port = p;
          }
        }
      }
    }

    if (server.length === 0) {
      return null;
    }
    const uniqueName: string = SubscriptionParser.ensureUniqueName(name, usedNames);
    const region = SubscriptionParser.detectCountry(uniqueName);
    return {
      id: `yaml_${index}_${server}_${port}`,
      name: uniqueName,
      type: type,
      server: server,
      port: port,
      countryCode: region.code,
      regionLabel: region.label,
      latencyMs: -1,
      rawYamlLines: normalized,
      rawUri: ''
    };
  }

  static parseUri(uri: string, index: number): ProxyNode | null {
    const lower: string = uri.toLowerCase();
    if (lower.startsWith('aegis://')) {
      return SubscriptionParser.parseAegisUri(uri, index);
    }
    if (lower.startsWith('vless://')) {
      return SubscriptionParser.parseVlessUri(uri, index);
    }
    if (lower.startsWith('vmess://')) {
      return SubscriptionParser.parseVmessUri(uri, index);
    }
    if (lower.startsWith('trojan://')) {
      return SubscriptionParser.parseTrojanUri(uri, index);
    }
    if (lower.startsWith('ss://')) {
      return SubscriptionParser.parseShadowsocksUri(uri, index);
    }
    if (lower.startsWith('hysteria2://') || lower.startsWith('hy2://')) {
      return SubscriptionParser.parseHysteria2Uri(uri, index);
    }
    if (lower.startsWith('tuic://')) {
      return SubscriptionParser.parseTuicUri(uri, index);
    }
    if (lower.startsWith('anytls://')) {
      return SubscriptionParser.parseAnyTlsUri(uri, index);
    }
    if (lower.startsWith('socks5://') || lower.startsWith('socks://')) {
      return SubscriptionParser.parseSocks5Uri(uri, index);
    }
    return null;
  }

  private static splitUriParts(uri: string): UriParts | null {
    const schemeEnd: number = uri.indexOf('://');
    if (schemeEnd < 0) {
      return null;
    }
    let rest: string = uri.substring(schemeEnd + 3);
    let fragment: string = '';
    const hashIdx: number = rest.indexOf('#');
    if (hashIdx >= 0) {
      fragment = SubscriptionParser.safeDecodeUri(rest.substring(hashIdx + 1));
      rest = rest.substring(0, hashIdx);
    }

    const params: Map<string, string> = new Map<string, string>();
    const qIdx: number = rest.indexOf('?');
    if (qIdx >= 0) {
      const qStr: string = rest.substring(qIdx + 1);
      rest = rest.substring(0, qIdx);
      for (const pair of qStr.split('&')) {
        if (pair.length === 0) {
          continue;
        }
        const eqIdx: number = pair.indexOf('=');
        if (eqIdx > 0) {
          const k: string = SubscriptionParser.safeDecodeUri(pair.substring(0, eqIdx));
          const v: string = SubscriptionParser.safeDecodeUri(pair.substring(eqIdx + 1));
          params.set(k, v);
        }
      }
    }

    // Strip path if present after host:port
    let path: string = '';
    const slashIdx: number = rest.indexOf('/');
    if (slashIdx >= 0) {
      path = rest.substring(slashIdx);
      rest = rest.substring(0, slashIdx);
    }

    let userInfo: string = '';
    let hostPort: string = rest;
    const atIdx: number = rest.lastIndexOf('@');
    if (atIdx >= 0) {
      userInfo = SubscriptionParser.safeDecodeUri(rest.substring(0, atIdx));
      hostPort = rest.substring(atIdx + 1);
    }

    let host: string = '';
    let port: number = 443;
    if (hostPort.startsWith('[')) {
      const closeBracket: number = hostPort.indexOf(']');
      if (closeBracket > 0) {
        host = hostPort.substring(1, closeBracket);
        const portPart: string = hostPort.substring(closeBracket + 1);
        if (portPart.startsWith(':')) {
          port = Number(portPart.substring(1)) || 443;
        }
      }
    } else {
      const colonIdx: number = hostPort.lastIndexOf(':');
      if (colonIdx > 0) {
        host = hostPort.substring(0, colonIdx);
        port = Number(hostPort.substring(colonIdx + 1)) || 443;
      } else {
        host = hostPort;
      }
    }

    if (host.length === 0) {
      return null;
    }

    return {
      userInfo: userInfo,
      host: host,
      port: port,
      path: path,
      params: params,
      fragment: fragment
    };
  }

  private static parseAegisUri(uri: string, index: number): ProxyNode | null {
    const parts: UriParts | null = SubscriptionParser.splitUriParts(uri);
    if (!parts) {
      return null;
    }
    const name: string = parts.fragment || `Aegis-${index + 1}`;
    const region = SubscriptionParser.detectCountry(name);
    const pubkey: string = parts.params.get('pubkey') || parts.params.get('pubkey_b64') ||
      parts.params.get('server-pubkey-b64') || parts.params.get('public_key') || '';
    const sni: string = parts.params.get('sni') || parts.params.get('snidomain') || parts.host;
    const hostHeader: string = parts.params.get('host') || sni;
    const path: string = parts.params.get('path') || parts.path || '/chat';
    const fp: string = parts.params.get('fp') || parts.params.get('client-fingerprint') || 'chrome';
    const insecure: boolean = parts.params.get('insecure') === '1' || parts.params.get('allowInsecure') === '1' ||
      parts.params.get('skip-cert-verify') === 'true';
    const mux: boolean = parts.params.get('mux') === '1' || parts.params.get('mux') === 'true';

    const yaml: string[] = [
      `  - name: ${SubscriptionParser.yamlQuote(name)}`,
      `    type: aegis`,
      `    server: ${SubscriptionParser.yamlQuote(parts.host)}`,
      `    port: ${parts.port}`,
      `    password: ${SubscriptionParser.yamlQuote(parts.userInfo)}`,
      `    server-pubkey-b64: ${SubscriptionParser.yamlQuote(pubkey)}`,
      `    sni: ${SubscriptionParser.yamlQuote(sni)}`,
      `    host: ${SubscriptionParser.yamlQuote(hostHeader)}`,
      `    path: ${SubscriptionParser.yamlQuote(path)}`,
      `    client-fingerprint: ${SubscriptionParser.yamlQuote(fp)}`,
      `    skip-cert-verify: ${insecure}`,
      `    udp: true`
    ];
    if (mux) {
      yaml.push(`    mux: true`);
    }

    return {
      id: `aegis_${index}_${parts.host}_${parts.port}`,
      name: name,
      type: 'aegis',
      server: parts.host,
      port: parts.port,
      countryCode: region.code,
      regionLabel: region.label,
      latencyMs: -1,
      rawYamlLines: yaml,
      rawUri: uri
    };
  }

  private static parseVlessUri(uri: string, index: number): ProxyNode | null {
    const parts: UriParts | null = SubscriptionParser.splitUriParts(uri);
    if (!parts) {
      return null;
    }
    const name: string = parts.fragment || `VLESS-${index + 1}`;
    const region = SubscriptionParser.detectCountry(name);
    const security: string = (parts.params.get('security') || 'none').toLowerCase();
    const network: string = (parts.params.get('type') || 'tcp').toLowerCase();
    const sni: string = parts.params.get('sni') || parts.params.get('servername') || '';
    const fp: string = parts.params.get('fp') || 'chrome';
    const flow: string = parts.params.get('flow') || '';
    const pbk: string = parts.params.get('pbk') || '';
    const sid: string = parts.params.get('sid') || '';
    const wsPath: string = parts.params.get('path') || '/';
    const wsHost: string = parts.params.get('host') || sni;
    const grpcService: string = parts.params.get('serviceName') || '';
    const insecure: boolean = parts.params.get('allowInsecure') === '1' || parts.params.get('insecure') === '1';

    const yaml: string[] = [
      `  - name: ${SubscriptionParser.yamlQuote(name)}`,
      `    type: vless`,
      `    server: ${SubscriptionParser.yamlQuote(parts.host)}`,
      `    port: ${parts.port}`,
      `    uuid: ${SubscriptionParser.yamlQuote(parts.userInfo)}`,
      `    udp: true`,
      `    tls: ${security === 'tls' || security === 'reality'}`,
      `    network: ${SubscriptionParser.yamlQuote(network)}`
    ];
    if (flow.length > 0) {
      yaml.push(`    flow: ${SubscriptionParser.yamlQuote(flow)}`);
    }
    if (sni.length > 0) {
      yaml.push(`    servername: ${SubscriptionParser.yamlQuote(sni)}`);
    }
    if (fp.length > 0 && (security === 'tls' || security === 'reality')) {
      yaml.push(`    client-fingerprint: ${SubscriptionParser.yamlQuote(fp)}`);
    }
    if (insecure) {
      yaml.push(`    skip-cert-verify: true`);
    }
    if (security === 'reality' && pbk.length > 0) {
      yaml.push(`    reality-opts:`);
      yaml.push(`      public-key: ${SubscriptionParser.yamlQuote(pbk)}`);
      if (sid.length > 0) {
        yaml.push(`      short-id: ${SubscriptionParser.yamlQuote(sid)}`);
      }
    }
    if (network === 'ws') {
      yaml.push(`    ws-opts:`);
      yaml.push(`      path: ${SubscriptionParser.yamlQuote(wsPath)}`);
      if (wsHost.length > 0) {
        yaml.push(`      headers:`);
        yaml.push(`        Host: ${SubscriptionParser.yamlQuote(wsHost)}`);
      }
    } else if (network === 'grpc' && grpcService.length > 0) {
      yaml.push(`    grpc-opts:`);
      yaml.push(`      grpc-service-name: ${SubscriptionParser.yamlQuote(grpcService)}`);
    }

    return {
      id: `vless_${index}_${parts.host}_${parts.port}`,
      name: name,
      type: 'vless',
      server: parts.host,
      port: parts.port,
      countryCode: region.code,
      regionLabel: region.label,
      latencyMs: -1,
      rawYamlLines: yaml,
      rawUri: uri
    };
  }

  private static parseVmessUri(uri: string, index: number): ProxyNode | null {
    const rawB64: string = uri.substring('vmess://'.length).trim();
    const decoded: string = SubscriptionParser.decodeBase64(rawB64);
    if (decoded.length === 0) {
      return null;
    }
    try {
      const cfg = JSON.parse(decoded) as VmessJson;
      const server: string = cfg.add || '';
      const port: number = Number(cfg.port) || 443;
      const uuid: string = cfg.id || '';
      if (server.length === 0 || uuid.length === 0) {
        return null;
      }
      const name: string = cfg.ps || `VMess-${index + 1}`;
      const region = SubscriptionParser.detectCountry(name);
      const network: string = (cfg.net || 'tcp').toLowerCase();
      const tlsOn: boolean = cfg.tls === 'tls' || cfg.tls === '1';
      const sni: string = cfg.sni || cfg.host || '';
      const alterId: number = Number(cfg.aid) || 0;
      const cipher: string = cfg.scy || 'auto';

      const yaml: string[] = [
        `  - name: ${SubscriptionParser.yamlQuote(name)}`,
        `    type: vmess`,
        `    server: ${SubscriptionParser.yamlQuote(server)}`,
        `    port: ${port}`,
        `    uuid: ${SubscriptionParser.yamlQuote(uuid)}`,
        `    alterId: ${alterId}`,
        `    cipher: ${SubscriptionParser.yamlQuote(cipher)}`,
        `    udp: true`,
        `    tls: ${tlsOn}`,
        `    network: ${SubscriptionParser.yamlQuote(network)}`
      ];
      if (sni.length > 0 && tlsOn) {
        yaml.push(`    servername: ${SubscriptionParser.yamlQuote(sni)}`);
      }
      if (network === 'ws') {
        yaml.push(`    ws-opts:`);
        yaml.push(`      path: ${SubscriptionParser.yamlQuote(cfg.path || '/')}`);
        if (cfg.host && cfg.host.length > 0) {
          yaml.push(`      headers:`);
          yaml.push(`        Host: ${SubscriptionParser.yamlQuote(cfg.host)}`);
        }
      } else if (network === 'grpc' && cfg.path) {
        yaml.push(`    grpc-opts:`);
        yaml.push(`      grpc-service-name: ${SubscriptionParser.yamlQuote(cfg.path)}`);
      }

      return {
        id: `vmess_${index}_${server}_${port}`,
        name: name,
        type: 'vmess',
        server: server,
        port: port,
        countryCode: region.code,
        regionLabel: region.label,
        latencyMs: -1,
        rawYamlLines: yaml,
        rawUri: uri
      };
    } catch (_e) {
      return null;
    }
  }

  private static parseTrojanUri(uri: string, index: number): ProxyNode | null {
    const parts: UriParts | null = SubscriptionParser.splitUriParts(uri);
    if (!parts) {
      return null;
    }
    const name: string = parts.fragment || `Trojan-${index + 1}`;
    const region = SubscriptionParser.detectCountry(name);
    const sni: string = parts.params.get('sni') || parts.params.get('peer') || parts.host;
    const insecure: boolean = parts.params.get('allowInsecure') === '1' || parts.params.get('insecure') === '1';
    const network: string = (parts.params.get('type') || 'tcp').toLowerCase();

    const yaml: string[] = [
      `  - name: ${SubscriptionParser.yamlQuote(name)}`,
      `    type: trojan`,
      `    server: ${SubscriptionParser.yamlQuote(parts.host)}`,
      `    port: ${parts.port}`,
      `    password: ${SubscriptionParser.yamlQuote(parts.userInfo)}`,
      `    sni: ${SubscriptionParser.yamlQuote(sni)}`,
      `    skip-cert-verify: ${insecure}`,
      `    udp: true`
    ];
    if (network === 'ws') {
      yaml.push(`    network: ws`);
      yaml.push(`    ws-opts:`);
      yaml.push(`      path: ${SubscriptionParser.yamlQuote(parts.params.get('path') || '/')}`);
    }

    return {
      id: `trojan_${index}_${parts.host}_${parts.port}`,
      name: name,
      type: 'trojan',
      server: parts.host,
      port: parts.port,
      countryCode: region.code,
      regionLabel: region.label,
      latencyMs: -1,
      rawYamlLines: yaml,
      rawUri: uri
    };
  }

  private static parseShadowsocksUri(uri: string, index: number): ProxyNode | null {
    let rest: string = uri.substring('ss://'.length);
    let fragment: string = '';
    const hashIdx: number = rest.indexOf('#');
    if (hashIdx >= 0) {
      fragment = SubscriptionParser.safeDecodeUri(rest.substring(hashIdx + 1));
      rest = rest.substring(0, hashIdx);
    }

    let method: string = '';
    let password: string = '';
    let host: string = '';
    let port: number = 443;

    const atIdx: number = rest.lastIndexOf('@');
    if (atIdx >= 0) {
      let userPart: string = SubscriptionParser.safeDecodeUri(rest.substring(0, atIdx));
      if (!userPart.includes(':')) {
        userPart = SubscriptionParser.decodeBase64(userPart);
      }
      const colon: number = userPart.indexOf(':');
      if (colon < 0) {
        return null;
      }
      method = userPart.substring(0, colon);
      password = userPart.substring(colon + 1);
      const hp: string = rest.substring(atIdx + 1).split('?')[0].split('/')[0];
      const hpColon: number = hp.lastIndexOf(':');
      host = hpColon > 0 ? hp.substring(0, hpColon) : hp;
      port = hpColon > 0 ? (Number(hp.substring(hpColon + 1)) || 443) : 443;
    } else {
      const decoded: string = SubscriptionParser.decodeBase64(rest);
      const dAt: number = decoded.lastIndexOf('@');
      if (dAt < 0) {
        return null;
      }
      const left: string = decoded.substring(0, dAt);
      const right: string = decoded.substring(dAt + 1);
      const colon: number = left.indexOf(':');
      if (colon < 0) {
        return null;
      }
      method = left.substring(0, colon);
      password = left.substring(colon + 1);
      const rColon: number = right.lastIndexOf(':');
      host = rColon > 0 ? right.substring(0, rColon) : right;
      port = rColon > 0 ? (Number(right.substring(rColon + 1)) || 443) : 443;
    }

    if (host.length === 0 || method.length === 0) {
      return null;
    }
    const name: string = fragment || `SS-${index + 1}`;
    const region = SubscriptionParser.detectCountry(name);

    const yaml: string[] = [
      `  - name: ${SubscriptionParser.yamlQuote(name)}`,
      `    type: ss`,
      `    server: ${SubscriptionParser.yamlQuote(host)}`,
      `    port: ${port}`,
      `    cipher: ${SubscriptionParser.yamlQuote(method)}`,
      `    password: ${SubscriptionParser.yamlQuote(password)}`,
      `    udp: true`
    ];

    return {
      id: `ss_${index}_${host}_${port}`,
      name: name,
      type: 'ss',
      server: host,
      port: port,
      countryCode: region.code,
      regionLabel: region.label,
      latencyMs: -1,
      rawYamlLines: yaml,
      rawUri: uri
    };
  }

  private static parseHysteria2Uri(uri: string, index: number): ProxyNode | null {
    const parts: UriParts | null = SubscriptionParser.splitUriParts(uri);
    if (!parts) {
      return null;
    }
    const name: string = parts.fragment || `HY2-${index + 1}`;
    const region = SubscriptionParser.detectCountry(name);
    const sni: string = parts.params.get('sni') || parts.host;
    const insecure: boolean = parts.params.get('insecure') === '1' || parts.params.get('allowInsecure') === '1';
    const obfs: string = parts.params.get('obfs') || '';
    const obfsPassword: string = parts.params.get('obfs-password') || '';

    const yaml: string[] = [
      `  - name: ${SubscriptionParser.yamlQuote(name)}`,
      `    type: hysteria2`,
      `    server: ${SubscriptionParser.yamlQuote(parts.host)}`,
      `    port: ${parts.port}`,
      `    password: ${SubscriptionParser.yamlQuote(parts.userInfo)}`,
      `    sni: ${SubscriptionParser.yamlQuote(sni)}`,
      `    skip-cert-verify: ${insecure}`
    ];
    if (obfs.length > 0) {
      yaml.push(`    obfs: ${SubscriptionParser.yamlQuote(obfs)}`);
      if (obfsPassword.length > 0) {
        yaml.push(`    obfs-password: ${SubscriptionParser.yamlQuote(obfsPassword)}`);
      }
    }

    return {
      id: `hy2_${index}_${parts.host}_${parts.port}`,
      name: name,
      type: 'hysteria2',
      server: parts.host,
      port: parts.port,
      countryCode: region.code,
      regionLabel: region.label,
      latencyMs: -1,
      rawYamlLines: yaml,
      rawUri: uri
    };
  }

  private static parseTuicUri(uri: string, index: number): ProxyNode | null {
    const parts: UriParts | null = SubscriptionParser.splitUriParts(uri);
    if (!parts) {
      return null;
    }
    const name: string = parts.fragment || `TUIC-${index + 1}`;
    const region = SubscriptionParser.detectCountry(name);
    const colon: number = parts.userInfo.indexOf(':');
    const uuid: string = colon > 0 ? parts.userInfo.substring(0, colon) : parts.userInfo;
    const password: string = colon > 0 ? parts.userInfo.substring(colon + 1) : '';
    const sni: string = parts.params.get('sni') || parts.host;
    const cc: string = parts.params.get('congestion_control') || 'bbr';
    const udpMode: string = parts.params.get('udp_relay_mode') || 'native';

    const yaml: string[] = [
      `  - name: ${SubscriptionParser.yamlQuote(name)}`,
      `    type: tuic`,
      `    server: ${SubscriptionParser.yamlQuote(parts.host)}`,
      `    port: ${parts.port}`,
      `    uuid: ${SubscriptionParser.yamlQuote(uuid)}`,
      `    password: ${SubscriptionParser.yamlQuote(password)}`,
      `    sni: ${SubscriptionParser.yamlQuote(sni)}`,
      `    congestion-controller: ${SubscriptionParser.yamlQuote(cc)}`,
      `    udp-relay-mode: ${SubscriptionParser.yamlQuote(udpMode)}`
    ];

    return {
      id: `tuic_${index}_${parts.host}_${parts.port}`,
      name: name,
      type: 'tuic',
      server: parts.host,
      port: parts.port,
      countryCode: region.code,
      regionLabel: region.label,
      latencyMs: -1,
      rawYamlLines: yaml,
      rawUri: uri
    };
  }

  private static parseAnyTlsUri(uri: string, index: number): ProxyNode | null {
    const parts: UriParts | null = SubscriptionParser.splitUriParts(uri);
    if (!parts) {
      return null;
    }
    const name: string = parts.fragment || `AnyTLS-${index + 1}`;
    const region = SubscriptionParser.detectCountry(name);
    const sni: string = parts.params.get('sni') || parts.host;
    const insecure: boolean = parts.params.get('insecure') === '1';

    const yaml: string[] = [
      `  - name: ${SubscriptionParser.yamlQuote(name)}`,
      `    type: anytls`,
      `    server: ${SubscriptionParser.yamlQuote(parts.host)}`,
      `    port: ${parts.port}`,
      `    password: ${SubscriptionParser.yamlQuote(parts.userInfo)}`,
      `    sni: ${SubscriptionParser.yamlQuote(sni)}`,
      `    skip-cert-verify: ${insecure}`,
      `    udp: true`
    ];

    return {
      id: `anytls_${index}_${parts.host}_${parts.port}`,
      name: name,
      type: 'anytls',
      server: parts.host,
      port: parts.port,
      countryCode: region.code,
      regionLabel: region.label,
      latencyMs: -1,
      rawYamlLines: yaml,
      rawUri: uri
    };
  }

  private static parseSocks5Uri(uri: string, index: number): ProxyNode | null {
    const parts: UriParts | null = SubscriptionParser.splitUriParts(uri);
    if (!parts) {
      return null;
    }
    const name: string = parts.fragment || `SOCKS5-${index + 1}`;
    const region = SubscriptionParser.detectCountry(name);
    const yaml: string[] = [
      `  - name: ${SubscriptionParser.yamlQuote(name)}`,
      `    type: socks5`,
      `    server: ${SubscriptionParser.yamlQuote(parts.host)}`,
      `    port: ${parts.port}`,
      `    udp: true`
    ];
    if (parts.userInfo.includes(':')) {
      const idx: number = parts.userInfo.indexOf(':');
      yaml.push(`    username: ${SubscriptionParser.yamlQuote(parts.userInfo.substring(0, idx))}`);
      yaml.push(`    password: ${SubscriptionParser.yamlQuote(parts.userInfo.substring(idx + 1))}`);
    }

    return {
      id: `socks5_${index}_${parts.host}_${parts.port}`,
      name: name,
      type: 'socks5',
      server: parts.host,
      port: parts.port,
      countryCode: region.code,
      regionLabel: region.label,
      latencyMs: -1,
      rawYamlLines: yaml,
      rawUri: uri
    };
  }

  static detectCountry(name: string): CountryResult {
    const lower: string = name.toLowerCase();
    for (const p of COUNTRY_PATTERNS) {
      for (const kw of p.keywords) {
        if (lower.includes(kw)) {
          return { code: p.code, label: p.label };
        }
      }
    }
    return { code: 'GL', label: '全球' };
  }

  private static ensureUniqueName(name: string, used: Set<string>): string {
    let candidate: string = name.trim();
    if (candidate.length === 0) {
      candidate = 'Node';
    }
    if (!used.has(candidate)) {
      used.add(candidate);
      return candidate;
    }
    let suffix: number = 2;
    while (used.has(`${candidate} #${suffix}`)) {
      suffix++;
    }
    const unique: string = `${candidate} #${suffix}`;
    used.add(unique);
    return unique;
  }

  private static safeDecodeUri(str: string): string {
    try {
      return decodeURIComponent(str);
    } catch (_e) {
      return str;
    }
  }

  static yamlQuote(value: string): string {
    const escaped: string = value.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
    return `"${escaped}"`;
  }
}

interface UriParts {
  userInfo: string;
  host: string;
  port: number;
  path: string;
  params: Map<string, string>;
  fragment: string;
}

interface CountryResult {
  code: string;
  label: string;
}
