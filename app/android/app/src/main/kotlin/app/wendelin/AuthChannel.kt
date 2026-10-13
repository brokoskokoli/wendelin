package app.wendelin

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.browser.customtabs.CustomTabsClient
import androidx.browser.customtabs.CustomTabsIntent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Platform side of `ChannelAuthorizationBrowser` (app/lib/platform/channel_authorization_browser.dart):
 * OAuth login of MCP servers (WP27). Opens the authorization page in a Custom Tab
 * (androidx.browser, no Google services, K7) or, without a Custom Tabs browser, in any browser.
 * The redirect to `app.wendelin://oauth/mcp` reaches [OAuthRedirectActivity], which hands it back
 * through [deliver]. `state` and issuer are checked in Dart (McpOAuthFlow), not here.
 *
 * Errors: `no_browser` (nothing can show the page), `cancelled` (the user came back without a
 * redirect, or a new login replaced this one), `bad_args`.
 */
class AuthChannel(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)
    private val handler = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null
    private var redirect: Uri? = null
    private var left = false

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        finish { it.error("cancelled", "Anmeldung abgebrochen", null) }
        if (waiting === this) waiting = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(browserIntent(Uri.parse("https://example.org")).let {
                it.resolveActivity(activity.packageManager) != null
            })
            "authorize" -> authorize(call, result)
            else -> result.notImplemented()
        }
    }

    private fun authorize(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url")?.let(Uri::parse)
        val back = call.argument<String>("redirect")?.let(Uri::parse)
        if (url == null || back == null || (url.scheme != "https" && url.scheme != "http")) {
            result.error("bad_args", "url oder redirect fehlt", null)
            return
        }
        // Only one login at a time; an older one counts as cancelled.
        finish { it.error("cancelled", "Neue Anmeldung gestartet", null) }
        if (!open(url)) {
            result.error("no_browser", "Kein Browser installiert", null)
            return
        }
        pending = result
        redirect = back
        left = false
        waiting = this
    }

    /** Custom Tab if a browser supports it, otherwise any browser. */
    private fun open(url: Uri): Boolean {
        val tabsPackage = CustomTabsClient.getPackageName(activity, null)
        return try {
            if (tabsPackage != null) {
                val tab = CustomTabsIntent.Builder().setShowTitle(true).build()
                tab.intent.setPackage(tabsPackage)
                tab.launchUrl(activity, url)
            } else {
                activity.startActivity(browserIntent(url))
            }
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
    }

    private fun browserIntent(url: Uri) =
        Intent(Intent.ACTION_VIEW, url).addCategory(Intent.CATEGORY_BROWSABLE)

    /** The activity went to the background (browser opened). */
    fun onPause() {
        if (pending != null) left = true
    }

    /**
     * Back in the app. Without a redirect shortly after, the user closed the browser: the login
     * counts as cancelled (the redirect activity delivers before this activity resumes).
     */
    fun onResume() {
        if (pending == null || !left) return
        val expected = pending
        handler.postDelayed({
            if (pending === expected) finish { it.error("cancelled", "Anmeldung abgebrochen", null) }
        }, CANCEL_DELAY_MS)
    }

    private fun complete(uri: Uri): Boolean {
        val expected = redirect ?: return false
        if (uri.scheme != expected.scheme || uri.host != expected.host || uri.path != expected.path) {
            return false
        }
        finish { it.success(uri.toString()) }
        // Back to the app: closes the Custom Tab above it in this task.
        activity.startActivity(
            Intent(activity, activity.javaClass)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP),
        )
        return true
    }

    private fun finish(answer: (MethodChannel.Result) -> Unit) {
        val result = pending ?: return
        pending = null
        redirect = null
        left = false
        if (waiting === this) waiting = null
        answer(result)
    }

    companion object {
        const val CHANNEL = "app.wendelin/auth"
        private const val CANCEL_DELAY_MS = 1500L

        /** The channel with a running login, if any. */
        private var waiting: AuthChannel? = null

        /** Hands a redirect to the running login; `false` if none expects it. */
        fun deliver(uri: Uri): Boolean = waiting?.complete(uri) ?: false
    }
}
