package app.wendelin

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.FileNotFoundException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Platform side of `SafListFilePort` and `DocumentPicker`
 * (app/lib/platform/saf_list_file_port.dart): Storage Access Framework documents with
 * persisted read/write grants. Content is passed as raw bytes (UTF-8 handled in Dart).
 * Errors: `notFound`, `permissionDenied`, `failed`.
 */
class FilesChannel(private val activity: Activity, messenger: BinaryMessenger) :
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

    /** Result of the picker started by [openDocument] or [createDocument]. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_REQUEST) return false
        val result = pendingPick ?: return true
        pendingPick = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return true
        }
        try {
            activity.contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
            result.success(uri.toString())
        } catch (e: SecurityException) {
            result.error("permissionDenied", "permissionDenied", null)
        }
        return true
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openDocument" -> pick(result, Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                // Default: list files; the routing import asks for JSON.
                val types = call.argument<List<String>>("mimeTypes")
                    ?: listOf("text/markdown", "text/x-markdown", "text/plain")
                putExtra(Intent.EXTRA_MIME_TYPES, types.toTypedArray())
            })
            "createDocument" -> pick(result, Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "text/markdown"
                putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "Liste.md")
            })
            else -> io.execute {
                val reply: () -> Unit = try {
                    val value = handle(call)
                    ({ result.success(value) })
                } catch (e: FileNotFoundException) {
                    ({ result.error("notFound", "notFound", null) })
                } catch (e: FileTooLarge) {
                    ({ result.error("tooLarge", "tooLarge", null) })
                } catch (e: SecurityException) {
                    ({ result.error("permissionDenied", "permissionDenied", null) })
                } catch (e: Exception) {
                    ({ result.error("failed", e.javaClass.simpleName, null) })
                }
                main.post(reply)
            }
        }
    }

    private fun pick(result: MethodChannel.Result, intent: Intent) {
        if (pendingPick != null) {
            result.error("failed", "busy", null)
            return
        }
        intent.addFlags(
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
        )
        pendingPick = result
        try {
            activity.startActivityForResult(intent, PICK_REQUEST)
        } catch (e: ActivityNotFoundException) {
            // No document picker on this device (possible without GMS apps).
            pendingPick = null
            result.error("unsupported", "unsupported", null)
        }
    }

    private val resolver get() = activity.contentResolver

    private fun handle(call: MethodCall): Any? {
        val uri = Uri.parse(call.argument<String>("uri")!!)
        return when (call.method) {
            "read" -> resolver.openInputStream(uri)?.use { input ->
                val out = ByteArrayOutputStream()
                val buffer = ByteArray(64 * 1024)
                while (true) {
                    val n = input.read(buffer)
                    if (n < 0) break
                    out.write(buffer, 0, n)
                    if (out.size() > MAX_BYTES) throw FileTooLarge()
                }
                out.toByteArray()
            } ?: throw FileNotFoundException()
            // "wt": truncate, so a shorter content leaves no rest of the old one.
            "write" -> {
                val bytes = call.argument<ByteArray>("bytes")!!
                resolver.openOutputStream(uri, "wt")?.use { it.write(bytes); it.flush() }
                    ?: throw FileNotFoundException()
                null
            }
            // A missing document is `false`; a lost grant is an error
            // (SecurityException → permissionDenied), never a silent `false`.
            "exists" -> try {
                resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                    ?.use { it.moveToFirst() } ?: false
            } catch (e: FileNotFoundException) {
                false
            } catch (e: IllegalArgumentException) {
                false
            }
            "hasAccess" -> resolver.persistedUriPermissions.any {
                it.uri == uri && it.isReadPermission && it.isWritePermission
            }
            "displayName" -> resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { if (it.moveToFirst()) it.getString(0) else null }
            "release" -> {
                try {
                    resolver.releasePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                    )
                } catch (e: SecurityException) {
                    // No grant held any more: nothing to release.
                }
                null
            }
            else -> throw IllegalArgumentException(call.method)
        }
    }

    private class FileTooLarge : Exception()

    companion object {
        const val CHANNEL = "app.wendelin/files"
        /** Lists are small Markdown files; anything bigger is refused. */
        private const val MAX_BYTES = 5 * 1024 * 1024
        private const val PICK_REQUEST = 4712
    }
}
