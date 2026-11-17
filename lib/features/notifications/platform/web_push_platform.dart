// 依平台選擇實作：網頁用瀏覽器 API 判斷，其他平台（含測試）用預設值。
export 'web_push_platform_stub.dart'
    if (dart.library.js_interop) 'web_push_platform_web.dart';
