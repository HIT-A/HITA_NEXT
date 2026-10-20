/** Mounted only while the timetable is visible and the ability is in the foreground. */
@Component
export struct TimetableVideoBackground {
  @Prop source: string = '';
  @State private ready: boolean = false;
  onPlaybackError: () => void = () => {};

  build() {
    Video({ src: this.source })
      .muted(true)
      .autoPlay(true)
      .controls(false)
      .loop(true)
      .objectFit(ImageFit.Cover)
      .width('100%')
      .height('100%')
      .opacity(this.ready ? 1 : 0)
      .hitTestBehavior(HitTestMode.None)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .onStart(() => { this.ready = true; })
      .onError(() => { this.onPlaybackError(); })
  }
}
