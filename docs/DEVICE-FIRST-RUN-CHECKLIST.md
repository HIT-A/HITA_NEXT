# DEVICE-FIRST-RUN-CHECKLIST — 装机后请逐项核对并回传

> 目的：一次真机首跑尽量带回“能让我继续联调”的所有信息（日志/会话摘要/抓包）。
> 前置：已完成签名装机并启动 App（见 DEVICE-RUNBOOK.md）。

## 1. 首屏（Home）
- [ ] 四 Tab（时间线/课表/成绩/我的）正常切换，无白屏/崩溃
- [ ] 「课表」Tab 点「生成本地演示数据」→ toast 成功
- [ ] 「时间线」出现演示日程；点条目可进编辑页

## 2. 网页登录（核心）
- [ ] 「我的 → 网页登录（EAS）」出现深圳统一认证页（若 UA 异常：截图）
- [ ] 输入校园账号登录，走完（可能出现的）二次验证 → 自动返回
- [ ] 「我的」页会话卡出现形如：`会话：SHENZHEN（N cookies）`，并能看到 `gen=1` 与 `base=…`

## 3. 需要回传的信息（最重要）
A. **我的页截图或文本**：会话摘要全部文字（含 webBaseUrl、cookie 数、gen）。
B. **抓包两请求**（Charles/mitm，见 eas-api-capture.md）：
   1) 学期列表：`URL`、`Method`、`Request Body`、`Response JSON（脱敏前几行）`
   2) 成绩查询：同上（尤其确认 termCode 参数名与 JSON 里成绩字段）
C. 若“真实查询”报错：把 ScorePage 红字完整文案发我（如 `EAS_SCORES_ENDPOINT_NOT_CAPTURED…`）。

## 4. 常见预期
| 页面 | 预期 |
|---|---|
| 首页/自检 | 「离线解析自检」输出 `code=0 … count=3` 及样例行 |
| 时间线 | 演示今日事件（含「交课程设计」等） |
| 周视图 | 课程块按时间轴显示（08:00–24:00），可上/下周滑动 |
| 我的-备份 | 导出 JSON / ICS 到沙箱成功（toast 字节数） |

## 5. 回传模板（粘贴即可）
```
会话：<粘贴“我的”页摘要文本>
学期请求：
  URL: 
  Method/Body: 
  返回: 
成绩请求：
  URL: 
  Method/Body: 
  返回: 
ScorePage 报错（若有）: 
截图/日志附件: 
```
收到后我将回填 `EasShenzhenEndpoints` 并给出下一个可安装包。
