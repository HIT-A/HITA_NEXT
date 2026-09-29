# M0 抓包记录表（eas-api-capture）— 供回填 HitaNEXT

> 目的：真机抓包后逐行填写，回填代码/配置即可打通「登录→数据」真链路。
> 相关实现位置：
> - 深圳端点：`feature/eas/EasDataProvider.ets` → `EasShenzhenEndpoints.termsPath / scoresPath`
> - 请求入口：`EasApiClient.request(session, cfg, path, opts)`（自动注入 Cookie/UA）
> - 响应解析：`data/ShenzhenWebScores.ets`（parseShenzhenWebScores，1:1 ShenzhenWebScoreParser）
> 工具建议：Charles / mitmproxy（代理 + HTTPS 解密），或 DevEco 预览器抓包；需校园账号登录环境。

## 0. 抓取步骤（深圳，本科）
1. 打开 HitaNEXT → 首页「网页登录」→ 校区=深圳 → 走完统一认证直到进入系统。
2. 打开成绩页点「真实查询」或手动操作教务成绩页，记录下列请求。
3. 另记录「学期列表」请求（首次打开成绩/查询时会请求可用学期）。

## 1. 公共信息
| 项 | 值 |
|---|---|
| 登录后数据基址 webBaseUrl（proxy/direct） | 例 `https://jw-hitsz-edu-cn.hitsz.edu.cn` |
| 会话 Cookie（必要 key） | `JSESSIONID / route / SESSION`（深圳判据用） |
| 默认请求头（UA 等） | 记录 |

## 2. 学期列表接口
| 项 | 值 |
|---|---|
| URL（相对 base 的 path） | ← `EasShenzhenEndpoints.termsPath` 回填 |
| Method / Body | GET? POST? 参数？ |
| 返回 JSON 结构（字段样例） | 例 `content.list[]`？每项 `yearCode/yearName/termCode/termName/isCurrent`？ |
| Cookie 要求 | 与上表一致？ |

## 3. 成绩查询接口（getPersonalScores）
| 项 | 值 |
|---|---|
| URL path | ← `EasShenzhenEndpoints.scoresPath` 回填 |
| Method / Body | 例 POST JSON `{"termCode":"2023-2024-1"}`？或表单？ |
| 返回 JSON 字段 → 模型映射 | `xscj/zzcj/zpcj→finalScores*`、`kcdm→courseCode`、`kcmc→courseName`、`xf→credits`、`xs→hours`、`kcxz/kcxzen→courseProperty`、`kclb/kclben→courseCategory`、`yxmc→schoolName`、`khfs→assessMethod`、`xnxqmc→termName` |
| 响应样例（脱敏贴一段） | |

## 4. 其它预留（后续 M2/功能）
- 课表结构/导入（TimetableStructure）URL 与结构样例；
- 考试接口 URL 与字段（对齐 `EasExamItem`）；
- 空教室（威海另有 webvpn 前缀端点 `kjscx/queryJxlListBySjid` 等）；
- 个人信息（`user/me` 或对应）→ 会话身份字段。

## 5. 填完后的改动
```ts
// EasDataProvider.ets
EasShenzhenEndpoints.termsPath = '从上面复制';   // 例 '/…terms…'
EasShenzhenEndpoints.scoresPath = '…';
// 若请求体/Header 与默认不同，改 EasDataProvider.getPersonalScores / getAllTerms 内 opts
```
然后重新 `assembleHap`，真机验证：登录 → 成绩页「真实查询」列出真实成绩。

## 6. 反编译已知佐证（抓不到时参考）
- 深圳成绩解析字段顺序与兜底（xscj/zzcj/zpcj）见 `ShenzhenWebScoreParser.java`；
- 深圳会话成立判据 `(JSESSIONID ∧ route) ∨ SESSION`（`EASToken$Companion`）；
- 威海/本部 URL 常量全集见 `EasWebLoginConfig.ets`（源自 `CampusUrls.java`）。
