# HITA WebViewLoginActivity.java → ArkTS 移植素材：页面判定谓词与页面推进/修补行为笔记

- 源文件：`C:\heyiwei\HITA\.analysis\decomp\cn\limpu\hita\ui\eas\login\WebViewLoginActivity.java`（共 4844 行；本文行号均指该反编译文件行号）。
- 本文目标：把判定/推进逻辑还原为可直接改写成 ArkTS 纯函数/常量的形式；凡需注入 WebView 的 JS 字符串尽量原样保留（ArkTS 侧作常量注入 `runJavaScript`）。
- 校区枚举顺序依据 `isPortalHomePage`/`isSuccessPage` 的 `WhenMappings.$EnumSwitchMapping$0` 反推：`case 1 = BENBU`、`case 2 = WEIHAI`、`case 3 = SHENZHEN`（各 case 内校验的 host 印证）。

## 记号约定（Kotlin → 语义）

| 写法 | 语义 |
|---|---|
| `StringsKt.equals(a,b,true)` | 忽略大小写相等；`equals(a,b,false)` 精确相等 |
| `StringsKt.contains(a,needle,true)` | 忽略大小写子串包含 |
| `StringsKt.contains$default(a,needle,false,2,null)` | 大小写敏感子串包含（`mask 2` = ignoreCase=false 默认值，反编译统一写作 `false,2`） |
| `StringsKt.startsWith(a,needle,true)` | 忽略大小写前缀 |
| `StringsKt.isBlank` | 空或全空白 |
| `Intrinsics.areEqual` | `Objects.equals`（host 比较通常用此 = 精确且大小写敏感） |
| `Locale.ROOT` | `String.toLowerCase(ROOT)`/`toUpperCase(ROOT)`（土耳其语安全） |
| `Uri.parse(url).getHost()/getPath()` | null 会被置为 `""` 的地方均已注明 |
| `MfaOverlayState(false,…,4095,…)` | 掩码构造：`4095` 表示全部用默认值（=默认 overlay 状态）；`4094` 表示除 visible 位外默认 |

> `trimEnd(s, '/')` 只去尾部 `/`。`trimIndent` 去掉多行字符串公共缩进（所有注入 JS 都先拼后 `trimIndent`）。

---

## 0. 常量速查（多方法共用）

### 0.1 Intent extra 名与 UA 常量（L218-229）
```java
EXTRA_CAMPUS       = "campus"
EXTRA_SILENT_MODE  = "silent_mode"
EXTRA_STUDENT_TYPE = "student_type"
SHENZHEN_DESKTOP_USER_AGENT =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36"
```
字段：`shenzhenMobileUserAgent`（L256，运行时从 `WebSettings.getUserAgentString()` 快照，见 §10 setupWebView）；标志位 `shenzhenDesktopUserAgentApplied`、`shenzhenForceWebModeApplied`、`shenzhenReauthenticationStarted`、`autoOpeningJwts`、`finished`、代数 `mfaDetectionGeneration` / `cookiePollingGeneration` / `shenzhenAutoAdvanceGeneration`。

### 0.2 CampusUrls 常量（`WebViewLoginActivity$Companion$CampusUrls.java`，供 configFor / 判定引用）
```java
// BENBU 本部（ivpn 内网 http）
BENBU_BASE         = "http://i-hit-edu-cn.ivpn.hit.edu.cn:1080"
BENBU_LOGIN        = "http://i-hit-edu-cn.ivpn.hit.edu.cn:1080/portal/home/"
BENBU_JWTS         = "http://jwts-hit-edu-cn.ivpn.hit.edu.cn:1080/loginCAS"
BENBU_GRADUATE_LOGIN = BENBU_LOGIN                       // 研究生登录 URL 与本科相同
BENBU_GRADUATE_JWTS = "http://yjsgl-hit-edu-cn.ivpn.hit.edu.cn:1080/common/casLogin"
BENBU_PROBE_URLS  = [BENBU_JWTS, "http://i-hit-edu-cn.ivpn.hit.edu.cn:1080/", BENBU_LOGIN]
BENBU_GRADUATE_PROBE_URLS = [BENBU_GRADUATE_JWTS,
  "http://yjsgl-hit-edu-cn.ivpn.hit.edu.cn:1080/xs/index",
  "http://yjsgl-hit-edu-cn.ivpn.hit.edu.cn:1080/"]
// WEIHAI
WEIHAI_BASE       = "https://webvpn.hitwh.edu.cn"
WEIHAI_LOGIN      = "https://webvpn.hitwh.edu.cn/"
WEIHAI_JWTS       = "https://webvpn.hitwh.edu.cn/http/77726476706e69737468656265737421fae0558f693861446900c7a99c406d3667/loginCAS"
WEIHAI_PROBE_URLS = [WEIHAI_JWTS,
  ".../777264.../kjscx/queryJxlListBySjid",
  ".../777264.../cjcx/queryQmcj",
  WEIHAI_LOGIN]
// SHENZHEN
SHENZHEN_DIRECT_BASE = "https://jw.hitsz.edu.cn"          // 直连（jw.hitsz.edu.cn）
SHENZHEN_PROXY_BASE  = "https://jw-hitsz-edu-cn.hitsz.edu.cn" // aTrust 代理
SHENZHEN_LOGIN       = "https://jw-hitsz-edu-cn.hitsz.edu.cn/"
SHENZHEN_JWTS        = "https://jw-hitsz-edu-cn.hitsz.edu.cn/authentication/main"
SHENZHEN_PROBE_URLS  = WebLoginSuccessPolicy.shenzhenCookieProbeUrls(SHENZHEN_PROXY_BASE, SHENZHEN_DIRECT_BASE)
```
CampusWebConfig 结构（`WebViewLoginActivity$CampusWebConfig.java`）：`(campus, loginUrl, jwtsUrl, cookieProbeUrls, studentType)`；studentType 缺省默认 `"1"`。

### 0.3 `configFor(campus)`（L1277-1334）→ config 各校区 URL/studentType
- `case 3 SHENZHEN`：反编译为 `new CampusWebConfig(SHENZHEN, "https://jw-hitsz-edu-cn.hitsz.edu.cn/authentication/main", "https://jw-hitsz-edu-cn.hitsz.edu.cn/authentication/main", SHENZHEN_PROBE_URLS, null→默认"1", mask16)`。两个字符串字面量在反编译中完全相同（应为 `SHENZHEN_LOGIN` 与 `SHENZHEN_JWTS` 被 CFR 内联合并的产物）。**无法确定 L1293-1296 loginUrl 与 jwtsUrl 原始取值是否相同**；按 CampusUrls 常量，loginUrl 疑为 `https://jw-hitsz-edu-cn.hitsz.edu.cn/`、jwtsUrl 为 `.../authentication/main`。
- `case 2 WEIHAI`：`CampusWebConfig(WEIHAI, WEIHAI_LOGIN, WEIHAI_JWTS, WEIHAI_PROBE_URLS, "1")`。
- `case 1 BENBU`：studentType(归一化后) == `"2"` → 用 `BENBU_GRADUATE_*` 三件套且 studentType=`"2"`；否则 `BENBU_LOGIN/BENBU_JWTS/BENBU_PROBE_URLS`，studentType=`"1"`（benbuStudentType 原值）。

### 0.4 `ShenzhenWebAutoLogin`（同目录另一文件）辅助
- `UNDERGRAD="1"`、`POSTGRAD="2"`。
- `normalizeStudentType(s)`：`trim()` 后等于 `"2"` → `"2"`，否则 `"1"`（null 亦为 `"1"`）。
- `isProxyRoot(url, proxyBaseUrl)`：`url` 先 `substringBefore('#')` 再 `substringBefore('?')`，两边 `trimEnd('/')`，`equals(..., ignoreCase=true)`。
- `reauthenticationUrl(currentUrl, directBaseUrl, proxyBaseUrl)`：
  - 任一 URL `new URI(...)` 解析失败 → 返回 null。
  - `currentUrl.host == directBaseUrl.host` 且（小写）path 含 `"/authentication/require"` → 返回 `directBaseUrl.trimEnd('/') + "/cas"`。
  - `currentUrl.host == proxyBaseUrl.host` 且 path 含 `"/session/invalid"` → 返回 `proxyBaseUrl.trimEnd('/') + "/cas"`。
  - 否则 null。
- `buildClickScript(studentType, …)`：为深研院自动化点击生成 JS（含本科/研究生页面元素文本匹配），被 `scheduleShenzhenAutoAdvance$attempt`（L4076）使用，不在 §3 `autoOpenJwts` 内。

---

## 1. 页面判定谓词（可直接改写成纯函数）

入参均为 URL 字符串。除 isSuccessPage 外**均不读 Cookie**。

### 1.1 isAuthenticationPage(url) L2586-2595
```kotlin
fun isAuthenticationPage(url: String): Boolean {
    val path = Uri.parse(url).path ?: ""            // getPath null → ""
    return path.contains("/authserver/login", ignoreCase = true)
}
```
判定 = CAS 登录页。大小写不敏感包含；不查 cookie；不判校区。

### 1.2 isIvpnRedirectPage(url) L2676-2687
```kotlin
fun isIvpnRedirectPage(url): Boolean =
    config.campus == Campus.SHENZHEN 的同级枚举 BENBU &&
    Uri.parse(url).host == "ivpn.hit.edu.cn"         // Intrinsics.areEqual：精确、大小写敏感
```
校区必须是 BENBU，host 必须**等于** `ivpn.hit.edu.cn`。不查 cookie。

### 1.3 isJwtsPage(url) L2689-2759
```kotlin
fun isJwtsPage(url, campus, studentType): Boolean {
    if (campus == Campus.WEIHAI) return false        // 威海校区永远不算 jwts 页
    val host = Uri.parse(url).host ?: ""             // host==null 时“contains”整体为 false
    val hostOk = host.contains("jwts")               // 大小写敏感
                 || (studentType == "2" && host.contains("yjsgl"))   // 研究生走 yjsgl
    if (!hostOk) return false
    val low = url.toLowerCase(Locale.ROOT)
    return low.contains("logincas") || low.contains("login")   // 大小写敏感（已小写）
}
```
要点：威海一律 false；本部研究生只看 yjsgl host；最终还要求**整个 URL 小写**后含 `logincas` 或 `login`（`login` 为子串，`logincas` 也满足）。host 判断大小写敏感；URL 段先小写再敏感匹配。

### 1.4 isMfaPage(url) L2761-2769
```kotlin
val path = Uri.parse(url).path ?: ""
path.contains("/authserver/reAuthCheck/", ignoreCase = true)
```
CAS 二次认证（MFA）页。大小写不敏感；不查 cookie、不判校区。与检测 JS 里 `pathLooksLikeMfa` 正则对应。

### 1.5 isPortalHomePage(url) L2771-2837 —— 按校区分派（需 config.campus）
```kotlin
val trimmedPath = (Uri.parse(url).path ?: "").trimEnd('/')   // 只去尾部 '/'
when (campus) {
  BENBU   -> Uri.parse(url).host == "i-hit-edu-cn.ivpn.hit.edu.cn"   // 精确
             && (trimmedPath == "/portal/home" || trimmedPath == "/portal")
  WEIHAI  -> Uri.parse(url).host == "webvpn.hitwh.edu.cn"            // 精确
             && (trimmedPath.isBlank() || trimmedPath == "/portal/home")
  SHENZHEN-> ShenzhenWebAutoLogin.isProxyRoot(url, "https://jw-hitsz-edu-cn.hitsz.edu.cn")
             // = 去 #/query + trimEnd('/') + ignoreCase 相等
}
```
- BENBU：host 精确 `i-hit-edu-cn.ivpn.hit.edu.cn`，path 精确为 `/portal/home` 或 `/portal`。
- WEIHAI：host 精确 `webvpn.hitwh.edu.cn`，path 去掉尾 `/` 后为空（即根路径）或等于 `/portal/home`。
- SHENZHEN：代理根 = 与 `https://jw-hitsz-edu-cn.hitsz.edu.cn` 忽略大小写全等（忽略 #/query、忽略尾斜杠）。
- campus 非上述三值会 throw（`NoWhenBranchMatchedException`）。

### 1.6 isShenzhenProxyJwPage(url) L2839-2843
```kotlin
host(url) equalsIgnoreCase host("https://jw-hitsz-edu-cn.hitsz.edu.cn")
```
即 host 是否等于 `jw-hitsz-edu-cn.hitsz.edu.cn`（忽略大小写）。不查 cookie。

### 1.7 isSuccessPage(url) L2845-3013 —— 唯一查 cookie 的谓词
预处理：`path = (Uri.parse(url).path ?: "").toLowerCase(ROOT)`；`host = (Uri.parse(url).host ?: "").toLowerCase(ROOT)`；`Uri.parse(url)==null → false`。按校区分派：

```kotlin
when (campus) {
  SHENZHEN -> WebLoginSuccessPolicy.isShenzhenAuthenticatedPage(url, collectCookies())
  WEIHAI   -> WebLoginSuccessPolicy.isWeihaiAuthenticatedPage(url, collectCookies())
  BENBU    -> { /* 见下，全内联 */ }
}
```

**BENBU 分支（内联，L2911-3009）**：
```kotlin
if (studentType == "2") {                      // 研究生
    if (host.contains("yjsgl")) {              // 大小写敏感（host 已小写）
        if (path.contains("/xs/index")
            && hasRequiredCookies(collectCookies(), url)) return true
    }
    return false                               // 研究生非 yjsgl 一律 false
}
// 本科生 / 其它
val pathHasLogin = path.contains("login")
if (host.contains("jwts") && !pathHasLogin) {
    val c = collectCookies()
    if (c.containsKey("JSESSIONID") && c.containsKey("HIT")) return true
}
if (host.contains("jwts") || host.contains("hit.edu.cn")) {
    if (listOf("kbcx","cjcx","kjscx","xswh","query","index")
            .any { path.contains(it) }) return true   // 大小写敏感
}
return false
```
注：`"hit.edu.cn"` 是子串，yjsgl/jwts host 也含之；业务 token 路径（成绩/课表等）即使无 cookie 也判成功。

**SHENZHEN 分支 → `WebLoginSuccessPolicy.isShenzhenAuthenticatedPage(url, cookies)`（该文件 L46-158）**：
```text
host(小写) ∈ { "jw.hitsz.edu.cn", "jw-hitsz-edu-cn.hitsz.edu.cn" }  否则 false
path(小写) 含 "login" | "authserver" | "authentication/require" → false（登录/鉴权页不算成功）
否则 path 为空 / "/" / 含 "authentication/main" | "student_index" | "user/me" | "xszykb" | "xsxk"
      → 还需 EASToken.hasShenzhenWebSessionCookies(cookies) == true
```
（cookies 来自 `collectCookies()`：遍历 `config.cookieProbeUrls` 的 `CookieManager.getCookie(url)` 合并，再并入当前 webview URL 的 cookie，缺 JSESSIONID 时尝试从 URL 提取。深研院判定核心 = host 允许集 + 业务 path + 深研院会话 cookie。）

**WEIHAI 分支 → `WebLoginSuccessPolicy.isWeihaiAuthenticatedPage(url, cookies)`（该文件 L164-317；反编译注明 “Unable to fully structure code”，下述为结构化重建，L244-261 的 `lbl-1000` 标签有二义）**：
```text
path(小写) 含 "/http/" | "kbcx" | "cjcx" | "kjscx" | "query" | "index" → 业务侧命中（flag A）
path(小写) 含 "logincas" | "/login/" 或以 "/login" 结尾 → 登录型路径（flag B，命中则不算成功）
cookies 中任一 key 以 "wengine_vpn_ticket" 开头（或包含，忽略大小写）→ VPN ticket 存在（flag C）
成功 = A && !B && C && cookies["JSESSIONID"] 非空白
```
> 建议 ArkTS 移植时直接复刻 WebLoginSuccessPolicy 三个方法并保留“无法确定处按上述重建实现，另加日志”，或以实测 URL 校准。

### 1.8 isTrustPortalPage(url) L3015-3033
```kotlin
host(url) equalsIgnoreCase "trust.hitsz.edu.cn" &&
(Uri.parse(url).path ?: "").startsWith("/portal", ignoreCase = true)
```
aTrust 信任门户站内页面（host = trust.hitsz.edu.cn 且 path 前缀 `/portal`，均忽略大小写）。不查 cookie。

---

## 2. redirectExpiredShenzhenSession(webView, url) L3784-3807 —— 深研院会话过期跳 CAS

```kotlin
fun redirectExpiredShenzhenSession(webView, url): Boolean {
    if (config.campus != SHENZHEN) return false
    if (shenzhenReauthenticationStarted) return false       // 只做一次
    val target = ShenzhenWebAutoLogin.reauthenticationUrl(
        url,
        "https://jw.hitsz.edu.cn",          // directBaseUrl
        "https://jw-hitsz-edu-cn.hitsz.edu.cn")             // proxyBaseUrl
    if (target == null) return false                        // URL 非法或非“过期会话”形态
    shenzhenReauthenticationStarted = true
    webView.loadUrl(target)                                 // target = <base去掉尾/ > + "/cas"
    return true
}
```
- 触发条件（内部语义）：SHENZHEN 校区、尚未开启过重认证、当前 URL 满足 §0.4 的过期形态（proxy 上 `/authentication/require` 或 `/session/invalid`）。
- 跳往：`https://jw.hitsz.edu.cn/cas`（直连分支）或 `https://jw-hitsz-edu-cn.hitsz.edu.cn/cas`（代理分支）——由 `reauthenticationUrl` 决定。
- 实际调用点：不在本文件内（无直接调用），由 WebView 导航回调经 access 包装触发。**无法确定 Lxxxx（调用点在未包含的合成/Compose 代码中）**。

---

## 3. autoOpenJwts(webView) L978-1008 —— “进 JWTS 后自动打开 CAS 入口”

```kotlin
fun autoOpenJwts(webView) {
    if (autoOpeningJwts) return          // 幂等：一次会话只自动开一次
    autoOpeningJwts = true
    log("auto opening JWTS campus=" + config.campus)
    webView.loadUrl(config.jwtsUrl)      // 无任何注入 JS；无本科/研究生分支
}
```
- 关键结论：**该方法本身不做“二次跳 CAS 的脚本/JS”**；它只是 `loadUrl(config.jwtsUrl)`。本科/研究生差异不在方法内，而在 config 的 `jwtsUrl`（见 §0.3 configFor）：
  - BENBU 本科 → `http://jwts-hit-edu-cn.ivpn.hit.edu.cn:1080/loginCAS`
  - BENBU 研究生（studentType=="2"）→ `http://yjsgl-hit-edu-cn.ivpn.hit.edu.cn:1080/common/casLogin`
  - WEIHAI → `https://webvpn.hitwh.edu.cn/http/7772…/loginCAS`
  - SHENZHEN → `https://jw-hitsz-edu-cn.hitsz.edu.cn/authentication/main`
- 这些 jwtsUrl 本身是 CAS 登录入口（loginCAS / casLogin / authentication/main），“自动跳 CAS 并凭已有 cookie 放行”由服务端跳转完成；真正“模拟点击/选择本科研究生”的脚本是 `ShenzhenWebAutoLogin.buildClickScript`（L33，深研院自动推进 `scheduleShenzhenAutoAdvance` 使用）。
- 幂等标志 `autoOpeningJwts` 一次 true 后永不复位（除非重建 Activity）。调用点在本文件外（access 包装 L524-525），**无法确定具体触发回调**。

---

## 4. applyShenzhenForceWebMode(webView, url) L766-798 —— aTrust 强制 Web 模式

```kotlin
fun applyShenzhenForceWebMode(webView, url): Boolean {
    if (config.campus != SHENZHEN) return false
    if (shenzhenForceWebModeApplied) return false            // 只做一次
    if (host(url) equalsIgnoreCase "trust.hitsz.edu.cn"
        && (path(url) ?: "") equalsIgnoreCase "/portal/shortcut.html") {
        shenzhenForceWebModeApplied = true
        webView.evaluateJavascript(<forceWeb JS>, callback)
        return true
    }
    return false
}
```
- 触发页面：SHENZHEN + host `trust.hitsz.edu.cn` + path **等于** `/portal/shortcut.html`（忽略大小写相等）。
- 注入 JS 作用（原文，括号内为注释）：把 `sessionStorage` 设为强制 Web 模式；新版 aTrust 页面按 SDP 地址给 session 数据加命名空间，而 shortcut.html 仍读旧的无前缀 key，因此同时维护 `__Prefix_map__`（`JSON.parse(sessionStorage.getItem('__Prefix_map__')||'[]')`，非数组则重置），为当前 `location.origin` 找/新建形如 `{pre:'[N]', addr:origin}` 的条目（新 pre 号为现有 `[数字]` 前缀最大值 +1，`unshift`），再写 `sessionStorage.setItem('[N]forceWeb','true')`，并写旧 key `forceWeb='true'`：
```js
(function() {
  try {
    sessionStorage.setItem('forceWeb', 'true');
    var mapKey = '__Prefix_map__';
    var prefixMap = JSON.parse(sessionStorage.getItem(mapKey) || '[]');
    if (!Array.isArray(prefixMap)) prefixMap = [];
    var origin = window.location.origin;
    var entry = prefixMap.find(function(item) { return item && item.addr === origin; });
    if (!entry) {
      var maxPrefix = prefixMap.reduce(function(max, item) {
        var match = item && String(item.pre || '').match(/^\[(\d+)\]$/);
        return match ? Math.max(max, Number(match[1])) : max;
      }, 0);
      entry = {pre: '[' + (maxPrefix + 1) + ']', addr: origin};
      prefixMap.unshift(entry);
    }
    sessionStorage.setItem(mapKey, JSON.stringify(prefixMap));
    sessionStorage.setItem(entry.pre + 'forceWeb', 'true');
    return true;
  } catch (e) {
    return false;
  }
})();
```
- 回调（L800-818）：`finished` 直接返回；JS 返回值 == `"true"` → log success「enabled aTrust force-web mode; reloading shortcut」，否则 warn「could not confirm … retrying shortcut once」；**两种情况都** `webView.loadUrl(原 url)`（重载 shortcut.html）。

---

## 5. 三个 Viewport 修补 workaround

共同模式：`evaluateJavascript(IIFE, cb)`；cb 解析返回 JSON（`parseJavascriptJson`），`ok:true` → log + `webView.invalidate()`，否则 warn（deferred: <error>），JSON 解析异常 → error log。均为**常驻监听**（首帧注入后安装 `resize`/`orientationchange`/`visualViewport.resize`，由 `window.__hitaXxxInstalled` 保证只装一次）。触发页面由调用方决定（本文件无调用点，属外部回调；函数名对应页面）：MFA(authserver reAuth) / 深研院 JW 桌面 / trust 门户。JS 每次执行先算 `innerHeight`，`<=0` 直接返回 `{ok:false,error:'ZERO_VIEWPORT_HEIGHT'}`。

### 5.1 applyMfaViewportUnitWorkaround L704-707（+ cb L714-764）
- 目标页面：CAS 二次认证（MFA）页（函数名 + 内部选择器），无内部页面校验。
- JS 一句话：按 `innerHeight` 注入 style，把 `html,body` 最小高度与 `.mobile-page-center-box`(高=H-44)、`.mobile-page-content-box`(maxH=H-44)、`.mobile-page-white-box`(minH=H-112) 钉成 px，规避 CSS `vh`/`dvh` 在 WebView 里随地址栏变化的单位问题。
- 返回：`{ok, innerHeight, centerHeight}`（无 center 时为 -1）。

### 5.2 applyShenzhenJwDesktopViewportWorkaround L820-823（+ cb L830-900）
- 目标页面：深研院教务（JW，`.towlg_*` 元素，即 `jw-hitsz-edu-cn.hitsz.edu.cn` 桌面版）——与 §6 桌面 UA 配套。
- JS 一句话：① `desktopWidth=1200`，按 `screen.availWidth||screen.width||visualViewport.width||innerWidth||1200` 算 `initialScale=clamp(0.2..1, deviceWidth/1200)`；把 `meta[name=viewport]` 的 content 设为 `width=1200, initial-scale=<4位小数>, minimum-scale=0.2, maximum-scale=3.0, user-scalable=yes`（没有则创建）；② 另把 `html,body,#app,.towlg_body,.towlg_submain` 高度/最小高度钉为 `innerHeight` px。额外 `requestAnimationFrame` + `setTimeout(…,100)` 各再跑一次高度修正；视觉区监听用 `applyHitaShenzhenJwHeight`。
- 返回：`{ok, innerWidth, innerHeight, mainX, mainY, mainWidth}` + `initialScale`（`.towlg_main` 不存在时各 -1）。

### 5.3 applyTrustPortalViewportUnitWorkaround L902-905（+ cb L912-976）
- 目标页面：trust 门户登录页（`.login*` 选择器）。
- JS 一句话：把 `html,body,#app`、`.h-screen,.login` 高度钉为 px；`.login` 全宽去最小宽、横滚隐藏；`.login-head/.login-body` 全宽；`.login-content` 左右 0 并居中；`.login-notice` 隐藏；`.login-panel` 自适应 `max-width:calc(100vw - 24px)`。
- 返回：`{ok, innerHeight, loginHeight}`。

---

## 6. 深研院 UA 切换

### 6.1 ensureShenzhenDesktopUserAgentForProxy(webView, url) L1424-1444（+ reload lambda L1446-1451）
```kotlin
fun ensureShenzhenDesktopUserAgentForProxy(webView, url): Boolean {
    if (config.campus != SHENZHEN) return false
    if (!isShenzhenProxyJwPage(url)) return false     // host == jw-hitsz-edu-cn.hitsz.edu.cn（忽略大小写）
    if (shenzhenDesktopUserAgentApplied) return false // 已应用过则不再切
    shenzhenDesktopUserAgentApplied = true
    webView.settings.userAgentString = SHENZHEN_DESKTOP_USER_AGENT
    webView.setLayerType(LAYER_TYPE_SOFTWARE /*1*/, null)
    webView.post { if (!finished) webView.reload() }  // 换 UA 后整页重载
    return true
}
```
标志位语义：`shenzhenDesktopUserAgentApplied` = 「当前/本会话已把 UA 切到桌面 UA」，用于幂等 & 与 §6.2 双向切换的状态依据。

### 6.2 switchShenzhenUserAgentForNavigation(webView, url) L4444-4503（+ 两个 reload lambda L4505-4517）
```kotlin
fun switchShenzhenUserAgentForNavigation(webView, url): Boolean {
    if (config.campus != SHENZHEN) return false
    val host = Uri.parse(url).host ?: ""
    val proxyHost = hostOf("https://jw-hitsz-edu-cn.hitsz.edu.cn") // = jw-hitsz-edu-cn.hitsz.edu.cn
    val isProxyOrTrust = host equalsIgnoreCase proxyHost
                        || host equalsIgnoreCase "trust.hitsz.edu.cn"
    if (!isProxyOrTrust && shenzhenDesktopUserAgentApplied) {
        shenzhenDesktopUserAgentApplied = false
        webView.settings.userAgentString = shenzhenMobileUserAgent   // 恢复移动 UA（setupWebView 快照）
        webView.setLayerType(LAYER_TYPE_NONE /*0*/, null)
        webView.stopLoading()
        webView.post { if (!finished) webView.loadUrl(url) }          // 重载当前 URL
        return true
    }
    if (isProxyOrTrust && !shenzhenDesktopUserAgentApplied) {
        shenzhenDesktopUserAgentApplied = true
        webView.settings.userAgentString = SHENZHEN_DESKTOP_USER_AGENT
        webView.setLayerType(LAYER_TYPE_SOFTWARE /*1*/, null)
        webView.stopLoading()
        webView.post { if (!finished) webView.loadUrl(url) }
        return true
    }
    return false
}
```
- 桌面 UA + **软件层**（`LAYER_TYPE_SOFTWARE=1`）用于：`jw-hitsz-edu-cn.hitsz.edu.cn`（深研院代理 JW）与 `trust.hitsz.edu.cn`。
- 其余 host（如直连 CAS/其他页面）：若此前是桌面态 → 切回**移动 UA** + 默认层（`LAYER_TYPE_NONE=0`）。host 判定均忽略大小写。
- 每次切换都先 `stopLoading()` 再 `post` 一次 `loadUrl(url)` 重载，且只有 `!finished` 才重载。
- 注意 setupWebView 对 SHENZHEN 的初始状态即桌面 UA + 软件层（见 §10），所以首个非代理/trust 页会触发回切移动 UA。

---

## 7. detectMfaAndBridge(webView, url, generation, retryCount) L1336-1422

### 7.1 结构
```kotlin
fun detectMfaAndBridge(webView, url, generation, retry) {
    js = <下面的长 IIFE，L1337 一整行字符串常量>
    delay = if (retry == 0) 800L else 700L          // 首次 800ms，重试 700ms
    webView.postDelayed({
        if (!finished && generation == mfaDetectionGeneration
            && webView.url == url)                  // URL 必须未变
            webView.evaluateJavascript(js, callback)
    }, delay)
}
// callback（L1360-1422）:
//   generation 不匹配 → return
//   解析 JSON: mfa==true →
//       setMfaState(默认态 MfaOverlayState(false,…,4095))   // “native overlay disabled; showing school page directly”
//       setMfaError(null)
//       log "MFA_RAW_DIAG native overlay disabled; showing school page directly method=<method> methodType=<methodType>"
//       scheduleRawMfaDiagnostics(webView, url, generation)  // 原生覆盖层方案放弃，改走原始 DOM 诊断
//   mfa!=true 且 isMfaPage(url) 且 retry<4 → detectMfaAndBridge(webView,url,generation,retry+1)（重新 700ms）
//   解析异常 → 记 "MFA detect parse error"
```
- 前置调度 `scheduleMfaDetection(webView,url)`（L3869-3895）：要求 host 含 `"ids"` 或 path 含 `"authserver"`（大小写敏感），否则直接返回；通过则 `generation = ++mfaDetectionGeneration` 并以 retry=0 调 detectMfaAndBridge。scheduleMfaDetection 在文件内仅被 poll 方法改变后（L3739）调用；首次进入由外部导航回调触发。
- MFA 判定先到先得：generation/URL 双校验防止过期回调污染新页面。

### 7.2 检测 JS（L1337 原文，逐字关键部分）
结构：`isVisible(el)` / `plainText(value)` 辅助函数 → 采集 DOM → 提前返回 `{mfa:false,ready}` → 命中则返回 `{mfa:true,…}`。**methodNames 映射与判定条件逐字如下**（Java 源码中以 `\uXXXX` 转义存储；下表中括号内为解码）：

```js
(function() {
  function isVisible(el) {
    if (!el || el.disabled) return false;
    var style = window.getComputedStyle(el);
    var rect = el.getBoundingClientRect();
    return style.display !== 'none' && style.visibility !== 'hidden' &&
      style.opacity !== '0' && rect.width > 0 && rect.height > 0;
  }
  function plainText(value) {
    var container = document.createElement('div');
    container.innerHTML = String(value || '');
    return String(container.textContent || container.innerText || '').trim();
  }
  var params = (typeof reAuthParams === 'object' && reAuthParams) ? reAuthParams : {};
  var methodBtn = document.getElementById('changeReAuthTypeButton');
  var submitButtons = Array.prototype.slice.call(document.querySelectorAll('#reAuthSubmitBtn, [id*=reAuthSubmit]'));
  var submitButton = submitButtons.find(isVisible) || null;
  var specificInput = document.querySelector('#dynamicCode, input[name=dynamicCode], input[name=otpCode]');
  var pathLooksLikeMfa = /\/authserver\/reAuthCheck\//i.test(location.pathname);
  if (!pathLooksLikeMfa && !submitButton && !specificInput) {
    return JSON.stringify({mfa:false, ready:document.readyState});
  }
  var inputCandidates = Array.prototype.slice.call(document.querySelectorAll(
    '#dynamicCode, input[name=dynamicCode], input[name=otpCode], #password, input:not([type=hidden])'
  ));
  var visibleInput = inputCandidates.find(isVisible) || null;
  if (!submitButton && !visibleInput) {
    return JSON.stringify({mfa:false, ready:document.readyState});
  }
  var reAuthType = String(params.reAuthType || '');
  var methodNames = {
    '2':'\u7edf\u4e00\u8eab\u4efd\u8ba4\u8bc1\u5bc6\u7801', '7':'\u7edf\u4e00\u8eab\u4efd\u8ba4\u8bc1\u5bc6\u7801',
    '3':'\u624b\u673a\u53f7\u9a8c\u8bc1\u7801', '4':'\u4f01\u4e1a\u5fae\u4fe1\u9a8c\u8bc1\u7801', '5':'HIT APP \u9a8c\u8bc1\u7801',
    '10':'\u5b89\u5168\u4ee4\u724cC', '11':'\u90ae\u7bb1\u9a8c\u8bc1\u7801', '12':'\u9489\u9489\u9a8c\u8bc1\u7801',
    '13':'\u54c8\u5de5\u5927 APP \u9a8c\u8bc1\u7801'
  };
  var descriptionKey = reAuthType ? ('reAuthDec' + reAuthType) : '';
  var visiblePromptEl = Array.prototype.slice.call(
    document.querySelectorAll('[id^=reAuthDec]')
  ).find(isVisible) || null;
  var promptEl = visiblePromptEl ||
    (descriptionKey && document.getElementById(descriptionKey)) ||
    document.getElementById('reAuthDec');
  var visibleTypeMatch = promptEl && promptEl.id ? promptEl.id.match(/^reAuthDec(\d+)$/) : null;
  var effectiveType = visibleTypeMatch ? visibleTypeMatch[1] : reAuthType;
  var method = methodNames[effectiveType] ||
    (methodBtn ? methodBtn.textContent.trim() : '') || '\u4e8c\u6b21\u9a8c\u8bc1';
  var effectiveDescriptionKey = effectiveType ? ('reAuthDec' + effectiveType) : descriptionKey;
  var prompt = plainText((promptEl && promptEl.textContent) ||
    (effectiveDescriptionKey && params[effectiveDescriptionKey]) || '');
  var sendIds = ['getDynamicCode', 'getImprovePhoneCodeId_otp', 'getImproveEmailCodeId_otp'];
  var sendButton = null;
  for (var i = 0; i < sendIds.length && !sendButton; i++) {
    var candidate = document.getElementById(sendIds[i]);
    if (isVisible(candidate)) sendButton = candidate;
  }
  if (!sendButton) {
    sendButton = Array.prototype.slice.call(document.querySelectorAll(
      '[onclick*=DynamicCode], [onclick*=dynamicCode], [id*=DynamicCode], [id*=dynamicCode]'
    )).find(function(el) { return isVisible(el) && el !== visibleInput; }) || null;
  }
  var result = {
    mfa: true,
    method: method,
    methodType: effectiveType,
    prompt: prompt,
    inputs: [],
    submitId: submitButton ? (submitButton.id || 'visible-submit') : '',
    canSendCode: !!sendButton,
    ready: document.readyState
  };
  if (visibleInput) {
    result.inputs.push({
      id: visibleInput.id || '',
      name: visibleInput.name || '',
      type: visibleInput.type || 'text',
      placeholder: visibleInput.placeholder || ''
    });
  }
  return JSON.stringify(result);
})();
```

**methodNames 数字 → 文案映射表（逐字；Java 内为 \uXXXX 转义）**：

| key | \uXXXX 原文 | 解码 |
|---|---|---|
| `'2'` | `\u7edf\u4e00\u8eab\u4efd\u8ba4\u8bc1\u5bc6\u7801` | 统一身份认证密码 |
| `'7'` | 同上 | 统一身份认证密码 |
| `'3'` | `\u624b\u673a\u53f7\u9a8c\u8bc1\u7801` | 手机号验证码 |
| `'4'` | `\u4f01\u4e1a\u5fae\u4fe1\u9a8c\u8bc1\u7801` | 企业微信验证码 |
| `'5'` | `HIT APP \u9a8c\u8bc1\u7801` | HIT APP 验证码 |
| `'10'` | `\u5b89\u5168\u4ee4\u724cC`（安 全 令 牌 C，字面含尾部 `C`） | 安全令牌C（按字面保留） |
| `'11'` | `\u90ae\u7bb1\u9a8c\u8bc1\u7801` | 邮箱验证码 |
| `'12'` | `\u9489\u9489\u9a8c\u8bc1\u7801` | 钉钉验证码 |
| `'13'` | `\u54c8\u5de5\u5927 APP \u9a8c\u8bc1\u7801` | 哈工大 APP 验证码 |

**判定条件（逐字语义）**：
1. MFA 页面特征三选一即进入后续检查：`pathLooksLikeMfa`（pathname 正则 `/\/authserver\/reAuthCheck\//i`）**或** 可见 `#reAuthSubmitBtn`/`[id*=reAuthSubmit]` **或** 存在 `#dynamicCode, input[name=dynamicCode], input[name=otpCode]` 任一元素；三者全无 → `{mfa:false, ready}`。
2. 可见输入框（对 `#dynamicCode…, #password, input:not([type=hidden])` 用 isVisible 过滤）；无可提交按钮且无可视输入 → `{mfa:false, ready}`。
3. `effectiveType` 优先取**可见**的 `[id^=reAuthDec]` 元素 id 中 `reAuthDec(\d+)` 的数字；否则取 `params.reAuthType`。
4. method 名查 `methodNames[effectiveType]`，查不到 → 按钮 `#changeReAuthTypeButton` 的 textContent.trim()，再查不到 → 兜底 `\u4e8c\u6b21\u9a8c\u8bc1`（二次验证）。
5. prompt = `promptEl.textContent` 或 `params['reAuthDec'+effectiveType]`（均经 plainText）。
6. 发送验证码按钮：依次 `getDynamicCode` / `getImprovePhoneCodeId_otp` / `getImproveEmailCodeId_otp`（可见者），否则 `[onclick*=DynamicCode],[onclick*=dynamicCode],[id*=DynamicCode],[id*=dynamicCode]` 中可见且非输入框者。
7. **返回 JSON 字段**：`{ mfa:true, method, methodType, prompt, inputs:[{id,name,type,placeholder}], submitId, canSendCode, ready }`（mfa=false 时只含 `{mfa:false, ready}`）。

---

## 8. pollMfaMethodChange(url, methodType, generation, attempt, wasClicking) L3617-3631（+ 回调 L3644-3782）

**用途一句话**：在“原生切换验证方式”打开的网页选择器上每 ~400ms 轮询当前有效 methodType（reAuthType），若网页方法已从期望值变化 → 记日志并 `scheduleMfaDetection` 重检；若仍等于期望值且本会话尚未自动点击过，则自动去点“手机号/短信验证码”选项，最多 75 次后放弃并告警。

调用点：`switchNativeMfaMethod` 的 JS 回调（L4388-4423）中，当打开方法选择器成功（`mobileChangeOtherType()` 返回 ok）后调用 `pollMfaMethodChange(url, currentMethodType, generation, 0, false)`；此后由回调自递归推进（无外部再次触发）。

JS（拼装：`trimIndent` 的多行拼接，`currentType === <JSON.quote(methodType)> && <!wasClicking>` 处动态插入）：
```js
(function() {
  function isVisible(el) {
    if (!el || el.disabled) return false;
    var style = window.getComputedStyle(el);
    var rect = el.getBoundingClientRect();
    return style.display !== 'none' && style.visibility !== 'hidden' &&
      style.opacity !== '0' && rect.width > 0 && rect.height > 0;
  }
  function textOf(el) {
    return String(el && (el.textContent || el.innerText) || '').replace(/\s+/g, ' ').trim();
  }
  function effectiveType() {
    var visiblePrompt = Array.prototype.slice.call(
      document.querySelectorAll('[id^=reAuthDec]')
    ).find(isVisible);
    var match = visiblePrompt && visiblePrompt.id
      ? visiblePrompt.id.match(/^reAuthDec(\d+)$/) : null;
    var params = (typeof reAuthParams === 'object' && reAuthParams) ? reAuthParams : {};
    return match ? match[1] : String(params.reAuthType || '');
  }

  var currentType = effectiveType();
  var clickedPhone = false;
  var clickedText = '';
  if (currentType === ${JSON-quoted methodType} && ${!wasClicking}) {
    var candidates = Array.prototype.slice.call(document.querySelectorAll(
      'button, a, label, li, [role=button], [onclick], div, span'
    )).filter(function(el) {
      if (!isVisible(el) || /^reAuthDec\d+$/.test(el.id || '')) return false;
      var text = textOf(el);
      if (text.length === 0 || text.length > 40) return false;
      return /手机(?:号|短信)?(?:验证码|动态码)|短信(?:验证码|动态码)/.test(text);
    }).sort(function(a, b) {
      function score(el) {
        var score = textOf(el).length;
        if (el.matches('button, a, label, [role=button], [onclick]')) score -= 100;
        return score;
      }
      return score(a) - score(b);
    });
    if (candidates.length) {
      var candidate = candidates[0];
      var target = candidate.closest('button, a, label, li, [role=button], [onclick]') || candidate;
      clickedText = textOf(candidate);
      target.click();
      clickedPhone = true;
      currentType = effectiveType();
    }
  }
  return JSON.stringify({
    type: currentType,
    clickedPhone: clickedPhone,
    clickedText: clickedText
  });
})();
```
> 说明：Java 源码中该正则/文案以 `\u624b\u673a…` 形式出现在 L3621-3622 拼接串；上表按解码展示，注入时须保持原文案。自动点击候选要求文本 1..40 字符且匹配手机/短信验证码类文案，排除 `reAuthDecN` 自身，文本短的按钮优先（交互类标签加权 -100）。

节奏/控制（回调 L3644-3782）：
- 每轮：先 postDelayed 400ms → 校验 `!finished && generation==mfaDetectionGeneration && webView.url==url` → evaluate。
- 解析 `{type, clickedPhone, clickedText}`；`type` 非空且 `!= methodType`（期望）→ log「MFA method changed: <旧> -> <新>」并 `scheduleMfaDetection(webView, url)`（进入重新检测/桥接）。
- 否则（type 为空或仍等于期望）：`attempt < 75` → 以 `attempt+1`、`wasClicking' = wasClicking || clickedPhone` 自递归（即**一旦自动点过就不再重复自动点**，靠 `&& !wasClicking` 关闭）；`>= 75` → warn「MFA method picker left open: no method change detected」。
- 解析异常/其它 → error log「MFA method switch poll error」。
- `clickedPhone=true` 时 log「MFA phone method selected from web picker: <clickedText>」。

---

## 9. 原生 MFA 交互注入脚本

### 9.1 dismissNativeMfa() L4570-4574 —— 无 JS
```kotlin
setMfaState(MfaOverlayState(false, null×…, visible=false 默认, 4095掩码全部默认))
setMfaError(null)
```
即隐藏原生覆盖层并清错误。

### 9.2 submitNativeMfaInput(value) L4760-4793 —— 填码并点提交
前置：`mfaState.visible==false` → 直接 return。日志 hasInput/inputId/submitId。JS 为拼接后 `trimIndent` 的整串（L4781-4783），动态插入 `inputId = JSONObject.quote(mfaState.inputId)` 与 `value = JSONObject.quote(value)`；结构等价于：

```js
(function() {
  var result = {ok:false, error:''};
  // Find the visible code input field
  var input = null;
  var preferredId = ${JSON-quoted inputId};
  if (preferredId) {
    var preferred = document.getElementById(preferredId);
    if (preferred && preferred.offsetParent !== null) input = preferred;
  }
  var codeIds = ['dynamicCode','captcha_code','smsCode','otpCode','verifyCode'];
  for (var i=0; !input && i<codeIds.length;i++) {
    var el = document.getElementById(codeIds[i]);
    if (el && el.offsetParent !== null) { input = el; break; }
  }
  if (!input) {
    var inputs = document.querySelectorAll('input:not([type=hidden])');
    for (var i=0;i<inputs.length;i++) {
      if (inputs[i].offsetParent !== null && inputs[i].type !== 'password') {
        input = inputs[i]; break;
      }
    }
  }
  if (!input) {
    var pwd = document.getElementById('password');
    if (pwd) input = pwd;
  }
  if (input) {
    input.value = ${JSON-quoted value};
    input.dispatchEvent(new Event('input', {bubbles:true}));
    input.dispatchEvent(new Event('change', {bubbles:true}));
    result.inputId = input.id || input.name || 'unknown';
  }
  // Click submit button by exact ID
  var submitBtn = Array.prototype.slice.call(document.querySelectorAll('#reAuthSubmitBtn, [id*=reAuthSubmit], .submit_btn')).find(function(el) {
    var rect = el.getBoundingClientRect();
    var style = window.getComputedStyle(el);
    return style.display !== 'none' && style.visibility !== 'hidden' && rect.width > 0 && rect.height > 0;
  });
  if (submitBtn) {
    submitBtn.click();
    result.ok = true;
  } else {
    result.error = 'reAuthSubmitBtn not found';
  }
  return JSON.stringify(result);
})();
```
DOM 目标与点击逻辑：输入框按「native overlay 记录的 inputId（须可见 `offsetParent!==null`）→ codeIds 五个 id → 首个可见非 password 的 `input:not([type=hidden])` → `#password`」优先级找；赋值后派发 `input`/`change` 冒泡事件（React/Vue 需要）。提交按钮按 `#reAuthSubmitBtn, [id*=reAuthSubmit], .submit_btn` 集合中可见者（`display/visibility/rect` 三查）点 `click()`。
回调（L4304-4357）：`ok` → success log「MFA inject OK, waiting for page transition」、清 error、setMfaState(隐藏掩码 4094→visible=false…)；`!ok` → warn + `setMfaError("提交失败，请重试"(\u63d0\u4ea4\u5931\u8d25\uff0c\u8bf7\u91cd\u8bd5))`。

### 9.3 switchNativeMfaMethod() L4795-4825 —— 打开发送/切换选择器
前置流程：读 `mfaState.verifyMethodType` → `mfaDetectionGeneration++`（作废旧检测）→ `webView.url==null` 则 return → setMfaState(隐藏,4094)、清 error、清 inputValue → 注入下面 JS；回调见 §8（成功即开 poll）。
```js
(function() {
  try {
    if (typeof mobileChangeOtherType !== 'function') {
      return JSON.stringify({ok:false, error:'METHOD_PICKER_NOT_FOUND'});
    }
    mobileChangeOtherType();
    return JSON.stringify({ok:true});
  } catch (e) {
    return JSON.stringify({ok:false, error:String(e && e.message || e)});
  }
})();
```
DOM 目标：调用页面全局函数 `mobileChangeOtherType()` 打开展示“其他验证方式”选择器（该函数由 CAS 页面提供）。失败文案 `setMfaError("无法打开验证方式选择，请返回后重试"(\u65e0\u6cd5\u6253\u5f00\u9a8c\u8bc1\u65b9\u5f0f\u9009\u62e9\uff0c\u8bf7\u8fd4\u56de\u540e\u91cd\u8bd5))`，并把 overlay 置回可见。

### 9.4 triggerNativeMfaSendCode() L4827-4843 —— 触发发送验证码
```js
(function() {
  try {
    function isVisible(el) {
      if (!el || el.disabled) return false;
      var style = window.getComputedStyle(el);
      var rect = el.getBoundingClientRect();
      return style.display !== 'none' && style.visibility !== 'hidden' &&
        rect.width > 0 && rect.height > 0;
    }
    var targetIds = ['getDynamicCode', 'getImprovePhoneCodeId_otp', 'getImproveEmailCodeId_otp'];
    var target = null;
    for (var i = 0; i < targetIds.length; i++) {
      var btn = document.getElementById(targetIds[i]);
      if (isVisible(btn)) {
        target = btn;
        break;
      }
    }
    if (!target) {
      target = Array.prototype.slice.call(document.querySelectorAll(
        '[onclick*=DynamicCode], [onclick*=dynamicCode], [id*=DynamicCode], [id*=dynamicCode]'
      )).find(function(el) {
        return isVisible(el) && el.tagName !== 'INPUT';
      }) || null;
    }
    if (target) {
      target.click();
      return JSON.stringify({ok:true, id:target.id || 'dynamic-code-action'});
    }
    return JSON.stringify({ok:false, error:'NOT_FOUND'});
  } catch(e) {
    return JSON.stringify({ok:false, error: e.message});
  }
})();
```
DOM 目标：三个已知 id 的发送按钮（可见优先）→ 属性模糊匹配（onclick/id 含 DynamicCode/dynamicCode，须可见且非 `<input>`）→ `click()`。回调（L4524-4568）：ok → success log「MFA send code triggered: <id>」；否则 warn「MFA send code button not found: <error>」+ `setMfaError("未找到发送按钮，请尝试切换验证方式"(\u672a\u627e\u5230\u53d1\u9001\u6309\u94ae\uff0c\u8bf7\u5c1d\u8bd5\u5207\u6362\u9a8c\u8bc1\u65b9\u5f0f))`。

---

## 10. onCreate(Bundle) L4580-4693 —— 初始化要点

1. 校区解析：`campus = intent.getStringExtra(EXTRA_CAMPUS/*"campus"*/) ?: "BENBU"` → `EASToken.Campus.valueOf(...)`（try/catch，valueOf 失败回退 `Campus.BENBU`）。
2. `silentMode = intent.getBooleanExtra(EXTRA_SILENT_MODE/*"silent_mode"*/, false)`。
3. 学生类型：`studentTypeRaw = intent.getStringExtra(EXTRA_STUDENT_TYPE/*"student_type"*/)` → `shenzhenPreferredStudentType = ShenzhenWebAutoLogin.normalizeStudentType(raw)`（同值）与 `benbuStudentType = 同 normalize`（L4634-4645）。
4. `config = configFor(campus)`（见 §0.3）。
5. 主题：`silentMode ? theme(2131952458) : theme(2131952257)`（资源 id）；silentMode：window 背景设 drawable 17170445（透明背景资源）、`setDimAmount(0.0f)`；否则 window 背景设白色 `ColorDrawable(-1)`。
6. `super.onCreate`；`setContent { …Compose… }`（L4675-4678，内容为 Compose lambda，反编译体中不含 WebView 创建细节）。
7. 日志「onCreate silentMode=… campus=…」。

**WebView 实际初始化在 `setupWebView()`（L4218-4275，由 Compose/AndroidView 侧调用，非 onCreate 内联）**：
- `webView` 字段并非本文件 `new WebView(...)` 创建（文件内无 `new WebView`）；由外部注入后调 setupWebView。**无法确定 Lxxxx webView 注入点**。
- settings：`setJavaScriptEnabled(true)`、`setDomStorageEnabled(true)`、`setLoadWithOverviewMode(true)`、`setUseWideViewPort(true)`、`setBackgroundColor(-1 /*白*/)`、`setMixedContentMode(2 /*MIXED_CONTENT_COMPATIBILITY_MODE*/)`、`Build>=29: setForceDark(0)`、`Build>=33: setAlgorithmicDarkeningAllowed(false)`、`setSupportMultipleWindows(true)`、`setJavaScriptCanOpenWindowsAutomatically(true)`（配合多窗口/弹窗）。
- UA（仅 SHENZHEN）：`shenzhenMobileUserAgent = settings.getUserAgentString()`（快照默认移动 UA）→ `setUserAgentString(SHENZHEN_DESKTOP_USER_AGENT)`、`setLayerType(LAYER_TYPE_SOFTWARE=1)`、`shenzhenDesktopUserAgentApplied=true`（初始即桌面态）。
- 回调：`setWebChromeClient(new setupWebView.1.1(this))`、`setWebViewClient(new setupWebView.1.2(this))`（L4269-4274）——反编译以占位名引用两个匿名子类，**其 onPageFinished/onProgressChanged/shouldOverrideUrlLoading 等实现不在当前输出文件中（无法确定 Lxxxx）**；本笔记所有「何时触发」外部入口（apply*/redirect/autoOpenJwts/schedule*）都由这些回调或 Compose 层经 `access$…` 调用。
- **onCreate 后先 load 哪个 URL**：onCreate 本身无任何 `loadUrl`；首载由外部逻辑用 `config.loginUrl`（BENBU `…/portal/home/`、研究生同；WEIHAI `https://webvpn.hitwh.edu.cn/`；SHENZHEN 反编译存疑 `https://jw-hitsz-edu-cn.hitsz.edu.cn/authentication/main`，见 §0.3）。**无法确定 Lxxxx 首载调用点**。
- MFA 覆盖层初始状态：onCreate 可见代码未显式设置 overlay（字段默认值在 L200-300 区间的字段初始化/委托处，未逐一展开）；`setMfaState`/`dismissNativeMfa` 使用的“默认隐藏态”= `MfaOverlayState(false, …,4095)`。

---

## 11. onDestroy() L4695-4758 —— 清理

```kotlin
finished = true
stopCookiePolling()                 // cookiePollingGeneration++：作废所有挂起的 cookie 轮询 postDelayed
if (webView != null) {
    if (webView.parent is ViewGroup) (webView.parent as ViewGroup).removeView(webView)   // 从父容器摘除
    webView.stopLoading()
    webView.setWebChromeClient(WebChromeClient())   // 替换为无行为默认 client，防回调泄漏
    webView.setWebViewClient(WebViewClient())
    webView.destroy()
}
super.onDestroy()
```
- 不做 CookieManager 清理、不清缓存；不动 `mfaDetectionGeneration`/`shenzhenAutoAdvanceGeneration`（它们由各 postDelayed 回调自己比对；回调第一行都检查 `finished`，故作废）。`stopCookiePolling` 只递增 `cookiePollingGeneration`（L4294-4297），配合 startCookiePolling 的 500ms 自续轮询（L4277-4288 + checkCookiesAndFinish 内同样检查代数后自续，最多 cookieRetryCount<30 次）终止。

---

## 附：反编译不确定点汇总
1. L1293-1296 SHENZHEN config 的 loginUrl/jwtsUrl 字面量被 CFR 渲染为同一字符串（疑 `SHENZHEN_LOGIN` 内联丢失）。
2. L4269/4272 `setupWebView.1.1/.1.2`（WebChromeClient/WebViewClient 匿名子类）实现不在本文件；所有页面导航回调驱动点缺失。
3. WebView 实例创建点不在本文件（无 `new WebView`）。
4. `WebLoginSuccessPolicy.isWeihaiAuthenticatedPage`（L164+）反编译标注 “Unable to fully structure code”，本文已按标签重建（见 §1.7）。
5. 各 apply*/redirect/autoOpenJwts/poll 的“外部调用时机”只能给出方法内守卫语义；具体回调触发位置无法在现有反编译输出中确定。
