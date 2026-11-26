import { http, socket } from '@kit.NetworkKit';
import { ProxyNode, RoutingMode } from '../model/Models';

interface DelayResponse {
  delay?: number;
}

export class MihomoControllerService {
  private static instance: MihomoControllerService | null = null;

  static getInstance(): MihomoControllerService {
    if (!MihomoControllerService.instance) {
      MihomoControllerService.instance = new MihomoControllerService();
    }
    return MihomoControllerService.instance;
  }

  async hotSwitchNode(controllerPort: number, nodeName: string): Promise<boolean> {
    const req: http.HttpRequest = http.createHttp();
    try {
      const url: string = `http://127.0.0.1:${controllerPort}/proxies/PROXY`;
      const res: http.HttpResponse = await req.request(url, {
        method: http.RequestMethod.PUT,
        header: { 'Content-Type': 'application/json' },
        extraData: JSON.stringify({ name: nodeName }),
        connectTimeout: 3000,
        readTimeout: 3000
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
        connectTimeout: 3000,
        readTimeout: 3000
      });
      return res.responseCode >= 200 && res.responseCode < 300;
    } catch (_e) {
      return false;
    } finally {
      req.destroy();
    }
  }

  async testNodeDelayViaController(controllerPort: number, nodeName: string, timeoutMs: number = 5000): Promise<number> {
    const req: http.HttpRequest = http.createHttp();
    try {
      const encodedName: string = encodeURIComponent(nodeName);
      const testUrl: string = encodeURIComponent('http://www.gstatic.com/generate_204');
      const url: string = `http://127.0.0.1:${controllerPort}/proxies/${encodedName}/delay?timeout=${timeoutMs}&url=${testUrl}`;
      const res: http.HttpResponse = await req.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: timeoutMs + 1000,
        readTimeout: timeoutMs + 1000,
        expectDataType: http.HttpDataType.STRING
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

  async testTcpPing(host: string, port: number, timeoutMs: number = 3500): Promise<number> {
    const tcp: socket.TCPSocket = socket.constructTCPSocketInstance();
    const start: number = Date.now();
    try {
      await tcp.connect({
        address: { address: host, port: port, family: 1 },
        timeout: timeoutMs
      });
      const elapsed: number = Date.now() - start;
      await tcp.close();
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
      const delay: number = await this.testNodeDelayViaController(controllerPort, node.name);
      if (delay > 0) {
        return delay;
      }
    }
    return await this.testTcpPing(node.server, node.port);
  }
}
