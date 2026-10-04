<p align="center">
  <img src="AppScope/resources/base/media/app_icon.png" width="128" alt="HITA NEXT 图标">
</p>

# HITA NEXT

HITA NEXT 是基于开源项目 [HITA Android](https://github.com/HIT-A/HITA_Android) 开发的 HarmonyOS NEXT 客户端，采用 ArkTS 与 ArkUI 原生实现，为哈尔滨工业大学一校三区学生提供课表查看、教务登录和本地学习信息管理功能。

项目在功能逻辑上参考 HITA Android，在界面结构与交互体验上同时参考 [HITA Aura](https://github.com/HIT-A/HITA-Aura)，尽量保持不同平台之间一致的使用习惯。

## 核心功能

### 今日

- 显示当前日期、星期和教学周。
- 展示正在进行或即将开始的课程。
- 显示下一节课的时间、地点和倒计时。
- 按时间顺序展示当天全部课程及完成状态。

### 时间表

- 按周查看当前学期课程表。
- 显示周数、校区、学期、星期和日期。
- 支持左右滑动切换周次，并带有页面切换动画。
- 课程按照真实开始时间和持续时间绘制。
- 默认显示约 08:00–19:00，晚间课程可继续向下滚动查看。
- 显示课程名称、地点以及不同课程对应的颜色。

### 教务

- 提供深圳、本部和威海校区的 ArkWeb 网页登录入口。
- 保存登录会话，并在再次启动应用时恢复当前登录状态。
- 支持深圳、威海和本部本科生课表导入。
- 自动获取当前学期，将课程、科目和每周课次写入本地数据库。
- 支持使用深圳校区教务会话查询成绩。

### 更多

- 查看当前账号、校区和会话状态。
- 按校区管理会话并退出登录。
- 管理课表、手动添加课程，以及导入和导出 ICS 课表。
- 查看版本更新、服务与故障公告。

## 技术基线

- UI：ArkUI 声明式界面。
- 开发语言：ArkTS。
- 网页登录：ArkWeb。
- 网络访问：HarmonyOS NetworkKit。
- 本地课表：RelationalStore 关系型数据库。
- 会话与轻量配置：Preferences。
- 目标平台：HarmonyOS NEXT，模块声明支持 phone、tablet 和 2in1 设备。
- 当前兼容 SDK：26.0.0。

教务数据流：

```text
ArkUI 页面 -> EasDataProvider -> EasApiClient -> 校区教务系统
```

课表导入与本地展示数据流：

```text
教务会话 -> EasTimetableImporter -> RdbHelper -> 今日 / 时间表
```

## 关键结构

```text
HitaNEXT/
├── AppScope/                         # 应用级名称、图标与配置
├── entry/
│   └── src/main/
│       ├── ets/
│       │   ├── entryability/         # EntryAbility 应用入口
│       │   ├── pages/                # 今日、时间表、更多及功能页面
│       │   ├── feature/eas/          # 登录、会话、教务请求与课表导入
│       │   ├── feature/timetable/    # 周课表绘制、课表选择与 ICS 导入
│       │   └── common/               # 数据库、模型与通用工具
│       └── resources/                # 字符串、颜色、图标等资源
├── docs/                             # 迁移记录、接口笔记与设备调试文档
├── scripts/                          # 静态检查脚本
├── build-profile.json5
└── hvigorfile.ts
```

主要入口：

- `entry/src/main/ets/pages/Home.ets`：今日、时间表、更多三个主页面。
- `entry/src/main/ets/feature/eas/webLogin/`：ArkWeb 登录和 Cookie 会话采集。
- `entry/src/main/ets/feature/eas/EasDataProvider.ets`：深圳、本部本科与威海课表数据适配；真实成绩目前仅支持深圳。
- `entry/src/main/ets/feature/eas/EasTimetableImporter.ets`：远端课程到本地课表的转换与写入。
- `entry/src/main/ets/feature/timetable/views/TimetableWeekDraw.ets`：周课表网格及课程卡片绘制。
- `entry/src/main/ets/common/db/RdbHelper.ets`：本地课表、科目和事件数据库。

## 开发与构建

### 环境要求

- DevEco Studio 5.0 或更新版本。
- HarmonyOS NEXT SDK 5.0.0（API 12）或兼容版本。
- 用于运行辅助脚本的 Node.js 环境。

### 使用 DevEco Studio

1. 克隆仓库：

   ```bash
   git clone https://github.com/samerberry/HITA_NEXT.git
   ```

2. 使用 DevEco Studio 打开仓库根目录并等待工程同步完成。
3. 在 `File > Project Structure > Signing Configs` 中为本机重新配置自动签名。
4. 选择 `entry` 模块并执行 Build 或 Run。

签名配置包含设备和开发者相关材料，不同电脑需要使用自己的证书与 Profile，不能直接复用其他开发环境中的签名文件。

### 命令行构建

在 Windows PowerShell 中进入仓库根目录：

```powershell
$env:NODE_HOME = 'C:\Program Files\nodejs'
$env:DEVECO_SDK_HOME = 'C:\Program Files\Huawei\DevEco Studio\sdk'

& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' `
  --mode module -p product=default assembleHap --no-daemon
```

构建产物位于：

```text
entry/build/default/outputs/default/
```

配置签名后通常生成 `entry-default-signed.hap`。仓库中的 `install_and_run.bat` 可用于构建、检测 HDC 设备并安装已签名 HAP。

### 静态检查

```bash
node scripts/static-checks.cjs
```

## 数据与隐私

- 教务登录和数据请求直接访问哈尔滨工业大学各校区的统一认证及教务系统。
- 登录后的 Cookie 和会话信息当前保存在应用本地 Preferences 中，尚未接入 HUKS 加密，用于恢复登录状态和请求教务数据。
- 本地备份包含课表、科目和事件信息，请妥善保管，不要公开分享。
- 校方页面、认证方式或接口发生变化时，相关功能可能需要同步适配。

本项目不是哈尔滨工业大学官方应用。教务数据的所有权与使用规则以学校相关规定为准。

## 致谢

- [HITA Android](https://github.com/HIT-A/HITA_Android)：主要功能逻辑、数据结构和 Android 端交互参考。
- [HITA Aura](https://github.com/HIT-A/HITA-Aura)：iOS 端界面布局和跨平台体验参考。
- HITA 系列项目的开发者与贡献者。

## 授权状态

本仓库当前未附带正式的 `LICENSE` 文件。除非后续另行声明，当前代码与文档默认保留全部权利，不授予再分发、商用、二次上架或衍生发布许可。
