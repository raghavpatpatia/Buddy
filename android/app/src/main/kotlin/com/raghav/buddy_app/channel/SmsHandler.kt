package com.raghav.buddy_app.channel

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri

/** Bank transaction SMS only; the Dart side keeps just amount, direction, date and bank. */
class SmsHandler(private val ctx: Context) : ChannelHandler {
    override val routes: Map<String, Route> = mapOf(
        "bankSms" to { call, result -> Background.run(result) { bankSms(call.argument<Number>("since")?.toLong() ?: 0L) } },
    )

    /**
     * Bank transaction SMS since [since] (ms). Privacy filter happens here: only business sender IDs
     * (letters, e.g. "VM-HDFCBK") whose text mentions a debit/credit and an amount. SMS from phone
     * numbers (people) are never read into the app.
     */
    private fun bankSms(since: Long): List<Map<String, Any>> {
        if (ctx.checkSelfPermission(Manifest.permission.READ_SMS) != PackageManager.PERMISSION_GRANTED) return emptyList()
        val out = ArrayList<Map<String, Any>>()
        val business = Regex("[A-Za-z]")
        val money = Regex("(?i)(rs\\.?|inr|₹)\\s*[0-9]")
        val txn = Regex("(?i)(debit|credit|spent|withdrawn|withdrawal|received|deposited|refund|paid|sent|purchase|deducted)")
        ctx.contentResolver.query(
            Uri.parse("content://sms/inbox"), arrayOf("_id", "address", "body", "date"),
            "date > ?", arrayOf(since.toString()), "date DESC"
        )?.use { c ->
            while (c.moveToNext() && out.size < 2000) {
                val addr = c.getString(1) ?: continue
                if (!business.containsMatchIn(addr)) continue
                val body = c.getString(2) ?: continue
                if (!money.containsMatchIn(body) || !txn.containsMatchIn(body)) continue
                out.add(mapOf("id" to c.getLong(0), "addr" to addr, "body" to body, "date" to c.getLong(3)))
            }
        }
        return out
    }
}
