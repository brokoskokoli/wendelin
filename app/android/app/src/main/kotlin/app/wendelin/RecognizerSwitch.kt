package app.wendelin

import android.app.role.RoleManager
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings

/**
 * Keeps [WendelinRecognitionService] enabled only while Wendelin holds the assistant role.
 *
 * Android requires a recognition service for every assistant, but an enabled stub would be
 * picked as the system speech recognizer right after installation (when none is set) and break
 * speech input of other apps. The component is therefore disabled in the manifest and switched
 * on here when Wendelin is the assistant ([WendelinVoiceInteractionService.onReady], app start),
 * off again when it is not.
 */
object RecognizerSwitch {
    fun sync(context: Context, holdsRole: Boolean = holdsAssistantRole(context)) {
        val component = ComponentName(context, WendelinRecognitionService::class.java)
        val wanted = if (holdsRole) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        } else {
            PackageManager.COMPONENT_ENABLED_STATE_DEFAULT
        }
        val pm = context.packageManager
        if (pm.getComponentEnabledSetting(component) == wanted) return
        pm.setComponentEnabledSetting(component, wanted, PackageManager.DONT_KILL_APP)
    }

    fun holdsAssistantRole(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return context.getSystemService(RoleManager::class.java)
                ?.isRoleHeld(RoleManager.ROLE_ASSISTANT) == true
        }
        val current = Settings.Secure.getString(context.contentResolver, "assistant") ?: return false
        return ComponentName.unflattenFromString(current)?.packageName == context.packageName
    }
}
