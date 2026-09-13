package com.ankit.dailymint.prototype

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.provider.Telephony
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONObject

class SmsReader(private val context: Context, private val onChanged: () -> Unit) {
    private val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
        override fun onChange(selfChange: Boolean) { onChanged() }
    }
    private var registered = false
    fun allowed(): Boolean = ContextCompat.checkSelfPermission(context, Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED
    fun start() {
        if (allowed() && !registered) {
            context.contentResolver.registerContentObserver(Telephony.Sms.Inbox.CONTENT_URI, true, observer)
            registered = true
        }
    }
    fun stop() { if (registered) context.contentResolver.unregisterContentObserver(observer); registered = false }
    fun read(since: Long): String {
        if (!allowed()) return "[]"
        val values = JSONArray()
        val columns = arrayOf(Telephony.Sms._ID, Telephony.Sms.BODY, Telephony.Sms.ADDRESS, Telephony.Sms.DATE)
        // Overlap the timestamp boundary. The shared transaction identity makes re-reading safe.
        context.contentResolver.query(Telephony.Sms.Inbox.CONTENT_URI, columns, "date >= ?", arrayOf(since.toString()), "date ASC")?.use { cursor ->
            while (cursor.moveToNext()) {
                values.put(JSONObject().put("id", cursor.getString(0)).put("body", cursor.getString(1).orEmpty())
                    .put("sender", cursor.getString(2).orEmpty()).put("timestamp", cursor.getLong(3)))
            }
        }
        return values.toString()
    }
}
