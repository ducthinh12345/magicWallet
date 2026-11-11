package vn.vimathuat.magic_wallet

import android.app.Notification
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Nguồn S1/S2: đọc thông báo của app trong whitelist (ngân hàng, ví, app SMS nếu người dùng bật).
 * Không xin READ_SMS (mục 5.1). Thông báo ngoài whitelist bị bỏ qua ngay, không đọc nội dung.
 */
class WalletNotificationListener : NotificationListenerService() {
    private val main = Handler(Looper.getMainLooper())
    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (sbn.packageName !in CaptureStore.whitelist(this)) return
        val extras = sbn.notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT) ?: extras.getCharSequence(Notification.EXTRA_TEXT))?.toString() ?: ""
        if (text.isBlank()) return
        if (CaptureStore.append(this, sbn.packageName, title, text, sbn.postTime)) main.post { poke() }
    }

    /** Chạy phần Dart (captureMain) trong engine nền để tạo giao dịch nháp ngay, không chờ mở app. */
    private fun poke() {
        val ch = channel
        if (ch != null) {
            ch.invokeMethod("drain", null)
            return
        }
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(applicationContext)
        loader.ensureInitializationComplete(applicationContext, null)
        val e = FlutterEngine(applicationContext)
        val c = MethodChannel(e.dartExecutor.binaryMessenger, CaptureStore.CHANNEL)
        c.setMethodCallHandler { call, result ->
            when (call.method) {
                "takeQueue" -> result.success(CaptureStore.take(this))
                // Engine nền không có Activity: các lệnh giao diện coi như không làm gì.
                "setWhitelist", "setSecure", "openListenerSettings" -> result.success(null)
                "isListenerEnabled" -> result.success(true)
                else -> result.notImplemented()
            }
        }
        e.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "captureMain"))
        engine = e
        channel = c
    }

    override fun onListenerDisconnected() {
        engine?.destroy()
        engine = null
        channel = null
        super.onListenerDisconnected()
    }
}
