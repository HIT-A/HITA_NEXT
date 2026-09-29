# WebViewLoginActivity.java → ArkTS 移植笔记（Cookie / 完成判定 / 轮询 / 深材自动前进）

来源：`HITA/.analysis/decomp/cn/limpu/hita/ui/eas/login/WebViewLoginActivity.java`（CFR 0.152，行号按该文件；下文 Lxxxx 均指该文件行号，除非另注文件名）。配套文件：`WebViewLoginActivity$Companion$CampusUrls.java`（CampusUrls 常量）、`WebViewLoginActivity$CampusWebConfig.java`、`WebLoginSuccessPolicy.java`、`ShenzhenWebAutoLogin.java`、`data/model/eas/EASToken*.java`。所有日志为 Android Log（LogUtils）。

> 行号口径：read 工具显示总行数 4844（PowerShell 计 4619，系 CRLF 统计差异，不影响区间内容）。内层 WebViewClient/WebChromeClient（L4269-4274 创建的 `setupWebView.1.1/1.2`）在本反编译输出中缺失，凡"由谁触发轮询/成功页/自动前进"只能给辅助判定函数，触发点标注为无法确定。

---

## 0. 类级常量与字段（关键）

| 常量 | 值 | 行号 |
|---|---|---|
| COOKIE_RETRY_COUNT | 30 | L215 |
| COOKIE_RETRY_DELAY_MS | 500L | L216 |
| SHENZHEN_AUTO_ADVANCE_MAX_RETRIES | 12 | L227 |
| SHENZHEN_AUTO_ADVANCE_RETRY_DELAY_MS | 300L | L228 |
| SHENZHEN_DESKTOP_USER_AGENT | `Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36` | L229 |
| SILENT_TIMEOUT_MS | 18000L | L232（silent 模式 18s 无果自动结束） |
| WEIHAI_TICKET_COOKIE_PREFIX | `wengine_vpn_ticket` | L234 |
| BENBU_REQUIRED_COOKIES | {`JSESSIONID`,`HIT`} | L214+L457-460 |
| SHENZHEN_DIRECT_SESSION_COOKIES | {`JSESSIONID`,`route`} | L230+L461-464 |
| SHENZHEN_PROXY_SESSION_COOKIE | `SESSION` | L231 |
| WEIHAI_EAS_SESSION_COOKIE_HINTS | [`JSESSIONID`,`HIT`,`TWFID`] | L233+L465-469 |
| EXTRA_CAMPUS=`campus` EXTRA_SILENT_MODE=`silent_mode` EXTRA_STUDENT_TYPE=`student_type` | | L218-220 |
| 默认 studentType（两字段初值） | `"1"` | L500-502 |
| shenzhenAutoAdvanceScheduledGeneration 初值 | -1 | L503 |

实例字段（相关）：`finished`、`cookiePollingGeneration`、`cookieRetryCount`、`config(CampusWebConfig)`、`benbuStudentType`、`shenzhenPreferredStudentType`、`navigatingToEelab`、`eelabTokenFetching`、`collectedEasCookies(Map)`、`shenzhenAutoAdvanceGeneration`、`shenzhenAutoAdvanceScheduledGeneration`、`shenzhenRoleSelectionClicked`、`shenzhenUnifiedLoginClicked`、`silentMode`（L235-263）。

onCreate（L4580-4693）：campus 取 intent extra `campus`，缺省 `"BENBU"`，`EASToken.Campus.valueOf`（失败回退 BENBU）；`silentMode`=extra `silent_mode`(默认 false)；`shenzhenPreferredStudentType`/`benbuStudentType` 均 = `ShenzhenWebAutoLogin.normalizeStudentType(intent extra "student_type")`；`config = configFor(campus)`（L4646-4647）。
onDestroy（L4695+）：`finished=true; stopCookiePolling();` 摘除/销毁 webView。

### Campus 枚举与 configFor（L1277-1334）
- `EASToken$Campus`：SHENZHEN(0)、BENBU(1)、WEIHAI(2)（枚举声明序）。
- `configFor(campus)` switch（WhenMappings 映射后的 case）：case1=BENBU、case2=WEIHAI、case3=SHENZHEN（由各分支所用 URL/Probe 集反推，行为确定）。
- `CampusWebConfig` 字段：campus、loginUrl、jwtsUrl、cookieProbeUrls(List)、studentType（缺省 `"1"`，L22-38）。
- BENBU：`studentType=="2"` 用 Graduate 套件，否则本科套件（L1316-1330，规则同 hasRequiredCookies，见 §8）。

### CampusUrls 常量全集（文件 `WebViewLoginActivity$Companion$CampusUrls.java` L14-66）
- `BENBU_BASE=http://i-hit-edu-cn.ivpn.hit.edu.cn:1080`；`JWTS_BASE=http://jwts-hit-edu-cn.ivpn.hit.edu.cn:1080`；`GRADUATE_BASE=http://yjsgl-hit-edu-cn.ivpn.hit.edu.cn:1080`；`EELABINFO_URL=http://eelabinfo-hit-edu-cn.ivpn.hit.edu.cn:1080`
- `SHENZHEN_DIRECT_BASE=https://jw.hitsz.edu.cn`；`SHENZHEN_PROXY_BASE=https://jw-hitsz-edu-cn.hitsz.edu.cn`；`SHENZHEN_LOGIN=https://jw-hitsz-edu-cn.hitsz.edu.cn/`；`SHENZHEN_JWTS=https://jw-hitsz-edu-cn.hitsz.edu.cn/authentication/main`
- `WEIHAI_BASE=https://webvpn.hitwh.edu.cn`；`WEIHAI_EAS_PREFIX=https://webvpn.hitwh.edu.cn/http/77726476706e69737468656265737421fae0558f693861446900c7a99c406d3667`（意义未明，仅常量）
- BENBU_LOGIN=`http://i-hit-edu-cn.ivpn.hit.edu.cn:1080/portal/home/`；BENBU_JWTS=`http://jwts-hit-edu-cn.ivpn.hit.edu.cn:1080/loginCAS`
- BENBU_PROBE_URLS（顺序，L43-49）：[BENBU_JWTS, `http://i-hit-edu-cn.ivpn.hit.edu.cn:1080/`, BENBU_LOGIN]
- BENBU_GRADUATE_LOGIN=BENBU_LOGIN；BENBU_GRADUATE_JWTS=`http://yjsgl-hit-edu-cn.ivpn.hit.edu.cn:1080/common/casLogin`
- BENBU_GRADUATE_PROBE_URLS（顺序，L52-56）：[`.../common/casLogin`, `http://yjsgl-hit-edu-cn.ivpn.hit.edu.cn:1080/xs/index`, `http://yjsgl-hit-edu-cn.ivpn.hit.edu.cn:1080/`]
- WEIHAI_LOGIN=`https://webvpn.hitwh.edu.cn/`；WEIHAI_JWTS=`https://webvpn.hitwh.edu.cn/http/77726476706e69737468656265737421fae0558f693861446900c7a99c406d3667/loginCAS`
- WEIHAI_PROBE_URLS（顺序，L59-65）：[WEIHAI_JWTS, `https://webvpn.hitwh.edu.cn/http/77726476706e69737468656265737421fae0558f693861446900c7a99c406d3667/kjscx/queryJxlListBySjid`, `https://webvpn.hitwh.edu.cn/http/77726476706e69737468656265737421fae0558f693861446900c7a99c406d3667/cjcx/queryQmcj`, WEIHAI_LOGIN]
- SHENZHEN_PROBE_URLS = `WebLoginSuccessPolicy.shenzhenCookieProbeUrls(SHENZHEN_PROXY_BASE, SHENZHEN_DIRECT_BASE)` → 生成 8 个（见 §B3）。

---

## 1. buildCookieHeader(String url) L1010-1052
作用：组 "Cookie: …" 头（串接 CookieManager 里两个来源的裸 cookie 字符串）。
1. 取 `CookieManager.getInstance()`。
2. 建一个集合 Set<String>（Kotlin `mutableSetOf`，插入序即 LinkedHashSet）。
3. 若入参 `url` 非空：`c = cookieManager.getCookie(url)`；若 `c != null && !c.isBlank()` → 加入集合。
4. 无条件：`c2 = cookieManager.getCookie("https://webvpn.hitwh.edu.cn/")`（带结尾 `/`；Android 端实际按 host/domain 匹配，path 无关）；非 null 非空则加入。
5. 返回 `set.joinToString("; ")`；集合空时返回空串 `""`。
- 注：getCookie 是 Android CookieManager 原始 header 值（形如 `JSESSIONID=…; HIT=…`），不重新解析；L1028/1040。
- ArkTS 提示：等价于"取当前 URL 域 + webvpn.hitwh.edu.cn 域 的全部 cookie header 字符串，非空则并集去重后以 `; ` 连接"；顺序为插入序（当前域在前）。

## 2. checkCookiesAndFinish(int generation) L1054-1189
入口守卫：`if (finished != 0) return; if (generation != cookiePollingGeneration) return;`
1. `map = collectCookies()`（§3）。
2. `url = webView.getUrl() ?: ""`。
3. `hasVpn = hasWeihaiVpnTicket(map)`；`hasJsession = map.containsKey("JSESSIONID")`。
4. 日志（仅当 `cookieRetryCount==0 || cookieRetryCount%10==0`）：
   `checkCookies: retry=<cookieRetryCount> keys=<keySet 排序后 toString> host=<Uri.parse(url).getHost()>`（L1079-1092）。
5. 分支（顺序严格如下）：
   - **WEIHAI**：若 `hasVpn && hasJsession` → `fetchVpnEasCookies(callback)` 并 return（L1101-1105）。callback=§6 所述：合并 vpn 返回 cookies 后 `finishWithCookies(map, null)`（L1165-1183 `checkCookiesAndFinish$lambda$0`）。
   - **BENBU**：若 `hasRequiredCookies(map, url)` → `handleSuccessPage()`；return（L1112-1119）。
   - **SHENZHEN**：若 `hasRequiredCookies(map, url)` → `finishWithCookies(map, null)`（直接带 cookies、无 token）；return（L1126-1135）。
6. 超时：若 `cookieRetryCount >= 30` → 日志 w：`cookie polling timeout campus=<campus>`；**直接 return，不再调度**（轮询就此停止，不 finish）（L1137-1151）。
7. 否则 `cookieRetryCount++`；`webView.postDelayed(() -> checkCookiesAndFinish(generation), 500L)`（L1152-1160）。

## 3. collectCookies() L1189-1275
1. `cookieManager = CookieManager.getInstance()`；结果 `LinkedHashMap<String,String>`。
2. 遍历 `config.getCookieProbeUrls()` 每个 probeUrl：
   `cookieManager.getCookie(probeUrl)` → `parseCookies(header)`（§11）→ 逐项 `result.putIfAbsent(k,v)`（probe 顺序内后者不覆盖前者；各 probe 的 key 并集）。
3. 若 `webView.getUrl()` 非空且 `startsWith("http")`（大小写敏感前缀，L1251）：
   - `getCookie(当前完整 url（含 path）)` → `parseCookies` → `putIfAbsent` 各键；
   - 若结果仍**无** `JSESSIONID` 且 `extractJsessionidFromUrl(当前url) != null` → `result.put("JSESSIONID", 提取值)`（L1265-1271）。
4. 返回 map。
- 注：probe 命中一个域即可把该域的 cookie 全部抓进来（CookieManager 按域返回全部 cookie 串，parseCookies 拆成 k=v）。

## 4. extractJsessionidFromUrl(String url) L1488-1512
依次尝试下列正则（均 `RegexOption.IGNORE_CASE`，`find` 首个匹配即返回捕获组 1；全不中返回 null）：
1. `;jsessionid=([^;&?]*)`（URL 内以 `;jsessionid=` 出现）
2. `[?&]jsessionid=([^;&]*)`（query 形式）
即只取第一个匹配模式的首个捕获组。L1495-1509。

## 5. fetchEelabTokenViaHttp() L1514-1529（+ lambda$0 L1528-1829）
触发守卫（在 UI 线程调用处）：`!finished && navigatingToEelab` 才 `new Thread(lambda).start()`。
HTTP 语义要点（lambda$0，CFR 对控制流标记"Unable to fully structure code"，L1524-1528；URL/Header 字符串逐字可靠，分支顺序以日志与跳转推断）：
- 常量 BASE = `http://eelabinfo-hit-edu-cn.ivpn.hit.edu.cn:1080`（L1543）。
- 读取 `CookieManager.getCookie(BASE)`（**不带 path**，L1547-1548）。
- **not-found 分支**：cookie 为 null/blank，则（推断还含 `!cookie.contains("JSESSIONID")`，L1563-1572 反编译跳转混乱，方向约 9 成：必须含 JSESSIONID 才继续，实现时建议对照抓包复核）→ 日志 w：`fetchEelabToken: JSESSIONID not found, student likely has no eelab access`（L1777），并 post 回主线程：`navigatingToEelab=false; map = collectedEasCookies ?: collectCookies(); finishWithCookies(map, null)`（L1790-1792 + lambda$0$3 L1858-1870）。
- **主流程**：把 cookie header 按 `;` 切分、逐段 trim、首个 `=` 拆 k=v（跳过无 `=` 段/空段，与 parseCookies 同款解析，L1574-1639）作为 cookies。
- POST（Jsoup，L1641-1671）：
  - URL：`http://eelabinfo-hit-edu-cn.ivpn.hit.edu.cn:1080/api/cas/login?sf_request_type=ajax`（L1641）
  - 方法 POST；`.cookies(解析出的 map)`
  - Headers（L1644-1663）：
    - `User-Agent: Mozilla/5.0 (Linux; Android 16; sdk_gphone64_arm64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.6998.135 Mobile Safari/537.36`
    - `Accept: */*`
    - `Origin: http://eelabinfo-hit-edu-cn.ivpn.hit.edu.cn:1080`（=BASE）
    - `Referer: http://eelabinfo-hit-edu-cn.ivpn.hit.edu.cn:1080/login.html?t=suc`
    - `Content-Type: application/x-www-form-urlencoded`
    - `X-Requested-With: XMLHttpRequest`
    - `Accept-Language: zh-CN,zh-Hans;q=0.9`
  - `timeout(…)`、`ignoreContentType(true)`、`ignoreHttpErrors(true)`（L1664-1668）。**无法确定**：L1664-1665 反编译为 `timeout((int)(5000 != 0))`，疑似原码 `timeout(5000)`。
- 响应处理：
  - `statusCode != 200` → 日志 w：`fetchEelabToken: HTTP <code>`（L1749-1752）→ 走失败收尾（L1742-1767）。
  - body 解析为 JSONObject（解析异常 → 日志 e `fetchEelabToken: parse response failed`，L1731；同走失败收尾）。
  - `code = json.optInt("code", -1)`；若 `code == 0`：`data = json.optJSONObject("data")`；`token = data?.optString("token", "") ?: ""`；若 `token.length() >= 50` → 成功：日志 success `fetchEelabToken: got JWT token, length=<len>`（L1698），post 主线程：`navigatingToEelab=false; map = collectedEasCookies ?: collectCookies(); finishWithCookies(map, token)`（L1712 + lambda$0$2 L1845-1856）。token 长度 <50 / data 空 / code!=0 → 日志 w：`fetchEelabToken: unexpected response code=<code>`（L1720-1722）→ 失败收尾。
  - 任何 HTTP 异常 → 日志 e `fetchEelabToken: HTTP request failed`（L1815）→ 失败收尾（L1826-1827）。
  - 失败收尾统一 = lambda$0$3/$0$4（L1858-1884）：若 `!finished && navigatingToEelab`：`navigatingToEelab=false; map = collectedEasCookies ?: collectCookies(); finishWithCookies(map, null)`（不带 token）。

## 6. fetchVpnEasCookies(Function1) L1886-1928（威海 VPN 会话 → EAS cookies）
- L1886-1899：`url = webView.getUrl() ?: ""`；`cookieHeader = buildCookieHeader(url)`；起 `Thread(lambda$0(cookieHeader, this, callback))`。
- **无法确定（关键缺失）**：`fetchVpnEasCookies$lambda$0`（真正的"用什么 URL、什么请求顺序、怎么把威海 VPN 会话换成 EAS 会话"）CFR 反编译失败（L1901-1924，ConfusedCFRException），正文不在任何可读产物中。已知事实仅：
  - 入参是 buildCookieHeader 拼出的 cookie 头字符串（含 webvpn.hitwh.edu.cn 域 cookie 与当前页域 cookie）；
  - 结果经 `lambda$0$1`（L1926-1928）以 `callback.invoke(map)` 交回主流程，map 即"VPN 换来的 EAS cookies"（Kotlin 参数名 vpnCookies，L1167/2306）。
  - 两个调用点的回调都做同样的事（`checkCookiesAndFinish$lambda$0` L1165-1183 与 `handleSuccessPage$lambda$0` L2304-2322）：`newMap = LinkedHashMap(collectedMap); vpnMap 逐项 putIfAbsent; finishWithCookies(newMap, null)`。
  - 疑似语义：带该 Cookie 头请求威海 jwts 域某 URL，把 Set-Cookie/页面 cookie 解析成 EAS 会话 map。**实现 ArkTS 前需用抓包/MITM 实测还原请求（URL、方法、是否需要额外 body/Referer）**。触发条件见 §2 WEIHAI 分支与 §13：`hasWeihaiVpnTicket(collectCookies()) && map.containsKey("JSESSIONID")`。

## 7. finishWithCookies(Map cookies, String token) L2095-2181
1. `finished` 已 true → 直接 return；否则 `finished=true; stopCookiePolling()`（L2100-2106）。
2. `cookiesJson = new JSONObject(cookies).toString()`（org.json；形如 `{"JSESSIONID":"…","HIT":"…"}`；key/value 均为 String；顺序由 org.json 内部实现决定，不作保证）。
3. `intent.putExtra("cookies", cookiesJson)`（L2113）。
4. 仅当 `config.getCampus()==SHENZHEN`（L2121-2137）：
   `host = Uri.parse(webView.getUrl() ?: "").getHost()`；
   `base = WebLoginSuccessPolicy.shenzhenWebBaseUrl(host, "https://jw-hitsz-edu-cn.hitsz.edu.cn", "https://jw.hitsz.edu.cn")`；
   `intent.putExtra("web_base_url", base)`。
   shenzhenWebBaseUrl 规则（WebLoginSuccessPolicy L431-449）：`host` 与 `URI("https://jw.hitsz.edu.cn").getHost()`（即 `jw.hitsz.edu.cn`）忽略大小写相等 → 返回 `https://jw.hitsz.edu.cn`；否则返回 `https://jw-hitsz-edu-cn.hitsz.edu.cn`；两分支都 `trimEnd('/')`（即不带结尾斜杠）。
5. 若 `token != null && !token.isBlank()` → `intent.putExtra("electronic_exp_token", token)`（L2138-2150）。
6. 日志 success：`login complete campus=<campus> cookies=<map.size()> eelabToken=<token非空>`（L2151-2171）。
7. `setResult(RESULT_OK(-1), intent); finish()`（L2172-2173）。
- 另外 `finishWithCookies$default`（L2176-2181）mask 2 → token 传 null；两处默认调用 `finishWithCookies(map, null)`。
- `finishWithCancelledResult`（L2084-2093）：`finished=true; stopCookiePolling(); setResult(0); finish()`（取消结果，RESULT_CANCELED）。

## 8. hasRequiredCookies(Map map, String url) L2339-2426（三校区必选 Cookie 精确规则）
入口按 campus switch（case1=BENBU、case2=WEIHAI、case3=SHENZHEN）：
- **SHENZHEN（case3，L2366-2369）**：`return EASToken.Companion.hasShenzhenWebSessionCookies(map)`。
  hasShenzhenWebSessionCookies（EASToken$Companion L28-63）逐字语义：
  `js = map["JSESSIONID"] ?: ""`；`route = map["route"] ?: ""`；`session = map["SESSION"] ?: ""`；
  返回 `(!js.isBlank() && !route.isBlank()) || !session.isBlank()`。
  （反编译以 goto 表达，等价式如上；JSESSIONID 空时 route 不再参与。）
- **WEIHAI（case2，L2370-2376）**：`hasWeihaiVpnTicket(map) && map.containsKey("JSESSIONID")`。
- **BENBU（case1，L2377-2424）**：设 `grad = (config.getStudentType() == "2")`：
  - grad==true（研究生）：
    1. `sdp = map["sdp_user_token"] ?: ""`；`sdp.isBlank()` → **false**（L2395-2400）。
    2. `js = map["JSESSIONID"]`（可空）；`js` 非空且非 blank → **true**（L2401-2407）。
    3. 否则 `hasUrlJsession(url)`（§9）为 true → **true**，false → **false**（L2408-2410）。
    → 即：`sdp_user_token 非空 且 (map 有非空 JSESSIONID 或 url 带 jsessionid)`。
  - grad==false（本科生）：
    1. `c1 = map.containsKey("JSESSIONID") || hasUrlJsession(url)`（L2412-2418）。
    2. `c2 = map.containsKey("HIT")`（L2419-2420）。
    3. 两者都真 → **true**；任一假 → **false**（L2421-2423）。
    → 即：`(JSESSIONID 在 map 或在 url) 且 map 含 HIT`。
- url 形参只用于 hasUrlJsession（BENBU），SHENZHEN/WEIHAI 不依赖 url。

## 9. hasUrlJsession(String url) L2428-2446
`url.contains(";jsessionid=", ignoreCase=true) || url.contains("jsessionid=", ignoreCase=true)`（两处均忽略大小写；等价"URL 任意位置含 jsessionid=（大小写不敏感）"）。返回布尔。

## 10. hasWeihaiVpnTicket(Map map) L2452-2489
遍历 `map.keySet()`：存在任一 key 满足
`key.startsWith("wengine_vpn_ticket", ignoreCase=true) || key.contains("wengine_vpn_ticket", ignoreCase=true)`
→ true；否则 false。prefix 常量见 §0（L234）。注意：**key 判定是"前缀或包含"，且忽略大小写**；不含该前缀但含于中间也算命中。

## 11. parseCookies(String header) L3483-3592（Cookie header 串 → Map）
1. `header == null || header.isBlank()` → 返回 `emptyMap()`（L3492-3500）。
2. 按字面 `";"` 切分（`split(";")`，L3503-3505）。
3. 逐段处理（L3512-3588）：
   - 段 `trim()` 后为 blank → 跳过；
   - 不含 `"="` → 跳过；
   - 取首个 `=`：`key = trim(段.substring(0, idx))`，`value = trim(段.substring(idx+1))`；
   - `key.isBlank()` → 跳过（L3560-3563）；否则收集二元组 (key,value)（L3565）。
4. 返回 `toMap`（L3591）：k=v 列表转 LinkedHashMap；**重复 key 后到覆盖前到**（同一 header 罕见重复；跨域合并时 collectCookies 用 putIfAbsent 另行处理）。
- 说明：本方法不识别 path/expires 等属性（把 `; ` 之后所有内容当新段，遇 `Expires=…` 之类会把整串当 value），也不处理 `;jsessionid=` 场景——URL 内 jsessionid 由 `extractJsessionidFromUrl`/`hasUrlJsession` 负责（§4/§9），调用点在 collectCookies L1267 与 hasRequiredCookies §8。

## 12. 轮询与深圳自动前进
### startCookiePolling() L4277-4288 / stopCookiePolling() L4294-4297
- start：`cookiePollingGeneration += 1`（存到 n）→ `cookieRetryCount = 0` → `webView.postDelayed(checkCookiesAndFinish(n), 500L)`。
- stop：仅 `cookiePollingGeneration += 1`（使已排队的 checkCookiesAndFinish(generation) 在 L1056 守卫处失效）。
- 节奏：首检在 start 后 500ms；此后每次 check 不命中且未超时则再 postDelayed 500ms；`cookieRetryCount>=30` 即停（约 15s 窗口），日志 w `cookie polling timeout campus=…`。stop 被 finishWithCookies（L2106）、finishWithCancelledResult（L2090）、onDestroy（L4698）调用。
- 触发点：startCookiePolling/handleSuccessPage 由内层 WebViewClient 调用（有 access$ 桥 L584/692/696），**具体触发 URL 条件无法确定（内层类未反编译出）**；候选判定函数：isSuccessPage（§A）、isShenzhenProxyJwPage（§A）、isPortalHomePage、isJwtsPage。

### scheduleShenzhenAutoAdvance(webView,url) L4011-4052 + $attempt L4054-4082 + lambda L4087-4189
- 入口日志 d：`SHENZHEN_AUTO schedule requested generation=<gen> url=<safeUrl> finished=<bool>`。
- 条件：`campus==SHENZHEN && isShenzhenProxyJwPage(url) && !finished`：
  - `shenzhenAutoAdvanceScheduledGeneration == shenzhenAutoAdvanceGeneration` → 日志 d `SHENZHEN_AUTO schedule deduplicated generation=<n>`，return（防重复调度）。
  - 否则 `shenzhenAutoAdvanceScheduledGeneration = gen`；日志 d `SHENZHEN_AUTO schedule accepted generation=<n> studentType=<shenzhenPreferredStudentType>`；`attempt(gen, webView, attempt=0)`。
- attempt：守卫 `!finished && gen==shenzhenAutoAdvanceGeneration && isShenzhenProxyJwPage(webView.getUrl() ?: "")`：
  - `allowUnified = !shenzhenUnifiedLoginClicked`；`allowRole = !shenzhenRoleSelectionClicked`；两者都 false → return（无可点）。
  - 日志 d：`SHENZHEN_AUTO attempt=<n2> generation=<n> allowUnified=<..> allowRole=<..> url=<safeUrl>`。
  - `script = ShenzhenWebAutoLogin.buildClickScript(shenzhenPreferredStudentType, allowUnified, allowRole)`；`webView.evaluateJavascript(script, cb)`。
- cb（attempt$lambda$0）：守卫同 attempt；`json = runCatching { parseJavascriptJson(result ?: "") }.getOrNull()`；日志 d `SHENZHEN_AUTO result attempt=<n> parsed=<bool> payload=<sanitizeJsResult>`。
  - 若 `json != null && json.optBoolean("clicked", false)`：
    - `action = json.optString("action")`；
    - `"postgrad-role"` 或 `"undergrad-role"` → `shenzhenRoleSelectionClicked=true`（L4142-4156）；
    - `"unified-login"` → `shenzhenUnifiedLoginClicked=true`（L4158-4164）；
    - 日志 success：`Shenzhen Web auto advance action=<action> studentType=<shenzhenPreferredStudentType>`；return。
  - 否则 `next=attempt+1`；`next < 12`（SHENZHEN_AUTO_ADVANCE_MAX_RETRIES）→ `postDelayed(attempt(gen,webView,next), 300L)`；`>=12` → 日志 d `SHENZHEN_AUTO exhausted without matching action`。
  - 即：**每次轮询间隔 300ms，至多 12 次（约 3.6s 窗口）**，直到 JS 回报 clicked 且 action 命中并置位；generation/url/finished 任一变化即整体失效。

## 13. handleSuccessPage() L2207-2302
1. `finished` → return。`map = collectCookies()`（L2224）。
2. **WEIHAI**：`hasWeihaiVpnTicket(map)` 为真 → `fetchVpnEasCookies(回调：vpn map putIfAbsent 合并后 finishWithCookies(map,null))`；return（L2233-2241）。
3. **BENBU && studentType=="2"（研究生）**：`finishWithCookies(map, null)`；return（L2251-2266）。→ 研究生本部不走电子实验 token。
4. **非 BENBU**（即 SHENZHEN，或 WEIHAI 无 vpn ticket 走到这）：`finishWithCookies(map, null)`；return（L2273-2278）。
5. 剩下 = **BENBU 本科生**：
   - `navigatingToEelab = true; eelabTokenFetching = false; collectedEasCookies = map`（L2279-2283）；
   - `webView.postDelayed(handleSuccessPage$lambda$1, 10000L)`（L2291-2293）；
   - `webView.loadUrl("http://eelabinfo-hit-edu-cn.ivpn.hit.edu.cn:1080/api/cas/loginSuccess")`（L2300-2301）。
6. lambda$1（L2324-2337）超时守卫：`navigatingToEelab && !finished` → 日志 w `eelabinfo timeout, finishing without token`；`navigatingToEelab=false`；`finishWithCookies(map, null)`。
- 关联：本科本部流程 = 先让 webView 访问 eelab `loginSuccess`（收集 eelab 域 cookie）→（内层 WebViewClient，未反编译）在合适的时机调 `fetchEelabTokenViaHttp`（§5）→ 成功后 `finishWithCookies(map, token)`。token 即"电子实验"JWT，`electronic_exp_token` extra。

---

## A. http(s) 字符串常量清单（本文件内，方法归属）
WebViewLoginActivity.java 内直接出现：
- `https://webvpn.hitwh.edu.cn/` —— buildCookieHeader L1040（getCookie 域）。
- `https://jw-hitsz-edu-cn.hitsz.edu.cn/authentication/main` —— configFor 深圳 login/jwts（L1293/1296）。
- `http://eelabinfo-hit-edu-cn.ivpn.hit.edu.cn:1080` —— fetchEelabToken lambda BASE/Origin（L1543）；`…/api/cas/login?sf_request_type=ajax`（L1641）；`…/login.html?t=suc` Referer（L1653）；`…/api/cas/loginSuccess` handleSuccessPage L2300。
- `https://jw-hitsz-edu-cn.hitsz.edu.cn`、`https://jw.hitsz.edu.cn` —— finishWithCookies web_base_url（L2132-2133）；isShenzhenProxyJwPage/切换 UA 相关（L2811/2841/3796-3797/4465，见 isPortalHomePage L2811、isShenzhenProxyJwPage L2841、switchShenzhenUserAgentForNavigation L4465）。
其余校区/接口 URL 集中在 `CampusUrls`（见 §0，login/jwts/probe 全量；无其他隐藏域名——已全文 grep `https?://` 仅上述）。UA 常量：SHENZHEN_DESKTOP_USER_AGENT（§0）与 eelab 请求 UA（§5）。

辅助页面判定（用于内层 WebViewClient 触发，供移植参考）：
- `isShenzhenProxyJwPage(url)` L2839-2843：`Uri.parse(url).getHost()` 忽略大小写 == `Uri.parse("https://jw-hitsz-edu-cn.hitsz.edu.cn").getHost()`（即 `jw-hitsz-edu-cn.hitsz.edu.cn`）。
- `isSuccessPage(url)` L2845-3013：按校区 switch：
  - SHENZHEN：`WebLoginSuccessPolicy.isShenzhenAuthenticatedPage(url, collectCookies())`。
  - WEIHAI：`isWeihaiAuthenticatedPage(url, collectCookies())`。
  - BENBU：`grad = studentType=="2"`；grad：host 含 `yjsgl` 且 path 含 `/xs/index` 且 `hasRequiredCookies(collectCookies(), url)` → true；非 grad：`(host 含 jwts 且 path 不含 login 且 map 含 JSESSIONID 与 HIT)` 或 `((host 含 jwts 或含 hit.edu.cn) 且 path 含 kbcx/cjcx/kjscx/xswh/query/index)` → true。
- `WebLoginSuccessPolicy.isShenzhenAuthenticatedPage(url,cookies)`（Policy L46-158）：host∈{`jw.hitsz.edu.cn`,`jw-hitsz-edu-cn.hitsz.edu.cn`}；path 含 `login`/`authserver`/`authentication/require` → false；path 为 空/`/` 或含 `authentication/main`/`student_index`/`user/me`/`xszykb`/`xsxk`（大小写不敏感 contains）且 `hasShenzhenWebSessionCookies(cookies)` → true。
- `isWeihaiAuthenticatedPage(url,cookies)`（Policy L164-317）：path 含 `/http/`/`kbcx`/`cjcx`/`kjscx`/`query`/`index` 或含 `logincas` 或 endsWith `/login` 或含 `/login/`，且 key 含 `wengine_vpn_ticket`（startsWith 或 contains，忽略大小写）且 `JSESSIONID` 非空 → true（host 未校验）。注：WebViewLoginActivity 内 WEIHAI 完成判定走 hasRequiredCookies（§8），isWeihaiAuthenticatedPage 仅作成功页检测。
- `isJwtsPage(url)` L2689-2759：WEIHAI 直接 false；host 含 `jwts` **或**（studentType=="2" 且 host 含 `yjsgl`）且（path 或 url 小写含 `logincas` 或 `login`）→ true。
- `isPortalHomePage` L2771-2837：SHENZHEN→`ShenzhenWebAutoLogin.isProxyRoot(url,"https://jw-hitsz-edu-cn.hitsz.edu.cn")`（去掉 #/query/末尾 `/` 后相等）；WEIHAI→host==`webvpn.hitwh.edu.cn` 且（path 空或 `/portal/home`）；BENBU→host==`i-hit-edu-cn.ivpn.hit.edu.cn` 且 path∈{`/portal/home`,`/portal`}（path trimEnd `/` 后比较）。
- `isTrustPortalPage` L3015-3033：host==`trust.hitsz.edu.cn` 且 path startsWith `/portal`。
- `isMfaPage` L2761-2769：path 含 `/authserver/reAuthCheck/`（忽略大小写）。

## B. Cookie/CookieManager 域操作汇总（getCookie/setCookie、host/path 口径）
本文件**从不调用** CookieManager.setCookie/removeAllCookie；写入全靠 WebView 页面自己种（相关 accept 开关在 initViews）：
- initViews（L2499-2509）：`CookieManager.getInstance().setAcceptCookie(true)`；`setAcceptThirdPartyCookies(webView, true)`。
- getCookie 全部 5 处及"URL 是否带 path"：
  1. L1028 `getCookie(url)`：url = buildCookieHeader 入参（webView 当前页完整 URL，**带 path**）——匹配当前页域。
  2. L1040 `getCookie("https://webvpn.hitwh.edu.cn/")`：**host 根 + `/`**（威海 webvpn 域）。
  3. L1213 `getCookie(probeUrl)`：probe URL **带 path**（见 §0 probe 列表）。
  4. L1254 `getCookie(webView.getUrl())`：当前页完整 URL（仅当以 `http` 开头）。
  5. L1548 `getCookie("http://eelabinfo-hit-edu-cn.ivpn.hit.edu.cn:1080")`：**无 path、无结尾斜杠**。
- Android CookieManager.getCookie 实际按 host/domain 匹配（path 无效），返回 null（无 cookie）或 `k=v; k=v` 串；ArkTS Web Cookie 需按"域 + 需要的属性"映射，且**跨 http/https、端口**按原样保留（eelab 是 http://…:1080）。
- 对 getCookie 返回串的统一处理：`parseCookies`（§11）；jsessionid 兜底走 URL（§3/§4/§8/§9）。
- WebView cookie 与原生 HTTP（eelab、VPN 交换）间的桥梁：getCookie 裸串 → parseCookies → Jsoup `.cookies(map)`（eelab L1643）或拼 Cookie 头（buildCookieHeader，VPN 交换 L1895）。

## C. studentType / "1" / "2"（本科/研究生）判定与分叉
- 取值空间：`"1"`=本科生(UNDERGRAD)，`"2"`=研究生(POSTGRAD)（ShenzhenWebAutoLogin L22-23；与 EASToken.TYPE 枚举 UNDERGRAD/GRAD 对应，见 MainActivity L1573）。活动内两字段默认 `"1"`，由 intent extra `student_type` 经 `normalizeStudentType` 归一（onCreate L4634-4645；normalize 规则：trim 后恰好为 `"2"` 才返回 `"2"`，其余（含 null/空/其它串）一律 `"1"`，ShenzhenWebAutoLogin L56-72）。
- 分叉点（逐字条件 = `studentType == "2"` 或 `"2".equals`）：
  1. configFor（L1316-1330）：本部 == "2" → GRADUATE 套件（login 同本科 portal/home，jwts=yjsgl common/casLogin，probe=3 个 yjsgl URL）；否则本科套件（jwts loginCAS 等）。
  2. hasRequiredCookies BENBU（L2387-2410）：见 §8（研究生还要 `sdp_user_token`）。
  3. handleSuccessPage（L2261）：本部研究生 → 直接 finish，不取 eelab token；本部本科生 → 走 eelab token 流程（§13 步骤 5）。
  4. isJwtsPage（L2730）：本部 == "2" 时只有 host 含 `yjsgl` 才算 jwts 页。
  5. isSuccessPage BENBU（L2930-2949）：研究生成功页 = host 含 `yjsgl` + path 含 `/xs/index` + hasRequiredCookies；本科生成功页规则见 §A。
  6. 深圳 `shenzhenPreferredStudentType` 不参与"完成判定"，只用于自动点击脚本选择研究生/本科入口（scheduleShenzhenAutoAdvance 日志 L4046/4171 与 buildClickScript L4075；role action 值 `undergrad-role`/`postgrad-role` L4143/4149）。
- campus→studentType 由 CampusWebConfig 携带（BENBU 用 benbuStudentType；WEIHAI/SHENZHEN 由 mask 默认 `"1"`，见 CampusWebConfig L35-38 与 configFor L1296/1310）。

---

## D. 无法确定清单（反编译证据不足，勿脑补）
1. `fetchVpnEasCookies$lambda$0` 的完整 HTTP 交换（URL/方法/顺序/响应解析）——L1901-1924 CFR 直接抛 ConfusedCFRException，正文不可读；仅外围事实见 §6。实现前必须抓包。
2. fetchEelabToken 中 "cookie 非空但不含 JSESSIONID" 的走向：L1563-1572 的 `contains("JSESSIONID")` 门控方向（反编译 goto 混淆），疑似"必须含 JSESSIONID 才 POST，否则 not-found 收尾"；建议实现时保留该判断并抓包复核。
3. `timeout` 实参：L1664-1665 显示 `timeout((int)(5000 != 0))`，疑似原 `timeout(5000)`（毫秒）。
4. startCookiePolling/handleSuccessPage/scheduleShenzhenAutoAdvance 的确切页面触发条件：内层 WebViewClient/WebChromeClient（L4269-4274 `setupWebView.1.1/1.2`）未反编译输出；仅 access$ 桥（L584/616/648/692/696）与辅助判定函数（§A）可用作参考。
5. finishWithCookies 中 `JSONObject(map)` 的键序：org.json 内部实现，不保证与 LinkedHashMap 一致；若下游解析按 key 取则无碍。
6. eelab UA 中 `sdk_gphone64_arm64`（模拟器指纹）与 5000ms 一样照抄即可，但真实设备 UA 可能不同——字符串为字面常量（L1645），逐字照抄。
