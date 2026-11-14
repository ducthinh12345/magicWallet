package vn.vimathuat.magic_wallet

import android.app.NotificationManager
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
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
                "setupStatus" -> result.success(setupStatus())
                "openSetting" -> {
                    openSetting(call.arguments as? String ?: "")
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

    private val isMiui = Build.MANUFACTURER.equals("Xiaomi", ignoreCase = true)

    /** Trạng thái các thiết lập hệ thống mà ghi tự động cần. Tự khởi chạy của MIUI không đọc được → null. */
    private fun setupStatus(): Map<String, Any?> = mapOf(
        "listener" to isListenerEnabled(),
        "battery" to (getSystemService(POWER_SERVICE) as PowerManager).isIgnoringBatteryOptimizations(packageName),
        "notifications" to (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).areNotificationsEnabled(),
        "miui" to isMiui,
    )

    /** Mở thẳng màn cài đặt cần thiết; màn riêng của hãng không có thì lùi về trang thông tin app. */
    private fun openSetting(name: String) {
        val appDetails = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
        val intent = when (name) {
            "listener" -> Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
            "notifications" -> Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            "autostart" -> if (isMiui) Intent().setComponent(
                ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity")
            ) else appDetails
            "battery" -> if (isMiui) Intent().setComponent(
                ComponentName("com.miui.powerkeeper", "com.miui.powerkeeper.ui.HiddenAppsConfigActivity")
            ).putExtra("package_name", packageName).putExtra("package_label", packageManager.getApplicationLabel(applicationInfo).toString())
            else Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
            else -> appDetails
        }
        // Mở trang mới tinh: nếu Cài đặt đang mở sẵn ở trang khác, MIUI dùng lại trang cũ thay vì trang cần tới.
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        try {
            startActivity(intent)
        } catch (e: Exception) {
            startActivity(appDetails)
        }
    }

    private fun isListenerEnabled(): Boolean {
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners") ?: return false
        val me = ComponentName(this, WalletNotificationListener::class.java).flattenToString()
        return flat.split(":").contains(me)
    }
}
