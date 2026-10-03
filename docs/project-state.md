# HitaNEXT 工程状态总览（深圳链路接入快照 · 等待真机回归）

> 目标：把 HITA_X 功能 + 新版 HITA 登录整合移植为 HarmonyOS NEXT（ArkTS/ArkUI/ArkWeb），
> 以 `HITA/.analysis`（HITA_X-master 源码 + 新版 APK 反编译）为高保真基准。
>
> ✅ **DevEco 26（SDK API26）命令行构建通过**：`hvigorw --mode module -p product=default assembleHap`
> （产物 `entry/build/default/outputs/default/entry-default-unsigned.hap`；编译 0 error）。
> 静态回归：`node scripts/static-checks.cjs`（**ALL OK：35 源文件 / 12 路由**）。

## 编译记录（DevEco CLI 环境变量）
- `NODE_HOME=C:\Program Files\nodejs`；`DEVECO_SDK_HOME=C:\Program Files\Huawei\DevEco Studio\sdk`
- 调用：`"...\DevEco Studio\tools\hvigor\bin\hvigorw.bat" --mode module -p product=default assembleHap --no-daemon`
- 说明：工程 `hvigor-config.json5` 仍为 `modelVersion 5.0.0`/`compatibleSdkVersion 5.0.0(12)`，
  实际由 SDK26 工具链编译通过（wrapper 缓存 `@ohos/hvigor-ohos-plugin 6.26.4`）。
- 产物为 **unsigned**（未配置 signingConfig）：真机安装需在 DevEco 配置自动签名后重新打包。
- **WARN 收敛（R41–R47）**：迁移废弃 API 至 UIContext（`getRouter()`/`getPromptAction()`/`getHostContext()`）；
  `getCookie`→`fetchCookieSync`；RdbHelper/SessionStore/Controller/runJs 全量 try/catch 安全化后，
  deprecation 清零，`may throw` 余 **11**（页面级 UIKit/fileIo 调用，信息性非阻断）。
- UI 精化（R46–47）：Home 今日条目点击直达编辑（AddEvent 预填）。
- 曾发生：PowerShell 默认编码写 .ets 造成 UTF-8 损坏 → 已整文件重写恢复（后续一律显式 UTF-8 无 BOM 读写）。

## 代码布局（entry/src/main/ets）
- 入口：`entryability/EntryAbility` → 首屏 `pages/Home`（3-Tab：今日/课表/我的；成绩与考试从“我的”进入）
- 页面（13 路由）：Home、TimetablePreview、TimeLinePage、AddEventPage、ScorePage、ExamPage、SubjectsPage、SearchPage、ProfilePage、AboutPage、TimetableManagerPage、TimetableDetailPage、ImportTimetablePage
- EAS 登录核心：`feature/eas/webLogin/*`（EasSession 模型、CampusConfig、谓词、Controller、MfaBridge、EasLoginPage）+ `EasSessionStore/EasApiClient/EasDataProvider`
- 数据模型/解析：`feature/eas/model|data`（深圳成绩与网页登录课表 JSON 解析+样例）、`common/model/timetable`（课表域）、`common/util`（时间工具/ICS）、`common/db`（relationalStore 三表）
- 视图：`feature/timetable/views/TimetableWeekDraw`（Canvas：真实分钟轴/圆角块/今日遮罩/手势切周）

## 离线可用功能（演示/自检闭环）
- 生成本地演示数据（课表/科目/今日+明日事件，RDB 写读校验）
- 课表周视图（手势/按钮切周、ICS 导出）、科目管理（换色/级联删）
- 今日时间线：列表/新建/编辑（预填）/删除/返回自动刷新
- 成绩页（样例离线渲染 + 深圳真实请求适配）、考试页（本地 EXAM/样例）、本地搜索（教师/地点）
- 我的：会话总览/退出/清库/**JSON 备份导出⇄恢复**/关于
- 开发自检：深圳样例解析、Probe 谓词（Node 镜像验证 12/12）、周数学（Node 验证）

## 待办（按优先级；多数为外部环境依赖）
1. DevEco 配置当前自动签名并安装签名产物。
2. 深圳真机回归：门户登录 Cookie、学期/已选课程、JSON 课表、节次结构、成绩请求。
3. M2：威海/本部登录收尾、分校区数据端点、失效重登验证。
4. 周视图重复课程合并/ViewPager 手感精化；事件“课时段/周次”语义。
5. 会话 Cookie HUKS 加密（§4.4）；深色/主题资源；服务卡片（今日，二期）。
6. 与新版作者沟通登录源码授权（蓝本 §9-5）。

## 已知取舍（DevEco/真机再校准）
- ArkWeb UA/Cookie 域口径、`setCustomUserAgent('')` 复位、onProgressChange 字段等：README 验证清单 1–7。
- `fileIo.readTextSync`、relationalStore API 面、promptAction 回调参数推断：checklist E 项。
- Canvas 圆角用 quadraticCurveTo 拼角（不依赖 roundRect）。
