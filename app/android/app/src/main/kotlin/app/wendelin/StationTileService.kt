package app.wendelin

import android.app.PendingIntent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/**
 * Quick settings tile that starts the station mode (WP99). On a locked device it asks to unlock
 * first ([StationPolicy.tileNeedsUnlock]); the station itself then runs over the lock screen.
 */
class StationTileService : TileService() {
    override fun onStartListening() {
        qsTile?.let {
            it.state = if (StationState.active) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
            it.updateTile()
        }
    }

    override fun onClick() {
        if (StationPolicy.tileNeedsUnlock(isLocked)) unlockAndRun { launch() } else launch()
    }

    @Suppress("DEPRECATION")
    private fun launch() {
        val intent = StationChannel.launchIntent(this)
        if (Build.VERSION.SDK_INT >= 34) {
            startActivityAndCollapse(
                PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE),
            )
        } else {
            startActivityAndCollapse(intent)
        }
    }
}
