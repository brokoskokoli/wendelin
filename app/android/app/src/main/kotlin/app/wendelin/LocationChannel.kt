package app.wendelin

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Address
import android.location.Geocoder
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Platform side of `ChannelLocationPort` and `ChannelMapsLauncherPort`
 * (app/lib/platform/channel_location_port.dart): the position from `LocationManager` (no Google
 * Play services, foreground only, no background location), a place name from `Geocoder` if the
 * device has a backend, and map intents. Error codes: `permissionDenied`, `unavailable`,
 * `notFound`, `badArgs`, `failed`. Coordinates and place names never go into an error message
 * and never into a log.
 */
class LocationChannel(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)
    private val io: ExecutorService = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val manager = activity.getSystemService(Activity.LOCATION_SERVICE) as LocationManager
    private var pendingPermission: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        io.shutdown()
    }

    fun onPermissionResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != PERMISSION_REQUEST) return
        val result = pendingPermission ?: return
        pendingPermission = null
        // "Approximate" alone is enough for a place name and the straight-line distance.
        result.success(grantResults.any { it == PackageManager.PERMISSION_GRANTED })
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasPermission" -> result.success(hasFine() || hasCoarse())
            "requestPermission" -> requestPermission(result)
            "current" -> io.execute {
                val reply: () -> Unit = try {
                    val value = current()
                    ({ result.success(value) })
                } catch (e: LocationError) {
                    ({ result.error(e.code, e.code, null) })
                } catch (e: SecurityException) {
                    ({ result.error("permissionDenied", "permissionDenied", null) })
                } catch (e: Exception) {
                    ({ result.error("failed", e.javaClass.simpleName, null) })
                }
                main.post(reply)
            }
            "launch" -> launch(ChannelArgs.of(call.arguments), result)
            else -> result.notImplemented()
        }
    }

    private class LocationError(val code: String) : Exception(code)

    private fun hasFine() =
        activity.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    private fun hasCoarse() =
        activity.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    private fun requestPermission(result: MethodChannel.Result) {
        if (hasFine() || hasCoarse()) {
            result.success(true)
            return
        }
        if (pendingPermission != null) {
            result.error("failed", "busy", null)
            return
        }
        pendingPermission = result
        activity.requestPermissions(
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
            PERMISSION_REQUEST,
        )
    }

    /** Providers worth asking: GPS only with the fine permission, network always. */
    private fun providers(): List<String> {
        if (!hasFine() && !hasCoarse()) throw LocationError("permissionDenied")
        val enabled = manager.getProviders(true).toSet()
        return buildList {
            if (hasFine() && LocationManager.GPS_PROVIDER in enabled) add(LocationManager.GPS_PROVIDER)
            if (LocationManager.NETWORK_PROVIDER in enabled) add(LocationManager.NETWORK_PROVIDER)
            if (hasFine() && LocationManager.PASSIVE_PROVIDER in enabled) add(LocationManager.PASSIVE_PROVIDER)
        }
    }

    private fun current(): Map<String, Any?> {
        val providers = providers()
        if (providers.isEmpty()) throw LocationError("unavailable")
        val cached = providers.mapNotNull { p -> manager.getLastKnownLocation(p) }
        val now = System.currentTimeMillis()
        val index = LocationPick.pick(cached.map { FixInfo(it.provider ?: "", it.time, accuracy(it)) }, now)
        val location = index?.let { cached[it] } ?: fresh(providers) ?: throw LocationError("unavailable")
        return mapOf(
            "latitude" to location.latitude,
            "longitude" to location.longitude,
            "accuracyM" to accuracy(location)?.toDouble(),
            "place" to placeName(location),
        )
    }

    private fun accuracy(l: Location): Float? = if (l.hasAccuracy()) l.accuracy else null

    /** A new fix from the first provider that answers within a few seconds. */
    private fun fresh(providers: List<String>): Location? {
        val real = providers.filter { it != LocationManager.PASSIVE_PROVIDER }
        for (provider in real) {
            val latch = CountDownLatch(1)
            var found: Location? = null
            // The callbacks run on the main thread: this method blocks the IO thread.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val cancel = CancellationSignal()
                manager.getCurrentLocation(provider, cancel, activity.mainExecutor) { loc ->
                    found = loc
                    latch.countDown()
                }
                if (!latch.await(FIX_TIMEOUT_S, TimeUnit.SECONDS)) cancel.cancel()
            } else {
                val listener = object : LocationListener {
                    override fun onLocationChanged(loc: Location) {
                        found = loc
                        latch.countDown()
                    }
                }
                @Suppress("DEPRECATION")
                manager.requestSingleUpdate(provider, listener, Looper.getMainLooper())
                if (!latch.await(FIX_TIMEOUT_S, TimeUnit.SECONDS)) manager.removeUpdates(listener)
            }
            found?.let { return it }
        }
        return null
    }

    private fun placeName(l: Location): String? {
        if (!Geocoder.isPresent()) return null
        return try {
            val geocoder = Geocoder(activity)
            val address: Address? =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    val latch = CountDownLatch(1)
                    var first: Address? = null
                    geocoder.getFromLocation(l.latitude, l.longitude, 1, object : Geocoder.GeocodeListener {
                        override fun onGeocode(addresses: MutableList<Address>) {
                            first = addresses.firstOrNull()
                            latch.countDown()
                        }

                        override fun onError(errorMessage: String?) {
                            latch.countDown()
                        }
                    })
                    latch.await(GEOCODE_TIMEOUT_S, TimeUnit.SECONDS)
                    first
                } else {
                    @Suppress("DEPRECATION")
                    geocoder.getFromLocation(l.latitude, l.longitude, 1)?.firstOrNull()
                }
            address?.let { LocationPick.placeName(it.subLocality, it.locality, it.adminArea) }
        } catch (_: Exception) {
            null // no backend or no network: coordinates are the fallback
        }
    }

    private fun launch(args: ChannelArgs, result: MethodChannel.Result) {
        val uri = Uri.parse(args.string("uri") ?: return result.error("badArgs", "badArgs", null))
        val pkg = args.string("package")
        if (!LocationPick.isAllowedLaunch(uri.scheme, uri.host, uri.path, pkg)) {
            result.error("badArgs", "badArgs", null)
            return
        }
        val intent = Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (pkg != null) intent.setPackage(pkg)
        try {
            activity.startActivity(intent)
            result.success(null)
        } catch (_: ActivityNotFoundException) {
            result.error("notFound", "notFound", null)
        } catch (e: Exception) {
            result.error("failed", e.javaClass.simpleName, null)
        }
    }

    companion object {
        const val CHANNEL = "app.wendelin/location"
        // Request codes in use (must stay unique, they share one Activity):
        // Calendar 4711, Notify 4712, Files 4712 (pick, other callback),
        // Vault 4713, Location 4714. Next free: 4715.
        private const val PERMISSION_REQUEST = 4714
        private const val FIX_TIMEOUT_S = 12L
        private const val GEOCODE_TIMEOUT_S = 4L
    }
}
