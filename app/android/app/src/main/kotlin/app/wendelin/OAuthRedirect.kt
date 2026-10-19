package app.wendelin

/**
 * Checks of the OAuth login in [AuthChannel] on plain strings (no `Uri`), so they run on the JVM:
 * which `authorize` requests are accepted and which redirects belong to the running login.
 */
object OAuthRedirect {
    /** Scheme, host and path of an address; the parts that must match the registered redirect. */
    data class Target(val scheme: String?, val host: String?, val path: String?)

    /**
     * Whether an `authorize` request is usable: an http(s) authorization address, a redirect
     * address and a non-empty `state`.
     */
    fun isValidRequest(urlScheme: String?, hasRedirect: Boolean, state: String?): Boolean =
        (urlScheme == "https" || urlScheme == "http") && hasRedirect && !state.isNullOrEmpty()

    /**
     * Whether [actual] is the redirect of the running login: same scheme, host and path as the
     * expected one and exactly the expected `state` (another app may open the redirect address
     * with a made-up one; that is ignored).
     */
    fun accepts(expected: Target, actual: Target, expectedState: String?, actualState: String?): Boolean =
        actual == expected && actualState == expectedState

    /**
     * Whether [actual] is the registered redirect address but carries another `state` than the
     * running login: a stale or foreign answer. The login then ends with `state_mismatch`
     * instead of a plain `cancelled`.
     */
    fun isForeignState(expected: Target, actual: Target, expectedState: String?, actualState: String?): Boolean =
        actual == expected && actualState != expectedState

    /** Error code of a login the user left without a matching redirect. */
    fun leaveCode(sawForeignState: Boolean): String = if (sawForeignState) "state_mismatch" else "cancelled"
}
