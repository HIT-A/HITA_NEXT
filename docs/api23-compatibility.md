# API 23 兼容说明

当前 `main` 与 `api23` 版本最低支持 HarmonyOS 6.1.0（API 23）。`default`、`store` 两个产品的
`compatibleSdkVersion` 均为 `6.1.0(23)`；`compileSdkVersion`、`targetSdkVersion`
继续使用 `26.0.0`。API 22 及以下不在支持范围内。

## 底栏与界面

- API 26：保留原生 `BottomTabBarStyle`、`barFloatingStyle`、212vp 宽度、56vp 高度、
  安全区间距、壁纸遮罩规则及原有沉浸光感参数。材质模块通过惰性导入隔离，
  仅在版本判断通过后执行。
- API 26 的原生 Dock 材质设置 `interactive: true`，启用系统交互形变，同时保留
  `lightEffect: { color: Color.White }` 的光感反馈。实现遵循官方
  [内容区域组件适配](https://developer.huawei.com/consumer/cn/doc/doccenter-advanced-features/bpta-spatiality-immersive#section125241657204516)
  及 [ImmersiveMaterial 的交互形变示例](https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/arkts-apis-uimaterial)。
  继续通过 `barFloatingStyle.systemMaterial` 应用到原生 TabBar；API 23～25 的雾面 Dock 不使用该效果。
- API 23～25：复用同一个 `TabsController`、三页内容和切页动画；隐藏原生底栏，
  以 212×56vp 雾面玻璃底栏覆盖。使用旧版 `backgroundEffect` 模糊、着色和描边，
  保留安全区间距、选中状态与无障碍标签。
- 图标和文字使用 API 11 已提供的 `blendMode(DIFFERENCE, OFFSCREEN)` 按绘制轮廓
  与背景混合反色，避免 `invert(InvertOptions)` 在 API 23 上将整个文字/图标矩形填黑。
  不是仅随深浅色模式切换固定颜色。该反色算法与 API 26 材质的 `colorInvert` 不同，
  目标是接近其可读性与动态效果；不保证逐像素一致。
- 原生底栏高度直接按版本设置，避免声明式属性与 modifier 中的高度冲突。旧底栏为
  Tabs 的同级组件，不使用会拦截整页输入的 Tabs overlay。胶囊内消费点击，胶囊外触摸透传。
- API 23 与 API 26 共用手势分流：日期行底边以实际布局坐标测量，按触摸起点固定归属。
  日期行上方由原生 Tabs 跟手切换相邻页面；下方仅切周次，明确拒绝原生水平切页手势，
  保留垂直滚动。手指跨过日期行、快速甩动或周数到达边界，都不会改变这次拖动的归属。
- Dock 只通过点击切页。除拒绝原生横向拖动/滑动识别外，`onContentWillChange`
  会拦截 Dock 触摸产生的自动切页请求；仅完成点击校验的 `TabsController` 调用可切页。
  触摸最大位移及帧内历史点用于取消拖动后的点击，滑出 Dock 或滑回起点不会恢复点击资格。
  API 26 悬浮底栏可能先回调索引 0，再回调实际点击项；同一次事件只执行最后的点击请求，
  避免任意图标都回到第一页。API 23～25 的独立 Dock 保持现有布局、材质与点击方式。

## 教务 Cookie

API 26 保留普通 Cookie 与 `fetchCookie(url, false, true)` 的并行读取和原有合并规则。

API 23～25 使用普通 `fetchCookie(url)`，并尝试通过 API 23 的
`fetchAllCookies(false)` 补充当前顶层页面同主机下遗漏的 Cookie。补充读取：

- 异步执行，3 秒超时；失败或超时仍保留普通 Cookie。
- 检查域名边界、区分大小写的路径、Secure 和有效期。
- 保留 HttpOnly Cookie，普通 URL 定向读取的结果优先。
- 不对其他主机的探针执行补充，不猜测同名 Cookie 的冲突值，不记录 Cookie 值。

API 23 的 `WebHttpCookie` 没有分区键字段，也没有保证枚举接口一定返回所有分区 Cookie。
因此该补充可恢复旧接口实际暴露的条目，但无法完整复现 API 26 的“按当前分区读取”语义。
若旧版 ArkWeb 根本没有暴露目标条目，应用无法用旧 API 强行读取；不得声称已完全等价。

## 验证

本机主工程为 `D:\HITA_NEXT0.2.0`（`main`），已用 `D:\HITA_NEXT` 的 `api23` 完整版本更新；
两个工作目录在此次替换完成时对应同一提交，主工程也已最低兼容 API 23。
在 DevEco Studio 中打开主工程并同步构建配置。运行时选择 Application / OpenHarmony App
类型的 `entry` 配置，并选择手机或模拟器。若命令中出现
`requiredDeviceType=previewerDebug`，说明预览器目标被带入了应用运行或热重载构建；
重新选择真实设备后普通运行。页面预览使用编辑器的 Previewer。
不要将 `previewerDebug` 添加到 `module.json5` 的 `deviceTypes`。

自动检查包含 API 23～25 不触发 API 26 材质、API 26 参数保持、底栏交互连接、
Cookie 作用域与冲突过滤、读取超时以及现有教务登录回归。编译后的包还应检查
`minAPIVersion` 为 `60100023`（HarmonyOS 6.1.0 / API 23），目标为 `260000026`。

2026-10-08 验证记录：

- 176 项自动回归测试全部通过，静态检查通过，包含手势归属和原生水平/垂直手势分流。
- `default` 调试 HAP 与 `store` 发布 APP 均构建成功；未报告未处理的 SDK 版本兼容告警。
- 调试 HAP 已覆盖安装到连接的 API 26 手机并成功启动；用户确认未出现显示破坏。
- API 23 虚拟机已覆盖安装并启动。已验证只保留一个底栏、图标文字恢复轮廓、
  底栏点击、更多页上下滚动、底栏两侧触摸透传以及页面内设置项点击。
- API 23 带课表验证：按住顶部拖动未松手时相邻页面已经可见，左右释放后分别进入
  今日/更多，周数不变；下方左右拖动仅切周次。短滑、快速左右甩动、斜滑、
  从下方向上跨日期行、日期行紧下方拖动，均未切到相邻页。
- 用户反馈旧系统 Dock 仍有黑影，已按要求撤回后续分层裁剪、标准模糊与渐变试改，
  当前保留初次可用的雾面底栏并去除显式投影。黑影的最终视觉验收仍未完成。
- API 26 手机在本轮手势修复验证时已断开；此前显示确认有效，本轮跟手切页仍需
  API 26 实机复验。API 24/25、不同壁纸，以及完整教务认证流程未完成设备验收。

后续设备回归检查项（API 26 的基础显示已确认，其余按实际覆盖范围验收）：

1. 冷启动，今日/时间表/更多点击与左右切换，课表区域左右滑动仅切换周次。
2. 深浅色、纯色与高对比壁纸下的底栏反色；页面滚动时动态更新；底栏外触摸透传。
3. 横竖屏、平板、底部手势区、登录弹层和键盘弹出时的位置与遮挡。
4. 三校区登录、会话恢复、课表/成绩/考试查询及日历导出；特别检查需要分区 Cookie 的认证环境。
5. API 26 与原分支对照，确认悬浮底栏、材质、反色、遮罩和动画无可见变化。

自动测试和编译通过不能代替设备上的视觉及真实认证验证。

2026-10-09 Dock 点击修复：

- 192 项自动回归测试、静态检查通过；新增覆盖重复点击回调、拖动后回到起点、
  帧内合并触摸、多指、取消触摸，以及下一次内容区触摸恢复正常切页。
- API 23 模拟器验证三个图标点击与 Dock 内长短滑动、滑出 Dock 后松手；用户确认
  API 23 Dock 问题已解决，本次未调整其外观。
- API 26 手机日志复现同一次点击先返回 0、再返回实际图标索引；修复版已覆盖安装，
  用户实际测试并确认三个图标点击切页恢复正常。临时触摸诊断日志已移除。

## 2026-10-10 性能优化与向前兼容评估

本轮工程为 `C:\heyiwei\HITA_NEXT-0.2.0`。最低版本仍为 API 23，
没有改动 `default`、`store` 的最低版本，也没有部署到手机或推送仓库。

### 已优化

- API 23～25 底栏把三个图标、三段文字的六处离屏反色合并为一个前景层。
  选中底色独立绘制，不参与反色；212×56vp 尺寸、背景模糊、透明度、安全区、
  壁纸透出规则保持不变。选中提示改为同一底色胶囊的平移动画。
- 普通内容滚动不再为底栏校验读取触摸历史；已判定为拖动的底栏手势也不再重复读取。
  多指、取消、抬手和拖回原位不能切页的规则保留。
- 切换主页时暂停教室跑马灯，动画结束后恢复；取消滑动回到原页也能恢复。
  不在不可见页面继续提交跑马灯帧。
- 返回时间表复用现有画布；移除每 15 秒无条件整表重绘和仅位置变化引起的重绘。
  数据刷新、跨日、周次、尺寸、主题、壁纸、字体颜色变化仍触发重绘。
- 校区显示统一为“本部”，威海、深圳和内部 `BENBU` 标识不变。

235 项自动测试和静态检查通过，`default` 调试 HAP 编译、签名通过。
编译仍有原有的 API 能力、弃用接口和异常处理告警，不能视为零告警发布验证。
本轮连接的设备为 API 26，未完成 API 23 真机帧耗时和新底栏视觉验收，
因此以上为减少重复工作的代码优化，不代表已测得具体 FPS 增幅。

### 更早版本的主要限制

核对依据为本机华为官方 SDK `26.0.0.105` 的接口声明和设备版本表。
官网检索未取得可用正文，本轮未依赖第三方文章判断接口最低版本。
以下是重点调用链检查，不是对全部接口、资源和机型的完整兼容认证。

| 当前调用或行为 | SDK 声明/差异 | 更早版本所需工作 |
| --- | --- | --- |
| `LegacyCookieReader` 的 `WebCookieManager.fetchAllCookies(false)` | API 23 | API 20～22 只能先回退 URL 定向读取；必须验证三校区认证，尤其是原来依靠补充读取才能获取的 Cookie。不可承诺登录效果等价。 |
| `EasLoginPage` 的 `Web.onLoadFinished` | API 20 | API 18～19 需要组合旧页面回调与实际 URL 检查，覆盖重定向、页内跳转和超时，不能简单删除这一回调。 |
| `Home` 中通用组件的 `ignoreLayoutSafeArea` | API 20 | API 18～19 需改为旧安全区布局方案，并复测底部手势区和键盘避让。不要与 API 12 的 Navigation 同名接口混淆。 |
| 日历 `getEvents()` 的默认返回字段 | API 20 起默认包含 `identifier` | API 18～19 需明确查询字段并验证旧重载，否则重复导出可能无法识别已有日程。 |
| `deviceInfo.apiAvailable` 版本检查 | 当前编译器生成 `__mockApiAvailable` 兼容函数 | 已检查构建缓存，当前不是直接在旧系统调用 API 26 方法；降低最低版本后仍需核对编译产物。 |
| API 26 原生底栏材质 | 惰性导入且受版本判断保护 | 旧系统继续使用兼容底栏，不需强行复刻新系统材质接口。 |

可复核的 SDK 文件，前四项位于 DevEco Studio 的 `sdk/default/openharmony/ets`：

- `api/@ohos.web.webview.d.ts`：`fetchAllCookies`，标注 `@since 23`。
- `component/web.d.ts`：`onLoadFinished`，标注 `@since 20`。
- `component/common.d.ts`：`CommonMethod.ignoreLayoutSafeArea`，标注 `@since 20`。
- `api/@ohos.calendarManager.d.ts`：`getEvents` 默认字段在 API 20 的变化说明。
- `sdk/default/hms/ets/api/device-define/api-version/ArkWeb.json`、
  `ArkUI.json`：用于交叉核对手机支持的 API 版本。

建议先单独验证 API 20～22：增加 Cookie 降级分支、降低测试产品的最低版本、
编译检查、旧设备覆盖安装，以及三校区登录/重新登录/课表/成绩/考试/日历回归。
通过后再考虑作为正式最低版本。API 18～19 理论上可继续适配，但改动和回归范围
明显更大；更早 API 尚未完成审计，不应仅修改版本号后对外宣称兼容。
