package io.github.instantreplay.replay_capture_android.broadcast

import java.text.BreakIterator
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
    val style: BoardStyle = BoardStyle.CLASSIC,
    val position: BoardPosition = BoardPosition.TOP_LEFT,
)

/** How the board is drawn: the one-row bar, the two-row plate or the wide banner with a clock tab. */
internal enum class BoardStyle { CLASSIC, PLATE, BANNER }

/** Where the board sits on the frame, inside the safe margins: [top] row or bottom, [column] 0 left, 1 centre, 2 right. */
internal enum class BoardPosition(val top: Boolean, val column: Int) {
    TOP_LEFT(true, 0),
    TOP_CENTER(true, 1),
    TOP_RIGHT(true, 2),
    BOTTOM_LEFT(false, 0),
    BOTTOM_CENTER(false, 1),
    BOTTOM_RIGHT(false, 2),
}

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
    val style: BoardStyle = BoardStyle.CLASSIC,
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

/**
 * The banner, in px: a bar [bar] high (edge stripe, HOME, home score, separator, away score, AWAY,
 * edge stripe; both names centred in equal columns so the score sits in the middle) and, centred
 * below it, a tab [tabHeight] high with the period and the clock.
 */
internal data class BannerLayout(
    val width: Int,
    val height: Int,
    val bar: Float,
    /** The bar's left edge and width; the bitmap is wider only when the tab is. */
    val barX: Float,
    val barWidth: Float,
    val edge: Float,
    /** Centres of the name columns. */
    val homeNameX: Float,
    val awayNameX: Float,
    /** The home score is right-aligned here, the away score left-aligned at [awayScoreX]. */
    val homeScoreX: Float,
    val separatorX: Float,
    val awayScoreX: Float,
    val tabX: Float,
    val tabWidth: Float,
    val tabHeight: Float,
    /** Left edge of the period (unused when empty) and centre of the clock in the tab. */
    val periodX: Float,
    val clockX: Float,
    val radius: Float,
)

/** The banner's fonts: names, scores (and separator), and the tab's period and clock. */
internal enum class BannerFont { NAME, SCORE, TAB }

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
        homeName = name(state.homeName, state.style),
        awayName = name(state.awayName, state.style),
        homeScore = state.homeScore.toString(),
        awayScore = state.awayScore.toString(),
        homeColor = state.homeColor,
        awayColor = state.awayColor,
        clock = formatClock(clockMs(state, elapsedMs), state.countDown),
        period = state.periodLabel,
        scalePercent = state.scalePercent.coerceIn(MIN_SCALE, MAX_SCALE),
        style = state.style,
    )

    /** Dart sends names as drawn; this only guards the lengths (5 on the bar, 16 on the plate, 3 on the banner). */
    private fun name(name: String, style: BoardStyle) = cut(
        name.uppercase(Locale.ROOT),
        when (style) {
            BoardStyle.CLASSIC -> CLASSIC_NAME_LENGTH
            BoardStyle.PLATE -> PLATE_NAME_LENGTH
            BoardStyle.BANNER -> BANNER_NAME_LENGTH
        },
    )

    /** The first [max] characters of [s] as people see them: an emoji is never cut in half. */
    fun cut(s: String, max: Int): String {
        val chars = BreakIterator.getCharacterInstance(Locale.ROOT).apply { setText(s) }
        var end = 0
        repeat(max) {
            val next = chars.next()
            if (next == BreakIterator.DONE) return s
            end = next
        }
        return s.substring(0, end)
    }

    /** [s] with every digit as 0: digits are measured as zeros so widths don't change as they tick. */
    private fun zeroDigits(s: String) = s.replace(DIGIT, "0")

    private val DIGIT = Regex("[0-9]")

    /**
     * Left to right: home stripe, HOME, home score, away score, AWAY, away stripe, clock, period
     * (omitted when empty). Sizes scale with [height]; [measure] returns a text's width in px at
     * [BarLayout.textSize]. Scores and clock reserve the width of their digits as zeros, so the bar
     * doesn't twitch every second with a proportional font.
     */
    fun layout(text: ScoreboardText, height: Int, measure: (String) -> Float): BarLayout {
        val pad = height * 0.25f
        val stripe = height * 0.14f
        val zeros = { s: String -> measure(zeroDigits(s)) }
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
        val zeros = { s: String -> measure(PlateFont.MONO, zeroDigits(s)) }
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

    /**
     * The banner for [text] with a bar [bar] px high (see [bannerBar]); [measure] returns a text's
     * width in px in the given font at this layout's sizes. Name columns fit the longer name,
     * scores reserve two digits and the clock its digits as zeros, so the banner doesn't twitch.
     */
    fun bannerLayout(text: ScoreboardText, bar: Float, measure: (BannerFont, String) -> Float): BannerLayout {
        val zeros = { font: BannerFont, s: String -> measure(font, zeroDigits(s)) }
        val edge = bar * BANNER_EDGE
        val pad = bar * 0.4f
        val gap = bar * 0.45f
        val names = maxOf(measure(BannerFont.NAME, text.homeName), measure(BannerFont.NAME, text.awayName))
        val score = maxOf(
            zeros(BannerFont.SCORE, text.homeScore),
            zeros(BannerFont.SCORE, text.awayScore),
            zeros(BannerFont.SCORE, "00"),
        )
        val separator = measure(BannerFont.SCORE, SEPARATOR) + 2 * bar * 0.12f

        val tabHeight = bar * 0.52f
        val tabPad = bar * 0.28f
        val period = if (text.period.isEmpty()) 0f else measure(BannerFont.TAB, text.period) + bar * 0.22f
        val clock = zeros(BannerFont.TAB, text.clock)
        val tabWidth = 2 * tabPad + period + clock

        val barWidth = 2 * (edge + pad + names + gap + score) + separator
        val width = maxOf(barWidth, tabWidth)
        val left = (width - barWidth) / 2
        val homeScoreX = left + edge + pad + names + gap + score
        val awayScoreX = homeScoreX + separator
        val tabX = (width - tabWidth) / 2
        return BannerLayout(
            width = kotlin.math.ceil(width).toInt(),
            height = kotlin.math.ceil(bar + tabHeight).toInt(),
            bar = bar,
            barX = left,
            barWidth = barWidth,
            edge = edge,
            homeNameX = left + edge + pad + names / 2,
            awayNameX = awayScoreX + score + gap + names / 2,
            homeScoreX = homeScoreX,
            separatorX = homeScoreX + separator / 2,
            awayScoreX = awayScoreX,
            tabX = tabX,
            tabWidth = tabWidth,
            tabHeight = tabHeight,
            periodX = tabX + tabPad,
            clockX = tabX + tabPad + period + clock / 2,
            radius = bar * BANNER_RADIUS,
        )
    }

    /** Banner bar height on a frame [frameHeight] px high: a little taller than the classic bar. */
    fun bannerBar(frameHeight: Int, scalePercent: Int = 100) = barHeight(frameHeight, scalePercent) * BANNER_BAR

    /*
     * Where a [width]x[height] board at [position] goes on a [frameWidth]x[frameHeight] frame: its
     * left edge ([placeX]) and, in GL coordinates (origin bottom-left), its bottom edge ([placeY]).
     * Sides and top keep [margin]; the bottom keeps [bottomMargin], clear of the player controls and
     * subtitles. Two plain ints rather than a pair: this runs on the GL thread every frame.
     */
    fun placeX(position: BoardPosition, frameWidth: Int, width: Int) = when (position.column) {
        0 -> margin(frameWidth)
        1 -> (frameWidth - width) / 2
        else -> frameWidth - margin(frameWidth) - width
    }

    fun placeY(position: BoardPosition, frameHeight: Int, height: Int) =
        if (position.top) frameHeight - margin(frameHeight) - height else bottomMargin(frameHeight)

    /**
     * The replay badge sits top-right, or top-left when a board on screen takes the top-right corner
     * ([boardShown]: drawn over the replay and not hidden).
     */
    fun badgeOnLeft(board: BoardPosition, boardShown: Boolean) = boardShown && board == BoardPosition.TOP_RIGHT

    /** Plate row height on a frame [frameHeight] px high: a little taller than the bar. */
    fun plateRow(frameHeight: Int, scalePercent: Int = 100) = barHeight(frameHeight, scalePercent) * PLATE_ROW

    /** Bar height on a frame [frameHeight] px high: 56 px at 1080p and [scalePercent] 100. */
    fun barHeight(frameHeight: Int, scalePercent: Int = 100) =
        maxOf(16, Math.round(frameHeight * 56f / 1080f * scalePercent.coerceIn(MIN_SCALE, MAX_SCALE) / 100f))

    const val MIN_SCALE = 50
    const val MAX_SCALE = 250

    /** Safe margin from the frame edges: 3% of each dimension. */
    fun margin(size: Int) = Math.round(size * 0.03f)

    /** Safe margin from the bottom edge: 6%, above YouTube's controls and subtitles. */
    fun bottomMargin(size: Int) = Math.round(size * 0.06f)

    const val TEXT_SIZE = 0.6f

    /** Plate row height relative to the bar height (the prototype: 44 px rows next to a 40 px bar). */
    const val PLATE_ROW = 1.1f

    /** Plate text sizes relative to the row height. */
    const val PLATE_NAME_SIZE = 0.43f
    const val PLATE_MONO_SIZE = 0.52f
    const val PLATE_PERIOD_SIZE = 0.27f
    const val CLASSIC_NAME_LENGTH = 5
    const val PLATE_NAME_LENGTH = 16
    const val BANNER_NAME_LENGTH = 3

    /** Banner bar height relative to the classic bar, and its text sizes relative to the bar. */
    const val BANNER_BAR = 1.15f
    const val BANNER_NAME_SIZE = 0.46f
    const val BANNER_SCORE_SIZE = 0.62f
    const val BANNER_TAB_SIZE = 0.34f
    const val SEPARATOR = "-"

    /** Banner proportions relative to its bar height, shared by the board and the replay badge. */
    const val BANNER_EDGE = 0.09f
    const val BANNER_RADIUS = 0.06f

    /** Banner navy (95 % opaque), shared by the board and the replay badge. */
    const val BANNER_NAVY = 0xF20B1240.toInt()
}
