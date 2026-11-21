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
    fun namesAreCutToFiveOnTheBarAndKeptOnThePlate() {
        val long = state.copy(homeName = "Halcones", awayName = "Leones de Madrid")
        val bar = Scoreboard.text(long, 0)
        assertEquals("HALCO", bar.homeName)
        assertEquals("LEONE", bar.awayName)
        assertEquals(BoardStyle.CLASSIC, bar.style)
        val plate = Scoreboard.text(long.copy(style = BoardStyle.PLATE), 0)
        assertEquals("HALCONES", plate.homeName)
        assertEquals("LEONES DE MADRID", plate.awayName)
        assertEquals(BoardStyle.PLATE, plate.style)
        val banner = Scoreboard.text(long.copy(style = BoardStyle.BANNER), 0)
        assertEquals("HAL", banner.homeName)
        assertEquals("LEO", banner.awayName)
        assertTrue(bar != plate, "a style change redraws the texture")
    }

    private val plateMeasure = { font: PlateFont, s: String ->
        s.length * when (font) {
            PlateFont.NAME -> 10f
            PlateFont.MONO -> 12f
            PlateFont.PERIOD -> 6f
        }
    }

    @Test
    fun plateFitsTheLongerNameAndSpansTheClockOverBothRows() {
        val text = Scoreboard.text(state.copy(style = BoardStyle.PLATE, homeName = "Halcones"), 0)
        val row = 44f
        val l = Scoreboard.plateLayout(text, row, plateMeasure)
        assertEquals(88, l.height)
        // Name column: padding, stripe, gap, the longer name (8 letters), padding.
        assertTrue(l.stripeX > 0 && l.nameX > l.stripeX + l.stripeWidth)
        assertEquals(l.nameX + 80f + row * 0.41f, l.scoreX, 0.001f)
        // Score cell reserves two digits; the clock column follows a 1 px line.
        assertEquals(24f + 2 * l.scorePad, l.scoreWidth, 0.001f)
        assertEquals(l.scoreX + l.scoreWidth, l.dividerX, 0.001f)
        assertEquals(1f, l.border)
        assertEquals(l.dividerX + l.border, l.clockX, 0.001f)
        assertEquals(kotlin.math.ceil(l.clockX + l.clockWidth).toInt(), l.width)
        assertEquals(row * 0.07f, l.radius, 0.001f)

        val longer = Scoreboard.plateLayout(
            Scoreboard.text(state.copy(style = BoardStyle.PLATE, awayName = "Leones de Madrid"), 0), row, plateMeasure,
        )
        assertEquals(l.scoreX + 80f, longer.scoreX, 0.001f, "the plate widens with the longest name")
    }

    @Test
    fun plateWidthIsStableAsTheScoreAndClockTick() {
        val base = state.copy(style = BoardStyle.PLATE)
        val a = Scoreboard.plateLayout(Scoreboard.text(base, 0), 44f, plateMeasure)
        val b = Scoreboard.plateLayout(Scoreboard.text(base.copy(homeScore = 19), 7_000), 44f, plateMeasure)
        assertEquals(a.width, b.width)
        val noPeriod = Scoreboard.plateLayout(Scoreboard.text(base.copy(periodLabel = ""), 0), 44f, plateMeasure)
        assertEquals(a.width, noPeriod.width, "the clock is wider than a short period label")
    }

    private val bannerMeasure = { font: BannerFont, s: String ->
        s.length * when (font) {
            BannerFont.NAME -> 10f
            BannerFont.SCORE -> 14f
            BannerFont.TAB -> 6f
        }
    }

    @Test
    fun bannerCentresTheScoreAndHangsTheTabBelow() {
        val bar = 64f
        val l = Scoreboard.bannerLayout(Scoreboard.text(state.copy(style = BoardStyle.BANNER), 0), bar, bannerMeasure)
        assertEquals(kotlin.math.ceil(bar + bar * 0.52f).toInt(), l.height)
        // Symmetric bar: the separator is in the middle, names mirror each other around it.
        assertEquals(l.barX + l.barWidth / 2, l.separatorX, 0.001f)
        assertEquals(l.separatorX - l.homeNameX, l.awayNameX - l.separatorX, 0.001f)
        assertTrue(l.homeNameX < l.homeScoreX && l.homeScoreX < l.separatorX && l.separatorX < l.awayScoreX)
        assertTrue(l.awayScoreX < l.awayNameX)
        // The tab is centred, period first then the clock.
        assertEquals(l.width / 2f, l.tabX + l.tabWidth / 2, 0.5f)
        assertTrue(l.periodX < l.clockX)
        assertEquals(0f, l.barX, 0.001f)
    }

    @Test
    fun bannerWidthIsStableAsTheScoreAndClockTick() {
        val base = state.copy(style = BoardStyle.BANNER)
        val a = Scoreboard.bannerLayout(Scoreboard.text(base, 0), 64f, bannerMeasure)
        val b = Scoreboard.bannerLayout(Scoreboard.text(base.copy(awayScore = 21), 7_000), 64f, bannerMeasure)
        assertEquals(a.width, b.width)
        val noPeriod = Scoreboard.bannerLayout(Scoreboard.text(base.copy(periodLabel = ""), 0), 64f, bannerMeasure)
        assertTrue(noPeriod.tabWidth < a.tabWidth, "no period, a narrower tab")
        assertEquals(64f * Scoreboard.BANNER_BAR, Scoreboard.bannerBar(1080, 114), 0.001f)
    }

    @Test
    fun placesTheBoardInsideTheSafeMargins() {
        val (w, h) = 1920 to 1080
        fun at(p: BoardPosition) = Scoreboard.placeX(p, w, 400) to Scoreboard.placeY(p, h, 100)
        assertEquals(58 to 1080 - 32 - 100, at(BoardPosition.TOP_LEFT))
        assertEquals(760 to 1080 - 32 - 100, at(BoardPosition.TOP_CENTER))
        assertEquals(1920 - 58 - 400 to 1080 - 32 - 100, at(BoardPosition.TOP_RIGHT))
        // The bottom keeps a larger margin, above the player controls.
        assertEquals(58 to 65, at(BoardPosition.BOTTOM_LEFT))
        assertEquals(760 to 65, at(BoardPosition.BOTTOM_CENTER))
        assertEquals(1920 - 58 - 400 to 65, at(BoardPosition.BOTTOM_RIGHT))
    }

    @Test
    fun theBadgeMovesLeftOnlyWhenABoardOnScreenTakesTheTopRight() {
        assertTrue(Scoreboard.badgeOnLeft(BoardPosition.TOP_RIGHT, boardShown = true))
        assertTrue(!Scoreboard.badgeOnLeft(BoardPosition.TOP_RIGHT, boardShown = false))
        BoardPosition.entries.filter { it != BoardPosition.TOP_RIGHT }.forEach {
            assertTrue(!Scoreboard.badgeOnLeft(it, boardShown = true))
        }
    }

    @Test
    fun namesAreNeverCutInsideAnEmoji() {
        assertEquals("AB\uD83E\uDD81", Scoreboard.cut("AB\uD83E\uDD81X", 3))
        assertEquals("ABC", Scoreboard.cut("ABCDE", 3))
        assertEquals("AB", Scoreboard.cut("AB", 3))
        assertEquals("AB\uD83E\uDD81", Scoreboard.text(state.copy(style = BoardStyle.BANNER, homeName = "AB\uD83E\uDD81X"), 0).homeName)
    }

    @Test
    fun plateScalesLikeTheBar() {
        assertEquals(56 * Scoreboard.PLATE_ROW, Scoreboard.plateRow(1080), 0.001f)
        assertEquals(84 * Scoreboard.PLATE_ROW, Scoreboard.plateRow(1080, 150), 0.001f)
        assertEquals(2f, Scoreboard.plateLayout(Scoreboard.text(state.copy(style = BoardStyle.PLATE), 0), 88f, plateMeasure).border)
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
