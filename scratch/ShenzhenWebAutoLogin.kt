package cn.limpu.hita.ui.eas.login

import java.net.URI

/** Pure helpers for advancing the Shenzhen Web login without storing credentials. */
internal object ShenzhenWebAutoLogin {
    const val UNDERGRAD = "1"
    const val POSTGRAD = "2"

    fun normalizeStudentType(value: String?): String =
        if (value?.trim() == POSTGRAD) POSTGRAD else UNDERGRAD

    fun isProxyRoot(url: String, proxyBaseUrl: String): Boolean {
        val normalizedUrl = url.substringBefore('#').substringBefore('?').trimEnd('/')
        return normalizedUrl.equals(proxyBaseUrl.trimEnd('/'), ignoreCase = true)
    }

    fun reauthenticationUrl(
        currentUrl: String,
        directBaseUrl: String,
        proxyBaseUrl: String
    ): String? {
        val current = runCatching { URI(currentUrl) }.getOrNull() ?: return null
        val direct = runCatching { URI(directBaseUrl) }.getOrNull() ?: return null
        val proxy = runCatching { URI(proxyBaseUrl) }.getOrNull() ?: return null
        val path = current.path.orEmpty().lowercase()
        return when {
            current.host.equals(direct.host, ignoreCase = true) &&
                path.contains("/authentication/require") -> "${directBaseUrl.trimEnd('/')}/cas"
            current.host.equals(proxy.host, ignoreCase = true) &&
                path.contains("/session/invalid") -> "${proxyBaseUrl.trimEnd('/')}/cas"
            else -> null
        }
    }

    fun buildClickScript(
        studentType: String,
        allowUnifiedLogin: Boolean,
        allowRoleSelection: Boolean
    ): String {
        val normalizedType = normalizeStudentType(studentType)
        return """
            (function() {
              function normalized(value) {
                return String(value || '').replace(/\s+/g, '');
              }
              function visible(element) {
                if (!element || typeof element.click !== 'function') return false;
                var style = window.getComputedStyle ? window.getComputedStyle(element) : null;
                if (style && (style.display === 'none' || style.visibility === 'hidden')) return false;
                var rect = element.getBoundingClientRect ? element.getBoundingClientRect() : null;
                return !rect || (rect.width > 0 && rect.height > 0);
              }
              function labelOf(element) {
                return normalized(
                  element.innerText || element.textContent || element.value ||
                  element.getAttribute('aria-label') || element.getAttribute('title') || ''
                );
              }
              function candidates() {
                return Array.prototype.slice.call(document.querySelectorAll(
                  'button,a,[role="button"],input[type="button"],input[type="submit"],' +
                  '[onclick],[tabindex],div,span,p'
                )).filter(visible);
              }
              function shortestMatch(items, predicate) {
                return items.filter(function(element) {
                  return predicate(labelOf(element));
                }).sort(function(left, right) {
                  return labelOf(left).length - labelOf(right).length;
                })[0] || null;
              }
              function click(element, action) {
                if (!element) return null;
                element.click();
                return JSON.stringify({clicked:true, action:action, label:labelOf(element)});
              }

              var items = candidates();
              if (${allowUnifiedLogin}) {
                var unified = shortestMatch(items, function(label) {
                  return label === '统一身份认证登录' || label === '统一身份认证';
                });
                var unifiedResult = click(unified, 'unified-login');
                if (unifiedResult) return unifiedResult;
              }

              if (${allowRoleSelection}) {
                var pageText = normalized(document.body && document.body.innerText);
                // Only choose a role on a page that visibly offers both training levels.
                if (pageText.indexOf('本科') >= 0 && pageText.indexOf('研究生') >= 0) {
                  var preferred = '$normalizedType';
                  var role = shortestMatch(items, function(label) {
                    if (preferred === '2') {
                      return label.indexOf('研究生') >= 0 &&
                        (label.length <= 5 || label.indexOf('登录') >= 0 ||
                          label.indexOf('入口') >= 0 || label.indexOf('教务') >= 0);
                    }
                    return label.indexOf('本科') >= 0 &&
                      (label.length <= 5 || label.indexOf('登录') >= 0 ||
                        label.indexOf('入口') >= 0 || label.indexOf('教务') >= 0);
                  });
                  var roleResult = click(role, preferred === '2' ? 'postgrad-role' : 'undergrad-role');
                  if (roleResult) return roleResult;
                }
              }
              return JSON.stringify({clicked:false, action:'none'});
            })();
        """.trimIndent()
    }
}
