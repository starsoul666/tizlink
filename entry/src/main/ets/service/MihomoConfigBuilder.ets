import { AppSettings, ProxyNode } from '../model/Models';
import { SubscriptionParser } from './SubscriptionParser';

export class MihomoConfigBuilder {
  static buildConfigYaml(
    nodes: ProxyNode[],
    selectedNodeId: string,
    settings: AppSettings
  ): string {
    const lines: string[] = [];

    lines.push(`mixed-port: ${settings.mixedPort}`);
    lines.push(`allow-lan: false`);
    lines.push(`bind-address: 127.0.0.1`);
    lines.push(`mode: ${settings.routingMode}`);
    lines.push(`log-level: ${settings.logLevel}`);
    lines.push(`ipv6: ${settings.enableIpv6}`);
    lines.push(`external-controller: 127.0.0.1:${settings.controllerPort}`);
    lines.push(`secret: ""`);
    lines.push(`geodata-mode: true`);
    lines.push(`geo-auto-update: false`);
    lines.push(`profile:`);
    lines.push(`  store-selected: false`);
    lines.push(`  store-fake-ip: false`);
    lines.push('');

    // DNS configuration mirroring TizLink Android
    lines.push(`dns:`);
    lines.push(`  enable: true`);
    lines.push(`  listen: 127.0.0.1:1053`);
    lines.push(`  ipv6: ${settings.enableIpv6}`);
    lines.push(`  enhanced-mode: ${settings.enableFakeIp ? 'fake-ip' : 'redir-host'}`);
    lines.push(`  fake-ip-range: 198.19.0.1/16`);
    lines.push(`  fake-ip-filter:`);
    lines.push(`    - "*.lan"`);
    lines.push(`    - "*.local"`);
    lines.push(`    - "localhost.ptlogin2.qq.com"`);
    lines.push(`    - "+.stun.*.*"`);
    lines.push(`    - "+.stun.*.*.*"`);
    lines.push(`    - "time.*.com"`);
    lines.push(`    - "ntp.*.com"`);
    lines.push(`  default-nameserver:`);
    lines.push(`    - 223.5.5.5`);
    lines.push(`    - 119.29.29.29`);
    lines.push(`  nameserver:`);
    lines.push(`    - 223.5.5.5`);
    lines.push(`    - 119.29.29.29`);
    lines.push(`    - https://223.5.5.5/dns-query`);
    lines.push(`  fallback:`);
    lines.push(`    - 8.8.8.8`);
    lines.push(`    - 1.1.1.1`);
    lines.push(`    - https://dns.cloudflare.com/dns-query`);
    lines.push(`  fallback-filter:`);
    lines.push(`    geoip: true`);
    lines.push(`    geoip-code: CN`);
    lines.push(`  proxy-server-nameserver:`);
    lines.push(`    - 223.5.5.5`);
    lines.push(`    - 119.29.29.29`);
    lines.push('');

    // Proxies
    lines.push(`proxies:`);
    const orderedNodes: ProxyNode[] = MihomoConfigBuilder.orderSelectedFirst(nodes, selectedNodeId);
    for (const node of orderedNodes) {
      for (const rawLine of node.rawYamlLines) {
        lines.push(rawLine);
      }
    }

    // Optional Chained / Secondary Proxy (dialer-proxy: PROXY)
    const hasChain: boolean = settings.chainProxy.enabled && settings.chainProxy.server.trim().length > 0;
    if (hasChain) {
      lines.push(`  - name: "CHAIN-OUT"`);
      lines.push(`    type: ${settings.chainProxy.type}`);
      lines.push(`    server: ${SubscriptionParser.yamlQuote(settings.chainProxy.server.trim())}`);
      lines.push(`    port: ${settings.chainProxy.port}`);
      if (settings.chainProxy.username.trim().length > 0) {
        lines.push(`    username: ${SubscriptionParser.yamlQuote(settings.chainProxy.username.trim())}`);
      }
      if (settings.chainProxy.password.trim().length > 0) {
        lines.push(`    password: ${SubscriptionParser.yamlQuote(settings.chainProxy.password.trim())}`);
      }
      lines.push(`    dialer-proxy: "PROXY"`);
      lines.push(`    udp: true`);
    }
    lines.push('');

    // Proxy Groups
    const targetGroupName: string = hasChain ? 'OUTBOUND' : 'PROXY';
    lines.push(`proxy-groups:`);
    if (hasChain) {
      lines.push(`  - name: "OUTBOUND"`);
      lines.push(`    type: select`);
      lines.push(`    proxies:`);
      lines.push(`      - "CHAIN-OUT"`);
      lines.push(`      - "PROXY"`);
    }
    lines.push(`  - name: "PROXY"`);
    lines.push(`    type: select`);
    lines.push(`    proxies:`);
    if (orderedNodes.length === 0) {
      lines.push(`      - DIRECT`);
    } else {
      if (selectedNodeId.length === 0) {
        lines.push(`      - "AUTO"`);
      }
      for (const node of orderedNodes) {
        lines.push(`      - ${SubscriptionParser.yamlQuote(node.name)}`);
      }
      if (selectedNodeId.length > 0) {
        lines.push(`      - "AUTO"`);
      }
    }

    if (orderedNodes.length > 0) {
      lines.push(`  - name: "AUTO"`);
      lines.push(`    type: url-test`);
      lines.push(`    url: "http://www.gstatic.com/generate_204"`);
      lines.push(`    interval: 300`);
      lines.push(`    tolerance: 50`);
      lines.push(`    proxies:`);
      for (const node of orderedNodes) {
        lines.push(`      - ${SubscriptionParser.yamlQuote(node.name)}`);
      }
    }
    lines.push('');

    // Rules (exact match with TizLink Android rules)
    lines.push(`rules:`);
    if (settings.routingMode === 'global') {
      lines.push(`  - IP-CIDR,127.0.0.0/8,DIRECT,no-resolve`);
      lines.push(`  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve`);
      lines.push(`  - IP-CIDR,172.16.0.0/12,DIRECT,no-resolve`);
      lines.push(`  - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve`);
      lines.push(`  - MATCH,${targetGroupName}`);
    } else {
      lines.push(`  # DNS Direct`);
      lines.push(`  - DOMAIN,dns.alidns.com,DIRECT`);
      lines.push(`  - DOMAIN,doh.pub,DIRECT`);
      lines.push(`  - DOMAIN-SUFFIX,alidns.com,DIRECT`);
      lines.push(`  - IP-CIDR,223.5.5.5/32,DIRECT,no-resolve`);
      lines.push(`  - IP-CIDR,223.6.6.6/32,DIRECT,no-resolve`);
      lines.push(`  - IP-CIDR,119.29.29.29/32,DIRECT,no-resolve`);
      lines.push(`  # Exit IP check via proxy`);
      lines.push(`  - DOMAIN-SUFFIX,ifconfig.me,${targetGroupName}`);
      lines.push(`  - DOMAIN-SUFFIX,ipify.org,${targetGroupName}`);
      lines.push(`  - DOMAIN-SUFFIX,icanhazip.com,${targetGroupName}`);
      lines.push(`  - DOMAIN,checkip.amazonaws.com,${targetGroupName}`);
      lines.push(`  # Private / LAN Direct`);
      lines.push(`  - IP-CIDR,127.0.0.0/8,DIRECT,no-resolve`);
      lines.push(`  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve`);
      lines.push(`  - IP-CIDR,100.64.0.0/10,DIRECT,no-resolve`);
      lines.push(`  - IP-CIDR,172.16.0.0/12,DIRECT,no-resolve`);
      lines.push(`  - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve`);
      lines.push(`  # CN Direct`);
      lines.push(`  - GEOSITE,CN,DIRECT`);
      lines.push(`  - GEOIP,CN,DIRECT`);
      lines.push(`  # Everything else via Proxy`);
      lines.push(`  - MATCH,${targetGroupName}`);
    }

    return lines.join('\n') + '\n';
  }

  private static orderSelectedFirst(nodes: ProxyNode[], selectedNodeId: string): ProxyNode[] {
    if (selectedNodeId.length === 0) {
      return nodes.slice();
    }
    const selected: ProxyNode | undefined = nodes.find((n: ProxyNode) => n.id === selectedNodeId);
    if (!selected) {
      return nodes.slice();
    }
    const result: ProxyNode[] = [selected];
    for (const n of nodes) {
      if (n.id !== selectedNodeId) {
        result.push(n);
      }
    }
    return result;
  }
}
