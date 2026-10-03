# HITA_X 课表周视图 → ArkUI Canvas 移植笔记

源目录：`HITA\.analysis\HITA_X-master\app\src\main\java\com\stupidtree\hitax\ui\main\timetable\`
目标读者据此写 ArkTS Canvas 组件（Stack 网格 + Canvas 绘制 + 子组件叠放皆可）。
行号 = 源文件内行号。`px` = Android 原始像素（未乘 density），`dp` = 尺寸资源。**凡无法从源码确定处均标注，不臆测。**

---

## 0. 视图层级总览（先看结构）

自上而下：

```
FragmentTimetableBinding (fragment_timetable.xml)
├─ 顶部固定行：month(月) TextView + 7 个「星期名」圆点(周一…周日)，paddingBottom=4dp，高度 wrap
│    (fragment_timetable.xml:13-180；圆 28dp、textSize 10sp、背景 element_round_primary_lighter 圆角)
└─ VerticalNestedScrollView ── 水平 LinearLayout
     ├─ LeftLabelView「labels」 宽 @dimen/timetable_label_width=24dp，marginTop=24dp
     │     (fragment_timetable.xml:193-199)
     └─ WrapContentHeightViewPager「pager」（横向翻页 = 切周）
          └─ 每页 = TimetableWeekView (view_timetable_week.xml, LinearLayout VERTICAL, MATCH_PARENT)
               ├─ 日期数字行：高 @dimen/timetable_date_height=24dp（月 TextView GONE + 7 个日数字）
               │     (view_timetable_week.xml:9-110；日数字 11sp、alpha 0.9、水平均分 weight=1)
               └─ TimeTableView「timetableView」 marginTop=4dp marginBottom=2dp
                     (view_timetable_week.xml:112-121)
```

- 7 列 = 周一..周日；dow 语义 **周一=1 … 周日=7**（`TimeTools.getDow`，TimeTools.kt:69-78；EventItem.kt:72-74）。
- **没有任何“双周/单双周”UI**：本 fragment 只按“周”横向翻页（见 §2）。若旧版有双周格，本仓库未实现。
- 顶行星期名（周一…周日）在滚动区**外**固定；每页自己的日期数字行（1 日…7 日）随内容滚动。
- LeftLabelView 的 marginTop=24dp 恰好等于每页日期数字行高 24dp，使小时刻度与网格对齐（差值 4dp 见 §5 注）。

---

## 1. TimetableWeekView.kt —— 周视图外壳（仅 87 行，逻辑很薄）

- `TimetableWeekView : LinearLayout`（VERTICAL），inflate `view_timetable_week.xml`，内部持有一个 `TimeTableView`（id=timetableView，view_timetable_week.xml:112）+ 8 个 `TextView`（topDateTexts[0..7]：0=月，1..7=日数字，TimetableWeekView.kt:16,58-70,78-85）。
- 回调全部转发给内部 TimeTableView：`setOnCardClickListener / setOnAddClickListener / setOnCardLongClickListener`（:34-44）。
- `refresh(startDate, events, style, dateOnly)`（:47-56）：
  - 先 `setDateTexts(startDate)`：topDateTexts[0]=月份字符串（R.array.months），topDateTexts[k]=startDate+(k-1) 天的「日」，即 7 个日数字分别对应该页周一..周日（:58-70）。
  - `dateOnly=true` 只 `setStartDate`（改页日期、不重建）；否则 `notifyRefresh(startDate, events, style)` 全量重建（:54-55）。
- `getStyleSheet()` / `getEventsViewNum()`（=childCount 事件块数）供 fragment 判断“是否值得全量刷新”（TimetableFragment.kt:139-142）。
- **重要**：周视图没有自己的坐标算法 —— 全部几何在 TimeTableView 内；本文件只负责“页=一周(周一00:00 起)+头部日期”。

---

## 2. TimeTableView.kt —— 网格几何核心（最重要的移植参考）

### 2.1 网格参数与坐标体系（px）

| 变量 | 来源 | 值 |
|---|---|---|
| `sectionWidth` | onMeasure 中 `mWidth/7` 整除 (px) | 每列宽（:258） |
| `sectionHeight` | `styleSheet.cardHeight`（默认 **180**） | **每小时高 180px**（:29,134,291） |
| `endTime` | 默认 `TimeInDay(24,0)`（:31） | 网格底端 24:00 |
| `startTime` | styleSheet 默认 **800 = 08:00**（TimetableStyleSheet.kt:18） | 网格顶端 |
| 网格高度 | `totalMinutes/60*sectionHeight`，EXACTLY（:244-257） | (24:00−08:00)=16h → **2880px** |
| `timetableStructure` | **static** `Timetable().scheduleStructure`（:24），fragment 切学期时覆写（TimetableFragment.kt:209） | 节次表（见 §6.3） |

- `mWidth`=整宽 px；**列数固定 7，无左右留白、无内部 gutter**（块的自带 margin 见 §3）。
- 时间换算的核心公式（全文件通用）：
  - `minutesFromStart(t) = (t的时 − startHour)*60 + t的分 − startMin`（TimeInDay.getDistanceInMinutes，TimeInDay.kt:44-67）
  - `yTop = minutesFromStart / 60f * sectionHeight`（:310）
  - `blockHeight = durationMinutes / 60f * sectionHeight`（:311）
  - `xLeft = sectionWidth * (dow − 1)`，`xRight = xLeft + sectionWidth`（:306-308）
- **课程块定位是按“真实时刻分钟”而非节序号**：EventItem.from/to 是绝对 Timestamp（数据库按学期周写出），EventItem.kt:32-35；fromNumber/lastNumber 字段存在（:36-37）但**周视图布局未使用**——只有 add 流程把节次→时刻（§2.4）。节次 → 时刻映射用 `Timetable.scheduleStructure[i].from/.to`（Timetable.kt:50-62）。

### 2.2 绘制顺序 dispatchDraw（:68-74,92-118）

1. 若本页 startDate 所在周 == 当前周（`TimeTools.isSameWeekWithStartDate`，即 `now ∈ [pageStart, pageStart+WEEK_MILLS)`，TimeTools.kt:113-122）→ `drawTodayRect`：**整列高亮**，`left=sectionWidth*(currentDOW-1)`，fill 到 mHeight，色 `styleSheet.todayBGColor`（默认 `#10000000` 约 6% 黑，TimetableStyleSheet.kt:23）。**这就是“今日/当前周”高亮的全部机制**（:92-98）。
2. `drawLabels`：小时虚线，仅 `styleSheet.drawBGLine==true` 时画；`mLinePaint` stroke 1px、色=timelineColor（XML `custom:timeLineColor`，默认 BLACK）、alpha=50、`DashPathEffect([20f,20f],0)`（20px 虚/20px 空）；对 i ∈ [startHour..23] 在 `y=i小时线=i*sectionHeight−startHour*sectionHeight` 画横线 0..mWidth（:101-118）。
3. `super.dispatchDraw` 画子视图（各 TimeTableBlockView）。

> 未画竖线（列分隔线）——背景仅小时横虚线。也**没有整页背景色**逻辑（除今日列遮罩）。

### 2.3 事件 → 画块：聚合与重叠处理（:121-188,339-372）

- `notifyRefresh`（:124-135）：存 styleSheet/startDate → `removeAllViewsInLayout` → 对 `aggregateEvents(events)` 每组 `addBlock` → invalidate → `sectionHeight = cardHeight`。
- `aggregateEvents`（:158-188）：
  1. 先按 dow 分 7 桶（:163-165）；
  2. 每桶按 from 升序（:169）；
  3. 归并成 Interval（同一纵列内互相重叠且重叠度较大的课合为一张“重复卡”）：
     - 新 Interval：无重叠 `last.to < e.from`，**或**重叠 < 各自时长的 50%（`:172-176` 条件：`last.to−e.from < e.duration*0.5 && last.to−e.from < last.duration*0.5` 时为不重叠判据的补集——即“重叠不到任一者一半”则分开，否则合并）。
     - 合并时 Interval 扩张到 `[min from, max to]`、事件入组（:148-155）。
- `addBlock`（:339-372）：单事件 → `TimeTableBlockView(ctx, o[0], style)`；多事件 → 复用构造 `TimeTableBlockView(ctx, o, style)`（重复卡外观见 §3.4），并分别接 click/longClick/duplicate 回调。
- 回调接口：OnCardClickListener（onEventClick / onDuplicateEventClick）、OnCardLongClickListener、OnAddClickListener（:374-390）。

### 2.4 空白点击 → “添加”浮层（触发条件与 TimeTableBlockAddView 关系）

- `init()` 置 `isClickable=true` 才收得到触摸（:289-293）。课程块自身 clickable，触摸被子 View 消费；**父级 onTouchEvent 只在点到“空白处”时收到**。
- `onTouchEvent`（:198-239）：
  - 任何非 ACTION_UP：`removeView(addButton)`（隐藏浮层，:236）。
  - ACTION_UP：先 `removeView(addButton)`，再算落点：
    - `dow = floor(x / sectionWidth) + 1`（:202；注意靠右边缘可能算出 8——原实现缺陷，移植应 clamp 1..7）；
    - `time = startTime + floor(y / sectionHeight * 60)` 分钟（:204）；
    - 在 `timetableStructure` 中匹配该时刻所在节/空隙（:206-222）：
      - 在首节前 → `[startTime, 首节.from)`；
      - `contains(time)` → 该节克隆；
      - 落在节 i 与 i+1 之间 → `[节i.to, 节i+1.from)`；
      - 在末节后 → `[末节.to, 23:59]`；
      - 落点比 startTime 早则钳到 startTime（:224）。
  - 若 period != null：add `TimeTableBlockAddView(context, period, dow)`（尺寸 = 该空隙的 from..to，见 :272-278 测量、:322-331 布局），点其“+”图标 → `onAddClick(dow, period)`（fragment 弹 PopupAddEvent 新建课程，TimetableFragment.kt:304-326）→ 移除浮层（TimeTableBlockAddView.kt:27-31）。
  - **“空白点击添加”触发条件** = TimeTableView 空白区域 ACTION_UP，且该 y 时刻能映射出一个非空 time gap/节；**不会直接创建事件**，只显示半透明 + 号浮层需二次点击确认（浮层样式见 §3.5）。
- 触摸结束返回 `super.onTouchEvent`（无手势代码：**左右滑切周由外层 ViewPager 完成，不是本 View 手势**）。

### 2.5 测量与布局（:241-337）

- onMeasure：自身高度 EXACTLY 固定（见上表），块/NowLine/AddView 分别 measure（宽=sectionWidth；块高=duration 映射；NowLine 高 4px；AddView 高=duration 映射）。
- onLayout 对三类子视图统一按分钟→px 摆放（:295-337）：
  - TimeTableBlockView：`layout(sectionWidth*(dow−1), minutesFromStart/60f*sectionHeight, +sectionWidth, +duration 高)`；
  - TimeTableNowLine：`layout(0, 当前时刻距 start 分钟/60f*sectionHeight, mWidth, top+4)`（:315-321）—— **全宽**（左 0 右 mWidth），高 4px；
  - TimeTableBlockAddView：同块公式，`top = startTime.getDistanceInMinutes(period.from)/60f*sectionHeight`，高 = `period.getLengthInMinutes()/60f*sectionHeight`（:322-331）。
- 块实际绘制区域 = 网格单元，视觉缩小靠块内部卡片的 margin（见 §3.2），不是网格留白。

---

## 3. TimeTableBlockView.kt —— 课程块外观与交互

### 3.1 结构

`TimeTableBlockView : FrameLayout`，构造入参 `block: Any`（单个 EventItem 或合并 List）+ styleSheet。`onAttachedToWindow` 时按类型 inflate（:118-125）：
- 单事件 → `fragment_timetable_class_card.xml`
- 合并列表 → `fragment_timetable_duplicate_card.xml`

### 3.2 单课程卡外观（fragment_timetable_class_card.xml + :53-115）

- 卡内 LinearLayout `card`（match/match，**margin L1dp/T1dp/R1dp/B2dp**）垂直排列：
  - `icon`：ImageView 8dp×8dp 圆点，居中、四周 margin 3dp（顶部额外 3dp）；
  - `title`：TextView，左右 margin 4dp、上 2dp，weight=1 居中，**maxLines=4，textSize 12sp**，gravity 可被 styleSheet.titleGravity 覆盖（默认 CENTER，TimetableStyleSheet.kt:24）；
  - `subtitle`：TextView wrap、左右 4dp、下 2dp，**singleLine + marquee(横向滚动)，textSize 11sp，textStyle bold**；内容 = **`ei.place`（地点，非教师）**，place 为空则空串（:106）；teacher 字段不展示。
- 背景/着色（:60-69,107）：
  - `isFadeEnabled`(默认 true) → 渐变 drawable `spec_timetable_card_background_fade`（45° #beffffff→白，radius **12dp**，spec_timetable_card_background_fade.xml:6-15）；否则纯色 drawable `spec_timetable_card_background`（白底 radius **12dp**，.xml:12-13）；
  - 然后 `card.backgroundTintList = ei.color`（科目色）或 theme colorPrimary（`isColorEnabled` 默认 true；:65-69）；
  - **透明度**：`card.background.mutate().alpha = round(255 * cardOpacity/100)`，cardOpacity 默认 **95 → alpha≈242**（:107）。
- 文字颜色（title/subtitle 各自独立策略，默认 `"white"`，:70-85）：white/black/primary(主题色)/subject(科目色)。
- 图标色：icon 默认白 8dp 圆点 + `cardIconEnabled` 默认 true（:86-99；图标色规则同上，white/black/primary/subject）。
- 粗体：`isBoldText`(默认 true) → 标题/副标题 DEFAULT_BOLD（:108-111）。
- 额外 alpha：`title.alpha = titleAlpha/100`（默认 100）、`subtitle.alpha = subtitleAlpha/100`（默认 **60**，:112-113）。
- 点击/长按：`card.setOnClickListener → onEventClick(v, ei)`；长按 → onEventLongClick 返回是否消费（:101-104）。fragment 侧：点击=EventsUtils.showEventItem 详情；长按=PopupMenu（删除：确认后 ExplosionField 爆炸粒子 + haptic，再入库删除，TimetableFragment.kt:256-303）。

### 3.3 合并(重复)卡外观（fragment_timetable_duplicate_card.xml + :128-191）

- 只显示**课程名**：`names.joinToString(",\n")`（:135-137），无地点/教师行。
- 双层卡：外层 `card`（margin L1/T1/R1/B2，radius **8dp** `spec_timetable_card_background_duplicate`，:12-13）+ 内层 `card1`（同 drawable，marginBottom 6dp，weight 1）+ 右下角 20dp 箭头图标（旋转 −45°，白色）。
- 着色（:148-168）：内层 `card1` 用 `list[0]` 色，外层 `card` 用 `list[1]` 色（仅 1 个事件时同色）；`card.background.mutate().alpha = cardOpacity 映射`（:185）；标题规则同 §3.2（title 12sp、center|top、maxLines=4，:137）；无 subtitle。
- 点击 → onDuplicateEventClick(v, list)；长按 → onDuplicateEventLongClick（:138-147）。

### 3.4 辅助几何 getter（:198-233）

- `getDow()`：单事件 = ei.getDow()；列表 = 首事件（按 bucket 保证同列）。
- `getDuration()`：单事件 = 分钟差；列表 = maxEnd−minStart 分钟。
- `getStartTime()`：单事件 from.time；列表 = 各组员最小 from（→ 合并卡的 yTop 用最早开始）。

### 3.5 TimeTableBlockAddView（添加浮层，TimeTableBlockAddView.kt + dynamic_timetable_block_add.xml）

- FrameLayout 铺在目标空隙格上：整格 ImageView `card`（圆角 8dp 主题按钮底，**alpha 0.2**）+ 居中 32dp “+” 图标（ic_baseline_add，colorAccent，内 padding 4dp，:13-38）。
- 点 “+” 或 card → onAddClickListener → 父 fragment 打开添加页，随即从父 View 移除浮层（.kt:27-32）。duration getter = period 分钟长（.kt:14-15）。

---

## 4. TimeTableNowLine.kt —— “现在时间线”（**本仓库为死代码**）

- 类本身仅 34 行：`View`，构造传 color → setBackgroundColor(color)（:12-19）。
- **没有任何代码实例化/添加它**（grep 全仓库：仅 TimeTableView 测量/布局 switch 分支引用，TimeTableView.kt:267-271,315-321；styleSheet.drawNowLine 标志位也无人读取，TimetableStyleSheet.kt:27）。→ 现版本不显示 NowLine。
- 若 ArkTS 要补此线，其布局算法（死代码里可见的完整意图）：
  - 宽 = **全宽** `0..mWidth`（不是今天列宽；measure 曾给 sectionWidth 但 onLayout 覆盖为 mWidth，:268 vs :320）；
  - 高 = **4px**；
  - `yTop = startTime.getDistanceInMinutes(nowMillis)/60f * sectionHeight`（:316-319）；
  - 绘制 = 纯背景色实心 View（无端点圆点/箭头）。
  - 原代码无“每秒/分钟定时刷新”机制；若实现，建议按 min 对齐。整周翻页时各页都会出现线（若全加），只有当前周页有意义——移植时建议仅当页含今天时画。

---

## 5. LeftLabelView.kt —— 左侧节次时间标签

- 自定义 View，直接 onDraw 文本；无子视图。
- 绘制范围：`i ∈ [startDate.hour .. 23]`，每个整点画一条时间文本（:61-66）：
  - `temp.hour = i`；`yTop = startDate.getDistanceInMinutes(temp)/60f * sectionHeight`；
  - 画字坐标：x=0，**textAlign=LEFT**，baseline y = `yTop + labelSize`（:64-65）→ 文本紧贴在该小时线上方基线之下（视觉上“刻度文字位于整点线上/下沿”，非精确居中）。
- 文本 = `temp.toString()`：TimeInDay.toString 分钟为 0 → `"8:00"`，否则 `"8:30"`（**无前导 0**，TimeInDay.kt:28-31）。
- `sectionHeight` 字段默认 180（:54），**全仓库无人给它赋值**——若 styleSheet.cardHeight 被改（非默认 180）刻度会与网格错位（源码缺陷，移植应让标签复用网格每小时高）。
- `setStartDate(hour, minute)` 由 fragment 的 startTimeLiveData 驱动：`it/100, it%100`（TimetableFragment.kt:129-131）→ 默认 8,0。
- 样式：labelSize 来自 XML `custom:timeLabelSize`（fragment 里 **11sp**；attr 默认 sp8，LeftLabelView.kt:38-42）；**labelColor 解析了但绘制固定用 Color.BLACK（:58 硬编码），labelColor 未被使用 —— 源码缺陷**。标签无背景。
- 注：LeftLabelView marginTop=24dp、网格实际顶部还有 marginTop=4dp（view_timetable_week.xml:116），二者相差 4dp，原实现并未对齐到像素级（视觉误差 4dp，可接受）。

---

## 6. Fragment / ViewModel / StyleSheet —— 状态与常量

### 6.1 TimetableFragment Companion 常量（TimetableFragment.kt:37-40）

- `WINDOW_SIZE = 5`（同时存活 5 页）。
- `WEEK_MILLS = 1000*60*60*24*7`（7 天毫秒，:39）。
- Pager 伪无限：`getCount() = WINDOW_SIZE * 80000`（:343-345），初始 `currentItem = count/2 + WINDOW_SIZE/2`（:118，中心落在当前周）。
- “周上界”不在 fragment 而在 `Timetable.getWeekNumber(ts)`（Timetable.kt:30-47）：以学期 `startTime`(周一00:00) 为第 1 周，`week = round((ts − startTime)/WEEK_MILLS)+1`；ts 早于学期或晚于 `endTime` 返回 −1 → UI 显示“假期/无课表”（TimetableFragment.kt:196-213）。

### 6.2 周切换（滑动）状态机（TimetableFragment.kt:76-158,238-379）

- `onPageSelected`：与 `currentIndex` 差 ≤ WINDOW_SIZE/2 才处理；左滑 = 当前中心日期 `addStartDate(−WEEK_MILLS)` + 窗口左滚；右滑同理（:89-112）。即**每次只翻一周**，用 5 页环形窗口复用（scrollLeft/scrollRight 只改写一页的 windowStartData，:347-356）。
- 环形窗口：`windowStartData[i]` 记第 i 槽的周一 00:00；事件 = `getEventsDuringWithColor(slotStart, slotStart+WEEK_MILLS)`（TimetableViewModel.kt:55-60）。当前页索引语义：`currentPageStartDate` 恒为**中心页**的周一 00:00。
- `scrollToDate`（FAB“回到今天”，:221-235,358-379）：把日期归一到本周周一 00:00，再在窗口内平移页码（超出则整体重建窗口并重设 startIndex）。
- 数据刷新路径：`timetableLiveData`（List<Timetable>）与 `currentPageStartDate` 任一变化 → `refreshWeekLayout`（更新标题/学期/静态 timetableStructure，:183-213）；每槽 windowStartData → 事件查询 → windowEventsData（Pair<events, styleSheet>）→ `views[i].refresh(...)`，用 style 引用/hash/块数差判断是否全量（:132-150）。
- 今日高亮判断 `drawTodayRect` 只发生在“页包含今天”的页（§2.2）。

### 6.3 TimetableStyleSheet（样式状态，TimetableStyleSheet.kt:7-38）

默认值：`isColorEnabled=true, isFadeEnabled=true, cardTitleColor/subTitleColor/iconColor="white", isBoldText=true, drawBGLine=true, cardIconEnabled=true, cardOpacity=95, cardHeight=180(px/小时), startTime=800(08:00), todayBGColor=#10000000, titleGravity=CENTER, titleAlpha=100, subtitleAlpha=60, drawNowLine=true(未用)`。equals/hashCode 全字段参与（:40-84）→ fragment 用“style 对象不同则全量刷新”。

### 6.4 默认节次表（Timetable.getDefaultTimeStructure，Timetable.kt:101-116）——ArkTS 作息表默认值

| 节 | from | to | | 节 | from | to |
|---|---|---|---|---|---|---|
| 1 | 08:30 | 09:20 | | 7 | 16:00 | 16:50 |
| 2 | 09:25 | 10:15 | | 8 | 16:55 | 17:45 |
| 3 | 10:30 | 11:20 | | 9 | 18:45 | 19:35 |
| 4 | 11:25 | 12:15 | | 10 | 19:40 | 20:30 |
| 5 | 14:00 | 14:50 | | 11 | 20:45 | 21:35 |
| 6 | 14:55 | 15:45 | | 12 | 21:40 | 22:30 |

- 节↔时刻换算（用于定位/新建）：`getTimestamps(week,dow,start节,end节)` = 学期起点 + (week−1)·7d + (dow−1)·1d + structure[start−1].from / structure[end−1].to（Timetable.kt:50-53）；add 时 `transformCourseNumber(period)` 反向节号 1 基（:64-72）。

### 6.5 数据模型关键字段

- `EventItem`（EventItem.kt:14-49）：`id,type(CLASS…),name,place,teacher,subjectId,timetableId,from/to:Timestamp,fromNumber,lastNumber`（节次 1 基，用于创建/重复逻辑，不参与周视图布局）；运行期 `color`（科目色，非持久化 :45）。getDow/getDurationInMinutes/getDurationInMills/containsTimeStamp（:55-108）。
- `TimeInDay`（TimeInDay.kt）：hour/minute、getAdded(min)、getDistanceInMinutes(h:m|ts)、toString `h:mm`。
- `TimePeriodInDay`（TimePeriodInDay.kt）：from/to、contains、before/after、getLengthInMinutes、clone。
- `Timetable`（Timetable.kt）：startTime/endTime（学期起止 Timestamp）、scheduleStructure、getWeekNumber、getDefaultTimeStructure。

---

## 7. 像素/尺寸常量汇总（单位已标注）

dp（资源，density 缩放）：
- `timetable_label_width = 24dp`（左侧时间列宽；dimen.xml:11）
- `timetable_date_height = 24dp`（每页日期数字行高；dimen.xml:12）
- 每页网格 TimeTableView margin：top **4dp**、bottom **2dp**（view_timetable_week.xml:116-117）
- 卡内 margin：L/T/R/B = **1/1/1/2dp**；图标 8dp(边距3dp)；标题 12sp(边 4dp、上 2dp、maxLines 4)；副标题 11sp bold 单行滚动(下 2dp)；卡圆角 **12dp**（fade 同 12dp）；重复卡圆角 **8dp**（双卡间距 6dp）；+ 号浮层 icon 32dp（alpha 0.2 底、圆角 8dp）
- 顶行星期名圆 **28dp**（字 10sp）、星期列 paddingBottom 4dp；fragment 月字 10sp、页内日期数字 11sp(alpha 0.9)；LeftLabelView 字 **11sp**（标签无背景、无宽边距）
- FAB margin 16dp（回到今天）

px（未乘 density，直接用于 measure/canvas）：
- `cardHeight/sectionHeight = 180px` = 每小时高度（网格总高 = (24:00−startTime)/60×180）
- 小时虚线：宽 1px、Dash 20/20、alpha 50
- NowLine：高 4px、全宽（死代码）
- 默认网格高 = 2880px、网格宽 = 容器宽（7 列等分 `mWidth/7` 整除）

> ⚠️ 移植建议：Android 侧“180”按 px 使用（density 不参与），屏幕密度不同会变矮/高；**ArkTS 不应抄死 180px**，应取相对比例：`小时高 H = (可用高/最大节次跨度小时数)`，课程块按分钟线性插值即可视觉一致。

---

## 8. ArkTS Canvas 复刻公式（结论版）

设：`start = 8:00`（可配），跨度 16h→24:00；`colW = gridW/7`；左侧时间列 `labelW=24dp 比例`（原 24dp）；`H = gridH / (24:00−start 小时数)`。

- 每列 x：`col(dow) = (dow−1)*colW`（dow 1..7，周一=1）
- 事件块：`x = col(dow)`；`y = (eventStartMin − startMin)/60 * H`；`h = eventDurMin/60 * H`；`w = colW`
- 内边视觉：块内再收边 ≈ 1/1/1/2 dp 比例；圆角 12dp 比例（小卡 8dp）
- 小时线：`y_i = (i−startHour)*H`，i = startHour..23
- 今日列高亮：仅当本周，列 dow=今天，全高 fill `#10000000`
- NowLine（可选）：全宽，`y = (nowMin − startMin)/60 * H`
- 空白点击 add：dow、时刻→节（§2.4 规则）；y 必须 clamp 到网格内
- 重复卡：外层色=list[1]、内层色=list[0]、多课程名逗号/换行拼接
- 时间轴坐标原点：Android 是 View 自身 top；ArkTS 若含头部 24dp 日期行/顶部标题，注意叠加偏移，别把 8:00 画到 (0,0) 之外的口径混掉

**主要存疑点**（未臆测，标来源）：
1. NowLine 无任何实例化与定时刷新（§4）——是否要线、什么更新频率由产品决定。
2. `LeftLabelView.sectionHeight` 无人赋值；labelColor 解析未用（§5）——均为源码缺陷。
3. 无“双周模式/单双周”代码路径（§0）。
4. 网格高/宽用原始 px，密度相关（§7）——复刻取相对比例。
5. dow 边缘溢出 8、重叠卡归并 50% 阈值等行为已注明（§2.3/2.4），照抄或修正自行决定。
6. 卡片文字、标题 gravity、图标显隐等全部可配项默认值见 §6.3，按需暴露设置。
