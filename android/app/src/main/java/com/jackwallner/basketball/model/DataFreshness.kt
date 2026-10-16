package com.jackwallner.basketball.model

import java.time.Instant
import java.time.format.DateTimeFormatter
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** The small, stable vocabulary the app shows while a release moves through the pipeline. */
enum class DataFreshnessStatus(val accessibilityName: String) {
    READY("Ready"),
    CHECKING("Checking"),
    PENDING("Waiting for source data"),
    PARTIAL("Partial data"),
    STALE("Stale data"),
    OFFLINE("Offline"),
    FAILED("Refresh failed");

    val raw: String get() = name.lowercase()

    companion object {
        fun from(raw: String): DataFreshnessStatus = when (raw.lowercase()) {
            "ready", "published", "complete", "completed", "healthy", "unchanged" -> READY
            "checking", "probing", "building", "retrying" -> CHECKING
            "pending", "waiting", "waiting_for_source", "source_pending" -> PENDING
            "partial", "degraded" -> PARTIAL
            "stale", "regressed" -> STALE
            "offline", "unavailable" -> OFFLINE
            "failed", "error" -> FAILED
            else -> READY
        }
    }
}

/** The games a dataset covers, separate from when its row was written. */
data class DataCoverage(
    val asOf: Instant,
    val week: Int?,
    val phase: SeasonPhase,
    val gamesIncluded: Int? = null,
    val expectedGames: Int? = null,
)

/** `data_refresh_status`, accepting the older names during rollout. */
data class DataFreshness(
    val status: DataFreshnessStatus = DataFreshnessStatus.READY,
    val revision: String? = null,
    val sourcePublishedAt: Instant? = null,
    val publishedAt: Instant? = null,
    val checkedAt: Instant? = null,
    val coverage: DataCoverage? = null,
    val message: String? = null,
    val isCached: Boolean = false,
    /**
     * Publisher state of the optional feeds. The columns keep their pre-NBA
     * names: `ngs_status` is the shot feed, `pfr_status` the play-by-play feed.
     */
    val shotsStatus: String? = null,
    val playByPlayStatus: String? = null,
    /** The status string as the publisher wrote it; the rollover tells `source_pending` from a plain pending. */
    val rawStatus: String? = null,
    /** The season the calendar names, which can be ahead of the data. */
    val season: Int? = null,
    /** The season the live revision actually covers. */
    val publishedSeason: Int? = null,
    val lastErrorCode: String? = null,
) {
    /**
     * The new season has started on the calendar but no games are played yet:
     * the schedule exists, the box scores do not, and the last revision still
     * describes the previous season.
     */
    val isSeasonPending: Boolean
        get() {
            if (rawStatus?.lowercase() != "source_pending" || lastErrorCode?.lowercase() != "season_pending") return false
            val s = season ?: return false
            val p = publishedSeason ?: return false
            return s > p
        }

    /** A local display override (offline, failed) is no longer what the publisher said, so the raw string goes. */
    fun withStatus(newStatus: DataFreshnessStatus, cached: Boolean = isCached, newMessage: String? = message): DataFreshness =
        copy(status = newStatus, isCached = cached, message = newMessage, rawStatus = null)

    /** True while the shot or play-by-play feed trails the published games. */
    val isAdvancedPending: Boolean
        get() = listOf(shotsStatus, playByPlayStatus).any { status ->
            val s = status?.lowercase() ?: return@any false
            s != "ready" && s != "not_applicable" && s != "unavailable"
        }

    fun toJson(): JsonObject = buildJsonObject {
        put("status", rawStatus ?: status.raw)
        revision?.let { put("revision", it) }
        sourcePublishedAt?.let { put("source_published_at", ISO.format(it)) }
        publishedAt?.let { put("published_at", ISO.format(it)) }
        checkedAt?.let { put("checked_at", ISO.format(it)) }
        coverage?.let { c ->
            put("as_of", ISO.format(c.asOf))
            c.week?.let { put("week", it) }
            put("season_type", c.phase.raw)
            c.gamesIncluded?.let { put("games_included", it) }
            c.expectedGames?.let { put("expected_games", it) }
        }
        message?.let { put("message", it) }
        put("is_cached", isCached)
        shotsStatus?.let { put("ngs_status", it) }
        playByPlayStatus?.let { put("pfr_status", it) }
        season?.let { put("season", it) }
        publishedSeason?.let { put("published_season", it) }
        lastErrorCode?.let { put("last_error_code", it) }
    }

    companion object {
        private val ISO = DateTimeFormatter.ISO_INSTANT

        fun fromJson(o: JsonObject): DataFreshness {
            val nested = o.obj("coverage")
            val rawAsOf = o.string("as_of") ?: o.string("max_game_date") ?: nested?.string("as_of")
            val rawWeek = o.int("week") ?: o.int("end_week") ?: o.int("max_week") ?: nested?.int("week") ?: nested?.int("end_week")
            val rawPhase = o.string("season_type") ?: nested?.string("season_type")
            val gamesIncluded = o.int("games_included") ?: o.int("games_through") ?: o.int("observed_games")
                ?: nested?.int("games_included") ?: nested?.int("games_through")
            val expectedGames = o.int("expected_games") ?: nested?.int("expected_games")
            val coverage = rawAsOf?.let(::parseDate)?.let { asOf ->
                DataCoverage(asOf, rawWeek, rawPhase?.let { SeasonPhase.from(it) } ?: SeasonPhase.REGULAR, gamesIncluded, expectedGames)
            }
            val rawStatus = o.string("status")
            return DataFreshness(
                status = DataFreshnessStatus.from(rawStatus ?: "ready"),
                revision = o.string("revision") ?: o.string("refresh_id") ?: o.string("source_fingerprint"),
                sourcePublishedAt = o.string("source_published_at")?.let(::parseDate),
                publishedAt = o.string("published_at")?.let(::parseDate),
                checkedAt = o.string("checked_at")?.let(::parseDate) ?: o.string("last_checked_at")?.let(::parseDate),
                coverage = coverage,
                message = o.string("message") ?: o.string("error_message"),
                isCached = o.bool("is_cached") ?: false,
                shotsStatus = o.string("ngs_status"),
                playByPlayStatus = o.string("pfr_status"),
                rawStatus = rawStatus,
                season = o.int("season"),
                publishedSeason = o.int("published_season"),
                lastErrorCode = o.string("last_error_code"),
            )
        }
    }
}
