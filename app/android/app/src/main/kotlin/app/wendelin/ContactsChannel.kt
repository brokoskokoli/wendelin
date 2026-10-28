package app.wendelin

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.ContactsContract
import android.provider.ContactsContract.CommonDataKinds.Phone
import android.provider.ContactsContract.CommonDataKinds.StructuredPostal
import android.telephony.SmsManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Platform side of `ChannelContactsPort` (app/lib/platform/channel_contacts_port.dart): address
 * book (READ_CONTACTS), SMS (SmsManager, SEND_SMS) and calls (ACTION_CALL with CALL_PHONE, else the
 * dialer). The channel never asks the user: Dart confirms before `sendSms` and `call`.
 *
 * Error codes: `permissionDenied`, `unsupported`, `bad_args`, `failed`.
 */
class ContactsChannel(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)
    private val io: ExecutorService = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pendingPermission: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        io.shutdown()
    }

    fun onPermissionResult(requestCode: Int, grantResults: IntArray, permissions: Array<out String>) {
        if (requestCode != PERMISSION_REQUEST) return
        val result = pendingPermission ?: return
        pendingPermission = null
        // The answer is whether the address book may be read; SMS and call fall back on their own.
        result.success(has(Manifest.permission.READ_CONTACTS))
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasPermission" -> result.success(has(Manifest.permission.READ_CONTACTS))
            "requestPermission" -> requestPermission(result)
            "canSendSms" -> result.success(has(Manifest.permission.SEND_SMS))
            "all" -> {
                val args = ChannelArgs.of(call.arguments)
                val fields = try {
                    ContactRows.parseFields(args.stringList("fields"))
                } catch (e: ArgumentException) {
                    result.error("bad_args", e.message, null)
                    return
                }
                io.execute { reply(result) { readAll(fields) } }
            }
            "details" -> {
                val args = ChannelArgs.of(call.arguments)
                val ids: List<Long>
                val fields: Set<ContactRows.Kind>
                try {
                    ids = ContactRows.parseIds(args.stringList("ids"))
                    fields = ContactRows.parseDetailFields(args.stringList("fields"))
                } catch (e: ArgumentException) {
                    result.error("bad_args", e.message, null)
                    return
                }
                io.execute { reply(result) { readDetails(ids, fields) } }
            }
            "sendSms" -> {
                val args = ChannelArgs.of(call.arguments)
                io.execute {
                    reply(result) {
                        sendSms(args.requireString("number"), args.requireString("text"))
                    }
                }
            }
            "call" -> {
                val args = ChannelArgs.of(call.arguments)
                try {
                    result.success(placeCall(args.requireString("number")))
                } catch (e: ArgumentException) {
                    result.error("bad_args", e.message, null)
                } catch (e: SecurityException) {
                    result.error("permissionDenied", "CALL_PHONE", null)
                } catch (e: Exception) {
                    result.error("failed", e.javaClass.simpleName, null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun reply(result: MethodChannel.Result, body: () -> Any?) {
        val answer: () -> Unit = try {
            val value = ContactRows.channelValue(body())
            ({ result.success(value) })
        } catch (e: ArgumentException) {
            ({ result.error("bad_args", e.message, null) })
        } catch (e: PermissionException) {
            ({ result.error("permissionDenied", e.message, null) })
        } catch (e: UnsupportedOperationException) {
            ({ result.error("unsupported", e.message, null) })
        } catch (e: SecurityException) {
            ({ result.error("permissionDenied", e.message, null) })
        } catch (e: Exception) {
            ({ result.error("failed", e.javaClass.simpleName, null) })
        }
        main.post(answer)
    }

    private class PermissionException(message: String) : RuntimeException(message)

    private fun has(permission: String): Boolean =
        activity.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    private fun requestPermission(result: MethodChannel.Result) {
        val missing = PERMISSIONS.filter { !has(it) }
        if (missing.isEmpty()) {
            result.success(true)
            return
        }
        if (pendingPermission != null) {
            result.error("failed", "busy", null)
            return
        }
        pendingPermission = result
        activity.requestPermissions(missing.toTypedArray(), PERMISSION_REQUEST)
    }

    /**
     * The search index: phone and mail rows are always read (they decide which contacts exist, as
     * before); for requested address, birthday or organization only the presence is queried (no
     * content column), so the content itself is read later, for the hits only ([readDetails]).
     */
    private fun readAll(fields: Set<ContactRows.Kind>): List<Map<String, Any>> {
        if (!has(Manifest.permission.READ_CONTACTS)) throw PermissionException("READ_CONTACTS")
        val data = query(
            ContactRows.DATA_PROJECTION,
            ContactRows.selection(ContactRows.DEFAULT_FIELDS),
        )
        val extras = fields.filter { it in ContactRows.EXTRA_FIELDS }.toSet()
        val presence = if (extras.isEmpty()) {
            emptyList()
        } else {
            query(ContactRows.PRESENCE_PROJECTION, ContactRows.selection(extras, nonEmpty = true))
        }
        return ContactRows.index(data, presence, fields)
    }

    /** Address, birthday and organization of the contacts [ids] (the hits of a search) only. */
    private fun readDetails(ids: List<Long>, fields: Set<ContactRows.Kind>): List<Map<String, Any>> {
        if (!has(Manifest.permission.READ_CONTACTS)) throw PermissionException("READ_CONTACTS")
        val rows = query(ContactRows.DATA_PROJECTION, ContactRows.selection(fields, ids))
        return ContactRows.merge(rows, fields, withId = true)
    }

    /** Runs one query on the data table; presence projections yield rows with [ContactRows.PRESENT]. */
    private fun query(projection: Array<String>, where: Pair<String, Array<String>>): List<ContactRows.Row> {
        val rows = mutableListOf<ContactRows.Row>()
        val withData = projection.size > ContactRows.PRESENCE_PROJECTION.size
        activity.contentResolver.query(
            ContactsContract.Data.CONTENT_URI,
            projection,
            where.first,
            where.second,
            "${ContactsContract.Data.DISPLAY_NAME} COLLATE NOCASE",
        )?.use { c ->
            while (c.moveToNext()) {
                val mime = c.getString(2)
                val kind = ContactRows.Kind.values().firstOrNull { it.mime == mime } ?: continue
                if (!withData) {
                    rows.add(ContactRows.Row(c.getLong(0), c.getString(1), kind, ContactRows.PRESENT, null))
                    continue
                }
                val label = when (kind) {
                    ContactRows.Kind.PHONE ->
                        Phone.getTypeLabel(activity.resources, c.getInt(4), c.getString(5)).toString()
                    ContactRows.Kind.ADDRESS ->
                        StructuredPostal.getTypeLabel(activity.resources, c.getInt(4), c.getString(5)).toString()
                    else -> null
                }
                rows.add(ContactRows.Row(c.getLong(0), c.getString(1), kind, c.getString(3), label))
            }
        }
        return rows
    }

    private fun sendSms(number: String, text: String) {
        if (!ContactRows.validNumber(number)) throw ArgumentException("number")
        if (text.isBlank()) throw ArgumentException("text")
        if (!has(Manifest.permission.SEND_SMS)) throw PermissionException("SEND_SMS")
        if (!activity.packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY_MESSAGING)) {
            throw UnsupportedOperationException("no telephony")
        }
        val manager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            activity.getSystemService(SmsManager::class.java)
        } else {
            @Suppress("DEPRECATION")
            SmsManager.getDefault()
        }
        val parts = manager.divideMessage(text)
        if (parts.size > 1) {
            manager.sendMultipartTextMessage(number, null, parts, null, null)
        } else {
            manager.sendTextMessage(number, null, text, null, null)
        }
    }

    private fun placeCall(number: String): String {
        if (!ContactRows.validNumber(number)) throw ArgumentException("number")
        val uri = Uri.fromParts("tel", number, null)
        val direct = has(Manifest.permission.CALL_PHONE)
        val intent = Intent(if (direct) Intent.ACTION_CALL else Intent.ACTION_DIAL, uri)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        activity.startActivity(intent)
        return if (direct) "direct" else "dialer"
    }

    companion object {
        const val CHANNEL = "app.wendelin/contacts"
        private const val PERMISSION_REQUEST = 4721
        private val PERMISSIONS = arrayOf(
            Manifest.permission.READ_CONTACTS,
            Manifest.permission.SEND_SMS,
            Manifest.permission.CALL_PHONE,
        )
    }
}
