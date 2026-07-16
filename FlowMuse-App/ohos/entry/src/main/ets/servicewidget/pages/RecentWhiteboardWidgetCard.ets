let recentWhiteboardStorage = new LocalStorage();

@Entry(recentWhiteboardStorage)
@Component
struct RecentWhiteboardWidgetCard {
  @LocalStorageProp('appName') appName: string = 'FlowMuse';
  @LocalStorageProp('headline') headline: string = '开始你的第一块白板';
  @LocalStorageProp('detail') detail: string = '';
  @LocalStorageProp('buttonText') buttonText: string = '立即创建';
  @LocalStorageProp('buttonAction') buttonAction: string = 'createNote';

  build() {
    Column({ space: 8 }) {
      Text(this.appName)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .opacity(0.7)

      Text(this.headline)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.detail) {
        Text(this.detail)
          .fontSize(12)
          .opacity(0.65)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      Button(this.buttonText)
        .width('100%')
        .height(32)
        .margin({ top: 8 })
        .onClick(() => {
          postCardAction(this, {
            action: 'router',
            abilityName: 'EntryAbility',
            params: { action: this.buttonAction }
          });
        })
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#F4F8F4')
  }
}
