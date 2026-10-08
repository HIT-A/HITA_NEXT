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
