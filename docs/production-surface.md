# 应用内开发入口清理

## 范围

- 今日、时间表和本地搜索不再提供演示数据生成入口。
- 无课表时提供教务登录/导入及课表管理入口，未登录会打开现有登录弹窗。
  手动创建和 ICS 导入保持可用。
- 按要求保留空教室入口及当前尚未开放提示，暂不实现查询功能。
- 移除已无导航引用的旧周视图预览、时间线、科目管理和会话调试页及路由。
  日常课程编辑、科目管理和会话管理继续使用现有课表详情页及弹窗。
- 样例课表生成器和解析器自检数据不再进入应用源码；解析回归数据保留在
  `scripts/production-surface.test.cjs`，不打包到 HAP。
- 新建课程使用明确指定或当前选择的课表，不再自动附加到旧样例课表。
- 旧版已保存的数据不自动删除；自动课表选择不再回退到旧样例记录，
  用户仍可在课表管理中查看、选择或删除这些记录。

## 公告

仓库根目录的 `notices.json` 已移除示例公告。应用的公告地址仍由
`AppNoticeCenter.ets` 中的 `NOTICES_URL` 配置，目前指向独立的 Gitee 公告源。
本次没有修改该外部仓库，也不会覆盖其中的正式公告。

## 验证

```powershell
node scripts/static-checks.cjs
node --test scripts/production-surface.test.cjs
```

回归脚本使用 TypeScript 转译实际 ArkTS 纯逻辑模块。在安装 DevEco 的电脑上，
可将 `NODE_PATH` 指向 DevEco 的 `plugins/codelinter/node_modules`，无需向应用
添加运行时依赖。UI 和平台调用仍需通过 DevEco 的 `assembleHap` 编译验证。

设备回归：首次安装无课表、未登录导入、手动新建并添加课程、切换已有课表、
本地搜索无结果。历史迁移文档中的“生成演示数据”等验收步骤不再适用。
