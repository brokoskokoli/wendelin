package app.wendelin

import android.content.pm.PackageManager
import org.junit.Assert.assertEquals
import org.junit.Test

/** Decision of [RecognizerSwitch]: shutdown must not trust the (still lagging) role query. */
class RecognizerSwitchTest {
    private val enabled = PackageManager.COMPONENT_ENABLED_STATE_ENABLED
    private val default = PackageManager.COMPONENT_ENABLED_STATE_DEFAULT

    @Test
    fun shutdownDisablesEvenWhenRoleQueryStillReportsHeld() {
        assertEquals(default, RecognizerSwitch.targetState(RecognizerSwitch.Trigger.SHUTDOWN, queriedRole = true, offered = true))
    }

    @Test
    fun readyEnablesEvenWhenRoleQueryLags() {
        assertEquals(enabled, RecognizerSwitch.targetState(RecognizerSwitch.Trigger.READY, queriedRole = false, offered = true))
    }

    @Test
    fun otherTriggersFollowTheRoleQuery() {
        assertEquals(enabled, RecognizerSwitch.targetState(RecognizerSwitch.Trigger.QUERY, queriedRole = true, offered = true))
        assertEquals(default, RecognizerSwitch.targetState(RecognizerSwitch.Trigger.QUERY, queriedRole = false, offered = true))
    }

    @Test
    fun notOfferedStaysOff() {
        for (t in RecognizerSwitch.Trigger.values()) {
            assertEquals(default, RecognizerSwitch.targetState(t, queriedRole = true, offered = false))
        }
    }
}
