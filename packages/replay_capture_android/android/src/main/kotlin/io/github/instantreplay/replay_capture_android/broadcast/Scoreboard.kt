package io.github.instantreplay.replay_capture_android.broadcast

import java.util.Locale

/** The overlay state as received from Dart (mirrors the pigeon `OverlayState`, kept free of Flutter types). */
internal data class ScoreboardState(
    val visible: Boolean,
    val homeName: String,
    val awayName: String,
    val homeScore: Int,
    val awayScore: Int,
    val homeColor: Int,
    val awayColor: Int,
    val periodLabel: String,
    val clockMs: Long,
    val clockRunning: Boolean,
    val countDown: Boolean,
    /** Bar size relative to the 56 px (at 1080p) default; 100 = default. */
    val scalePercent: Int = 100,
    /** Two-row plate with full names instead of the one-row bar. */
    val plate: Boolean = false,
)

/** Everything the bar shows. The bitmap is redrawn only when this changes (at most once per second). */
internal data class ScoreboardText(
    val homeName: String,
    val awayName: String,
    val homeScore: String,
    val awayScore: String,
    val homeColor: Int,
    val awayColor: Int,
    val clock: String,
    val period: String,
    val scalePercent: Int = 100,
    val plate: Boolean = false,
)

internal enum class CellKind { STRIPE, NAME, SCORE, CLOCK, PERIOD }

/** One cell of the bar, x and width in px. [color] is the stripe color for [CellKind.STRIPE]. */
internal data class Cell(val kind: CellKind, val x: Float, val width: Float, val text: String = "", val color: Int = 0)

internal data class BarLayout(val width: Int, val height: Int, val textSize: Float, val cells: List<Cell>)

/**
 * The two-row plate, in px: a name column (stripe + name), a score column and, past a 1 px
 * divider at [dividerX], a clock column spanning both rows (clock over period). Rows are [row]
 * high; text sizes are for the name, score/clock and period fonts.
 */
internal data class PlateLayout(
    val width: Int,
    val height: Int,
    val row: Float,
    val nameSize: Float,
    val scoreSize: Float,
    val periodSize: Float,
    val stripeX: Float,
    val stripeWidth: Float,
    val stripeHeight: Float,
    val nameX: Float,
    val scoreX: Float,
    val scoreWidth: Float,
    /** Right padding of a score (right-aligned in its cell). */
    val scorePad: Float,
    val dividerX: Float,
    val clockX: Float,
    val clockWidth: Float,
    val radius: Float,
    val border: Float,
)

/** What a text measurer is asked to measure with: each plate font has its own size. */
internal enum class PlateFont { NAME, MONO, PERIOD }

/** Pure scoreboard logic: clock, text and layout. Drawing is in `gl/OverlayRenderer`. */
internal object Scoreboard {
    /** Clock value [elapsedMs] after the state arrived: a running clock advances, a count-down stops at 0. */
    fun clockMs(state: ScoreboardState, elapsedMs: Long): Long {
        if (!state.clockRunning) return maxOf(0, state.clockMs)
        val ms = if (state.countDown) state.clockMs - elapsedMs else state.clockMs + elapsedMs
        return maxOf(0, ms)
    }

    /**
     * `mm:ss`, minutes not capped (93:12). Counting up shows whole elapsed seconds; counting down
     * rounds up, so 0:00 appears only when time is really over.
     */
    fun formatClock(ms: Long, countDown: Boolean): String {
        val seconds = if (countDown) (ms + 999) / 1000 else ms / 1000
        return String.format(Locale.ROOT, "%02d:%02d", seconds / 60, seconds % 60)
    }

    fun text(state: ScoreboardState, elapsedMs: Long) = ScoreboardText(
        homeName = name(state.homeName, state.plate),
        awayName = name(state.awayName, state.plate),
        homeScore = state.homeScore.toString(),
        awayScore = state.awayScore.toString(),
        homeColor = state.homeColor,
        awayColor = state.awayColor,
        clock = formatClock(clockMs(state, elapsedMs), state.countDown),
        period = state.periodLabel,
        scalePercent = state.scalePercent.coerceIn(MIN_SCALE, MAX_SCALE),
        plate = state.plate,
    )

    /** Dart sends names as drawn; this only guards the lengths (5 letters on the bar, 16 on the plate). */
    private fun name(name: String, plate: Boolean) =
        name.uppercase(Locale.ROOT).take(if (plate) PLATE_NAME_LENGTH else CLASSIC_NAME_LENGTH)

    /**
     * Left to right: home stripe, HOME, home score, away score, AWAY, away stripe, clock, period
     * (omitted when empty). Sizes scale with [height]; [measure] returns a text's width in px at
     * [BarLayout.textSize]. Scores and clock reserve the width of their digits as zeros, so the bar
     * doesn't twitch every second with a proportional font.
     */
    fun layout(text: ScoreboardText, height: Int, measure: (String) -> Float): BarLayout {
        val pad = height * 0.25f
        val stripe = height * 0.14f
        val zeros = { s: String -> measure(s.replace(Regex("[0-9]"), "0")) }
        val cells = mutableListOf<Cell>()
        var x = 0f
        fun add(kind: CellKind, width: Float, text: String = "", color: Int = 0) {
            cells += Cell(kind, x, width, text, color)
            x += width
        }
        add(CellKind.STRIPE, stripe, color = text.homeColor)
        add(CellKind.NAME, measure(text.homeName) + 2 * pad, text.homeName)
        add(CellKind.SCORE, maxOf(zeros(text.homeScore), zeros("00")) + 2 * pad, text.homeScore)
        add(CellKind.SCORE, maxOf(zeros(text.awayScore), zeros("00")) + 2 * pad, text.awayScore)
        add(CellKind.NAME, measure(text.awayName) + 2 * pad, text.awayName)
        add(CellKind.STRIPE, stripe, color = text.awayColor)
        add(CellKind.CLOCK, zeros(text.clock) + 2 * pad, text.clock)
        if (text.period.isNotEmpty()) add(CellKind.PERIOD, measure(text.period) + 2 * pad, text.period)
        return BarLayout(kotlin.math.ceil(x).toInt(), height, height * TEXT_SIZE, cells)
    }

    /**
     * The plate for [text] with rows [row] px high (see [plateRow]); [measure] returns a text's
     * width in px in the given font at this layout's sizes. The name column fits the longer name;
     * scores reserve two digits and the clock its digits as zeros, so the plate doesn't twitch.
     */
    fun plateLayout(text: ScoreboardText, row: Float, measure: (PlateFont, String) -> Float): PlateLayout {
        val zeros = { s: String -> measure(PlateFont.MONO, s.replace(Regex("[0-9]"), "0")) }
        val border = maxOf(1f, kotlin.math.round(row / 44f))
        val stripeX = row * 0.23f
        val stripeWidth = row * 0.11f
        val nameX = stripeX + stripeWidth + row * 0.2f
        val names = maxOf(measure(PlateFont.NAME, text.homeName), measure(PlateFont.NAME, text.awayName))
        val scoreX = nameX + names + row * 0.41f
        val scorePad = row * 0.32f
        val scoreWidth = maxOf(zeros(text.homeScore), zeros(text.awayScore), zeros("00")) + 2 * scorePad
        val dividerX = scoreX + scoreWidth
        val clockX = dividerX + border
        val periodWidth = if (text.period.isEmpty()) 0f else measure(PlateFont.PERIOD, text.period)
        val clockWidth = maxOf(zeros(text.clock), periodWidth) + 2 * row * 0.36f
        return PlateLayout(
            width = kotlin.math.ceil(clockX + clockWidth).toInt(),
            height = kotlin.math.ceil(2 * row).toInt(),
            row = row,
            nameSize = row * PLATE_NAME_SIZE,
            scoreSize = row * PLATE_MONO_SIZE,
            periodSize = row * PLATE_PERIOD_SIZE,
            stripeX = stripeX,
            stripeWidth = stripeWidth,
            stripeHeight = row * 0.45f,
            nameX = nameX,
            scoreX = scoreX,
            scoreWidth = scoreWidth,
            scorePad = scorePad,
            dividerX = dividerX,
            clockX = clockX,
            clockWidth = clockWidth,
            radius = row * 0.07f,
            border = border,
        )
    }

    /** Plate row height on a frame [frameHeight] px high: a little taller than the bar. */
    fun plateRow(frameHeight: Int, scalePercent: Int = 100) = barHeight(frameHeight, scalePercent) * PLATE_ROW

    /** Bar height on a frame [frameHeight] px high: 56 px at 1080p and [scalePercent] 100. */
    fun barHeight(frameHeight: Int, scalePercent: Int = 100) =
        maxOf(16, Math.round(frameHeight * 56f / 1080f * scalePercent.coerceIn(MIN_SCALE, MAX_SCALE) / 100f))

    const val MIN_SCALE = 50
    const val MAX_SCALE = 250

    /** Safe margin from the frame edges: 3% of each dimension. */
    fun margin(size: Int) = Math.round(size * 0.03f)

    const val TEXT_SIZE = 0.6f

    /** Plate row height relative to the bar height (the prototype: 44 px rows next to a 40 px bar). */
    const val PLATE_ROW = 1.1f

    /** Plate text sizes relative to the row height. */
    const val PLATE_NAME_SIZE = 0.43f
    const val PLATE_MONO_SIZE = 0.52f
    const val PLATE_PERIOD_SIZE = 0.27f
    const val CLASSIC_NAME_LENGTH = 5
    const val PLATE_NAME_LENGTH = 16
}
