package com.jackwallner.basketball.model

import com.jackwallner.basketball.data.KeyValueStore
import java.time.LocalDate
import java.time.ZoneId

/**
 * Which season the app treats as live, and how that is decided.
 *
 * A hoopR season is named for the year it ends: 2026 is 2025-26 and 2027 is
 * 2026-27. The calendar flips to the new season on October 1, but the first
 * tip-off is about three weeks later, so for those weeks the calendar's season
 * has a schedule and nothing else. [resolveLive] reconciles the two from the
 * publisher's status row, so a build never has to ship to roll a season over.
 */
object StatScoutSeason {
    /** October through December belong to the season that ends next summer. */
    fun calendarSeason(today: LocalDate = LocalDate.now(ZoneId.systemDefault())): Int =
        if (today.monthValue >= 10) today.year + 1 else today.year

    /** hoopR's player box starts in 2002; 2003 (2002-03) is the first full season. */
    const val EARLIEST = 2003

    /** Newest season the bundled archive carries; the fallback before the server answers. */
    const val BUNDLED_NEWEST = 2026

    /** Oldest season with per-game history, the floor for Recent Form. */
    const val EARLIEST_RECENT_FORM = 2026

    /** Sentinel for the career rollup; zero sorts below every real year. */
    const val ALL_TIME = 0

    fun isAllTime(season: Int): Boolean = season == ALL_TIME

    /** The newest season with published data, plus a scheduled season with no games yet. */
    data class Live(val season: Int, val upcoming: Int?) {
        val isPending: Boolean get() = upcoming != null
    }

    /**
     * The status row carries the season the calendar names and the season the
     * live revision covers. Between the October rollover and opening night the
     * first is ahead; the app keeps the finished season live and surfaces the
     * new one only as a schedule.
     */
    fun resolveLive(status: DataFreshness?, fallback: Int): Live {
        status ?: return Live(fallback, null)
        val season = status.publishedSeason ?: status.season ?: fallback
        val upcoming = if (status.isSeasonPending) status.season else null
        return Live(season, upcoming)
    }

    /** Before the first status check lands: the last live season this device saw, else the calendar capped at the bundle. */
    fun initialLive(defaults: KeyValueStore, calendarSeason: Int = calendarSeason()): Live {
        val stored = defaults.getInt(LIVE_SEASON_KEY, 0)
        if (stored < EARLIEST) return Live(minOf(calendarSeason, BUNDLED_NEWEST), null)
        val upcoming = defaults.getInt(UPCOMING_SEASON_KEY, 0)
        return Live(stored, if (upcoming > stored) upcoming else null)
    }

    fun remember(live: Live, defaults: KeyValueStore) {
        defaults.putInt(LIVE_SEASON_KEY, live.season)
        defaults.putInt(UPCOMING_SEASON_KEY, live.upcoming ?: 0)
    }

    private const val LIVE_SEASON_KEY = "statscout.liveSeason"
    private const val UPCOMING_SEASON_KEY = "statscout.upcomingSeason"
}

/**
 * NBA seasons span two calendar years and hoopR names one for the year it
 * ends: 2026 is "2025-26". Every label the user sees goes through here.
 */
object SeasonLabel {
    fun display(season: Int): String {
        if (StatScoutSeason.isAllTime(season)) return "All Time"
        return "${season - 1}-" + "%02d".format(season % 100)
    }

    /** "2025-26 Regular Season"; "All Time · Playoffs" for the career rollup. */
    fun display(season: Int, phase: SeasonPhase): String =
        if (StatScoutSeason.isAllTime(season)) "${display(season)} · ${phase.label}" else "${display(season)} ${phase.label}"
}
