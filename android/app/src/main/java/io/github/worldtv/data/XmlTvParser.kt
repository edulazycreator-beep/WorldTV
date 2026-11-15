package io.github.worldtv.data

import io.github.worldtv.model.EpgChannel
import io.github.worldtv.model.Programme
import io.github.worldtv.model.ProgrammeGuide
import org.xml.sax.Attributes
import org.xml.sax.InputSource
import org.xml.sax.SAXException
import org.xml.sax.helpers.DefaultHandler
import java.io.ByteArrayInputStream
import java.io.InputStream
import java.util.Calendar
import java.util.TimeZone
import java.util.zip.GZIPInputStream
import javax.xml.parsers.SAXParserFactory

class XmlTvParseException(message: String) : Exception(message)

/**
 * Streaming SAX parser for XMLTV (`<tv>`, `<channel>`, `<programme>`).
 * Accepts plain XML or gzip-compressed (`.xml.gz`) data.
 */
object XmlTvParser {
    fun isGzipped(bytes: ByteArray): Boolean =
        bytes.size >= 2 && bytes[0] == 0x1f.toByte() && bytes[1] == 0x8b.toByte()

    fun parse(bytes: ByteArray): ProgrammeGuide {
        val input: InputStream =
            if (isGzipped(bytes)) GZIPInputStream(ByteArrayInputStream(bytes)) else ByteArrayInputStream(bytes)
        return input.use { parse(it) }
    }

    fun parse(stream: InputStream): ProgrammeGuide {
        val handler = Handler()
        val factory = SAXParserFactory.newInstance().apply { isNamespaceAware = false }
        for (feature in listOf(
            "http://xml.org/sax/features/external-general-entities",
            "http://xml.org/sax/features/external-parameter-entities",
        )) runCatching { factory.setFeature(feature, false) }
        runCatching { factory.setFeature("http://apache.org/xml/features/nonvalidating/load-external-dtd", false) }

        try {
            factory.newSAXParser().parse(InputSource(stream), handler)
        } catch (e: SAXException) {
            if (!handler.sawRoot) throw XmlTvParseException("This file is not an XMLTV programme guide.")
            // Keep what we parsed if the file is merely truncated.
            if (handler.programmes.isEmpty()) throw XmlTvParseException("The guide file is malformed: ${e.message}")
        } catch (e: java.io.IOException) {
            if (handler.programmes.isEmpty()) {
                if (!handler.sawRoot) throw XmlTvParseException("This file is not an XMLTV programme guide.")
                throw XmlTvParseException("The guide file is malformed: ${e.message}")
            }
        }
        if (!handler.sawRoot) throw XmlTvParseException("This file is not an XMLTV programme guide.")
        return ProgrammeGuide(handler.channels, handler.programmes)
    }

    /**
     * Parses XMLTV timestamps: `YYYYMMDDhhmmss ±hhmm`. Missing time parts are treated as zero
     * and a missing offset as UTC, per the XMLTV DTD. Returns epoch millis.
     */
    fun parseDate(raw: String): Long? {
        val trimmed = raw.trim()
        val digits = trimmed.takeWhile { it.isDigit() }
        if (digits.length < 8) return null
        val padded = (digits + "000000").take(14)
        fun part(start: Int, length: Int) = padded.substring(start, start + length).toInt()

        var offsetMillis = 0
        val rest = trimmed.substring(digits.length).trim()
        if (rest.isNotEmpty() && (rest[0] == '+' || rest[0] == '-')) {
            val offsetDigits = rest.substring(1).takeWhile { it.isDigit() }
            if (offsetDigits.length == 4) {
                val value = offsetDigits.toInt()
                offsetMillis = ((value / 100) * 3600 + (value % 100) * 60) * 1000
                if (rest[0] == '-') offsetMillis = -offsetMillis
            }
        }
        val calendar = Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply {
            clear()
            set(part(0, 4), part(4, 2) - 1, part(6, 2), part(8, 2), part(10, 2), part(12, 2))
        }
        return calendar.timeInMillis - offsetMillis
    }

    private class Handler : DefaultHandler() {
        val channels = HashMap<String, EpgChannel>()
        val programmes = ArrayList<Programme>()
        var sawRoot = false

        private var channelId: String? = null
        private var channelNames = mutableListOf<String>()
        private var channelIcon: String? = null

        private var progChannel: String? = null
        private var progStart = 0L
        private var progStop: Long? = null
        private var title: String? = null
        private var subtitle: String? = null
        private var desc: String? = null
        private var categories = mutableListOf<String>()
        private val text = StringBuilder()

        override fun startElement(uri: String?, localName: String?, qName: String, attributes: Attributes) {
            text.setLength(0)
            when (qName) {
                "tv" -> sawRoot = true
                "channel" -> {
                    channelId = attributes.getValue("id")
                    channelNames = mutableListOf()
                    channelIcon = null
                }
                "icon" -> if (channelId != null && progChannel == null) channelIcon = attributes.getValue("src")
                "programme" -> {
                    val channel = attributes.getValue("channel")
                    val start = attributes.getValue("start")?.let { parseDate(it) }
                    if (channel != null && start != null) {
                        progChannel = channel
                        progStart = start
                        progStop = attributes.getValue("stop")?.let { parseDate(it) }
                        title = null
                        subtitle = null
                        desc = null
                        categories = mutableListOf()
                    }
                }
            }
        }

        override fun characters(ch: CharArray, start: Int, length: Int) {
            text.appendRange(ch, start, start + length)
        }

        override fun endElement(uri: String?, localName: String?, qName: String) {
            val value = text.toString().trim()
            when (qName) {
                "display-name" -> if (channelId != null && value.isNotEmpty()) channelNames += value
                "channel" -> {
                    channelId?.let { channels[it] = EpgChannel(it, channelNames.toList(), channelIcon) }
                    channelId = null
                }
                "title" -> if (title == null && value.isNotEmpty()) title = value
                "sub-title" -> if (subtitle == null && value.isNotEmpty()) subtitle = value
                "desc" -> if (desc == null && value.isNotEmpty()) desc = value
                "category" -> if (progChannel != null && value.isNotEmpty()) categories += value
                "programme" -> {
                    val channel = progChannel
                    if (channel != null) {
                        // Missing stop: assume 30 minutes.
                        val stop = progStop ?: (progStart + 30 * 60_000)
                        programmes += Programme(
                            channelId = channel,
                            start = progStart,
                            stop = maxOf(stop, progStart),
                            title = title ?: "Untitled",
                            subtitle = subtitle,
                            description = desc,
                            categories = categories.toList(),
                        )
                    }
                    progChannel = null
                }
            }
            text.setLength(0)
        }
    }
}
