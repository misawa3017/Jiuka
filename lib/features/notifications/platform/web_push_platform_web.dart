import 'package:web/web.dart' as web;

/// iPhone／iPad 的瀏覽器（iPadOS 會偽裝成 Mac，所以也看觸控點數）。
bool isIosBrowser() {
  final navigator = web.window.navigator;
  final agent = navigator.userAgent;
  return RegExp('iPhone|iPad|iPod').hasMatch(agent) ||
      (agent.contains('Macintosh') && navigator.maxTouchPoints > 1);
}

/// 是否從主畫面圖示打開（加入主畫面後的獨立視窗）。iPhone 只有這樣才支援推播。
bool isStandaloneApp() =>
    web.window.matchMedia('(display-mode: standalone)').matches;
