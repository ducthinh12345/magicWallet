package vn.vimathuat.magic_wallet

import android.content.ComponentName
import android.content.Intent
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity: local_auth cần FragmentActivity để hiện hộp thoại sinh trắc học.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CaptureStore.CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "takeQueue" -> result.success(CaptureStore.take(this))
                "setWhitelist" -> {
                    CaptureStore.setWhitelist(this, (call.arguments as? List<*>)?.filterIsInstance<String>()?.toSet() ?: emptySet())
                    result.success(null)
                }
                "isListenerEnabled" -> result.success(isListenerEnabled())
                "openListenerSettings" -> {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    result.success(null)
                }
                "setSecure" -> {
                    // FLAG_SECURE: chặn chụp màn hình và che nội dung trong trình chuyển app (mục 10.1).
                    if (call.arguments == true) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isListenerEnabled(): Boolean {
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners") ?: return false
        val me = ComponentName(this, WalletNotificationListener::class.java).flattenToString()
        return flat.split(":").contains(me)
    }
}
