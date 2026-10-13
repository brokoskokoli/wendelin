package app.wendelin

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
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
                val name = rootName(uri)
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

    private class VaultError(val code: String) : Exception(code)

    private data class Doc(
        val id: String,
        val name: String,
        val mime: String,
        val modified: Long?,
        val size: Long?,
    ) {
        val isFolder get() = mime == Document.MIME_TYPE_DIR
    }

    private fun handle(call: MethodCall): Any? {
        val tree = Uri.parse(call.argument<String>("tree")!!)
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
        val path = segments(call.argument<String>("path") ?: "")
        return when (call.method) {
            "list" -> {
                val folder = find(tree, path) ?: throw FileNotFoundException()
                if (!folder.isFolder) throw FileNotFoundException()
                children(tree, folder.id).map(::entry)
            }
            "stat" -> find(tree, path)?.let(::entry)
            "read" -> {
                val doc = file(tree, path)
                resolver.openInputStream(uri(tree, doc.id))?.use { input ->
                    val out = ByteArrayOutputStream()
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val n = input.read(buffer)
                        if (n < 0) break
                        out.write(buffer, 0, n)
                        if (out.size() > MAX_BYTES) throw VaultError("tooLarge")
                    }
                    out.toByteArray()
                } ?: throw FileNotFoundException()
            }
            "write" -> {
                val bytes = call.argument<ByteArray>("bytes")!!
                val existing = find(tree, path)
                val doc = when {
                    existing == null -> createFile(tree, path)
                    existing.isFolder -> throw VaultError("isFolder")
                    else -> existing
                }
                // "wt": truncate, so a shorter content leaves no rest of the old one. SAF has no
                // atomic rename-over; the whole content is written in one call.
                writeBytes(tree, doc, bytes)
                null
            }
            "create" -> {
                if (find(tree, path) != null) throw VaultError("exists")
                writeBytes(tree, createFile(tree, path), call.argument<ByteArray>("bytes")!!)
                null
            }
            "delete" -> {
                val doc = file(tree, path)
                if (!DocumentsContract.deleteDocument(resolver, uri(tree, doc.id))) {
                    throw VaultError("failed")
                }
                null
            }
            else -> throw IllegalArgumentException(call.method)
        }
    }

    /** Vault-relative path → segments; refuses anything that could leave the tree. */
    private fun segments(path: String): List<String> {
        val parts = path.split('/').filter { it.isNotEmpty() }
        if (parts.any { it == "." || it == ".." || it.contains('\\') || it.contains('\u0000') }) {
            throw VaultError("rejected")
        }
        return parts
    }

    private fun uri(tree: Uri, id: String) = DocumentsContract.buildDocumentUriUsingTree(tree, id)

    private fun root(tree: Uri) =
        Doc(DocumentsContract.getTreeDocumentId(tree), "", Document.MIME_TYPE_DIR, null, null)

    private fun rootName(tree: Uri): String? = resolver.query(
        uri(tree, DocumentsContract.getTreeDocumentId(tree)),
        arrayOf(Document.COLUMN_DISPLAY_NAME),
        null,
        null,
        null,
    )?.use { if (it.moveToFirst()) it.getString(0) else null }

    private fun children(tree: Uri, parentId: String): List<Doc> = resolver.query(
        DocumentsContract.buildChildDocumentsUriUsingTree(tree, parentId),
        COLUMNS,
        null,
        null,
        null,
    )?.use { c ->
        val out = ArrayList<Doc>(c.count)
        while (c.moveToNext()) {
            out.add(
                Doc(
                    id = c.getString(0),
                    name = c.getString(1) ?: continue,
                    mime = c.getString(2) ?: "",
                    modified = if (c.isNull(3)) null else c.getLong(3),
                    size = if (c.isNull(4)) null else c.getLong(4),
                ),
            )
        }
        out
    } ?: throw FileNotFoundException()

    private fun find(tree: Uri, path: List<String>): Doc? {
        var current = root(tree)
        for (segment in path) {
            if (!current.isFolder) return null
            current = children(tree, current.id).firstOrNull { it.name == segment } ?: return null
        }
        return current
    }

    private fun file(tree: Uri, path: List<String>): Doc {
        val doc = find(tree, path) ?: throw FileNotFoundException()
        if (doc.isFolder || path.isEmpty()) throw VaultError("isFolder")
        return doc
    }

    /** Creates missing parent folders and a new, empty file with exactly the last segment. */
    private fun createFile(tree: Uri, path: List<String>): Doc {
        if (path.isEmpty()) throw VaultError("isFolder")
        var parent = root(tree)
        for (segment in path.dropLast(1)) {
            val existing = children(tree, parent.id).firstOrNull { it.name == segment }
            parent = when {
                existing == null -> created(
                    tree,
                    DocumentsContract.createDocument(
                        resolver,
                        uri(tree, parent.id),
                        Document.MIME_TYPE_DIR,
                        segment,
                    ),
                    segment,
                )
                existing.isFolder -> existing
                else -> throw VaultError("rejected")
            }
        }
        val name = path.last()
        val mime = if (name.lowercase().endsWith(".md")) "text/markdown" else "application/octet-stream"
        return created(
            tree,
            DocumentsContract.createDocument(resolver, uri(tree, parent.id), mime, name),
            name,
        )
    }

    /** The new document; if the provider renamed it (name taken meanwhile), it is removed again. */
    private fun created(tree: Uri, docUri: Uri?, name: String): Doc {
        if (docUri == null) throw VaultError("failed")
        val id = DocumentsContract.getDocumentId(docUri)
        val doc = resolver.query(uri(tree, id), COLUMNS, null, null, null)?.use { c ->
            if (!c.moveToFirst()) null else Doc(c.getString(0), c.getString(1) ?: "", c.getString(2) ?: "", null, null)
        } ?: throw VaultError("failed")
        if (doc.name != name) {
            DocumentsContract.deleteDocument(resolver, uri(tree, id))
            throw VaultError("exists")
        }
        return doc
    }

    private fun writeBytes(tree: Uri, doc: Doc, bytes: ByteArray) {
        resolver.openOutputStream(uri(tree, doc.id), "wt")?.use {
            it.write(bytes)
            it.flush()
        } ?: throw FileNotFoundException()
    }

    private fun entry(doc: Doc): Map<String, Any?> = mapOf(
        "name" to doc.name,
        "folder" to doc.isFolder,
        "modified" to doc.modified,
        "size" to if (doc.isFolder) null else doc.size,
    )

    companion object {
        const val CHANNEL = "app.wendelin/vault"
        private const val PICK_REQUEST = 4713
        /** Larger files are not read (notes are text; the tools refuse > 2 MB anyway). */
        private const val MAX_BYTES = 16 * 1024 * 1024
        private val COLUMNS = arrayOf(
            Document.COLUMN_DOCUMENT_ID,
            Document.COLUMN_DISPLAY_NAME,
            Document.COLUMN_MIME_TYPE,
            Document.COLUMN_LAST_MODIFIED,
            Document.COLUMN_SIZE,
        )
    }
}
