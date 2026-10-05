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
- 更多页面可以滚动到底，公告入口不会被底部导航栏挡住。

设备未连接时只能完成构建及自动检查，应单独记录尚未完成的设备回归项。
签名不一致导致覆盖安装失败时，先核对签名配置，不要为排查问题直接清除用户数据。
