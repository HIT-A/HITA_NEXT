# DEVICE-RUNBOOK — 编译 → 签名 → 装机 → M0 抓包 单一操作手册

> 适用：HitaNEXT（DevEco 26 / SDK API26）。当前 CLI 编译已通过（unsigned HAP）。
> 环境变量：`NODE_HOME=C:\Program Files\nodejs`；`DEVECO_SDK_HOME=C:\Program Files\Huawei\DevEco Studio\sdk`

## 1. 命令行编译（已通过，可随时重跑）
```bat
"C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat" --mode module -p product=default assembleHap --no-daemon
:: 产物：entry\build\default\outputs\default\entry-default-unsigned.hap
:: 注意：在项目根目录执行；若报 SDK/工具找不到，先设置上表环境变量。
```

## 2. 签名（在 DevEco Studio GUI 完成一次即可，材料会回写 build-profile）
1. DevEco 打开 `C:\heyiwei\HitaNEXT`；
2. File → Project Structure → Signing Configs → 勾选 **Automatically generate signature**（需登录华为账号/真机调试授权）；
3. 保存后 `build-profile.json5` 会写入 `signingConfigs` 与产品 `signingConfig`；
4. 此后命令行 `assembleHap` 会产出 **signed** HAP，或用 GUI Build → Build Hap(s)。

## 3. 连接真机/模拟器
- 真机：开启开发者模式 + USB 调试；确认 `hdc list targets` 显示设备。
- 模拟器：DevEco Device Manager 启动 HarmonyOS 模拟器（登录校园网络）。

## 4. 安装与首跑（真机）
```bat
hdc install -r <signed-hap路径>
hdc shell aa start -a EntryAbility -b cn.berry.hitanext
```
预期路径：
- Home 四 Tab 正常；
- 「我的 → 网页登录（EAS）→ 深圳」弹出 ArkWeb 统一认证，输入校园账号走完登录；
- 返回后「我的」显示会话（cookies/gen/webBaseUrl）；数据已落库（preferences，明文 JSON，加密为二期）。

## 5. M0 抓包（深链路必需）
1. 启动抓包代理（Charles/mitmproxy），设备或模拟器设代理并装根证书；
2. 登录成功后进入 **成绩页 → 查询**（或教务系统内点成绩）；
3. 先验证深圳学期、已选课程、课表 JSON、节次结构和成绩查询请求是否均返回 2xx；如字段变化，再按 `docs/eas-api-capture.md` 记录 URL/Method/Body/返回 JSON；
4. 若接口字段变化，回填 `EasShenzhenEndpoints` 或对应解析器 → 重新编译装机验证「登录→课表/成绩」真链路。

## 6. 常见问题
| 现象 | 处理 |
|---|---|
| install 失败 signature 错 | 未用 signed HAP（第 2 步后重打） |
| 登录页空白/UA 异常 | 深圳 UA 双切换在真机验证（README 清单 3/4） |
| http 明文被拦 | 网络策略按域放行（README 清单 5） |
| 成绩请求失败 | 检查深圳网页登录 Cookie、校园网络和响应 JSON；本部/威海暂未接入同等数据链路 |
| WebView Cookie 采集为空 | `fetchCookieSync` 域口径对照 `eas-cookie-finish-notes.md` B 节 |

## 7. 之后（M2）
威海/本部：configFor 已就位；本科本部走 EELAB token 流、威海走 webvpn；VPN 交换与端点以抓包回填（蓝本 §2.2.6 与笔记 D 节）。
