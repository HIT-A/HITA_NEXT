# 构建与设备验证

## 构建

在 DevEco Studio 中打开仓库根目录，完成工程同步，并为本机配置签名。
SDK 版本以根目录 `build-profile.json5` 为准。
当前编译 / 目标 SDK 为 26.0.0，最低运行系统为 HarmonyOS 6.1.0（API 23）。

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

发布构建使用本机正式签名配置，与本地调试签名分开。下例的 `online` 为本机正式签名名称：

```powershell
.\scripts\build-agc-store-app.ps1 -SigningConfig online
```

上传文件为 `build/outputs/default/HITA-NEXT-0.2.0-AGC-signed.app`。脚本会核验内外签名和最低系统版本，不要误用只签外层的 `*-signed.app`。不要提交本机签名材料、密码或构建产物。

## 自动检查

```powershell
node scripts/static-checks.cjs
$env:NODE_PATH = 'C:\Program Files\Huawei\DevEco Studio\plugins\codelinter\node_modules'
node --test scripts/*.test.cjs
```

回归脚本依赖 TypeScript 转译器，示例使用 DevEco 自带版本。
这些测试不替代 ArkTS 编译和设备验证。

## 设备回归

- 分别在 HarmonyOS 6.1（API 23）与 API 26 及以上系统执行以下项目；模拟测试不能代替这一步。
- 今日、时间表、更多可以正常切换，助手和资讯可从更多进入。
- API 23 使用紧凑胶囊导航栏，API 26 及以上使用原生悬浮栏；选中指示、左右切换、深色模式正常，导航周围及系统手势栏区域不截断课表。
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
