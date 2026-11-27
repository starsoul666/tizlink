import { connection, http, socket } from '@kit.NetworkKit';
import { ProxyNode, RoutingMode } from '../model/Models';

interface DelayResponse {
  delay?: number;
}

interface CachedIpEntry {
  ip: string;
  ts: number;
}

const DELAY_TEST_URL: string = 'http://www.gstatic.com/generate_204';

export class MihomoControllerService {
  private static instance: MihomoControllerService | null = null;
  private dnsCache: Map<string, CachedIpEntry> = new Map<string, CachedIpEntry>();

  static getInstance(): MihomoControllerService {
    if (!MihomoControllerService.instance) {
      MihomoControllerService.instance = new MihomoControllerService();
    }
    return MihomoControllerService.instance;
  }

  private isIpv4Literal(host: string): boolean {
    const parts: string[] = host.split('.');
    if (parts.length !== 4) {
      return false;
    }
    for (const p of parts) {
      if (p.length === 0 || p.length > 3) {
        return false;
      }
      const n: number = Number(p);
      if (Number.isNaN(n) || n < 0 || n > 255) {
        return false;
      }
    }
    return true;
  }

  async resolveHostIpv4(host: string): Promise<string> {
    const clean: string = host.trim();
    if (clean.length === 0 || this.isIpv4Literal(clean)) {
      return clean;
    }
    const cached: CachedIpEntry | undefined = this.dnsCache.get(clean);
    if (cached && (Date.now() - cached.ts) < 60000) {
      return cached.ip;
    }
    try {
      const addrs: connection.NetAddress[] = await connection.getAddressesByName(clean);
      for (const a of addrs) {
        if (a.address && this.isIpv4Literal(a.address)) {
          this.dnsCache.set(clean, { ip: a.address, ts: Date.now() });
          return a.address;
        }
      }
      if (addrs.length > 0 && addrs[0].address) {
        this.dnsCache.set(clean, { ip: addrs[0].address, ts: Date.now() });
        return addrs[0].address;
      }
    } catch (_e) {
      // fallback to raw host
    }
    return clean;
  }

  async hotSwitchNode(controllerPort: number, nodeName: string): Promise<boolean> {
    const req: http.HttpRequest = http.createHttp();
    try {
      const url: string = `http://127.0.0.1:${controllerPort}/proxies/PROXY`;
      const res: http.HttpResponse = await req.request(url, {
        method: http.RequestMethod.PUT,
        header: { 'Content-Type': 'application/json' },
        extraData: JSON.stringify({ name: nodeName }),
        connectTimeout: 2500,
        readTimeout: 2500,
        usingProxy: false
      });
      return res.responseCode >= 200 && res.responseCode < 300;
    } catch (_e) {
      return false;
    } finally {
      req.destroy();
    }
  }

  async switchMode(controllerPort: number, mode: RoutingMode): Promise<boolean> {
    const req: http.HttpRequest = http.createHttp();
    try {
      const url: string = `http://127.0.0.1:${controllerPort}/configs`;
      const res: http.HttpResponse = await req.request(url, {
        method: http.RequestMethod.PUT,
        header: { 'Content-Type': 'application/json' },
        extraData: JSON.stringify({ mode: mode }),
        connectTimeout: 2500,
        readTimeout: 2500,
        usingProxy: false
      });
      return res.responseCode >= 200 && res.responseCode < 300;
    } catch (_e) {
      return false;
    } finally {
      req.destroy();
    }
  }

  /**
   * Batch concurrent URLTest inside Mihomo Go core via GET /group/PROXY/delay.
   * Tests all nodes in parallel in ~1s instead of serial per-node HTTP calls.
   */
  async testGroupDelayViaController(
    controllerPort: number,
    groupName: string = 'PROXY',
    timeoutMs: number = 3000
  ): Promise<Record<string, number> | null> {
    const req: http.HttpRequest = http.createHttp();
    try {
      const encodedGroup: string = encodeURIComponent(groupName);
      const testUrl: string = encodeURIComponent(DELAY_TEST_URL);
      const url: string = `http://127.0.0.1:${controllerPort}/group/${encodedGroup}/delay?timeout=${timeoutMs}&url=${testUrl}`;
      const res: http.HttpResponse = await req.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 2000,
        readTimeout: timeoutMs + 2500,
        expectDataType: http.HttpDataType.STRING,
        usingProxy: false
      });
      if (res.responseCode >= 200 && res.responseCode < 300) {
        const parsed = JSON.parse(String(res.result ?? '{}')) as Record<string, number>;
        return parsed;
      }
      return null;
    } catch (_e) {
      return null;
    } finally {
      req.destroy();
    }
  }

  async testNodeDelayViaController(controllerPort: number, nodeName: string, timeoutMs: number = 3000): Promise<number> {
    const req: http.HttpRequest = http.createHttp();
    try {
      const encodedName: string = encodeURIComponent(nodeName);
      const testUrl: string = encodeURIComponent(DELAY_TEST_URL);
      const url: string = `http://127.0.0.1:${controllerPort}/proxies/${encodedName}/delay?timeout=${timeoutMs}&url=${testUrl}`;
      const res: http.HttpResponse = await req.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 2000,
        readTimeout: timeoutMs + 1500,
        expectDataType: http.HttpDataType.STRING,
        usingProxy: false
      });
      if (res.responseCode >= 200 && res.responseCode < 300) {
        const parsed = JSON.parse(String(res.result ?? '{}')) as DelayResponse;
        if (typeof parsed.delay === 'number' && parsed.delay > 0) {
          return Math.round(parsed.delay);
        }
      }
      return -2;
    } catch (_e) {
      return -2;
    } finally {
      req.destroy();
    }
  }

  async testTcpPing(host: string, port: number, timeoutMs: number = 2500): Promise<number> {
    const resolvedIp: string = await this.resolveHostIpv4(host);
    const tcp: socket.TCPSocket = socket.constructTCPSocketInstance();
    const start: number = Date.now();
    try {
      await tcp.connect({
        address: { address: resolvedIp, port: port, family: 1 },
        timeout: timeoutMs
      });
      const elapsed: number = Date.now() - start;
      try {
        await tcp.close();
      } catch (_ignore) {
        // ignore
      }
      return Math.max(1, elapsed);
    } catch (_e) {
      try {
        await tcp.close();
      } catch (_ignore) {
        // ignore close error
      }
      return -2;
    }
  }

  async testNodeLatency(
    node: ProxyNode,
    isVpnConnected: boolean,
    controllerPort: number
  ): Promise<number> {
    if (isVpnConnected) {
      return await this.testNodeDelayViaController(controllerPort, node.name, 3000);
    }
    return await this.testTcpPing(node.server, node.port, 2500);
  }
}
