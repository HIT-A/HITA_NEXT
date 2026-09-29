# HitaNEXT — HITA × HarmonyOS NEXT (ArkTS) 整合移植工程

> 依据 `../HITA_X_新版登录_鸿蒙NEXT整合实现蓝本.md`（v1.0）实施。
> 基线素材位于 `../HITA/.analysis/`（HITA_X 源码镜像 + 新版 HITA v2.7.0 反编译）。
> 阶段：**M1/M3 开发预览（登录子系统 + 数据层 + 本地课表域 + 3-Tab 主框架 Home）**。
> 静态一致性自检：`node scripts/static-checks.cjs`（导入导出/路由/资源三层，0=全过）。
>
> 📌 **当前状态**：代码与文档齐备（35 .ets / 12 路由），静态自检 ALL OK；
> ✅ **DevEco 26（SDK API26）命令行 `assembleHap` 编译通过**（unsigned HAP 已产出，0 error；
> 真机安装需先在 DevEco 配置当前签名）。深圳网页登录后的学期、已选课程、JSON 课表、节次结构和成绩请求链路已经接入；本部/威海链路仍待真机回归。
> 接续入口：`docs/usage.md`（操作手册）→ `docs/arkts-compile-checklist.md`（逐项销项）→ `docs/project-state.md`（待办队列+编译记录）。

## 目录结构

```
HitaNEXT/
├─ AppScope/                      # 应用级配置（bundle/label/icon）
├─ docs/
│  ├─ mapping-hitax-to-arkts.md        # HITA_X → ArkTS 逐文件映射表（蓝本附录①）
│  ├─ eas-cookie-finish-notes.md       # 反编译：Cookie采集/必选规则/轮询/EELAB（带行号）
│  ├─ eas-page-predicate-notes.md      # 反编译：页面谓词/UA切换/MFA脚本（带行号）
│  ├─ eas-timetable-view-notes.md      # 反编译：课表视图几何/常量
│  ├─ arkts-compile-checklist.md       # DevEco 编译前自查清单（A–E 销项）
│  ├─ project-state.md                 # 工程状态总览（待办+编译记录）
│  ├─ usage.md                         # 使用手册（离线走查 + 真机联调）
│  ├─ eas-api-capture.md               # M0 抓包记录模板（回填端点用）
│  ├─ DEVICE-RUNBOOK.md                # 编译→签名→装机→M0 抓包 操作手册
│  └─ DEVICE-FIRST-RUN-CHECKLIST.md    # 真机首跑核对 + 回传模板
├─ entry/                         # 唯一 HAP 模块（feature 目录组织，后续可拆 HAR）
│  └─ src/main/
│     ├─ ets/
│     │  ├─ entryability/EntryAbility.ets
│     │  ├─ pages/Index.ets                       # 首页：校区选择 + 会话状态 + 解析自检
│     │  ├─ common/                               # 网络/RDB/偏好/工具（增量）+ db/RdbHelper·util/EasTimeTools·model/timetable 课表域
│     │  └─ feature/
│     │     ├─ eas/
│     │     │  ├─ EasSession.ets                  # 会话模型(对应 EASToken) + 校验
│     │     │  ├─ EasSessionStore.ets             # 持久化（preferences + JSON）
│     │     │  ├─ EasApiClient.ets                # 教务数据 HTTP 客户端(Cookie注入)
│     │     │  ├─ EasDataProvider.ets             # 数据提供者（对齐新版 EASService 方法面）
│     │     │  ├─ model/EasModels.ets             # EasTerm/EasCourseScore/EasExam/EasCourse
│     │     │  ├─ data/ShenzhenWebScores.ets      # 深圳成绩 JSON 解析(1:1) + 离线样例自检
│     │     │  └─ webLogin/                       # —— 本蓝本核心 ——
│     │     │     ├─ EasWebLoginConfig.ets        # 三校区 CampusConfig 表(§2.2.3)
│     │     │     ├─ EasWebLoginProbe.ets         # URL/页面判定谓词纯函数(§2.2.4)
│     │     │     ├─ EasWebMfaBridge.ets          # MFA 探测脚本 + 原生输入桥接
│     │     │     ├─ EasWebLoginController.ets    # 登录状态机（轮询式驱动）
│     │     │     └─ EasLoginPage.ets             # 登录页 UI（ArkWeb+MFA覆盖层）
│     │     └─ feature-timetable|search|profile… # 后续阶段
│     ├─ module.json5 / resources / …             # DevEco 工程配置
```

## 移植对照速查

| 原 Android 能力 | ArkTS 替代 | 状态 |
|---|---|---|
| WebView / CookieManager / evaluateJavascript | `@kit.ArkWeb` `Web` + `webview.WebviewController` + `WebCookieManager.getCookieSync` + `runJavaScript` | 骨架（待真机销项） |
| Room / SharedPreferences | `@ohos.data.relationalStore` / `@kit.ArkData` preferences | 会话先用 preferences |
| Retrofit/OkHttp/Gson | `@kit.NetworkKit` http + `JSON.parse` | `EasApiClient` Cookie 注入与校区 UA 已落地 |
| 深圳成绩 JSON 解析（新版 ShenzhenWebScoreParser） | `data/ShenzhenWebScores.ets`（1:1 移植） | 已落地；离线样例自检通过（Node 镜像验证） |
| 深圳网页登录课表 JSON（`/xszykb/queryxszykbzong`） | `data/ShenzhenWebTimetableParser.ets` + `EasDataProvider` | 已落地；登录 Cookie → 学期/课程 → 课表 → 本地 RDB |
| jsoup 旧登录链（HITA_X EASource） | 弃用，由新版网页登录替换 | 不迁移 |
| Room 三表（timetable/subject/events） | `common/db/RdbHelper.ets`（relationalStore，DAO 语义同步方法） | 已落地；Index「本地课表演示」自检入口 |
| 课表周视图（TimeTableView 系） | `feature/timetable/views/TimetableWeekDraw.ets`（真实时刻分钟映射绘制）+ `pages/TimetablePreview.ets` | 预览页周切换已接通（08:00–24:00 轴/今日遮罩）；圆角/手势/归并按视图笔记续做 |
| 课表/日程/成绩/搜索等其余 UI | ArkUI 重写（时间线/事件/成绩页等，后续阶段） | 未开始 |

## 如何打开 / 编译（重要）

1. 用 **DevEco Studio 5.0.x（API 12+）** 打开本目录（File > Open）。
2. 若 SDK 版本不同，调整：
   - `build-profile.json5`（根 + entry）的 `compatibleSdkVersion`（如 `5.0.0(12)` / `5.1.0(13)`）
   - `hvigor/hvigor-config.json5` 的 `modelVersion`
   - 根 `oh-package.json5` / `entry/oh-package.json5` 的 hvigor 依赖版本（Sync 时按提示）
3. 首次需配置签名（File > Project Structure > Signing Configs，勾选自动签名）。
4. `entry/src/main/resources/base/media/` 内已包含 HITA NEXT 启动图标（`app_icon/startIcon/ic_launcher`）；AppScope 图标与其保持同步。
5. 真机/模拟器需联网访问门户；`module.json5` 已声明 `ohos.permission.INTERNET`。
   ⚠️ 本部 ivpn 与威海 webvpn 门户含 `http://` 明文，若被鸿蒙网络策略拦截需按域放行（见蓝本 §8）。

## 代码注意事项（ArkTS 严格模式）

- 不使用 `any`；接口/类/枚举显式类型；对象字面量须带类型标注。
- `Web` 组件与 `webview.WebviewController` 的控制器回调（`onControllerAttached`/`onPageEnd`/`onProgressChange`）驱动状态机。
- Cookie 采集使用 `webview.WebCookieManager.getCookieSync(url)`（API 12 经 `@kit.ArkWeb`）。
- 门户判定谓词全部为**纯函数**（`EasWebLoginProbe`），与平台无关，可单测回归。
- 深圳成绩解析为纯函数（`parseShenzhenWebScores`），首页「离线解析自检」按钮可直接验证（不依赖网络）。

## 阶段路线（对照蓝本 §7）

- [x] M0 前置：反编译抽取笔记 `docs/`、逐文件映射表（+ 静态一致性工具 scripts/static-checks.cjs）
- [x] M1/M3 开发预览：工程骨架、webLogin 登录子系统、深圳真实课表/成绩解析与 Provider、本地课表域(RDB/周视图/时间线/事件 CRUD/科目/备份⇄恢复/ICS/搜索)、成绩/考试样例页、我的/关于、3-Tab Home(12 路由)
- [x] DevEco 26（API26 SDK）CLI 编译：`assembleHap` 通过（unsigned HAP，0 error；仅 deprecation WARN）
- [ ] 待真机环境：配置签名 → 安装 → 深圳门户登录验证 → 真实 Cookie/端点回归；本部/威海数据端点仍需补齐
- [ ] M2：威海/本部登录收尾、分校区数据端点、失效重登验证
- [ ] M3 精化：周视图合并/ViewPager 手感、事件“周课时段”语义、深色/主题；二期：服务卡片、会话 HUKS 加密
- [ ] M3+ 课表/日程/成绩/考试/空教室/搜索精化（周视图预览、今日时间线、事件编辑、深圳真实课表/成绩、我的/会话管理已落地；本部/威海真链路与设备回归待完成）

## 真机/编译验证清单（本机无法验证，需 DevEco 同步后逐项确认）

1. **工程可同步**：`compatibleSdkVersion`/`modelVersion`/hvigor 依赖按本机 DevEco 调整；启动图标资源已替换为 HITA NEXT 风格化正式图标。
2. **ArkTS 严格模式编译**：`Record`/对象字面量/`enum`/`Set`/`get` 访问器用法、接口类型断言（`as`）、`@Prop` 传字符串、普通成员变量传闭包（页面回调）等按 DevEco 报错微调。
3. **ArkWeb API 面**：`webview.WebviewController`（`getUrl/getCustomUserAgent/setCustomUserAgent('')/runJavaScript/stopLoading/reload`）、`WebCookieManager.getCookieSync(url)`（域/path 口径、http/https/端口跨域）——口径与原 Android `CookieManager` 不同处需按笔记 B 节对齐。
4. **UA 语义**：原版“桌面 UA + 软件层渲染”中的软件层在 ArkTS 无对应物（已注释）；UA 双向切换触发 reload 的防抖由幂等标志+500ms 轮询保证，真机观察是否抖动。
5. **明文 HTTP 门户**（本部 ivpn `:1080`、威海 webvpn、eelab `http://…:1080`）：若被网络策略拦截按域放行。
6. **待真机校准项（笔记 D 节）**：威海 `fetchVpnEasCookies` 交换请求、深圳 `buildClickScript` 自动化点击、三个 viewport 修补脚本注入时机、eelab `JSESSIONID` 门控与 5000ms 超时；深圳课表/成绩端点代码已接入，需验证真实 Cookie 与返回字段。
7. 门户判定谓词改动影响三校区：`docs/eas-page-predicate-notes.md` §1 记录了与源码逐字对应关系，改前先比对。

详见 `docs/mapping-hitax-to-arkts.md` 与各源码文件头注释中的出处标注（形如 `@see Lxxxx` 指向反编译行号）。
