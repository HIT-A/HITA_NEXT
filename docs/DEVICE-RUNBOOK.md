# 构建与设备验证

## 构建

在 DevEco Studio 中打开仓库根目录，完成工程同步，并为本机配置签名。
SDK 版本以根目录 `build-profile.json5` 为准。

以下命令在仓库根目录执行，工具路径按本机安装位置调整：

```powershell
$env:NODE_HOME = 'C:\Program Files\nodejs'
$env:DEVECO_SDK_HOME = 'C:\Program Files\Huawei\DevEco Studio\sdk'

& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' `
  --mode module -p product=default assembleHap --no-daemon
```

配置签名后的调试包：

```text
entry/build/default/outputs/default/entry-default-signed.hap
```

发布构建使用 `store` 产品及发布签名，与本地调试签名分开：

```powershell
& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' `
  --mode project -p product=store -p buildMode=release assembleApp --no-daemon
```

发布产物在 `build/outputs/store/`。不要提交本机签名材料、密码或构建产物。

## 自动检查

```powershell
node scripts/static-checks.cjs
$env:NODE_PATH = 'C:\Program Files\Huawei\DevEco Studio\plugins\codelinter\node_modules'
node --test scripts/*.test.cjs
```

回归脚本依赖 TypeScript 转译器，示例使用 DevEco 自带版本。
这些测试不替代 ArkTS 编译和设备验证。

## 设备回归

- 今日、时间表、助手、资讯、更多可以正常切换。
- 未登录且无课表时，今日不显示登录和课表管理按钮。
- 更多保留正常业务入口，不显示本地搜索和开发样例入口。
- 教务登录弹窗可以关闭；登录后会话状态正确更新。
- 导入、选择课表后，今日与时间表显示同一份课表的数据。
- 周切换、课程地点滚动、课程与考试详情正常。
- 手动添加、编辑和删除课程或考试后，列表与时间表正确刷新。
- 「更多 → 课表工具 → 导出至手机日历」导出当前课表；课表详情不显示日历导出按钮。
- 首次允许日历权限后，系统日历出现「HITA · 课表名称」，课程日期、起止时间、地点及教师与课表一致；检查单双周、晚课和考试。
- 重复导出、重新导入教务课表后再导出不会增加重复日程；修改时间或删除部分课程后再导出，旧日程更新，个人日程保留。
- 拒绝日历权限、空课表、无效课程时间和中途写入失败均显示正确提示；重新授权或重试后可恢复导出。
- 更多页面可以滚动到底，公告入口不会被底部导航栏挡住。

设备未连接时只能完成构建及自动检查，应单独记录尚未完成的设备回归项。
签名不一致导致覆盖安装失败时，先核对签名配置，不要为排查问题直接清除用户数据。


## 空教室：安卓移植路径与验收

参考版本为 HITA Android v3.0.0，提交 `a2989d6674b9ddf58ed301c46dd9e94bfd3ab4db`。对应源码：

- `ui/eas/classroom/EmptyClassroomActivity.kt`：三项横向选择器、自动查询、双列教室卡片、状态判断。
- `ui/eas/classroom/EmptyClassroomViewModel.kt`：当前学年筛选、当前学期选择、切换条件后查询。
- `ui/eas/classroom/detail/EmptyClassroomDetailFragment.kt`：底部详情、七天切换、每节时间及占用状态。
- `data/repository/TimetableRepository.kt`：从本地课表取得当前周；无对应课表时第 1 周。
- `data/repository/EASRepository.kt`：先缓存后网络、保留失败前的缓存、180 天清理。
- `data/source/web/eas/{EASWebSource,BenbuEASWebSource,WeihaiEASWebSource,ShenzhenWebAcademicParser,BenbuClassroomParser}.kt`：三校区查询和解析。

### 鸿蒙实现路径

`Home.ets → EmptyClassroomPage.ets → EmptyClassroomService.ets → EasApiClient → EmptyClassroomData.ets → EmptyClassroomDisplay.ets → 页面／底部详情`。

文件均在 `entry/src/main/ets` 内：

1. `pages/Home.ets` 和 `resources/base/profile/main_pages.json` 保留已有入口与路由登记。
2. `pages/EmptyClassroomPage.ets` 复用 `EasSessionStore.loadPreferred()` 读取账号，`EasDataProvider` 读取学期、深圳作息，`RdbHelper` 读取对应校区本地课表周次。选择教学楼／学期／周次即查询；周次选择 1～20；点击卡片显示底部节次表。请求代数保证旧响应不能覆盖新条件或已退出页面。
3. `feature/eas/classroom/EmptyClassroomService.ets` 复用现有带 Cookie 的客户端。深圳使用 `/pksd/queryjxlList`、`/cdkb/querycdzyleftzhou`、`/cdkb/querycdzyrightzhou`，34 位周掩码与安卓相同，并完整读取教室分页。本部／威海使用 `/kjscx/queryJxlListBySjid`、`/kjscx/queryKjs`；本部 `pageXiaoqu` 为空，威海带 WebVPN 参数并适配区域、楼号前导零和两种空教室选择器值。
4. `EmptyClassroomData.ets` 解析深圳 JSON，合并教室与占用数据；本部／威海选最宽的 `dataTable`，末尾 42 格映射为七天、每天六组双节课。
5. `EmptyClassroomDisplay.ets` 对应安卓状态、学期格式、详情行。卡片依据所选周、今天星期和当前节次，显示空闲／被占／将占／未知；详情使用校区作息，显示每节时间。
6. `EmptyClassroomCache.ets` 使用独立 Preferences 保存查询快照，按账号、校区、学期、区域、楼号、周次隔离，不保存登录凭据；先缓存后网络，成功空结果也替换旧缓存，过期快照在写入时清理。

平台适配与明确差异：选择器、网格、底部弹层用 ArkUI，沿用鸿蒙主题与账号入口；失败提示和缓存时间可见。威海不沿用安卓的“空楼号查询所有楼”兜底，以免把其他楼的结果显示在所选楼下。无法识别的占用数据返回错误或未知，不当作空闲。深圳 Web 作息失败时不猜测时间。没有新加校区切换条、名称搜索、节次范围或“仅空闲”筛选。

### 自动检查

在仓库目录运行，按本机 DevEco 路径配置 Node 和 TypeScript：

```powershell
$env:NODE_PATH = 'D:\HITA Harmony\DevEco Studio\plugins\codelinter\node_modules'
& 'D:\HITA Harmony\DevEco Studio\tools\node\node.exe' --test scripts/empty-classroom.test.cjs scripts/production-surface.test.cjs
```

然后执行项目静态检查：

```powershell
& 'D:\HITA Harmony\DevEco Studio\tools\node\node.exe' scripts/static-checks.cjs
```

构建使用本手册前文的 `assembleHap` 步骤或 DevEco 运行按钮。测试执行实际解析、接口参数、页面异步逻辑和缓存逻辑，响应来自合成数据；不代表真实教务接口已验收。

### 用户检查方式

对本部、威海、深圳分别使用对应本科账号，并与安卓 3.0.0／学校教务网站的同一学期、教学楼、周次对照：

- 入口：从「更多 → 空教室」进入；顶部只有教学楼／学期／周次三项选择；有数据时显示双列教室卡片。
- 默认项：当前学期、第一栋楼；已导入同校区同学期课表时周次对应当前周，否则第 1 周。
- 自动查询：分别换楼、换学期、换周，观察加载和结果变化；快速换周时旧请求返回不能覆盖新周。重复选择同一条件不重复请求。
- 状态：核对被占、下一节将占、空闲；详情默认今天，切换周一／周日，核对每节时间、借用和课程占用。旧表格一格占用必须对应两节。
- 详情：确认底部弹层可以滚动到底、切换星期、关闭并打开另一间教室；返回键行为正常；核对深色／浅色、长教室名和文字缩放。
- 缓存：同条件查询成功后断网重试，显示缓存时间及更新失败；换楼或换周不能显示上一条件的缓存。恢复网络查询成功后缓存标记消失，成功空结果不保留旧教室。
- 账号与错误：未登录／过期会话／断网／格式异常须提示错误；登录后返回可重新加载，不能变成“整楼空闲”。切换校区由「更多」中的教务账号完成。

2026-10-10 开发验证：50 项专项和入口回归测试通过，静态检查 70 文件／13 路由通过，ArkTS 编译及调试签名通过。最终调试包已覆盖安装到 HarmonyOS 7 / API 26 模拟器并从真实「更多」入口打开。

深圳实际会话的学期接口现已返回 HTTP 200；已显示 2026–2027 秋季第 6 周 A 楼教室列表。打开 A103，周一显示占用，切回周六显示空闲，能滚动到第 12 节（21:40–22:30）；切换第 7 周自动重新查询，教学楼选择器能切换 F 楼。缓存先显示、网络完成后清除缓存标记的流程已观察。实际检查发现并修正了 ArkUI 构建器初始文字未刷新、详情列表复用上一星期文字的问题。

这些结果证明深圳查询及页面操作已运行，不代表已逐项对照学校网页核实占用准确性。本部、威海只有解析与请求参数测试，仍需对应账号验收；浅色、文字缩放、过期会话恢复也留在人工检查项中。此前 HTTP 405 未在本轮复现。未修改本地签名设置或清除课表数据，未提交或推送代码。
