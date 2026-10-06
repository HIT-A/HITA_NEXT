# 深色模式

入口：更多 → 设置 → 深色模式。设置行显示当前模式，点击后右侧箭头转向下方，展开「开启」「关闭」「跟随系统」三个等宽单选项，再次点击可收起。默认跟随系统，选择后立即生效并保存在本机。

## 实现范围

- 今日、时间表、更多及其子页面使用同名的 `base/element/color.json` 和 `dark/element/color.json` 资源。
- `AppearanceStore` 统一管理偏好、应用颜色模式和沉浸式系统栏。主题切换不修改课表、登录会话或系统设置。
- 在主窗口 `loadContent` 成功后调用 `ApplicationContext.setColorMode`；跟随系统使用 `COLOR_MODE_NOT_SET`，由 `onConfigurationUpdate` 更新有效模式。
- 时间表 Canvas 监听有效模式并重绘背景、网格及文字。课程配色不变，自选壁纸和字体色不被覆盖；无壁纸时默认文字随主题适配。
- 顶部渐隐遮罩、底栏材质遮罩、课程详情与编辑弹窗一并适配。
- 内置浏览器跟随应用主题。教务认证页关闭强制反色，避免影响验证码和第三方认证样式；不支持深色样式的教务网页可能保持浅色。

## 华为官方参考

- [应用深浅色适配](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-dark-light-color-adaptation)：颜色限定词资源、模式监听及应用主动设置。
- [ApplicationContext](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-inner-application-applicationcontext)：`setColorMode` 参数和调用时机。
- [Web 深色模式适配](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/web-set-dark-mode)：`darkMode`、`forceDarkAccess` 与网页背景色。

实现使用项目现有 SDK 支持的接口，没有增加权限、依赖或最低系统版本要求。

## 验证

自动测试包含：

- 三档映射、默认模式、偏好恢复和非法旧值回退。
- 跟随系统的运行时变化，以及固定模式不受系统变化影响。
- 设置保存失败回滚、并发写入保护、透明系统栏及文字颜色。
- 深浅资源完整性、深色文字对比度、课表几何与课程配色保持不变。
- 自选课表壁纸、标题字体色和教室滚动显示不受主题切换影响。

设备验收步骤：

1. 在系统浅色下选择「开启」，检查今日、时间表、更多、详情弹窗和课程编辑。
2. 重启应用，确认仍为深色；选择「关闭」并重启，确认仍为浅色。
3. 选择「跟随系统」，在系统设置中切换深浅色，确认返回应用后立即更新。
4. 在固定模式下修改系统主题，确认应用保持原选择；再选「跟随系统」确认正确恢复。
5. 检查课表壁纸、默认及自定义字体色、日期栏、状态栏和底部手势条。

自动测试运行：安装项目所用 TypeScript 后执行 `node --test scripts/*.test.cjs`；
完整 ArkTS 编译使用 DevEco Studio 的 `assembleHap`。
