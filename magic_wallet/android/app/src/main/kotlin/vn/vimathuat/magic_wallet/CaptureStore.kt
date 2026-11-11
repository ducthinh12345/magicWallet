package vn.vimathuat.magic_wallet

import android.content.Context
import org.json.JSONObject
import java.io.File

/**
 * Hàng đợi thông báo thô giữa NotificationListenerService và phần Dart.
 * File nằm trong bộ nhớ riêng của app, chỉ giữ tới khi Dart lấy đi (thường vài giây).
 */
object CaptureStore {
    const val CHANNEL = "magic_wallet/capture"
    private const val PREFS = "capture"
    private const val QUEUE = "capture_queue.jsonl"
    private val lock = Any()

    // Lọc sớm cả ở đây để OTP không bao giờ chạm đĩa (mục 10.2.3). Dart lọc lại lần nữa.
    private val sensitive = Regex(
        """\bOTP\b|m[ãa] x[áa]c (th[ựu]c|nh[ậa]n)|m[ậa]t kh[ẩa]u|passcode|verification code""",
        RegexOption.IGNORE_CASE
    )

    fun setWhitelist(ctx: Context, pkgs: Set<String>) =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putStringSet("whitelist", pkgs).apply()

    fun whitelist(ctx: Context): Set<String> =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getStringSet("whitelist", emptySet()) ?: emptySet()

    /** Trả về false nếu bị bỏ (ngoài whitelist hoặc có OTP). */
    fun append(ctx: Context, pkg: String, title: String, text: String, postedAt: Long): Boolean {
        if (pkg !in whitelist(ctx)) return false
        if (sensitive.containsMatchIn(title) || sensitive.containsMatchIn(text)) return false
        val line = JSONObject()
            .put("package", pkg).put("title", title).put("text", text).put("postedAt", postedAt)
            .toString()
        synchronized(lock) { File(ctx.filesDir, QUEUE).appendText(line + "\n") }
        return true
    }

    /** Lấy hết và xoá — mỗi mục chỉ được xử lý một lần dù UI và engine nền cùng gọi. */
    fun take(ctx: Context): String = synchronized(lock) {
        val f = File(ctx.filesDir, QUEUE)
        if (!f.exists()) return ""
        val s = f.readText()
        f.delete()
        s
    }
}
