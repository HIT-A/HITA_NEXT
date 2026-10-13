export interface EasSessionResponse {
  statusCode: number;
  body: string;
}

export enum EasSessionStatus {
  SAVED = '已登录',
  CHECKING = '验证中',
  CONNECTED = '已连接',
  EXPIRED = '已过期',
  UNKNOWN = '无法验证'
}

/** A saved cookie is not proof of a live session; require an authentication failure from the server. */
export function isExpiredEasResponse(response: EasSessionResponse): boolean {
  if (response.statusCode === 401) {
    return true;
  }
  if (response.statusCode === 0 || response.statusCode >= 500) {
    return false;
  }
  const expiredMessage: RegExp =
    /未登[录陆]|请(?:先|重新)登[录陆]|(?:登[录陆]|会话|身份认证)(?:状态)?(?:已)?(?:失效|过期|超时)|(?:session|token)\s+(?:has\s+)?(?:expired|invalid)|not\s+(?:logged|signed)\s+in/i;
  const body: string = response.body.trim();
  if (body.startsWith('{')) {
    try {
      const record: Record<string, Object> = JSON.parse(body) as Record<string, Object>;
      const code: string = String(record['code'] ?? record['status'] ?? record['statusCode'] ?? '');
      const message: string = String(record['msg'] ?? record['message'] ?? record['error'] ?? '');
      return code === '401' || /^(?:UNAUTHORIZED|LOGIN_EXPIRED|NOT_LOGIN)$/i.test(code) ||
        expiredMessage.test(message);
    } catch (_) {
      return false;
    }
  }
  const html: string = body.replace(/<!--[\s\S]*?-->/g, '');
  const markup: string = html.replace(/<script\b[^>]*>[\s\S]*?<\/script\s*>/gi, '');
  if (/<input\b[^>]*(?:type\s*=\s*["']?password\b|name\s*=\s*["']?(?:password|mm)\b)/i.test(markup) ||
    /<form\b[^>]*action\s*=\s*["'][^"']*(?:login|authentication\/require)/i.test(markup)) {
    return true;
  }
  // Match a redirect, not an ordinary navigation link back to the login page.
  if (/(?:window|top|parent)?\.?location(?:\.href)?\s*=\s*["'][^"']*(?:login|authentication\/require|reauth)/i.test(html) ||
    /location\.(?:replace|assign)\(\s*["'][^"']*(?:login|authentication\/require|reauth)/i.test(html) ||
    /<meta\b[^>]*content\s*=\s*["'][^"']*url\s*=[^"']*(?:login|authentication\/require|reauth)/i.test(markup)) {
    return true;
  }
  return expiredMessage.test(markup.replace(/<[^>]*>/g, ' '));
}
