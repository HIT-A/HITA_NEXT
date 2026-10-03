/**
 * SearchPage.ets — 搜索本地课程、教师与地点。
 */
import { common } from '@kit.AbilityKit';
import { HeaderBackButton } from '../common/components/HeaderBackButton';
import { RdbHelper } from '../common/db/RdbHelper';
import { EasEventItem } from '../common/model/timetable/TimetableModels';

class SearchResultRow {
  kind: string = '';   // 教师 / 地点
  name: string = '';
  count: number = 0;
}

@Entry
@Component
struct SearchPage {
  @State rows: SearchResultRow[] = [];
  @State keyword: string = '';
  @State note: string = '搜索课程、教师或地点';
  @State searched: boolean = false;

  async doSearch(): Promise<void> {
    const kw: string = this.keyword.trim().toLowerCase();
    if (kw.length === 0) {
      this.note = '请输入关键字';
      return;
    }
    const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
    const rdb: RdbHelper = RdbHelper.getInstance();
    await rdb.init(ctx);
    // 收集全部事件中的教师/地点（跨课表 + 独立事件 timetableId=='' 也要）
    const candidates: EasEventItem[] = [];
    const tts = await rdb.getTimetables();
    for (let i = 0; i < tts.length; i++) {
      const list = await rdb.getEventsOfTimetable(tts[i].id);
      for (let j = 0; j < list.length; j++) {
        candidates.push(list[j]);
      }
    }
    // 独立事件（timetableId==''，如事件编辑页新建）
    const alone = await rdb.getEventsOfTimetable('');
    for (let j = 0; j < alone.length; j++) {
      candidates.push(alone[j]);
    }

    const teacherMap: Map<string, number> = new Map<string, number>();
    const placeMap: Map<string, number> = new Map<string, number>();
    const nameMap: Map<string, number> = new Map<string, number>();
    for (let i = 0; i < candidates.length; i++) {
      const ev: EasEventItem = candidates[i];
      if (ev.teacher.length > 0 && ev.teacher.toLowerCase().indexOf(kw) >= 0) {
        teacherMap.set(ev.teacher, (teacherMap.get(ev.teacher) ?? 0) + 1);
      }
      if (ev.place.length > 0 && ev.place.toLowerCase().indexOf(kw) >= 0) {
        placeMap.set(ev.place, (placeMap.get(ev.place) ?? 0) + 1);
      }
      if (ev.name.length > 0 && ev.name !== 'NULL' && ev.name.toLowerCase().indexOf(kw) >= 0) {
        nameMap.set(ev.name, (nameMap.get(ev.name) ?? 0) + 1);
      }
    }
    const out: SearchResultRow[] = [];
    teacherMap.forEach((count: number, name: string) => {
      const row: SearchResultRow = new SearchResultRow();
      row.kind = '教师';
      row.name = name;
      row.count = count;
      out.push(row);
    });
    placeMap.forEach((count: number, name: string) => {
      const row: SearchResultRow = new SearchResultRow();
      row.kind = '地点';
      row.name = name;
      row.count = count;
      out.push(row);
    });
    nameMap.forEach((count: number, name: string) => {
      const row: SearchResultRow = new SearchResultRow();
      row.kind = '事件';
      row.name = name;
      row.count = count;
      out.push(row);
    });
    out.sort((a: SearchResultRow, b: SearchResultRow): number => {
      return b.count - a.count;
    });
    this.rows = out;
    this.searched = true;
    this.note = '找到 ' + out.length.toString() + ' 项（教师 ' + teacherMap.size.toString() +
      ' / 地点 ' + placeMap.size.toString() + ' / 事件 ' + nameMap.size.toString() + '）';
  }

  build() {
    Column() {
      Row() {
        HeaderBackButton({
          onBack: () => this.getUIContext().getRouter().back()
        })
          .margin({ right: 12 })
        Text('本地搜索')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1A1A1A')
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .backgroundColor('#FFFFFF')
      .border({ width: { bottom: 1 }, color: '#EAECF0' })
      .alignItems(VerticalAlign.Center)

      Row({ space: 8 }) {
        TextInput({ placeholder: '课程 / 教师 / 地点', text: this.keyword })
          .layoutWeight(1)
          .height(40)
          .backgroundColor('#FFFFFF')
          .borderRadius(20)
          .border({ width: 1, color: '#EAECF0' })
          .onChange((value: string) => {
            this.keyword = value;
          })
          .onSubmit(() => {
            this.doSearch();
          })
        Button('搜索')
          .height(40)
          .padding({ left: 20, right: 20 })
          .backgroundColor('#3390EC')
          .borderRadius(20)
          .onClick(() => {
            this.doSearch();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      Text(this.note)
        .fontSize(12)
        .fontColor('#666666')
        .width('100%')
        .padding({ left: 16, bottom: 8 })

      if (!this.searched || this.rows.length === 0) {
        Column() {
          Text(this.rows.length === 0 && this.searched ? '无匹配结果' : this.note)
            .fontSize(14)
            .fontColor('#888888')
            .margin({ bottom: 12 })
        }
        .width('100%')
        .margin({ top: 40 })
      } else {
        List({ space: 8 }) {
          ForEach(this.rows, (row: SearchResultRow) => {
            ListItem() {
              Row() {
                Text(row.kind)
                  .fontSize(11)
                  .fontColor('#FFFFFF')
                  .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                  .borderRadius(8)
                  .backgroundColor(row.kind === '教师' ? '#3390EC' :
                    (row.kind === '事件' ? '#7E57C2' : '#26A69A'))
                Text(row.name)
                  .fontSize(15)
                  .margin({ left: 8 })
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(row.count.toString() + ' 次')
                  .fontSize(12)
                  .fontColor('#8A8F99')
              }
              .width('100%')
              .padding(12)
              .backgroundColor('#FFFFFF')
              .borderRadius(10)
            }
          }, (row: SearchResultRow) => row.kind + row.name)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 12, right: 12 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F6F8')
  }
}
