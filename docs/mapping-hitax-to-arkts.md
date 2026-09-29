# HITA_X（Android/Kotlin）→ HarmonyOS NEXT（ArkTS）逐文件映射文档

> 基线：`.analysis/HITA_X-master/`（346 个 .kt，其中生产代码 336 个 + 测试 10 个，6 模块：app(hitax)/component/style/sync/theta/user）
> 配套蓝本：`HITA_X_新版登录_鸿蒙NEXT整合实现蓝本.md`（本表是对其 §2.1「功能地图/处置表」的逐文件细化）
> 目标工程：`C:\heyiwei\HitaNEXT\`（单 entry 模块，`entry/src/main/ets/` 下按 feature 目录组织）

---

## 0. 总览与统计（≤50 行）

**覆盖口径**：每个 HITA_X 生产源文件一行（或同处置同去向合并行，注明文件数）；测试文件 10 个统一裁剪。

| 统计项 | 数值 | 说明 |
|---|---|---|
| 源码 .kt 总数 | 346 | 6 模块全部计入（蓝本口径一致） |
| 生产代码文件 | 336 | app/hitax=180；component=10；style=35；sync=10；theta=77；user=24 |
| 测试文件 | 10 | app 2 + style/sync/theta/user 各 2，全部裁剪 |
| 映射表格行覆盖 | 252 行（文件级全量：346 个文件，合并行注明文件数） | 见各 ### 小节 |
| 裁剪（默认不做） | 200 文件 / 57.8%（含 10 测试；生产 190/336=56.5%） | θ社区 77 + 自有账号/云端 user 大部分 + sync 10 + style 35 + UI 基座/Compose 遗留/死代码等 |
| 弃用（被新版替换） | 4 | 旧 jsoup 登录链 EASource 及其调起 UI（PopUpLoginEAS/LoginEASViewModel/LoginTrigger） |
| 合并 | 18 | EASToken 模型→EasSession、repo→store/feature 数据层、双 today 小组件等 |
| 直接迁移（移植） | 23 | 纯数据模型/纯算法/纯工具（TimeTools/ColorTools/TextTools/Snowflake 等） |
| 重写（ArkUI/ArkTS 语义重做） | 101 | 登录由 webLogin 全新实现；数据层由 JSON+Cookie 会话重做；其余 UI 按 ArkUI 重写 |
| 裁剪+弃用合计（不进入交付） | 204 / 59.0% | 交付侧=直接迁移+合并+重写 142 / 41.0% |

**P0 / P1 / P2 归类（对齐蓝本 §5，括号内为关键文件集）**：

- **P0（先做，骨架+登录+数据闭环）**：webLogin 登录子系统（EasLoginPage/EasWebLoginController/EasWebLoginConfig/EasWebLoginProbe/EasWebMfaBridge/EasSession/EasSessionStore/EasApiClient——由新版逆向规格**新写**，非 HITA_X 文件）；EAS 数据客户端与成绩页（EasApiClient.ets 对接 CourseScoreItem/TermItem/ExamItem 模型）；课表查看（TimeTableView 等 Canvas 重写）；课表导入（EASRepository.startImportTimetableOfTerm → TimetableImportService）；本地 RDB 三表（AppDatabase/DAO/Timetable 模型族）。
- **P1（核心功能补齐）**：时间线（ui/main/timeline）、事件编辑（ui/event）、考试（ui/eas/exam）、空教室（ui/eas/classroom）、教师/课程/搜索（ui/search、ui/teacher、ui/subject、ui/timetable/detail+manager）、主题/深色（ui/theme 色彩值参考）。
- **P2（打磨）**：新闻/讲座（ui/news、ui/lecture）、个人资料本地化（ui/myprofile+user 本地模型→feature/profile）、关于页（ui/about）、今日小组件→服务卡片（ui/widgets/today/*，二期 feature/card）。
- **默认裁剪**：θ社区（theta 77 文件）、自有账号注册/登录与云端同步（welcome 10、sync 10、user 云端 20+、style 35、component 响应式/网络基座大部分）。

**处置类别口径**：`直接迁移`=逻辑平移（换 ArkTS 语法/系统 API）；`重写`=按 ArkTS/ArkUI 语义重建（数据面常连同新版 JSON 端点一起重做）；`合并`=并入既定 ArkTS 文件/接口（不单设去向文件）；`裁剪`=不做/默认不做；`弃用`=被新版登录/会话方案显式替换。

---

## 1. 目标工程与去向约定（可微调，表中按此缩写）

```
entry/src/main/ets/
├─ entryability/            # EntryAbility.ets（对应 HApplication/ActivitySplash 的初始化与启动）
├─ pages/                   # MainTabs.ets 主框架（底导航 时间线/课表/我的-功能中心）
├─ common/                  # 通用层
│   ├─ net/                 # HttpClient.ets、ApiResp/错误模型（JSON 端点+Cookie 注入）
│   ├─ db/                  # RdbHelper.ets + EventDao/SubjectDao/TimetableDao(.ets 语义: RDB store)
│   ├─ pref/                # Preferences 封装
│   ├─ state/               # DataState/Trigger 概念（AppStorage/State/@Watch/EventHub 替代）
│   ├─ model/timetable/     # EventItem/TermSubject/Timetable/TimeInDay/TimePeriodInDay/SubjectColor
│   └─ util/                # TimeTools/ColorTools/TextTools/Json/ICS 导出/权限/图片…
├─ feature/eas/             # (蓝本 feature-eas)
│   ├─ model/               # CourseScoreItem/TermItem/ExamItem/CourseItem/BuildingItem/ClassroomItem/TeacherSearched
│   ├─ webLogin/            # EasSession.ets EasApiClient.ets EasSessionStore.ets
│   │                       # webLogin/{EasLoginPage,EasWebLoginController,EasWebLoginConfig,EasWebLoginProbe,EasWebMfaBridge}.ets
│   └─ pages/               # 成绩/考试/空教室/课表导入页（ArkUI 重写）
├─ feature/timetable/       # 课表(Canvas 周视图)/时间线/事件编辑/课表管理/课表详情/课程详情/风格面板
│   ├─ views/  components/  model/  data/  pages/
├─ feature/search/          # 教师搜索/教师官网页/新闻讲座/地点联想
├─ feature/profile/         # 本地个人页（EAS 身份回填）+ 我的资料编辑 + 协议/关于
└─ feature/card/            # (二期) 今日服务卡片（ui/widgets/today 的去向）
```

表内「移植去向」列统一用上面的相对缩写（如 `common/model/timetable/EventItem.ets`、`feature/eas/webLogin/…`）。凡标注 `（裁剪）` 者表示默认不做、无 ArkTS 去向。

---

## 2. app(hitax) 顶层与 utils（19 文件）

### 2.1 hitax 根（HApplication/MFileProvider）＋ ui/ActivitySplash

| HITA_X 源文件(包.类) | 职责摘要(一句) | 移植去向 | 处置 | 备注(依赖/风险/API 映射) |
|---|---|---|---|---|
| com.stupidtree.hitax.HApplication | Application 入口：建 Room 三表、注册 StupidSync 同步委托（写删回读 timetable/subject/event）、全局信任所有 HTTPS 证书 | entryability/EntryAbility.ets + common/db 初始化 | 重写 | 去掉 StupidSync 与明文证书信任；同步委托在裁剪 sync 后删除；Room→relationalStore 见 data/AppDatabase |
| com.stupidtree.hitax.MFileProvider | FileProvider 空声明（相册/裁剪 content://Uri 用） | （裁剪） | 裁剪 | Harmony 沙箱+PhotoViewPicker 无此概念 |
| com.stupidtree.hitax.ui.ActivitySplash | 闪屏，onCreate 直跳 MainActivity | entryability 启动流程 | 合并 | 15 行无逻辑；ArkTS 冷启动页面即入口 |

### 2.2 utils（16 文件）

| HITA_X 源文件(包.类) | 职责摘要(一句) | 移植去向 | 处置 | 备注(依赖/风险/API 映射) |
|---|---|---|---|---|
| utils.TimeTools | 课表时间核心：周一零点/季节/星期几/当前节次/日期文案 TTY 模式/同周同日判定 | common/util/TimeTools.ets | 直接迁移 | Calendar/SimpleDateFormat → @ohos.i18n/时间戳算术；WEEK_MILLS、节次结构常量保留；被 30+ 文件依赖，最先移植 |
| utils.ColorTools | Material 色板随机取色（队列轮换防重复）与透明度调节 | common/util/ColorTools.ets | 直接迁移 | 纯静态逻辑；卡片/科目着色用 |
| utils.TextTools | 用户名/密码/昵称校验与聊天式相对时间文案（今天/昨天/跨年） | common/util/TextTools.ets | 直接迁移 | 资源文案改为资源文件/i18n；注册校验随 welcome 裁剪 |
| utils.AnimationUtils | 旋转/漂浮/加载按钮 loading-done 动画工具 | 各 ArkUI 组件 animateTo | 重写 | CircularProgressButton 第三方库弃；按 @ohos.animator/属性动画重做 |
| utils.EditModeHelper | 列表编辑模式控制器（工具栏注入/全选/删除/计数） | feature 各列表页（List 原生多选编辑） | 重写 | ArkUI List 自带 editMode/多选删除，逻辑并入页面状态 |
| utils.ActivityUtils | 集中导航：跳各 Activity/搜索/教务登录校验弹窗/更新提示 | common/router + 各 feature 路由表 | 重写 | Intent.startActivity → @ohos.router/Navigation；showEasVerifyWindow 由 webLogin 会话门禁替代；checkUpdate 走版本检查 |
| utils.HintUtils | 向时间线注入“提示”假事件并按偏好记录已读 | feature/timetable/data + common/pref | 重写 | 复用 EventItem TYPE.TAG 语义；SharedPreferences→Preferences |
| utils.HTMLUtils | jsoup 便捷取 class/tag 文本属性（教务/官网抓取用） | common/net/html（正则/轻量解析） | 重写 | 与新版 JSON 端点策略配合，仅残存 HTML 场景用 |
| utils.ImageUtils | 资源图转 Bitmap、Glide 圆形头像、dp→px | common/media + ArkUI Image | 重写 | Glide→Image/PixelMap；dp→vp |
| utils.JsonUtils | Gson/org.json 混合取值兜底 | （并入 common/util） | 裁剪 | ArkTS 原生 JSON.parse+类型收窄替代 |
| utils.LiveDataUtils | 快速构造带初值 MutableLiveData | （并入状态管理） | 裁剪 | 无迁移价值（9 行） |
| utils.MaterialCircleAnimator | 圆形揭露 Reveal/旋转动画封装 | ArkUI 组件动画 | 裁剪 | 无系统 circular reveal，按遮罩/属性动画自绘（非必需） |
| utils.PermissionUtils | 存储/相机/录音动态权限（API 版本分支） | common/abilityAccessCtrl 封装 | 重写 | requestPermissions → abilityAccessCtrl.requestPermissionsFromUser |
| utils.FileProviderUtils | FileProvider/MediaStore/DocumentsContract 多机型 Uri↔路径 | （裁剪） | 裁剪 | picker 沙箱路径模型替代 |
| utils.GalleryPicker | 拍照/相册/系统裁剪流程封装 | feature/profile（头像选图） | 重写 | MediaStore Intent → PhotoViewPicker/CameraPicker，裁剪自实现 |
| utils.EventsUtils | 点击事件→弹出事件信息 bottom-sheet；当前节次文案 | feature/timetable（导航辅助） | 重写 | showEventItem 分发到 EventSheet |

## 3. data 层（38 文件）

### 3.1 data（2：Room 数据库与转换）

| HITA_X 源文件(包.类) | 职责摘要(一句) | 移植去向 | 处置 | 备注(依赖/风险/API 映射) |
|---|---|---|---|---|
| data.AppDatabase | Room 单例（entity=event/subject/timetable 三表，v1） | common/db/RdbHelper.ets | 重写 | relationalStore 建同构表 events/subject/timetable；另加 eas_session/eas_cache 等新表；启动初始化迁至 EntryAbility |
| data.TypeConverters | Room 类型转换：Timestamp↔Long、TYPE/GENDER 枚举、TimePeriodInDay 列表↔Gson JSON | common/db（store 内处理） | 裁剪 | RDB 字段直接用 long/string/json 存储，转换在读写处完成 |

### 3.2 data/model 与 Gson 序列化（4：DateSerializer/DateDeserializer/GsonBuilderUtil/service.ApiResponse）

| HITA_X 源文件(包.类) | 职责摘要(一句) | 移植去向 | 处置 | 备注(依赖/风险/API 映射) |
|---|---|---|---|---|
| data.model.DateSerializer | Gson Date→String 自定义序列化 | （并入 JSON 层） | 裁剪 | 服务于 sync/user 的 Gson 序列化；ArkTS 用 ISO 时间串 |
| data.model.DateDeserializer | Gson String→Date 反序列化 | （并入 JSON 层） | 裁剪 | 同上 |
| data.model.GsonBuilderUtil | 组装带 Date 适配器的 Gson | （裁剪） | 裁剪 | 15 行 |
| data.model.service.ApiResponse | 自有后端响应 {code,msg,data} | common/net（响应模型参考） | 裁剪 | hita.store 后端弃用；新版按校园 JSON 字段结构建解析模型 |

### 3.3 data/model/timetable（6：RDB 实体与值对象——最优先直迁）

| HITA_X 源文件(包.类) | 职责摘要(一句) | 移植去向 | 处置 | 备注(依赖/风险/API 映射) |
|---|---|---|---|---|
| data.model.timetable.EventItem | 事件/课程实体（events 表）：id/type(CLASS,EXAM,OTHER,TAG)/name/place/teacher/subjectId/timetableId/from/to/fromNumber/lastNumber；含时长/进度/是否包含时间戳等计算 | common/model/timetable/EventItem.ets | 直接迁移 | 与 RDB/时间线/课表/小组件/ICS 全链路共享；TYPE 枚举 ArkTS union；color 不落库 |
| data.model.timetable.Timetable | 课表实体（timetable 表）：name/code/startTime/endTime/scheduleStructure；周号换算/getTimestamps/默认 12 节作息 | common/model/timetable/Timetable.ets | 直接迁移 | getWeekNumber/getTimestamps 是课表渲染核心，逻辑 1:1；默认作息表常量保留 |
| data.model.timetable.TermSubject | 科目实体（subject 表）：name/type(COM_A..MOOC,TAG)/credit/field/school/countInSPA/code/key/color | common/model/timetable/TermSubject.ets | 直接迁移 | TYPE 语义保留；color 随机色在写入处生成 |
| data.model.timetable.TimeInDay | 一天内时刻（hour/minute），比较/加减分钟/toMills | common/model/timetable/TimeInDay.ets | 直接迁移 | 纯值对象 |
| data.model.timetable.TimePeriodInDay | 时间段 from/to，含 contains/length/clone | common/model/timetable/TimePeriodInDay.ets | 直接迁移 | 节次结构/选时间弹窗共用 |
| data.model.timetable.SubjectColor | (id,color) 轻量投影（事件取色） | common/model/timetable/SubjectColor.ets | 直接迁移 | 8 行投影，可并入 SubjectDao 返回结构 |

### 3.4 data/model/eas（5）＋ data/model/service（1，见 3.2）

| HITA_X 源文件(包.类) | 职责摘要(一句) | 移植去向 | 处置 | 备注(依赖/风险/API 映射) |
|---|---|---|---|---|
| data.model.eas.EASToken | 教务登录会话模型：cookies+username/password+身份字段(stuId/school/major/grade/email/phone/picture…) | feature/eas/webLogin/EasSession.ets | 合并 | 新版 EASToken(逆向)增加 campus/webBaseUrl/sessionGeneration/必选 Cookie 规则；密码字段去除（会话登录不存密码）；身份字段保留供个人页 |
| data.model.eas.TermItem | 学年学期（yearCode/yearName/termCode/termName/isCurrent） | feature/eas/model/TermItem.ets | 直接迁移 | 导入/成绩/空教室共用选择器 |
| data.model.eas.CourseItem | 总课表课程条目（name/weeks/teacher/classroom/dow/begin/last），导入课表用 | feature/eas/model/CourseItem.ets | 直接迁移 | 解析来源改为新版 JSON 端点（EASource HTML 解析弃用） |
| data.model.eas.CourseScoreItem | 成绩条目（finalScores/credits/hours/courseName/code/property/category/school/assessMethod/termName） | feature/eas/model/CourseScoreItem.ets | 直接迁移 | 字段映射新版深圳 JSON：xscj/zzcj/zpcj、kcmc/xf… 见蓝本 §2.2.6 |
| data.model.eas.ExamItem | 考试条目（courseName/examDate/examTime/type/location/termName/campusName） | feature/eas/model/ExamItem.ets | 直接迁移 | 新版端点确认后微调字段 |

### 3.5 data/source/dao（3：Room DAO → RDB 访问层）

| HITA_X 源文件(包.类) | 职责摘要(一句) | 移植去向 | 处置 | 备注(依赖/风险/API 映射) |
|---|---|---|---|---|
| data.source.dao.EventItemDao | events 表查询：时段内/之后/科目课程/计数/批量删改/偏移更新/clear | common/db/EventDao.ets | 重写 | SQL→relationalStore predicates；LiveData 查询→订阅/刷新回调；事务方法（删课表级联、改作息偏移）逐个迁移 |
| data.source.dao.SubjectDao | subject 表：按 id/timetable/name 查、批量存删、改色、取色集合、clear | common/db/SubjectDao.ets | 重写 | 同上 |
| data.source.dao.TimetableDao | timetable 表：按 easCode/最近学期/计数/地点模糊查询、存删、clear | common/db/TimetableDao.ets | 重写 | 同上；搜索地点(place)用于添加事件联想 |

### 3.6 data/source/preference（2）

| HITA_X 源文件(包.类) | 职责摘要(一句) | 移植去向 | 处置 | 备注(依赖/风险/API 映射) |
|---|---|---|---|---|
| data.source.preference.EasPreferenceSource | 教务会话偏好：EAS token/身份字段/cookies JSON 存取与清除 | feature/eas/webLogin/EasSessionStore.ets | 重写 | 存 cookies（不存明文密码）；加密（cryptoFramework/HUKS 派生密钥）；新增 campus/studentType/webBaseUrl/eelabToken/sessionGeneration/updatedAt 字段（蓝本 §4.4 eas_session） |
| data.source.preference.TimetablePreferenceSource | 课表作息节次结构偏好（class_num + class_i JSON）+ 本科默认 13 节 | common/pref + feature/timetable | 直接迁移 | Preferences 存节次数组；默认 13 节常量保留（与 Timetable.getDefaultTimeStructure 12 节并存，需对齐口径） |

### 3.7 data/source/web 与 service（9：网络链）

| HITA_X 源文件(包.类) | 职责摘要(一句) | 移植去向 | 处置 | 备注(依赖/风险/API 映射) |
|---|---|---|---|---|
| data.source.web.service.EASService | 教务数据服务接口面：login/loginCheck/getAllTerms/getStartDate/getSubjectsOfTerm/getTimetableOfTerm/getScheduleStructure/getTeachingBuildings/queryEmptyClassroom/getPersonalScores/getExamItems | feature/eas/EasDataProvider（接口面） | 重写 | 方法面=新版数据访问清单（蓝本 §4.5）；登录/登录检查方法删除，由 EasApiClient+webLogin 会话承担 |
| data.source.web.eas.EASource | jsoup 裸 HTTP 模拟教务登录(CAS→SSO)+HTML 抓取成绩/考试/课表/空教室/课表结构（737 行） | （弃用，不迁移） | 弃用 | 旧登录链已失效；HTML 解析不迁移，模型与 UI 语义保留（蓝本 §4.5） |
| data.source.web.service.StaticService | 自有静态后端接口（about/user_agreement/privacy_policy 三 HTML 页） | feature/profile（协议/关于静态内容本地化） | 裁剪 | hita.store 后端弃用；改为本地资源或随发布维护的文本 |
| data.source.web.StaticWebSource | BaseWebSource 实现，拉取三静态页返回 DataState<String> | （并入 StaticService 去向） | 裁剪 | 同上 |
| data.source.web.service.AdditionalService | 讲座分页列表 + 新闻元数据（link→{text,time}）接口 | feature/search/api | 重写 | 新版接口若走校园 JSON 则重写解析；讲座来源 www.hitsz.edu.cn |
| data.source.web.additional.AdditionalSource | jsoup 抓 hitsz.edu.cn 讲座列表/新闻详情 HTML | feature/search/api + common/net/html | 重写 | jsoup→HTTP+解析（新 APK 若提供 JSON 则优先） |
| data.source.web.service.TeacherService | 教师接口：官网资料/多页介绍/按名搜索 | feature/search/api | 重写 | 教师官网 faculty.hitsz.edu.cn 公开数据 |
| data.source.web.TeacherWebSource | jsoup 抓教师资料页(faculty.hitsz.edu.cn)+搜索 JSON 接口 | feature/search/api | 重写 | 与 AdditionalSource 同类处理；search 用 JSONObject，迁移后 JSON.parse |
| data.source.web.service.codes | 自有 API 返回码常量(200/301/303/304/2005) | （裁剪） | 裁剪 | 自有后端弃用；新版以响应字段/HTTP 状态判定 |

### 3.8 data/repository（7：仓库层 → feature Store）

| HITA_X 源文件(包.类) | 职责摘要(一句) | 移植去向 | 处置 | 备注(依赖/风险/API 映射) |
|---|---|---|---|---|
| data.repository.TimetableRepository | 课表/事件读写：查询/删课表级联/增删事件/改开始日期(偏移事件)/改作息(联动课时)/导出 ICS(actionExportToICS)/清空 | feature/timetable/data + common/db | 重写 | ICS 导出 → 手写 RFC5545 最小子集（iCal4j 弃，蓝本 §3.2）；StupidSync 记录删除；getTodayEventsSync 供服务卡片 |
| data.repository.SubjectRepository | 科目读写：按课表查询/教师聚合/进度(已上/总节)/颜色重置/改色/删除科目及事件 | feature/timetable/data | 重写 | getProgressOfSubject 用于课程详情进度条 |
| data.repository.TimetableStyleRepository | 课表样式偏好(start/drawBg/color/fade)→MediatorLiveData 组装 TimetableStyleSheet | feature/timetable/data + common/pref | 直接迁移 | 键值同前；样式 sheet 观察链→状态订阅 |
| data.repository.EASRepository | EAS 门面：登录/登录检查/学期/开始日期/课表结构/教学楼/空教室/成绩/考试 + 课表导入写库流程 | feature/eas/EasRepository + feature/timetable/data/TimetableImportService | 拆分/重写 | 会话+远端查询→EasRepository(EasApiClient)；startImportTimetableOfTerm（拉取→清旧→建科目→按周展开事件→存库）→ TimetableImportService |
| data.repository.StaticRepository | about/协议/隐私三页转发 | feature/profile | 裁剪 | 随 StaticService |
| data.repository.AdditionalRepository | 讲座分页/新闻元数据转发 | feature/search/api | 重写 | 薄转发删除 |
| data.repository.TeacherInfoRepository | 教师资料/介绍/搜索转发 | feature/search/api | 重写 | 薄转发删除 |

## 4. ui/main/timetable（课表主界面，P0，11 文件）

### 4.1 timetable 页与 ViewModel（3）

| HITA_X 源文件(包.类) | 职责摘要(一句) | 移植去向 | 处置 | 备注(依赖/风险/API 映射) |
|---|---|---|---|---|
| ui.main.timetable.TimetableFragment | 主课表页：5 周窗口无限 ViewPager、周切换同步标题/回到今天 FAB、卡片点击/长按删除(爆炸动画)/添加事件分发 | feature/timetable/pages/TimetablePage.ets | 重写 | ViewPager→Swiper(循环)或自管理窗口；WEEK_MILLS/WINDOW_SIZE 常量保留；长按菜单→ArkUI 菜单/确认框 |
| ui.main.timetable.TimetableViewModel | 5 周窗口数据编排：每窗口(开始日,事件+样式)链式 LiveData、当前页周起始 | feature/timetable/data（窗口状态） | 重写 | 状态订阅/懒加载窗口语义迁移到页面状态管理 |
| ui.main.timetable.TimetableStyleSheet | 课表样式字段集合(配色/字色/图标/粗细/背景线/开始时间/今日底色/透明度) | feature/timetable/model/TimetableStyle.ets | 直接迁移 | 纯字段类；与偏好/面板联动 |

### 4.2 timetable views（自定义绘制，6 文件）

| HITA_X 源文件(包.类) | 职责摘要(一句) | 移植去向 | 处置 | 备注(依赖/风险/API 映射) |
|---|---|---|---|---|
| ui.main.timetable.views.TimeTableView | 课表画布 ViewGroup：时间刻度线/今日列底色/按周几聚合重叠事件→事件块布局、触摸计算落点时段触发“新增块” | feature/timetable/views/TimeTableView.ets | 重写 | 核心：ViewGroup/onLayout→Stack/Column 定位或 Canvas 全绘制；aggregateEvents 重叠聚类算法 1:1 移植；触摸→手势识别节次 |
| ui.main.timetable.views.TimetableWeekView | 周视图容器：顶部月份/7 日文字 + 内嵌 TimeTableView 组合 | feature/timetable/views/TimetableWeekView.ets | 重写 | LinearLayout→Column；日期文本刷新 |
| ui.main.timetable.views.TimeTableBlockView | 事件卡片：单事件卡/多事件重叠卡（标题/副标题/图标/配色/透明度/字号） | feature/timetable/views/EventBlockCard.ets | 重写 | FrameLayout→自定义组件；按 TimetableStyle 参数化渲染；点按/长按回调 |
| ui.main.timetable.views.TimeTableNowLine | “当前时间”指示横线（纯色 View） | feature/timetable/views（并入画布） | 重写 | 画布内绘制当前时刻线；定时刷新对齐分钟 |
| ui.main.timetable.views.LeftLabelView | 左侧时间刻度标签（Canvas 每整点文字） | feature/timetable/views（时间轴标签） | 重写 | Canvas drawText→画布/Text 行；与主画布同步 sectionHeight |
| ui.main.timetable.views.TimeTableBlockAddView | 触摸产生的“新增课程时段”半透明块，点击回调 + 移除自身 | feature/timetable/views（并入 TimeTableView） | 合并 | 与添加事件 sheet 联动 |

### 4.3 timetable panel（2：课表样式底部面板）

| HITA_X 源文件(包.类) | 职责摘要(一句) | 移植去向 | 处置 | 备注(依赖/风险/API 映射) |
|---|---|---|---|---|
| ui.main.timetable.panel.FragmentTimetablePanel | 样式面板：开始时间(TimePicker)/背景线/科目色/渐变开关 | feature/timetable/pages/StylePanel.ets | 重写 | 底部面板（bindSheet/CustomDialog）；开关→Toggle |
| ui.main.timetable.panel.TimetablePanelViewModel | 面板 VM：读写样式偏好、重置最近科目颜色 | feature/timetable/data（并入 Style 状态） | 合并 | 并入 3.8 TimetableStyleRepository 去向 |

## 5. ui/main/timeline（时间线/今日，P1，4 文件）

| HITA_X 源文件(包.类) | 职责摘要(一句) | 移植去向 | 处置 | 备注(依赖/风险/API 映射) |
|---|---|---|---|---|
| ui.main.timeline.FragmentTimeLine | 时间线页：今日事件列 + 可下拉展开的“本周临近”头部 + 倒计时头部卡，监听时间/日期广播自动刷新 | feature/timetable/pages/TimelinePage.ets | 重写 | BroadcastReceiver(时间/日期)→定时器/系统时间 tick；pull-extend 展开头→折叠面板手势（组件见 12.3 注释） |
| ui.main.timeline.FragmentTimelineViewModel | 今日事件 + 未来 4 日事件的仓库查询编排 | feature/timetable/data | 重写 | switchMap→状态订阅；复用 EventDao 查询 |
| ui.main.timeline.TimelineListAdapter | 时间线列适配器：头部问候/进行中进度/临上课/提示行/空态/已过多种 viewType 与倒计时 | feature/timetable/components/TimelineList（ForEach + 多模板） | 重写 | 头部问候文案按时段（早/午/晚/夜）+now/next 事件进度逻辑保留 |
| ui.main.timeline.TimelineTopListAdapter | 顶部“本周后续事件”横向倒计时列表 | feature/timetable/components/TimelineTopList | 重写 | 横向 List；今天倒计时/非今天日期两种文案 |

## 6. ui/event（事件查看与编辑，P1，6 文件）

| HITA_X 源文件(包.类) | 职责摘要(一句) | 移植去向 | 处置 | 备注(依赖/风险/API 映射) |
|---|---|---|---|---|
| ui.event.FragmentTimeInfoSheet | 多事件底部弹窗：Tabs 切换各事件明细（复用 EventItemFragment） | feature/timetable/pages/EventSheet.ets | 重写 | Tabs→ArkUI Tabs/Segmented；单事件隐藏 Tabs |
| ui.event.EventItemFragment | 单事件明细：名称/地点/教师/节次/日期/课程进度/删改/跳转课程与教师搜索 | feature/timetable/pages/EventDetailSheet.ets | 重写 | 进度=已上节/总节；删除走确认弹窗 |
| ui.event.EventItemViewModel | 明细 VM：进度(已上/总)查询与删除动作 | feature/timetable/data（并入事件状态） | 合并 | getProgressOfSubject 已在 3.8 SubjectRepository |
| ui.event.add.CourseTime | 新增事件参数：节次时段 + dow + 周次列表 | feature/timetable/model/CourseTime.ets | 直接迁移 | 14 行 POJO |
| ui.event.add.PopupAddEvent | 新增/复制事件弹窗：选课表/科目(或新建)/教师联想/地点联想/周节次时间选择器，确认写库 | feature/timetable/pages/AddEventSheet.ets | 重写 | 联动校验“可提交”逻辑保留；教师/地点联想→searchLocation/教师搜索 API |
| ui.event.add.AddEventViewModel | 新增事件 VM：字段链式校验 + createEvent 逐周展开事件并扩展课表结束时间 | feature/timetable/data（AddEvent 状态） | 重写 | 校验状态机→@Watch/状态派生；写库动作→TimetableStore |

## 7. ui/eas（教务数据各页，23 文件：登录整块替换、数据页重写）

### 7.1 eas 基座（2）

| HITA_X 源文件(包.类) | 职责摘要(一句) | 移植去向 | 处置 | 备注(依赖/风险/API 映射) |
|---|---|---|---|---|
| ui.eas.EASActivity | 需登录的 EAS 页面基类：onStart 登录检查，未登录弹 PopUpLoginEAS（lock 模式退出） | feature/eas/pages（登录门禁基态） | 重写 | 会话门禁→EasSessionStore 有效性检查，失效即进入 webLogin（蓝本 §4.4） |
| ui.eas.EASViewModel | 基类 VM：loginCheckResult 状态（调 EasRepository.loginCheck） | feature/eas（会话状态，并入 EasRepository） | 合并 | 登录检查逻辑按新会话字段（JSESSIONID/必选 Cookie/代数）重写 |

### 7.2 ui/eas/login（3：旧表单登录 → 弃用）

| HITA_X 源文件(包.类) | 职责摘要(一句) | 移植去向 | 处置 | 备注(依赖/风险/API 映射) |
|---|---|---|---|---|
| ui.eas.login.PopUpLoginEAS | 用户名密码表单弹窗（底部 sheet）：调 EASRepository.login、loading 动画与成败回调 | （被 webLogin/EasLoginPage.ets 替换） | 弃用 | 新版为 ArkWeb 网页机器人登录 + MFA 覆盖层（蓝本 §2/§4），表单登录不再提供 |
| ui.eas.login.LoginEASViewModel | 表单登录 VM（switchMap→EASRepository.login） | （同上） | 弃用 | — |
| ui.eas.login.LoginTrigger | 登录参数载体(Trigger) | （同上） | 弃用 | — |

### 7.3 ui/eas/score（4：成绩查询）

| HITA_X 源文件(包.类) | 职责摘要(一句) | 移植去向 | 处置 | 备注(依赖/风险/API 映射) |
|---|---|---|---|---|
| ui.eas.score.ScoreInquiryActivity | 成绩页：学期选择/考试类型(全部/正常/补考/重修)筛选 + 下拉刷新 + 列表 | feature/eas/pages/ScorePage.ets | 重写 | 筛选弹窗→选择器；数据=新版 JSON 成绩接口（蓝本 §2.2.6 深圳字段样例） |
| ui.eas.score.ScoreInquiryViewModel | 成绩 VM：terms/选中学期/类型 → scores 组合查询 | feature/eas/data（成绩状态） | 重写 | MTransformations 双源组合→状态派生 |
| ui.eas.score.ScoresListAdapter | 成绩行（课名/分数/分隔线/点击详情） | feature/eas/components（行组件） | 重写 | ForEach 行 |
| ui.eas.score.ScoreDetailFragment | 成绩明细底部弹窗（学分/学时/类别/性质/院系/考核方式） | feature/eas/pages/ScoreDetailSheet.ets | 重写 | bindSheet 呈现 CourseScoreItem 字段 |

### 7.4 ui/eas/exam（4：考试查询）

| HITA_X 源文件(包.类) | 职责摘要(一句) | 移植去向 | 处置 | 备注(依赖/风险/API 映射) |
|---|---|---|---|---|
| ui.eas.exam.ExamActivity | 考试列表页（下拉刷新/点击详情） | feature/eas/pages/ExamPage.ets | 重写 | 数据=新版考试端点（蓝本 §5 P1） |
| ui.eas.exam.ExamViewModel | 考试 VM（trigger→getExamInfo） | feature/eas/data（考试状态） | 重写 | — |
| ui.eas.exam.ExamListAdapter | 考试行（课程/日期） | feature/eas/components | 重写 | — |
| ui.eas.exam.ExamDetailFragment | 考试详情弹窗（课程/时间/地点/类型/学期/校区） | feature/eas/pages/ExamDetailSheet.ets | 重写 | — |

### 7.5 ui/eas/classroom（7：空教室查询）

| HITA_X 源文件(包.类) | 职责摘要(一句) | 移植去向 | 处置 | 备注(依赖/风险/API 映射) |
|---|---|---|---|---|
| ui.eas.classroom.BuildingItem | 教学楼 (name,id) | feature/eas/model/BuildingItem.ets | 直接迁移 | 18 行 POJO |
| ui.eas.classroom.ClassroomItem | 教室(name/id/capacity/specialClassroom + 占用 scheduleList JSON) | feature/eas/model/ClassroomItem.ets | 直接迁移 | scheduleList 占用表按新版返回结构解析 |
| ui.eas.classroom.EmptyClassroomActivity | 空教室页：学期/教学楼/周次选择 + 2 列教室列表(空闲/被占状态) | feature/eas/pages/EmptyClassroomPage.ets | 重写 | 教室“空闲判定”取当前节次与占用表比对逻辑保留 |
| ui.eas.classroom.EmptyClassroomViewModel | 空教室 VM：学期/教学楼/周次/课表结构联动 → 查询 | feature/eas/data（空教室状态） | 重写 | 当前周次默认取本地课表周号 |
| ui.eas.classroom.EmptyClassroomListAdapter | 教室卡（名称/容量/占用状态着色） | feature/eas/components | 重写 | — |
| ui.eas.classroom.detail.EmptyClassroomDetailFragment | 教室周占用明细弹窗（Tabs 星期→每节占用/空） | feature/eas/pages/ClassroomWeekSheet.ets | 重写 | 每节状态来自 scheduleList 的 XQJ/XJ/JYBJ/PKBJ 字段 |
| ui.eas.classroom.detail.EmptyClassroomDetailAdapter | 占用明细行（节次/时间/状态） | feature/eas/components | 重写 | — |

### 7.6 ui/eas/imp（3：课表导入）

| HITA_X 源文件(包.类) | 职责摘要(一句) | 移植去向 | 处置 | 备注(依赖/风险/API 映射) |
|---|---|---|---|---|
| ui.eas.imp.ImportTimetableActivity | 课表导入页：选学期/本科-研究生结构/开学日期/12 节作息可调 → 一键导入写库 | feature/eas/pages/ImportTimetablePage.ets | 重写 | 页面在 eas，落库调 feature/timetable TimetableImportService；同步动作后通知服务卡片 |
| ui.eas.imp.ImportTimetableViewModel | 导入 VM：terms/开始日期/结构/本科标记 联动 + 导入结果 | feature/eas/data（导入状态） | 重写 | 结构=新版 getScheduleStructure 数据 |
| ui.eas.imp.TimetableStructureListAdapter | 12 节作息行（节次/时间，点击弹时间选择器改作息） | feature/eas/components（作息编辑器） | 重写 | — |

## 8. ui/main 主框架与导航（4 文件）

| HITA_X 源文件(包.类) | 职责摘要(一句) | 移植去向 | 处置 | 备注(依赖/风险/API 映射) |
|---|---|---|---|---|
| ui.main.MainActivity | 主壳：ViewPager(时间线/课表/导航)+底部导航、Drawer 抽屉(个人/搜索/协议/关于/主题/更新) | entry/src/main/ets/pages/MainTabs.ets | 重写 | Tabs 主框架；抽屉项并入各 feature 入口；自有账号相关移除 |
| ui.main.MainViewModel | 主壳 VM：登录用户/检查更新状态 | entry/src/main/ets（会话与更新状态） | 重写 | theta 未读数/云端用户裁剪；会话=webLogin 会话 |
| ui.main.navigation.NavigationFragment | “导航/中心”页：用户卡+EAS 登录状态卡+入口卡片网格(最近课表/导入/成绩/考试/空教室/讲座/新闻等) | feature/profile/pages/NavigationHubPage.ets（功能中心） | 重写 | 用户卡显示 EAS 身份/退出；入口网格→路由表；卡状态联动 EasSessionStore |
| ui.main.navigation.NavigationViewModel | 导航页 VM：最近课表/课表数/未读消息数 | feature/profile/data（并入 hub 状态） | 重写 | theta 消息未读数裁剪；保留最近课表/课表数 |

## 9. ui/timetable（课表详情与管理，8 文件，P1）

### 9.1 detail（5）

| HITA_X 源文件(包.类) | 职责摘要(一句) | 移植去向 | 处置 | 备注(依赖/风险/API 映射) |
|---|---|---|---|---|
| ui.timetable.detail.TimetableDetailActivity | 课表详情：折叠头+课程列表/授课教师/作息结构三区、编辑模式改色/改时/改名/重置/新增、导出 ICS 分享 | feature/timetable/pages/TimetableDetailPage.ets | 重写 | 编辑动作复用 Timetable/Subject repo 语义；导出 ICS 见 3.8 |
| ui.timetable.detail.TimetableDetailViewModel | 详情 VM：课程/教师/课表三路数据 + 各类保存动作 | feature/timetable/data（详情状态） | 重写 | — |
| ui.timetable.detail.SubjectsListAdapter | 课程行/大卡两种视图 + 进度条实时刷新 + 编辑多选 | feature/timetable/components | 重写 | 进度观察在行级订阅 |
| ui.timetable.detail.TeacherInfo | (教师名,课程名) POJO，教师横条去重用 | feature/timetable/model/TeacherInfo.ets | 直接迁移 | 21 行 |
| ui.timetable.detail.TeachersListAdapter | 授课教师横条列表（点击跳教师搜索） | feature/timetable/components | 重写 | — |

### 9.2 manager（3）

| HITA_X 源文件(包.类) | 职责摘要(一句) | 移植去向 | 处置 | 备注(依赖/风险/API 映射) |
|---|---|---|---|---|
| ui.timetable.manager.TimetableManagerActivity | 课表管理：2 列网格(季节图标)/新建(默认名+1)/EAS 导入入口/长按编辑删除/同步按钮 | feature/timetable/pages/TimetableManagerPage.ets | 重写 | 同步按钮裁剪（sync 模块不做）；季节图标按开始日期 |
| ui.timetable.manager.TimetableManagerViewModel | 管理 VM：课表列表 + 新建/批量删除 | feature/timetable/data（管理状态） | 重写 | — |
| ui.timetable.manager.TimetableListAdapter | 课表卡网格 + 尾部“新建/导入”入口 + 编辑复选 | feature/timetable/components | 重写 | — |

## 10. ui/subject、ui/teacher、ui/search（搜索与资料，15 文件，P1）

### 10.1 subject（3：课程详情 → 归 feature/timetable）

| HITA_X 源文件(包.类) | 职责摘要(一句) | 移植去向 | 处置 | 备注(依赖/风险/API 映射) |
|---|---|---|---|---|
| ui.subject.SubjectActivity | 课程详情：课程卡(类型/学分/教师/课表)+上课记录流式折叠+进度动画+编辑模式增删课 | feature/timetable/pages/SubjectDetailPage.ets | 重写 | 上课记录=该科目 EventItem 列表（来自事件数据） |
| ui.subject.SubjectCoursesListAdapter | 上课记录行（已上/未开始状态、more-less 标签、编辑复选） | feature/timetable/components | 重写 | — |
| ui.subject.SubjectViewModel | 课程详情 VM：课程/记录/教师三路数据 + 保存/删除 | feature/timetable/data（并入详情状态） | 合并 | — |

### 10.2 teacher（4：教师官网资料页 → feature/search）

| HITA_X 源文件(包.类) | 职责摘要(一句) | 移植去向 | 处置 | 备注(依赖/风险/API 映射) |
|---|---|---|---|---|
| ui.teacher.ActivityTeacherOfficial | 教师主页：头像/姓名/职务/简介 + 多页 HTML 介绍(Web/Tabs) + 刷新/联系 FAB | feature/search/pages/TeacherOfficialPage.ets | 重写 | HTML 富文本渲染按抓取结果转文本/Web 组件 |
| ui.teacher.TeacherContactFragment | 教师联系方式弹窗（电话/邮箱/地址，空值缺省） | feature/search/components（联系 sheet） | 重写 | — |
| ui.teacher.TeacherKey | (name,id,url) POJO，用作触发源 | feature/search/model/TeacherKey.ets | 直接迁移 | 6 行 |
| ui.teacher.TeacherViewModel | 教师页 VM：资料/多页介绍两路数据 | feature/search/data（教师状态） | 重写 | — |

### 10.3 search（8：全局搜索，去用户/文章 tab）

| HITA_X 源文件(包.类) | 职责摘要(一句) | 移植去向 | 处置 | 备注(依赖/风险/API 映射) |
|---|---|---|---|---|
| ui.search.SearchActivity | 搜索壳：搜索框 + Tabs(教师/用户/文章)；外链直达定位 | feature/search/pages/SearchPage.ets | 重写 | 用户/文章两 tab 随 theta/user 裁剪，仅保留教师（或并入地点） |
| ui.search.SearchViewModel | 空壳 VM 占位 | （裁剪） | 裁剪 | 5 行 |
| ui.search.BaseSearchResultViewModel | 搜索结果 VM 抽象：文本+分页+追加 → doSearch 模板 | feature/search/data（结果页状态模板） | 重写 | 分页/追加语义保留 |
| ui.search.BasicFragmentSearchResult | 搜索结果列表基类：RecyclerView+下拉刷新+追加/整表替换 | feature/search/components/SearchResultList | 重写 | List 增量合并/替换 |
| ui.search.SearchTrigger | 搜索触发参数(文本/页大小/页码/追加) | feature/search/data（并入模板状态） | 直接迁移 | 24 行 |
| ui.search.teacher.TeacherSearched | 教师搜索结果(name/id/url/department/avatar) | feature/search/model/TeacherSearched.ets | 直接迁移 | 8 行 |
| ui.search.teacher.FragmentSearchTeacher | 教师搜索结果页（头像+姓名+院系，点击进教师主页） | feature/search/pages/SearchTeacherResult.ets | 重写 | — |
| ui.search.teacher.SearchTeacherViewModel | 教师搜索 VM（分页 doSearch→searchTeachers） | feature/search/data（并入教师状态） | 合并 | — |

## 11. ui/myprofile、ui/profile、ui/about、ui/welcome、ui/news、ui/theme、ui/base（P2/裁剪，共 29 文件）

### 11.1 myprofile + profile（6 → feature/profile 本地化）

| HITA_X 源文件(包.类) | 职责摘要(一句) | 移植去向 | 处置 | 备注(依赖/风险/API 映射) |
|---|---|---|---|---|
| ui.myprofile.MyProfileActivity | 本人资料编辑：昵称/性别/签名/头像（相册裁剪），逐项保存 | feature/profile/pages/ProfileEditPage.ets | 重写 | 云端保存裁剪；头像/资料本地（EAS 身份回填，蓝本 §5 个人资料 P2） |
| ui.myprofile.MyProfileViewModel | 编辑 VM：校验登录后逐请求流保存 | feature/profile/data（编辑状态） | 重写 | — |
| ui.myprofile.ProfilePage | Compose 编写的资料页草稿（全注释死代码） | （裁剪） | 裁剪 | 100% 注释 |
| ui.myprofile.TypeTrigger | (type,subType,permission) 触发载体 | （裁剪） | 裁剪 | 17 行 |
| ui.profile.ProfileActivity | 他人资料页：头像昵称/粉丝关注/帖子入口/关注取关/本人可退出清库 | （裁剪） | 裁剪 | 依赖 theta/user 云端社交；Harmony 版无他人主页（若二期做，重写为只读） |
| ui.profile.ProfileViewModel | 他人资料/关注取关/登出 VM | （裁剪） | 裁剪 | 同上 |

### 11.2 about（4 → feature/profile/about，P2）

| HITA_X 源文件(包.类) | 职责摘要(一句) | 移植去向 | 处置 | 备注(依赖/风险/API 映射) |
|---|---|---|---|---|
| ui.about.ActivityAbout | 关于页：版本号+HTML 关于内容+隐私入口+检查更新按钮 | feature/profile/pages/AboutPage.ets | 重写 | 内容本地化（hita.store 静态页弃）；检查更新可保留版本比对或裁剪 |
| ui.about.AboutViewModel | 关于 VM：静态关于页+检查更新 | feature/profile/data | 重写 | — |
| ui.about.UserAgreementDialog | 协议/隐私底部弹窗（Tabs 分页） | feature/profile/pages/AgreementSheet.ets | 重写 | 文案本地资源 |
| ui.about.UserAgreementViewModel | 协议 VM：两路静态页请求 | feature/profile/data（并入 about 状态） | 合并 | — |

### 11.3 welcome（10：自有账号注册/登录 → 裁剪）

| HITA_X 源文件(包.类) | 职责摘要(一句) | 移植去向 | 处置 | 备注(依赖/风险/API 映射) |
|---|---|---|---|---|
| ui.welcome.WelcomeActivity | 登录/注册双 Tab 容器 | （裁剪） | 裁剪 | 自有账号体系移除后无需引导登录页；首次启动直接主界面 |
| ui.welcome.WelcomeViewModel | 空壳 VM（4 行） | （裁剪） | 裁剪 | — |
| ui.welcome.login.LoginFragment | 自有账号登录表单 | （裁剪） | 裁剪 | 登录改为 webLogin（ArkWeb 会话），不保留账号密码表单 |
| ui.welcome.login.LoginFormState | 登录表单校验状态 POJO | （裁剪） | 裁剪 | — |
| ui.welcome.login.LoginTrigger | 登录触发载体 | （裁剪） | 裁剪 | — |
| ui.welcome.login.LoginViewModel | 自有账号登录 VM（调 UserRepository） | （裁剪） | 裁剪 | — |
| ui.welcome.signup.SignUpFragment | 自有账号注册表单（含性别） | （裁剪） | 裁剪 | 不提供自有账号注册 |
| ui.welcome.signup.SignUpFormState | 注册表单校验状态 POJO | （裁剪） | 裁剪 | — |
| ui.welcome.signup.SignUpTrigger | 注册触发载体 | （裁剪） | 裁剪 | — |
| ui.welcome.signup.SignUpViewModel | 自有账号注册 VM | （裁剪） | 裁剪 | — |

### 11.4 news / lecture（5 → feature/search，P2）

| HITA_X 源文件(包.类) | 职责摘要(一句) | 移植去向 | 处置 | 备注(依赖/风险/API 映射) |
|---|---|---|---|---|
| ui.news.NewsDetailActivity | 新闻详情：WebView 加载官网新闻+注入 JS 大图回调+标题时间叠加 | feature/search/pages/NewsDetailPage.ets | 重写 | WebView→ArkWeb；addJavascriptInterface→runJavaScript 轮询/registerJavaScriptProxy；大图用 PhotoView 式组件 |
| ui.news.NewsViewModel | 新闻元数据 VM（link→meta） | feature/search/data（新闻状态） | 重写 | — |
| ui.news.lecture.ActivityLecture | 讲座列表：下拉刷新+触底分页加载+点击进详情 | feature/search/pages/LecturePage.ets | 重写 | List 分页；List<Map<String,String>>→强类型 Lecture 模型 |
| ui.news.lecture.LectureListAdapter | 讲座卡（标题/时间/地点/日期/图） | feature/search/components | 重写 | 图片 Image；空字段隐藏逻辑保留 |
| ui.news.lecture.LectureViewModel | 讲座分页 VM（append/replace 列表动作） | feature/search/data（讲座状态） | 重写 | — |

### 11.5 theme（2：Compose 遗留）与 ui/base（2）

| HITA_X 源文件(包.类) | 职责摘要(一句) | 移植去向 | 处置 | 备注(依赖/风险/API 映射) |
|---|---|---|---|---|
| ui.theme.Color | Compose 红系色常量 | common/theme（色值参考） | 裁剪 | 疑为主 UI 未用遗留，仅取色值参考 |
| ui.theme.Theme | Compose AppTheme(MaterialTheme/主色#304ffe)+AppBar | common/theme/Theme.ets | 重写 | ArkUI 主题/深浅色按资源目录与状态管理实现（主色可沿用 #304ffe） |
| ui.base.BaseActivityCompose | 全 App Activity 基类（VM 注入/沉浸/工具栏/主题色） | （裁剪） | 裁剪 | ArkUI 页面无基类概念；共用能力→common 组件/路由/状态基座 |
| ui.base.BaseEditableListAdapter | 旧可编辑列表 Adapter 骨架（全注释死代码） | （裁剪） | 裁剪 | 100% 注释 |

## 12. ui/widgets（通用控件与小组件，23 文件）

### 12.1 通用自绘/交互控件（11）

| HITA_X 源文件(包.类) | 职责摘要(一句) | 移植去向 | 处置 | 备注(依赖/风险/API 映射) |
|---|---|---|---|---|
| ui.widgets.FocusTextView | 恒焦点 TextView（跑马灯等） | （裁剪） | 裁剪 | ArkUI Text 无需焦点 hack |
| ui.widgets.LockedViewPager | 禁用触摸滑动 ViewPager | （裁剪） | 裁剪 | Swiper disableSwipe 语义，通常无需自写 |
| ui.widgets.mBottomHideBehavior | 列表滚动时底部栏显隐 Behavior | feature 各页底部栏 | 裁剪 | 监听 List onScrollIndex 驱动显隐动画即可 |
| ui.widgets.PopUpCalendarPicker | 底部日历选日期弹窗 | common/ui/DatePickSheet（或 DatePicker 组件） | 重写 | 日历→DatePicker/自定义月历 |
| ui.widgets.PopUpPickCourseTime | 排课时间弹窗：星期/节次滚轮+周次多选 | feature/timetable/components/WeekPeriodSheet.ets | 重写 | 选择结构（CourseTime）语义保留，UI 用选择器+周次网格 |
| ui.widgets.PopUpTimePeriodPicker | 双段滚轮起止时间互校验弹窗 | feature/timetable/components/TimePeriodSheet.ets | 重写 | 起≤止校验保留 |
| ui.widgets.RoundedBarView | 圆角卡(文本+图标)点击回传选中键 | （裁剪） | 裁剪 | ArkUI 卡片即组件，简单场景不单设 |
| ui.widgets.SelectableIconCardView | 可勾选图标卡（选中/禁用/触感） | common/ui/SelectableCard.ets | 重写 | stateStyles/选中态 |
| ui.widgets.VerticalNestedScrollView | 横向手势让权给横向列表的 NestedScrollView | （裁剪） | 裁剪 | ArkUI 滚动容器按需组合 |
| ui.widgets.WrapContentHeightViewPager | 高度自适应内容 ViewPager | （裁剪） | 裁剪 | — |
| ui.widgets.WidgetUtils | 广播“刷新小组件”注册表 | feature/card（卡片刷新通道，二期） | 重写 | sendBroadcast→服务卡片消息/EventHub（二期再落地） |

### 12.2 pullextend（下拉扩展组件，6 → 系统 Refresh 替代）

| HITA_X 源文件(包.类) | 职责摘要(一句) | 移植去向 | 处置 | 备注(依赖/风险/API 映射) |
|---|---|---|---|---|
| ui.widgets.pullextend.ExpendPoint | 下拉头部弹性圆点 Canvas 指示器 | （裁剪） | 裁剪 | 系统 Refresh 指示器替代 |
| ui.widgets.pullextend.ExtendLayout | 下拉头/上拉尾抽象基类（状态机） | （裁剪） | 裁剪 | 概念→ArkUI Refresh/PullToRefresh |
| ui.widgets.pullextend.ExtendListHeader | 时间线可展开头部（概览区+展开回调） | feature/timetable/components/TimelineExpandHead | 重写 | 若需保留“拉下展开本周日程”手势，用自定义手势+折叠面板重做；非必需 |
| ui.widgets.pullextend.IExtendLayout | 状态接口/枚举 | （裁剪） | 裁剪 | — |
| ui.widgets.pullextend.mRecyclerView | 空壳 RecyclerView（原逻辑全注释） | （裁剪） | 裁剪 | 死代码 |
| ui.widgets.pullextend.PullExtendLayout | 下拉刷新+上拉加载容器（嵌套滚动/阻尼回弹） | （裁剪） | 裁剪 | 系统 Refresh + List onReachEnd 替代 |

### 12.3 today（今日桌面小组件 6 → feature/card 二期服务卡片）

| HITA_X 源文件(包.类) | 职责摘要(一句) | 移植去向 | 处置 | 备注(依赖/风险/API 映射) |
|---|---|---|---|---|
| ui.widgets.today.TodayWidget | 普通版桌面小组件 AppWidgetProvider（刷新所有实例） | feature/card/TodayForm.ets（二期） | 重写 | AppWidgetProvider→FormExtensionAbility onAddForm/onUpdateForm/onEventForm |
| ui.widgets.today.TodayWidgetSlim | 瘦身版桌面小组件（同 TodayWidget 逻辑） | feature/card（与普通版合并参数化） | 合并 | 两版合并为单组件+布局分支 |
| ui.widgets.today.ListWidgetService | 小组件集合列表数据桥（按 extra 分发工厂） | feature/card（二期，数据提供） | 重写 | RemoteViewsService→Form 数据/状态刷新 |
| ui.widgets.today.TodayUtils | 构建 RemoteViews：标题/列表/空态/PendingIntent | feature/card（二期） | 重写 | RemoteViews 模型弃；卡片由声明式 UI 完成；取数复用“今日事件同步查询” |
| ui.widgets.today.normal.ListRemoteViewsFactory | 普通版列表数据工厂（同步读当日事件） | feature/card/data（今日事件源） | 重写 | 读库逻辑复用 TimetableStore.getTodayEvents |
| ui.widgets.today.slim.ListRemoteViewsSlimFactory | 瘦身版列表数据工厂（与普通版重复） | feature/card（合并） | 合并 | 与普通版合并 |

## 13. 顶层独立模块（component/user/sync/theta/style，共 156 文件）

> 默认全部**裁剪**（蓝本 §1.2/§2.1）：θ社区需自有后端、sync 需服务端同步协议、user 为自有账号体系、style 为 Android View 基座库、component 为 LiveData/Retrofit 响应式与网络基座。下表中仅少量“可并入/可参考”项给出 ArkTS 去向；处置=裁剪的行无去向。清单按文件列出以便追溯。

### 13.1 component（10 文件）

| HITA_X 源文件(包.类) | 职责摘要(一句) | 移植去向 | 处置 | 备注(依赖/风险/API 映射) |
|---|---|---|---|---|
| component.data.DataState | 数据+状态(成功/失败/未登录/token 失效)+列表动作枚举 | common/state/DataState.ets | 合并 | 状态机语义保留（ArkTS class/enum），供全部请求结果用 |
| component.data.Trigger | 一次性 UI 动作触发标记 | common/state（事件令牌） | 合并 | UI 事件→EventHub/@Watch；可选保留令牌模式 |
| component.data.BooleanTrigger | Boolean 触发载体 | （裁剪） | 裁剪 | — |
| component.data.StringTrigger | String 触发载体 | （裁剪） | 裁剪 | — |
| component.data.MTransformations | MediatorLiveData map/switchMap 双源组合 | （裁剪） | 裁剪 | 状态派生在 ArkTS 用 @Watch/组合状态替代 |
| component.data.SharedPreferenceLiveData | SP 键值封装为可观察 LiveData | common/pref（可观察偏好） | 合并 | preferences 数据变化监听封装 |
| component.web.ApiResponse | 服务器响应 {code,message,data} | （裁剪） | 裁剪 | 自有后端弃；参考 common/net 响应结构 |
| component.web.BaseWebSource | Retrofit+OkHttp+Gson 服务构建基类（baseUrl=hita.store） | common/net/HttpClient.ets（概念） | 重写 | Retrofit→@ohos.net.http/request；Cookie 注入/重试语义并入 EasApiClient 设计 |
| component.web.LiveDataCallAdapter | Retrofit Call→LiveData 适配器 | （裁剪） | 裁剪 | — |
| component.web.SslContextFactory | BKS 证书库 SSLContext（已注释停用） | （裁剪） | 裁剪 | 死代码；勿迁移明文信任策略 |

### 13.2 user（24 文件：自有账号云端全部裁剪，本地资料模型并入 feature/profile）

| HITA_X 源文件(包.类) | 职责摘要(一句) | 移植去向 | 处置 | 备注(依赖/风险/API 映射) |
|---|---|---|---|---|
| user.data.model.UserLocal | 本地登录用户模型（含 isValid 判定） | feature/profile/model（会话本地态） | 合并 | 字段按需精简（去云端 token/publicKey） |
| user.data.model.UserProfile | 资料实体（profile 表） | feature/profile/model/UserProfile.ets | 合并 | RDB 表 profile 保留（EAS 身份回填+本地编辑） |
| user.data.UserDatabase | 用户模块 Room（profile 表 v1） | common/db（并入主库或独立 profile 表） | 合并 | 与 AppDatabase 合并为单库（可加 eas_session/settings） |
| user.data.TypeConverters | Room 转换（Timestamp/GENDER） | （裁剪） | 裁剪 | RDB 存基础类型 |
| user.data.model.ApiResponse | 服务器响应封装 | （裁剪） | 裁剪 | 自有后端弃 |
| user.data.model.CheckUpdateResult | 检查更新模型 | （裁剪） | 裁剪 | 更新策略另定（可本地版本比对） |
| user.data.model.FollowResult | 关注结果 | （裁剪） | 裁剪 | 社交功能不做 |
| user.data.model.LoginResult | 登录结果状态机 | （裁剪） | 裁剪 | 自有账号登录移除 |
| user.data.model.SignUpResult | 注册结果状态机 | （裁剪） | 裁剪 | 自有账号注册移除 |
| user.data.repository.LocalUserRepository | 本地登录态内存缓存+登出清库+资料编辑 | feature/profile/data/UserStore.ets | 重写 | 会话管理改为 EasSessionStore；本地资料编辑并入 |
| user.data.repository.ManagerRepository | 检查更新转发 | （裁剪） | 裁剪 | — |
| user.data.repository.ProfileRepository | 资料/关注/头像上传（DB 缓存+网络） | feature/profile/data（仅本地+EAS 身份部分） | 裁剪 | 云端部分裁；头像本地/相册 |
| user.data.repository.UserRepository | 登录/注册仓库（写 SP+触发同步） | （裁剪） | 裁剪 | — |
| user.data.source.dao.UserProfileDao | profile 表 DAO | common/db/ProfileDao.ets | 合并 | 随 UserProfile 入库 |
| user.data.source.preference.UserPreferenceSource | 登录用户 SP 存取（含 setUID） | （并入 EasSessionStore/Preferences） | 裁剪 | 会话持久化统一到 eas_session |
| user.data.source.web.ManagerWebSource | 检查更新网络源 | （裁剪） | 裁剪 | — |
| user.data.source.web.ProfileWebSource | 资料/关注/上传网络源 | （裁剪） | 裁剪 | — |
| user.data.source.web.UserWebSource | 登录/注册网络源 | （裁剪） | 裁剪 | — |
| user.data.source.web.service.codes | API 返回码常量 | （裁剪） | 裁剪 | — |
| user.data.source.web.service.ManagerService | Retrofit 检查更新接口 | （裁剪） | 裁剪 | — |
| user.data.source.web.service.ProfileService | Retrofit 资料/关注/上传接口 | （裁剪） | 裁剪 | — |
| user.data.source.web.service.UserService | Retrofit 登录/注册接口（包名错位残留） | （裁剪） | 裁剪 | 历史残留 |
| user.util.HttpUtils | Bearer 请求头拼装 | （裁剪） | 裁剪 | — |
| user.util.ImageUtils | Glide 圆形头像/dp2px | （裁剪） | 裁剪 | 并入 hitax ImageUtils 去向 |

### 13.3 sync（10 文件：默认裁剪）

| HITA_X 源文件(包.类) | 职责摘要(一句) | 移植去向 | 处置 | 备注(依赖/风险/API 映射) |
|---|---|---|---|---|
| sync.StupidSync | 增量同步引擎（本地 history→PUSH/PULL→委托写删） | （裁剪） | 裁剪 | 若未来做多端，服务端协议需重定（蓝本 §9.4） |
| sync.HistoryDatabase | history Room 库 | （裁剪） | 裁剪 | — |
| sync.TypeConverters | Room 转换 | （裁剪） | 裁剪 | — |
| sync.data.model.History | 同步记录实体 | （裁剪） | 裁剪 | — |
| sync.data.model.SyncResult | PUSH/PULL 判定结果 | （裁剪） | 裁剪 | — |
| sync.data.source.dao.HistoryDao | history DAO | （裁剪） | 裁剪 | — |
| sync.data.source.web.SyncWebSource | sync/push 网络源 | （裁剪） | 裁剪 | — |
| sync.data.source.web.service.codes | 返回码（与 user 重复） | （裁剪） | 裁剪 | — |
| sync.data.source.web.service.SyncService | Retrofit 同步接口 | （裁剪） | 裁剪 | — |
| sync.util.Snowflake | 雪花 ID 算法（纯算法） | common/util/Snowflake.ets（如需本地 ID 可移植） | 裁剪 | 纯函数可直接直译，备用 |

### 13.4 theta（θ社区，77 文件：默认整模块裁剪）

> 去向=裁剪。表按目录合并行，文件名全列（处置相同），供追溯；社区恢复需自有后端（蓝本 §9.3）。

| HITA_X 源文件(包.类) | 职责摘要(一句) | 移植去向 | 处置 | 备注(依赖/风险/API 映射) |
|---|---|---|---|---|
| theta 顶层（2 文件） | ThetaActivity=3Tab+底部导航主壳；ThetaViewModel=空占位 | — | 裁剪 | 社区主壳；无迁移 |
| theta.data.model（7 文件） | Article/Comment/LikeResult/Message/StarResult/Topic/VoteResult 纯字段模型 | — | 裁剪 | 均为 Serializable/字段类 |
| theta.data.repository（4 文件） | ArticleRepository(发帖压缩/列表/详情/赞投票藏删)、CommentRepository、MessageRepository(含未读)、TopicRepository | — | 裁剪 | 依赖 theta WebSource+Luban |
| theta.data.source.web（4 文件） | ArticleWebSource/CommentWebSource/MessageWebSource/TopicWebSource：Retrofit 数据源 | — | 裁剪 | 复用 stupidduser 的 codes/HttpUtils（冗余残留） |
| theta.data.source.web.service（5 文件） | ArticleService/CommentService/MessageService/TopicService Retrofit 接口；codes 冗余常量 | — | 裁剪 | — |
| theta.ui（1 文件） | DirtyArticles 跨页脏数据内存总线 | — | 裁剪 | 概念可在 ArkTS 用 EventHub 复刻，但社区整体裁剪 |
| theta.ui.comment（4 文件） | 发评论弹窗/VM/触发载体（CommentRefreshTrigger/CreateCommentFragment/CreateCommentRequest/CreateCommentViewModel） | — | 裁剪 | — |
| theta.ui.comment.reply（3 文件） | 楼中楼回复列表页与 VM、Adapter（点赞走 Call） | — | 裁剪 | — |
| theta.ui.create（5 文件） | 发文章页/VM/九宫格选图 Adapter/表单/Glide 圆角变换 | — | 裁剪 | 含选话题/匿名/态度 |
| theta.ui.detail（4 文件） | 文章详情页/VM/热门评论/图片 Adapter | — | 裁剪 | 详情约 494 行主页面 |
| theta.ui.list（4 文件） | 文章流 Fragment/主 Adapter(约430行)/VM/分页触发器 | — | 裁剪 | ListPage 在 4 处重复（见 style/note），可作 ArkTS 通用列表页参考 |
| theta.ui.list.activity（2 文件） | 文章列表独立页外壳+空 VM | — | 裁剪 | — |
| theta.ui.me（2 文件） | 我的页(登录态分流+未读角标)+VM | — | 裁剪 | — |
| theta.ui.message（3 文件） | 消息列表页/Adapter/VM | — | 裁剪 | — |
| theta.ui.navigation（3 文件） | 发现/广场：热搜话题格+文章流子页+搜索入口 | — | 裁剪 | — |
| theta.ui.search（2 文件） | 文章搜索页+空 VM | — | 裁剪 | — |
| theta.ui.topic（4 文件） | 话题列表 Fragment/Adapter/VM/分页触发器 | — | 裁剪 | 发帖选话题复用 |
| theta.ui.topic.detail（2 文件） | 话题详情(折叠头+文章流) | — | 裁剪 | — |
| theta.ui.topic.search（2 文件） | 话题搜索页（复用 TopicListFragment） | — | 裁剪 | — |
| theta.ui.user（4 文件） | 用户列表(关注/粉丝)Fragment/Adapter/VM/触发器 | — | 裁剪 | Adapter 直连 followCall |
| theta.ui.user.activity（2 文件） | 用户列表独立页外壳 | — | 裁剪 | — |
| theta.ui.widgets（5 文件） | EmoticonsEditText/TextView×2/MarkerViewSpan（@提及 span 渲染）、PhotoDetailActivity 大图 | — | 裁剪 | @渲染为原生 span，无迁移价值（除非社区恢复） |
| theta.utils（3 文件） | ActivityTools(含反射跳 hitax ProfileActivity)、ImageUtils、TextTools | — | 裁剪 | 反射跳宿主资料页说明 theta 强依赖 hitax/user 模块 |

### 13.5 style（35 文件：Android View 基座库，默认裁剪）

> 去向=裁剪。Actvity/Fragment/Adapter 基类与弹窗/选择器均为 Android View 体系，不跨语言迁移；仅交互/视觉模式作为 ArkUI 组件设计的“参考”。表中按子目录合并行。

| HITA_X 源文件(包.类) | 职责摘要(一句) | 移植去向 | 处置 | 备注(依赖/风险/API 映射) |
|---|---|---|---|---|
| style 根（2 文件） | MFileProvider(FileProvider 声明)；ThemeTools(主题模式 SP+切换重建) | — | 裁剪 | 主题深浅色由 ArkUI 系统主题/资源目录承担 |
| style.base（13 文件） | BaseActivity/BaseFragment×系(VM 注入+ViewBinding)、BaseActivity/FragmentWithReceiver(广播)、BaseListAdapter(约416行 diff 式刷新)/Classic/ViewHolder、BaseCheckableListAdapter、Basic(Multiple)Checkable/SelectableListAdapter、BaseTabAdapter、FragmentSearchResult 接口 | — | 裁剪 | 概念→ArkUI 组件/ForEach/List 多选/路由与状态管理；BroadcastReceiver→系统事件/定时器 |
| style.picker（3 文件） | FileProviderUtils/GalleryPicker/PermissionUtils（选图裁剪权限链路，与 hitax utils 重复） | — | 裁剪 | 鸿蒙侧由 PhotoViewPicker/abilityAccessCtrl 承担（见 hitax utils 行） |
| style.widgets（17 文件） | TransparentDialog/TransparentBottomSheetDialog/TransparentModeledBottomSheetDialog 基类 + PopUp* 系列（AutoEditText/CheckableList/ColorPicker/EditText/FloatPicker/MultipleCheckableList/SelectableList/SelectableLiveList/Text/Update）与 DialogAutoEditText/DialogSelectableLiveList/FocusTextView/MWheel3DView | — | 裁剪 | bottom-sheet→bindSheet/半模态；选择器→@ohos 选择器与 CustomDialog；更新弹窗策略另定 |

### 13.6 测试文件（10 个，统一裁剪）

| HITA_X 源文件(包.类) | 职责摘要(一句) | 移植去向 | 处置 | 备注(依赖/风险/API 映射) |
|---|---|---|---|---|
| app 等 6 模块测试（10 文件） | Example 骨架测试：app 2 个 + style/user/sync/theta 各 2 个 | — | 裁剪 | 迁移期在 ArkTS 侧按 ohosTest/unit 重建关键逻辑测试（TimeTools/周换算/重叠聚类/EAS 判定谓词等） |

## 14. 与蓝本 §2.1 处置表的差异修订说明

逐文件核对后，以下处置与蓝本 §2.1 的“包级一句话处置”存在**差异或需要澄清**（其余一致）：

1. **登录整块替换的范围比蓝本字面更宽**：§2.1 说“ui/eas/…login 整块替换”。本表确认不仅 `login/*`（PopUpLoginEAS 等 3 文件）弃用，连 `ui/welcome/*`（自有账号注册/登录 10 文件）也整体**裁剪**（蓝本 §1.2 已默认裁 user 云端，但 §2.1 表把 welcome 归入“P2 简化”——修订为：**不做**而非“简化保留”，WelcomeActivity 不再存在，主框架直入）。
2. **EAS 数据接口“重写”= 模型直迁 + 会话/网络全换**：§2.1 将 `data/**` 笼统标为“参照模型，重写网络/解析”。细化后：6 个 timetable 模型 + 5 个 eas 模型 + TimeInDay/TimePeriodInDay 等为**直接迁移**；`EASService` 接口面保留为 `EasDataProvider` 方法面（重写实现）；`EASource` 明确**弃用**（jsoup 登录+HTML 解析零迁移）。
3. **今日小组件：§2.1 说“两个小组件”二期服务卡片**。实测为 6 文件（TodayWidget/TodayWidgetSlim/ListWidgetService/TodayUtils + 2×ListRemoteViewsFactory），且两个 Factory 逻辑几乎重复——修订为：**两版合并**为一个参数化卡片实现后再迁移（处置=合并而非分别重写）。
4. **`ui/profile`（他人资料/关注/粉丝）与 `ui/myprofile`（本人编辑）应区分**：蓝本只说“个人资料本地化”。细分后 myprofile → feature/profile **重写**（去自有账号、EAS 身份回填）；profile 依赖 theta/user 社交后端 → **裁剪**（蓝本未单列，若保留他人资料页将产生云端账号依赖）。
5. **课表导入的归属**：EASRepository 中“拉取教务总课表→本地写库/展开事件”的核心逻辑（startImportTimetableOfTerm）在蓝本无明确文件归属。修订：页面放 feature/eas/pages/ImportTimetablePage，**写库服务 TimetableImportService 放 feature/timetable/data**（与本地模型/DAO 同层），避免 eas 反向依赖 timetable 数据面。
6. **两个“死代码/注释遗留”文件应显式标注裁剪**：`ui/base/BaseEditableListAdapter.kt`、`ui/widgets/pullextend/mRecyclerView.kt`、`ui/myprofile/ProfilePage.kt`、`ui/theme/Color.kt|Theme.kt`（Compose 遗留疑似未用）与 `component/web/SslContextFactory.kt`（已注释）——蓝本未提及，均判**裁剪**，避免迁移时误工。
7. **NavigationFragment（功能中心页）的去向蓝本未定**：它同时承担“用户卡/EAS 卡/课表与 EAS 各功能入口”。修订：入口集散页归 **feature/profile（NavigationHubPage）**，不单设 feature-home；EAS 登录状态卡与 webLogin 门禁联动。
8. **style/component 两模块**：蓝本“概念迁移（BaseList→ArkUI 组件等）”。细化后确认二者**无数据层可迁移**（style 全部为 View 基座），仅 DataState/Trigger/BaseWebSource 的“状态与网络封装”概念以 common/state、common/net 形式吸收；表内行按文件全部标“裁剪/合并参考”，不留“半迁移”状态。
9. **user 模块并入范围收窄**：蓝本“保留 user 的本地资料模型可并入”。逐文件核对后**仅 5 个文件并入**（UserLocal/UserProfile/UserDatabase/UserProfileDao 与 LocalUserRepository 的本地资料编辑部分），其余 19 个云端/服务/工具文件全部裁剪——比“模型并入”口径更精确。

## 15. 统计口径说明

- 第 0 节数字由文档表格逐行解析得出：表行 252（每个生产源文件一行，同处置同去向合并行按“（N 文件）”折算），合计覆盖 346 个文件。
- 处置判定：按各行「处置」列主词归并（“拆分/重写”计入重写；“合并”含并入既定 ArkTS 文件者；弃用特指被新版登录/会话方案显式替换）。
- 裁剪比例口径：默认裁剪（200）+弃用（4）= 204/346 = 59.0%；若按生产代码 336 计且不含测试文件，裁剪 190/336 = 56.5%。

<!-- END -->






