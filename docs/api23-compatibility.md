# API 23 兼容说明

`api23` 分支最低支持 HarmonyOS 6.1.0（API 23）。`default`、`store` 两个产品的
`compatibleSdkVersion` 均为 `6.1.0(23)`；`compileSdkVersion`、`targetSdkVersion`
继续使用 `26.0.0`。API 22 及以下不在支持范围内。

## 底栏与界面

- API 26：保留原生 `BottomTabBarStyle`、`barFloatingStyle`、212vp 宽度、56vp 高度、
  安全区间距、壁纸遮罩规则及原有沉浸光感参数。材质模块通过惰性导入隔离，
  仅在版本判断通过后执行。
- API 23～25：复用同一个 `TabsController`、三页内容和切页动画；隐藏原生底栏，
  以 212×56vp 雾面玻璃底栏覆盖。使用旧版 `backgroundEffect` 模糊、着色、描边和阴影，
  保留安全区间距、选中状态与无障碍标签。
- 图标和文字各自使用 API 11 已提供的 `invert(InvertOptions)` 根据背景灰度动态反色，
  不是仅随深浅色模式切换固定颜色。该反色算法与 API 26 材质的 `colorInvert` 不同，
  目标是接近其可读性与动态效果；不保证逐像素一致。
- 旧底栏的背景遮罩不拦截触摸，三个点击区域驱动原有页签控制器。

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

在 DevEco Studio 中打开 `api23` 所在的工作目录（本机为 `D:\HITA_NEXT`）；
`D:\HITA_NEXT0.2.0` 仍是 `main` 分支。运行时选择 Application / OpenHarmony App
类型的 `entry` 配置，并选择手机或模拟器。若命令中出现
`requiredDeviceType=previewerDebug`，说明预览器目标被带入了应用运行或热重载构建；
重新选择真实设备后普通运行。页面预览使用编辑器的 Previewer。
不要将 `previewerDebug` 添加到 `module.json5` 的 `deviceTypes`。

自动检查包含 API 23～25 不触发 API 26 材质、API 26 参数保持、底栏交互连接、
Cookie 作用域与冲突过滤、读取超时以及现有教务登录回归。编译后的包还应检查
`minAPIVersion` 为 `60100023`（HarmonyOS 6.1.0 / API 23），目标为 `260000026`。

2026-10-08 验证记录：

- 175 项自动回归测试全部通过，静态检查通过。
- `default` 调试 HAP 与 `store` 发布 APP 均构建成功；未报告未处理的 SDK 版本兼容告警。
- 调试 HAP 已覆盖安装到连接的 API 26 手机并成功启动；用户确认未出现显示破坏。
- 尚未连接 API 23～25 设备，旧系统视觉与真实教务登录仍待实机验证。

后续设备回归检查项（API 26 的基础显示已确认，其余按实际覆盖范围验收）：

1. 冷启动，今日/时间表/更多点击与左右切换，课表区域左右滑动仅切换周次。
2. 深浅色、纯色与高对比壁纸下的底栏反色；页面滚动时动态更新；底栏外触摸透传。
3. 横竖屏、平板、底部手势区、登录弹层和键盘弹出时的位置与遮挡。
4. 三校区登录、会话恢复、课表/成绩/考试查询及日历导出；特别检查需要分区 Cookie 的认证环境。
5. API 26 与原分支对照，确认悬浮底栏、材质、反色、遮罩和动画无可见变化。

自动测试和编译通过不能代替设备上的视觉及真实认证验证。
