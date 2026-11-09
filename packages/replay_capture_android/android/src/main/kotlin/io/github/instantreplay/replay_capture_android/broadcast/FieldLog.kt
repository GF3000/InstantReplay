package io.github.instantreplay.replay_capture_android.broadcast

import java.io.File
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale

/** One field-log sample (SPEC §12.1). Null = not known at that moment (empty cell). */
internal data class FieldSample(
    val time: OffsetDateTime,
    val thermalStatus: Int?,
    val thermalHeadroom: Double?,
    val batteryTempC: Double?,
    val batteryPercent: Int?,
    val plugged: Boolean?,
    val cameraFps: Double?,
    val programFps: Double?,
    val targetKbps: Int,
    val measuredKbps: Long?,
    val droppedFrames: Long,
    val rtmpState: String,
    /** A replay is on air (SPEC §12.6): the extra decoder's heat shows against it. */
    val replay: Boolean = false,
)

/**
 * CSV log written every few seconds while broadcasting, read over USB after a match to see how
 * hot the phone got and how the stream held up. Appends; a crash loses at most the last row.
 */
internal class FieldLog(private val file: File) {
    init {
        file.parentFile?.mkdirs()
        if (!file.exists() || file.length() == 0L) file.writeText(HEADER + "\n")
    }

    fun append(sample: FieldSample) = file.appendText(row(sample) + "\n")

    companion object {
        const val HEADER = "time,thermal_status,thermal_headroom,battery_temp_c,battery_percent,plugged," +
            "camera_fps,program_fps,target_kbps,measured_kbps,dropped_frames,rtmp_state,replay"

        private val FILE_TIME = DateTimeFormatter.ofPattern("yyyy-MM-dd_HH-mm", Locale.ROOT)

        /** `broadcast_<yyyy-MM-dd_HH-mm>.csv` in `<dir>/broadcast`. */
        fun fileFor(dir: File, start: LocalDateTime): File =
            File(File(dir, "broadcast"), "broadcast_${start.format(FILE_TIME)}.csv")

        fun row(s: FieldSample): String = listOf(
            s.time.truncatedTo(ChronoUnit.SECONDS).format(DateTimeFormatter.ISO_OFFSET_DATE_TIME),
            s.thermalStatus?.toString(),
            s.thermalHeadroom?.let { fixed(it, 3) },
            s.batteryTempC?.let { fixed(it, 1) },
            s.batteryPercent?.toString(),
            s.plugged?.toString(),
            s.cameraFps?.let { fixed(it, 1) },
            s.programFps?.let { fixed(it, 1) },
            s.targetKbps.toString(),
            s.measuredKbps?.toString(),
            s.droppedFrames.toString(),
            s.rtmpState,
            if (s.replay) "1" else "0",
        ).joinToString(",") { it ?: "" }

        private fun fixed(value: Double, decimals: Int) = String.format(Locale.ROOT, "%.${decimals}f", value)
    }
}
