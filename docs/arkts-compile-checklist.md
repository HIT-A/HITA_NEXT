# ArkTS 编译前自查清单（DevEco 侧逐项销项）

> 状态更新（R42）：**DevEco 26 / SDK26 命令行 `assembleHap` 已通过（0 error）**。
> A/B/C/E 中可由编译器直接验证的项已销项；D(relationalStore) 残留 58 处 “may throw” WARN（非阻断）；
> 真机项（签名安装/门户登录/抓包）等待设备接入。

> 本工程在无 DevEco/鸿蒙 SDK 的环境编写，以下均按 API 12（`5.0.0(12)`）语义书写；
> 打开工程后请按此清单逐项核对/修正。行号随改动漂移，按关键字定位。

## A. 工程与配置
- [ ] `build-profile.json5`（根/entry）`compatibleSdkVersion`；`hvigor/hvigor-config.json5` `modelVersion`；根与 entry `oh-package.json5` 依赖版本 → 按本机 DevEco Sync 提示调整。
- [ ] 签名（Signing Configs 自动签名）；启动图标已替换为 HITA NEXT 风格化资源，需在 DevEco 中确认最终签名配置。
- [ ] `module.json5` `deviceTypes` 含 phone/tablet/2in1；`requestPermissions` INTERNET 已声明；`main_pages.json` 现有 6 页路径与文件名一致。

## B. ArkTS 严格模式（全局）
- [ ] **无 `any`**（自查通过）；`catch (e)` 未标注类型处若报错 → 改为 `catch (err: Error)` 或按提示调整。
- [ ] 对象字面量必须有类型上下文：`Record<string, …>` 字面量（EasSession/EasModels/各 RDB 桶）；若 `Record` 索引访问报错 → 改用显式 interface 或经 `as`。
- [ ] `JSON.parse` 返回值类型：多处 `JSON.parse(x) as Object / as Record<…> / as Array<…>`（数据/解析/序列化），按编译器提示微调（ArkTS 无 `unknown`）。
- [ ] 字符串/数字/布尔 `enum`（EasCampus/EasEventType…）：`xxx.toString()`/`valueOf` 语义，确保与落库文本（RDB type 列）一致。
- [ ] `Set`/`Map` 使用（probe、会话、HTTP 头）API 齐备；`Map.forEach((v,k))` 参数序确认（值在前）。
- [ ] 类 `get` 访问器（EasTermItem.name）与 `static` 成员：若报“不支持”则改为普通方法。
- [ ] @Builder 方法调用用 `this.xxx(...)`（Index/AddEventPage）；ForEach 第二参 key generator 必须唯一。
- [ ] @State 数组/对象引用替换触发渲染；未用装饰器传参仅初始化一次（TimetablePreview 静态场景 OK）。
- [ ] `async` 生命周期（aboutToAppear/onPageShow 返回 Promise）按编译器允许与否调整（可改内部 sync + 尾随 .then）。
- [ ] `setTimeout/setInterval/clearInterval` 返回 `number` 声明已在控制器/预览页/编辑页使用，类型按环境微调。

## C. ArkWeb（feature/eas/webLogin）
- [ ] `WebviewController`：`getUrl()/getCustomUserAgent()/setCustomUserAgent('')/runJavaScript/stopLoading/reload` 方法名与可用性（API12 经 `@kit.ArkWeb`）。
- [ ] UA 语义：SZ 启动即桌面 UA；`setCustomUserAgent('')` 复位默认的行为需真机验证（控制器 revert 分支）。
- [ ] `WebCookieManager.getCookieSync(url)`：域/path 口径、http/https/端口跨域与 Android 不同（笔记 eas-cookie-finish-notes.md B 节），真机校准。
- [ ] Web 组件事件：`onProgressChange((e)=>{e.newprogress})`、`onErrorReceive((e)=>e.error)`、`onPageBegin/End`、`onControllerAttached`、`onAreaChange`（`newValue.width as number`）字段名验证。
- [ ] 明文 `http://` 门户（ivpn/webvpn/eelab）按域网络安全配置放行（README 验证清单 5）。

## D. relationalStore（common/db/RdbHelper.ets）
- [ ] `getRdbStore(context, {name, securityLevel})` 配置；`StoreConfig`/`SecurityLevel` 枚举名。
- [ ] `ValuesBucket` 字面量（对象含 string/number/int-boolean）合法性；boolean 以 0/1 存。
- [ ] `RdbPredicates`：`equalTo/orderByAsc/orderByDesc/in/limitAs/greaterThanOrEqualTo/lessThanOrEqualTo` 链式 AND 语义验证；`delete/insert/update/query` 返回值类型。
- [ ] `ResultSet`：`goToNextRow/getColumnIndex/getString/getLong/getDouble`；`numD()` 用 getDouble 读 REAL 列（学分）。
- [ ] 表名/保留词：events 表列 `from/to` 在 DDL 已反引号；谓词/ResultSet 列名传 'from'/'to' 验证。

## E. 其它 Kit
- [ ] `preferences`（@kit.ArkData）get/put/delete/flush 返回类型（EasSessionStore）。
- [ ] `http`（@kit.NetworkKit）：HttpRequestOptions 字段（method/header/extraData/expectDataType/connectTimeout/readTimeout）与 HttpDataType。
- [ ] `router.pushUrl({url})`、`router.back()`；`promptAction.showDialog/showToast` 回调参数推断（`(ret)=>ret.index`，必要时标 `promptAction.ShowDialogSuccessResponse`）。
- [ ] Canvas：`RenderingContextSettings`（全局声明）与 `CanvasRenderingContext2D`；`textBaseline/font/textAlign/fillText/beginPath/moveTo/lineTo/stroke/strokeRect/fillRect/clearRect`。
- [ ] UI：`Scroll().scrollBar(BarState.Auto)`、`LoadingProgress()`、`Blank()/layoutWeight/alignItems/letterSpacing` 等属性按编译器微调。

## F. 已知设计取舍（非编译问题，真机再校准）
- 课表周视图：比例布局 + 真实分钟轴（08:00–24:00）；圆角/渐变/重复课程合并/ViewPager 手势翻周待做（docs/eas-timetable-view-notes.md 存疑清单）。
- 深圳 terms/scores/课表端点已按安卓版 Web 流程接入；仍需真机验证门户 Cookie、学期选择和响应字段兼容性。
- 威海 VPN 交换、SZ auto-advance 点击脚本、viewport 修补注入 = M0 抓包后按笔记补全。
- 会话 Cookie 加密（HUKS）未做（EasSessionStore.save 明文 JSON，标注 TODO）。

## 静态自检结论（R22–R23 程序化扫描，Node 一次性脚本）
- [x] **导入/导出一致性**：35 源文件全量扫描 ALL OK（曾发现并修复 `feature/timetable/**` 相对深度 `../../`→`../../../` 共 3 处）
- [x] **路由三方一致**：`main_pages.json` 10 页 = pages 目录 @Entry 页 = 全部 `pushUrl` 目标（无孤儿/漏注册）
- [x] **资源引用**：app.json5/module.json5 引用的 media/string/color/profile 全部存在

## 验收最小路径（全部离线）
1. Sync + 编译通过（销 B–E）。
2. 首页：生成本地演示数据 → 时间线(含今日) → ＋新建事件 → 返回自动出现；长按删除。
3. 课表周视图预览：上/下周切换、今日列遮罩、事件块定位。
4. 成绩页：载入样例渲染；无会话提示；真实查询给 EAS 端点提示。
5. 我的：会话展示（登录后）、退出/清除本地。
6. 网页登录（真机）：深圳登录→会话落库→课表/成绩真实请求回归；本部/威海端点仍需补齐。
