package app.wendelin

import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView

/**
 * Native placeholder of the assistant overlay (WP56): a small sheet at the bottom with
 * "Wendelin startet …" that stays until Flutter draws its first frame (`onFlutterUiDisplayed`). On a cold start (process
 * was gone, engine has to start) the user sees at once that the power button worked, instead of
 * a dimmed, empty screen for a second or more.
 */
object AssistantSplash {
    /** The placeholder view; the activity adds it over the Flutter view and removes it later. */
    fun create(context: Context): View {
        val density = context.resources.displayMetrics.density
        fun dp(v: Int) = (v * density).toInt()
        val text = TextView(context).apply {
            this.text = TEXT
            textSize = 16f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setPadding(dp(24), dp(32), dp(24), dp(32))
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#E61B1B1F"))
                val r = dp(24).toFloat()
                cornerRadii = floatArrayOf(r, r, r, r, 0f, 0f, 0f, 0f)
            }
        }
        return FrameLayout(context).apply {
            addView(
                text,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                    Gravity.BOTTOM,
                ),
            )
        }
    }

    const val TEXT = "Wendelin startet …"
}
