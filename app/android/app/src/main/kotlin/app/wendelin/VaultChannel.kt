package app.wendelin

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.FileNotFoundException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Platform side of `SafVaultPort` (app/lib/platform/saf_vault_port.dart): the Obsidian vault as
 * a Storage Access Framework tree (`ACTION_OPEN_DOCUMENT_TREE`) with a persisted read/write
 * grant. Paths are vault-relative (`Projekte/App.md`) and resolved segment by segment through
 * `DocumentsContract` (never `..`). Content is passed as raw bytes (UTF-8 in Dart).
 *
 * Errors: `notFound`, `permissionDenied`, `exists`, `isFolder`, `rejected`, `tooLarge`,
 * `failed`.
 */
class VaultChannel(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)
    private val io: ExecutorService = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pendingPick: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        io.shutdown()
    }

    /** Result of the folder picker started by `pickTree`. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_REQUEST) return false
        val result = pendingPick ?: return true
        pendingPick = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return true
        }
        io.execute {
            val reply: () -> Unit = try {
                resolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                )
                val name = SafVaultTree(resolver, uri).rootName()
                ({ result.success(mapOf("uri" to uri.toString(), "name" to name)) })
            } catch (e: SecurityException) {
                ({ result.error("permissionDenied", "permissionDenied", null) })
            } catch (e: Exception) {
                ({ result.error("failed", e.javaClass.simpleName, null) })
            }
            main.post(reply)
        }
        return true
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "pickTree") {
            pick(result)
            return
        }
        io.execute {
            val reply: () -> Unit = try {
                val value = handle(call)
                ({ result.success(value) })
            } catch (e: FileNotFoundException) {
                ({ result.error("notFound", "notFound", null) })
            } catch (e: VaultError) {
                ({ result.error(e.code, e.code, null) })
            } catch (e: SecurityException) {
                ({ result.error("permissionDenied", "permissionDenied", null) })
            } catch (e: Exception) {
                ({ result.error("failed", e.javaClass.simpleName, null) })
            }
            main.post(reply)
        }
    }

    private fun pick(result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("failed", "busy", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
        )
        pendingPick = result
        try {
            activity.startActivityForResult(intent, PICK_REQUEST)
        } catch (e: ActivityNotFoundException) {
            // No folder picker on this device (possible without GMS apps).
            pendingPick = null
            result.error("unsupported", "unsupported", null)
        }
    }

    private val resolver get() = activity.contentResolver

    private fun handle(call: MethodCall): Any? {
        val args = ChannelArgs.of(call.arguments)
        val tree = Uri.parse(args.requireString("tree"))
        if (call.method == "hasAccess") {
            return resolver.persistedUriPermissions.any {
                it.uri == tree && it.isReadPermission && it.isWritePermission
            }
        }
        if (call.method == "release") {
            try {
                resolver.releasePersistableUriPermission(
                    tree,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                )
            } catch (e: SecurityException) {
                // No grant held any more: nothing to release.
            }
            return null
        }
        val vault = VaultResolver(SafVaultTree(resolver, tree))
        val path = VaultResolver.segments(args.string("path") ?: "")
        return when (call.method) {
            "list" -> vault.list(path).map(VaultResolver::entry)
            "stat" -> vault.find(path)?.let(VaultResolver::entry)
            "read" -> vault.read(path)
            "write" -> vault.write(path, args.requireBytes("bytes")).let { null }
            "create" -> vault.create(path, args.requireBytes("bytes")).let { null }
            "delete" -> vault.delete(path).let { null }
            else -> throw IllegalArgumentException(call.method)
        }
    }

    companion object {
        const val CHANNEL = "app.wendelin/vault"
        private const val PICK_REQUEST = 4713
    }
}
