package app.wendelin

import android.app.Activity

/**
 * Catches the OAuth redirect `app.wendelin://oauth/mcp?code=…&state=…` (WP27) and hands it to the
 * running login ([AuthChannel.deliver]); without one it is ignored. Translucent, finishes at once.
 * Delivered in onResume, when this app is in the foreground, so the login's activity may bring
 * itself back to the front. Any app could start this activity with a made-up address: the waiting
 * login checks `state` (and `iss`), so such a redirect is refused there.
 */
class OAuthRedirectActivity : Activity() {
    override fun onResume() {
        super.onResume()
        intent?.data?.let { AuthChannel.deliver(it) }
        finish()
    }
}
