package io.github.instantreplay.replay_capture_android.broadcast

import java.io.File
import java.nio.file.Files
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertEquals

class FieldLogTest {
    private val time = OffsetDateTime.of(2026, 11, 15, 17, 4, 5, 678_000_000, ZoneOffset.ofHours(1))

    private fun sample() = FieldSample(
        time = time,
        thermalStatus = 2,
        thermalHeadroom = 0.71234,
        batteryTempC = 38.25,
        batteryPercent = 87,
        plugged = true,
        cameraFps = 29.97,
        programFps = 30.0,
        targetKbps = 4500,
        measuredKbps = 4620,
        droppedFrames = 3,
        rtmpState = "live",
    )

    @Test
    fun formatsARowMatchingTheHeader() {
        val row = FieldLog.row(sample())
        assertEquals("2026-11-15T17:04:05+01:00,2,0.712,38.3,87,true,30.0,30.0,4500,4620,3,live", row)
        assertEquals(FieldLog.HEADER.split(",").size, row.split(",").size)
    }

    @Test
    fun unknownValuesAreEmptyCells() {
        val row = FieldLog.row(
            sample().copy(
                thermalHeadroom = null, batteryTempC = null, batteryPercent = null, plugged = null,
                cameraFps = null, programFps = null, measuredKbps = null, rtmpState = "reconnecting",
            ),
        )
        assertEquals("2026-11-15T17:04:05+01:00,2,,,,,,,4500,,3,reconnecting", row)
    }

    @Test
    fun namesTheFileAfterTheStartMinute() {
        val file = FieldLog.fileFor(File("files"), LocalDateTime.of(2026, 11, 15, 9, 3, 59))
        assertEquals(File(File("files", "broadcast"), "broadcast_2026-11-15_09-03.csv"), file)
    }

    @Test
    fun writesTheHeaderOnceAndAppends() {
        val dir = Files.createTempDirectory("fieldlog").toFile()
        try {
            val file = FieldLog.fileFor(dir, LocalDateTime.of(2026, 11, 15, 9, 3))
            FieldLog(file).append(sample())
            FieldLog(file).append(sample()) // a restart in the same minute appends
            val lines = file.readLines()
            assertEquals(listOf(FieldLog.HEADER, FieldLog.row(sample()), FieldLog.row(sample())), lines)
        } finally {
            dir.deleteRecursively()
        }
    }
}
