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
)

internal enum class CellKind { STRIPE, NAME, SCORE, CLOCK, PERIOD }

/** One cell of the bar, x and width in px. [color] is the stripe color for [CellKind.STRIPE]. */
internal data class Cell(val kind: CellKind, val x: Float, val width: Float, val text: String = "", val color: Int = 0)

internal data class BarLayout(val width: Int, val height: Int, val textSize: Float, val cells: List<Cell>)

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
        homeName = state.homeName.uppercase(Locale.ROOT),
        awayName = state.awayName.uppercase(Locale.ROOT),
        homeScore = state.homeScore.toString(),
        awayScore = state.awayScore.toString(),
        homeColor = state.homeColor,
        awayColor = state.awayColor,
        clock = formatClock(clockMs(state, elapsedMs), state.countDown),
        period = state.periodLabel,
        scalePercent = state.scalePercent.coerceIn(MIN_SCALE, MAX_SCALE),
    )

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

    /** Bar height on a frame [frameHeight] px high: 56 px at 1080p and [scalePercent] 100. */
    fun barHeight(frameHeight: Int, scalePercent: Int = 100) =
        maxOf(16, Math.round(frameHeight * 56f / 1080f * scalePercent.coerceIn(MIN_SCALE, MAX_SCALE) / 100f))

    const val MIN_SCALE = 50
    const val MAX_SCALE = 250

    /** Safe margin from the frame edges: 3% of each dimension. */
    fun margin(size: Int) = Math.round(size * 0.03f)

    const val TEXT_SIZE = 0.6f
}
