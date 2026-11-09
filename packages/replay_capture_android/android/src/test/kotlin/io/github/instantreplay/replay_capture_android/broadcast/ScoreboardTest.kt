package io.github.instantreplay.replay_capture_android.broadcast

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ScoreboardTest {
    private val state = ScoreboardState(
        visible = true,
        homeName = "Rcd",
        awayName = "VAL",
        homeScore = 2,
        awayScore = 1,
        homeColor = 0xFF0000FF.toInt(),
        awayColor = 0xFFFF0000.toInt(),
        periodLabel = "2T",
        clockMs = 45 * 60_000L,
        clockRunning = true,
        countDown = false,
    )

    @Test
    fun runningClockAdvancesFromTheReceivedValue() {
        assertEquals(45 * 60_000L + 1_500, Scoreboard.clockMs(state, 1_500))
        assertEquals(45 * 60_000L, Scoreboard.clockMs(state.copy(clockRunning = false), 1_500))
    }

    @Test
    fun countDownStopsAtZero() {
        val down = state.copy(countDown = true, clockMs = 2_000)
        assertEquals(500L, Scoreboard.clockMs(down, 1_500))
        assertEquals(0L, Scoreboard.clockMs(down, 60_000))
    }

    @Test
    fun formatsMinutesUncapped() {
        assertEquals("00:00", Scoreboard.formatClock(0, countDown = false))
        assertEquals("00:59", Scoreboard.formatClock(59_999, countDown = false))
        assertEquals("45:00", Scoreboard.formatClock(45 * 60_000L, countDown = false))
        assertEquals("93:12", Scoreboard.formatClock(93 * 60_000L + 12_400, countDown = false))
        assertEquals("120:00", Scoreboard.formatClock(120 * 60_000L, countDown = false))
    }

    @Test
    fun countDownRoundsUpSoZeroMeansOver() {
        assertEquals("00:01", Scoreboard.formatClock(1, countDown = true))
        assertEquals("00:00", Scoreboard.formatClock(0, countDown = true))
        assertEquals("20:00", Scoreboard.formatClock(20 * 60_000L, countDown = true))
        assertEquals("19:59", Scoreboard.formatClock(20 * 60_000L - 1_000, countDown = true))
    }

    @Test
    fun textChangesOncePerSecond() {
        assertEquals(Scoreboard.text(state, 100), Scoreboard.text(state, 900))
        assertTrue(Scoreboard.text(state, 900) != Scoreboard.text(state, 1_000))
        val text = Scoreboard.text(state, 0)
        assertEquals("RCD", text.homeName)
        assertEquals("2", text.homeScore)
        assertEquals("45:00", text.clock)
    }

    private val measure = { s: String -> s.length * 10f }

    @Test
    fun laysOutLeftToRight() {
        val layout = Scoreboard.layout(Scoreboard.text(state, 0), 56, measure)
        assertEquals(
            listOf(
                CellKind.STRIPE, CellKind.NAME, CellKind.SCORE, CellKind.SCORE,
                CellKind.NAME, CellKind.STRIPE, CellKind.CLOCK, CellKind.PERIOD,
            ),
            layout.cells.map { it.kind },
        )
        assertEquals(listOf("", "RCD", "2", "1", "VAL", "", "45:00", "2T"), layout.cells.map { it.text })
        assertEquals(state.homeColor, layout.cells.first().color)
        assertEquals(state.awayColor, layout.cells[5].color)
        // Contiguous cells, total width rounded up.
        layout.cells.zipWithNext { a, b -> assertEquals(a.x + a.width, b.x, 0.001f) }
        val end = layout.cells.last().let { it.x + it.width }
        assertEquals(kotlin.math.ceil(end).toInt(), layout.width)
        assertEquals(56, layout.height)
        assertEquals(56 * Scoreboard.TEXT_SIZE, layout.textSize)
    }

    @Test
    fun omitsAnEmptyPeriodAndKeepsScoreWidthsStable() {
        val one = Scoreboard.layout(Scoreboard.text(state.copy(periodLabel = ""), 0), 56, measure)
        assertEquals(CellKind.CLOCK, one.cells.last().kind)
        val two = Scoreboard.layout(Scoreboard.text(state.copy(homeScore = 10, periodLabel = ""), 0), 56, measure)
        // One digit or two: a score cell reserves two digits, so the bar doesn't move.
        assertEquals(one.width, two.width)
    }

    @Test
    fun scalesWithTheFrame() {
        assertEquals(56, Scoreboard.barHeight(1080))
        assertEquals(37, Scoreboard.barHeight(720))
        assertEquals(84, Scoreboard.barHeight(1080, 150))
        assertEquals(140, Scoreboard.barHeight(1080, 999), "clamped to 250%")
        assertEquals(58, Scoreboard.margin(1920))
        assertEquals(32, Scoreboard.margin(1080))
    }
}
