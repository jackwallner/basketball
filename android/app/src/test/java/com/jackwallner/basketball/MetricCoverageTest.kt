package com.jackwallner.basketball

import com.jackwallner.basketball.model.MetricCategory
import com.jackwallner.basketball.model.MetricCoverage
import com.jackwallner.basketball.model.SeasonPhase
import com.jackwallner.basketball.model.StatScoutSeason
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The coverage notes exist so a gap in an old season reads as a limit of the
 * public record rather than as a broken app. These pin the boundaries to the
 * same years the pipeline uses.
 */
class MetricCoverageTest {
    @Test
    fun recentSeasonHasNoCoverageCaveat() {
        assertNull(MetricCoverage.note(2026))
        assertNull(MetricCoverage.note(2026, phase = SeasonPhase.PLAYOFFS))
        assertNull(MetricCoverage.note(2026, MetricCategory.IMPACT))
    }

    @Test
    fun shotZonesStartIn2004() {
        assertNotNull(MetricCoverage.note(2003, MetricCategory.SHOOTING))
        assertNull(MetricCoverage.note(2004, MetricCategory.SHOOTING))
        assertTrue(MetricCoverage.note(2003, MetricCategory.SHOOTING)?.contains("2003-04") == true)
    }

    @Test
    fun plusMinusStartsIn2009() {
        val note = MetricCoverage.note(2008, MetricCategory.IMPACT)
        assertTrue(note ?: "nil", note?.contains("2008-09") == true)
        assertFalse(MetricCoverage.isTracked("On-Court +/-", 2008))
        assertTrue(MetricCoverage.isTracked("On-Court +/-", 2009))
        assertFalse(MetricCoverage.isTracked("+/-", 2008))
    }

    @Test
    fun onOffFollowsThePerSeasonAndPhaseTable() {
        // Regular season: 2013-14, 2014-15, then 2020-21 onward.
        for (season in listOf(2014, 2015) + (2021..2027)) {
            assertTrue("REG $season", MetricCoverage.hasOnOff(season, SeasonPhase.REGULAR))
        }
        for (season in listOf(2009, 2010, 2011, 2012, 2013, 2016, 2017, 2018, 2019, 2020)) {
            assertFalse("REG $season", MetricCoverage.hasOnOff(season, SeasonPhase.REGULAR))
        }
        // Postseason: 2009, 2010, 2012-2015, then 2021 onward.
        for (season in listOf(2009, 2010, 2012, 2013, 2014, 2015) + (2021..2026)) {
            assertTrue("POST $season", MetricCoverage.hasOnOff(season, SeasonPhase.PLAYOFFS))
        }
        for (season in listOf(2011, 2016, 2017, 2018, 2019, 2020)) {
            assertFalse("POST $season", MetricCoverage.hasOnOff(season, SeasonPhase.PLAYOFFS))
        }
        // Career On-Off is never published.
        assertFalse(MetricCoverage.hasOnOff(StatScoutSeason.ALL_TIME))
    }

    @Test
    fun impactNoteNamesAMissingOnOff() {
        assertNotNull(MetricCoverage.note(2019, MetricCategory.IMPACT))
        assertNull(MetricCoverage.note(2021, MetricCategory.IMPACT))
        assertNotNull(MetricCoverage.note(2011, MetricCategory.IMPACT, SeasonPhase.PLAYOFFS))
        assertNotNull(MetricCoverage.note(2011, MetricCategory.IMPACT, SeasonPhase.REGULAR))
        assertNull(MetricCoverage.note(2012, MetricCategory.IMPACT, SeasonPhase.PLAYOFFS))
    }

    @Test
    fun earliestSeasonsCarryTheOldestAndMostSweepingLimit() {
        assertTrue(MetricCoverage.note(2003)?.contains("2003-04") == true)
        assertTrue(MetricCoverage.note(2006)?.contains("2008-09") == true)
    }

    @Test
    fun allTimeExplainsItSpansEras() {
        val note = MetricCoverage.note(StatScoutSeason.ALL_TIME)
        assertNotNull(note)
        assertTrue(note!!.contains("Career"))
        assertTrue(note.contains("not published"))
    }

    @Test
    fun pendingNotesNameTheFeedThatIsBehind() {
        assertEquals(
            "Shot-zone numbers for the latest games are still arriving.",
            MetricCoverage.pendingNote(MetricCategory.SHOOTING, "pending", "ready"),
        )
        assertEquals(
            "On/off numbers for the latest games are still arriving.",
            MetricCoverage.pendingNote(MetricCategory.IMPACT, "ready", "pending"),
        )
        assertNull(MetricCoverage.pendingNote(MetricCategory.SHOOTING, "ready", "pending"))
        assertNull(MetricCoverage.pendingNote(MetricCategory.SCORING, "pending", "pending"))
        assertNull(MetricCoverage.pendingNote(null, "ready", "not_applicable"))
        // The whole-board form says both when both are behind.
        val both = MetricCoverage.pendingNote(null, "pending", "degraded")
        assertTrue(both?.contains("Shot-zone") == true && both.contains("On/off"))
    }

    @Test
    fun isTrackedMatchesSourceStartYears() {
        assertFalse(MetricCoverage.isTracked("Rim FG%", 2003))
        assertTrue(MetricCoverage.isTracked("Rim FG%", 2004))
        assertFalse(MetricCoverage.isTracked("Corner 3%", 2003))
        assertTrue(MetricCoverage.isTracked("Assisted FG%", 2004))
        assertFalse(MetricCoverage.isTracked("On-Off", 2020))
        assertTrue(MetricCoverage.isTracked("On-Off", 2021))
    }

    /** Box-score metrics reach every bundled season, and the career rollup has everything but On-Off. */
    @Test
    fun unboundedMetricsAreAlwaysTracked() {
        assertTrue(MetricCoverage.isTracked("TS%", StatScoutSeason.EARLIEST))
        assertTrue(MetricCoverage.isTracked("PPG", StatScoutSeason.EARLIEST))
        assertTrue(MetricCoverage.isTracked("Rim FG%", StatScoutSeason.ALL_TIME))
        assertFalse(MetricCoverage.isTracked("On-Off", StatScoutSeason.ALL_TIME))
    }
}
