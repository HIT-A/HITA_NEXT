import { webview } from '@kit.ArkWeb';
import { hostOf, parseCookiesHeader } from './EasWebLoginProbe';

/** API 23 exposes all cookies, but does not expose their partition keys. */
export class LegacyCookieReader {
  private static pending: Promise<webview.WebHttpCookie[]> | undefined = undefined;

  static async read(url: string, topLevelUrl: string): Promise<string> {
    // Only supplement the active first-party host; never turn a probe into a
    // cross-site cookie read. Other probe URLs still use ordinary fetchCookie.
    if (hostOf(url).length === 0 || hostOf(url) !== hostOf(topLevelUrl)) {
      return '';
    }
    return LegacyCookieReader.select(await LegacyCookieReader.snapshot(), url);
  }

  private static snapshot(): Promise<webview.WebHttpCookie[]> {
    if (LegacyCookieReader.pending !== undefined) {
      return LegacyCookieReader.pending;
    }
    const request: Promise<webview.WebHttpCookie[]> = new Promise((resolve) => {
      const timer: number = setTimeout(() => resolve([]), 3000);
      try {
        webview.WebCookieManager.fetchAllCookies(false).then((cookies: webview.WebHttpCookie[]) => {
          clearTimeout(timer);
          resolve(cookies);
        }).catch(() => {
          clearTimeout(timer);
          resolve([]);
        });
      } catch (_) {
        clearTimeout(timer);
        resolve([]);
      }
    });
    LegacyCookieReader.pending = request;
    void request.then(() => {
      if (LegacyCookieReader.pending === request) {
        LegacyCookieReader.pending = undefined;
      }
    });
    return request;
  }

  static select(cookies: webview.WebHttpCookie[], url: string, now: number = Date.now()): string {
    const host: string = hostOf(url);
    // Cookie paths are case-sensitive, unlike the login URL predicates.
    const address: string = url.split('?')[0].split('#')[0];
    const authorityEnd: number = address.indexOf('/', address.indexOf('://') + 3);
    const path: string = authorityEnd < 0 ? '/' : address.slice(authorityEnd);
    if (host.length === 0 || (!url.startsWith('https://') && !url.startsWith('http://'))) {
      return '';
    }
    const values: Map<string, string> = new Map<string, string>();
    const ambiguous: Set<string> = new Set<string>();
    for (const cookie of cookies) {
      const domain: string = cookie.domain.toLowerCase();
      const domainMatch: boolean = domain.startsWith('.') ?
        (host === domain.slice(1) || host.endsWith(domain)) : host === domain;
      const cookiePath: string = cookie.path || '/';
      const pathMatch: boolean = path === cookiePath ||
        (path.startsWith(cookiePath) && (cookiePath.endsWith('/') || path.charAt(cookiePath.length) === '/'));
      if (!domainMatch || !pathMatch || (cookie.isSecure && !url.startsWith('https://'))) {
        continue;
      }
      if (!cookie.isSessionCookie) {
        const expires: number = Date.parse(cookie.expiresDate);
        if (!Number.isFinite(expires) || expires <= now) {
          continue;
        }
      }
      if (!LegacyCookieReader.validPair(cookie.name, cookie.value)) {
        continue;
      }
      // With no partition key available, conflicting values are not safe to
      // choose between. The URL-scoped native read remains authoritative.
      if (values.has(cookie.name) && values.get(cookie.name) !== cookie.value) {
        ambiguous.add(cookie.name);
      } else {
        values.set(cookie.name, cookie.value);
      }
    }
    const pairs: string[] = [];
    values.forEach((value: string, name: string) => {
      if (!ambiguous.has(name)) {
        pairs.push(name + '=' + value);
      }
    });
    return pairs.join('; ');
  }

  static merge(ordinary: string, extra: string): string {
    const existing: Map<string, string> = parseCookiesHeader(ordinary);
    const supplement: Map<string, string> = parseCookiesHeader(extra);
    const pairs: string[] = ordinary.length > 0 ? [ordinary] : [];
    supplement.forEach((value: string, name: string) => {
      if (!existing.has(name)) {
        pairs.push(name + '=' + value);
      }
    });
    return pairs.join('; ');
  }

  private static validPair(name: string, value: string): boolean {
    if (name.length === 0 || name.indexOf('=') >= 0 || name.indexOf(' ') >= 0) {
      return false;
    }
    const pair: string = name + value;
    for (let i: number = 0; i < pair.length; i++) {
      const code: number = pair.charCodeAt(i);
      if (code < 32 || code === 127 || pair.charAt(i) === ';') {
        return false;
      }
    }
    return true;
  }
}
