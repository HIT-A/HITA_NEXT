export class CampusPortalGroup {
  title: string;
  portals: CampusPortal[];

  constructor(title: string, portals: CampusPortal[]) {
    this.title = title;
    this.portals = portals;
  }
}

export class CampusPortal {
  title: string;
  subtitle: string;
  url: string;

  constructor(title: string, subtitle: string, url: string) {
    this.title = title;
    this.subtitle = subtitle;
    this.url = url;
  }

  static readonly GROUPS: CampusPortalGroup[] = [
    new CampusPortalGroup('学校官网', [
      new CampusPortal('哈工大官网', 'www.hit.edu.cn', 'https://www.hit.edu.cn/'),
      new CampusPortal('哈工大深圳', 'www.hitsz.edu.cn', 'https://www.hitsz.edu.cn/'),
      new CampusPortal('哈工大威海', 'www.hitwh.edu.cn', 'https://www.hitwh.edu.cn/')
    ]),
    new CampusPortalGroup('课程资源', [
      new CampusPortal('HOA 课程攻略', 'hoa.moe', 'https://hoa.moe/'),
      new CampusPortal('薪火笔记', 'fireworks.jwyihao.top', 'https://fireworks.jwyihao.top/'),
      new CampusPortal('深校课程平台', 'course.hitsz.edu.cn', 'https://course.hitsz.edu.cn/')
    ])
  ];
}
