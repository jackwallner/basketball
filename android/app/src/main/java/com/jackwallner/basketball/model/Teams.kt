package com.jackwallner.basketball.model

/** The 30 current NBA teams in the app's team codes. Shared by the Teams grid and switcher. */
val leagueTeamAbbreviations: List<String> = listOf(
    "ATL", "BKN", "BOS", "CHA", "CHI", "CLE", "DAL", "DEN", "DET", "GSW",
    "HOU", "IND", "LAC", "LAL", "MEM", "MIA", "MIL", "MIN", "NOP", "NYK",
    "OKC", "ORL", "PHI", "PHX", "POR", "SAC", "SAS", "TOR", "UTA", "WAS",
)

enum class LeagueConference(val label: String) {
    ALL("All"), EAST("East"), WEST("West");

    fun contains(team: String): Boolean {
        val abbr = normalizedTeamAbbreviation(team)
        return when (this) {
            ALL -> true
            EAST -> abbr in EAST_TEAMS
            WEST -> abbr in WEST_TEAMS
        }
    }

    private companion object {
        val EAST_TEAMS = setOf(
            "ATL", "BKN", "BOS", "CHA", "CHI", "CLE", "DET", "IND",
            "MIA", "MIL", "NYK", "ORL", "PHI", "TOR", "WAS", "NJN",
        )
        val WEST_TEAMS = setOf(
            "DAL", "DEN", "GSW", "HOU", "LAC", "LAL", "MEM", "MIN",
            "NOP", "OKC", "PHX", "POR", "SAC", "SAS", "UTA",
            "SEA", "NOH", "NOK", "VAN",
        )
    }
}

/**
 * Six divisions of five, grouped by conference. It is how people already hold
 * the league in their heads, and all thirty teams fit one screen.
 */
enum class LeagueDivision(val label: String, val teams: List<String>) {
    ATLANTIC("East · Atlantic", listOf("BOS", "BKN", "NYK", "PHI", "TOR")),
    CENTRAL("East · Central", listOf("CHI", "CLE", "DET", "IND", "MIL")),
    SOUTHEAST("East · Southeast", listOf("ATL", "CHA", "MIA", "ORL", "WAS")),
    NORTHWEST("West · Northwest", listOf("DEN", "MIN", "OKC", "POR", "UTA")),
    PACIFIC("West · Pacific", listOf("GSW", "LAC", "LAL", "PHX", "SAC")),
    SOUTHWEST("West · Southwest", listOf("DAL", "HOU", "MEM", "NOP", "SAS"));

    val conference: LeagueConference
        get() = if (label.startsWith("East")) LeagueConference.EAST else LeagueConference.WEST

    companion object {
        fun of(team: String): LeagueDivision? {
            val abbr = normalizedTeamAbbreviation(team)
            return entries.firstOrNull { abbr in it.teams }
        }

        /** The two conferences, for the standings tables. */
        val conferences: List<Pair<String, List<String>>>
            get() = listOf(
                "Eastern Conference" to entries.filter { it.conference == LeagueConference.EAST }.flatMap { it.teams },
                "Western Conference" to entries.filter { it.conference == LeagueConference.WEST }.flatMap { it.teams },
            )
    }
}

private val TEAM_NAMES = mapOf(
    "ATL" to "Atlanta Hawks", "BKN" to "Brooklyn Nets", "BOS" to "Boston Celtics",
    "CHA" to "Charlotte Hornets", "CHI" to "Chicago Bulls", "CLE" to "Cleveland Cavaliers",
    "DAL" to "Dallas Mavericks", "DEN" to "Denver Nuggets", "DET" to "Detroit Pistons",
    "GSW" to "Golden State Warriors", "HOU" to "Houston Rockets", "IND" to "Indiana Pacers",
    "LAC" to "Los Angeles Clippers", "LAL" to "Los Angeles Lakers", "MEM" to "Memphis Grizzlies",
    "MIA" to "Miami Heat", "MIL" to "Milwaukee Bucks", "MIN" to "Minnesota Timberwolves",
    "NOP" to "New Orleans Pelicans", "NYK" to "New York Knicks", "OKC" to "Oklahoma City Thunder",
    "ORL" to "Orlando Magic", "PHI" to "Philadelphia 76ers", "PHX" to "Phoenix Suns",
    "POR" to "Portland Trail Blazers", "SAC" to "Sacramento Kings", "SAS" to "San Antonio Spurs",
    "TOR" to "Toronto Raptors", "UTA" to "Utah Jazz", "WAS" to "Washington Wizards",
    // Historical franchises.
    "SEA" to "Seattle SuperSonics", "NJN" to "New Jersey Nets", "NOH" to "New Orleans Hornets",
    "NOK" to "New Orleans/Oklahoma City Hornets", "VAN" to "Vancouver Grizzlies",
)

private val TEAM_CODES_BY_NAME: Map<String, String> = TEAM_NAMES.entries.associate { it.value.uppercase() to it.key }

/** ESPN's short forms and the usual fan variants, mapped to the app's codes. */
private val TEAM_ALIASES = mapOf(
    "GS" to "GSW", "NO" to "NOP", "NY" to "NYK", "SA" to "SAS", "UTAH" to "UTA",
    "WSH" to "WAS", "NJ" to "NJN", "BRK" to "BKN", "PHO" to "PHX", "CHO" to "CHA",
)

fun normalizedTeamAbbreviation(team: String): String {
    val key = team.trim().uppercase()
    TEAM_ALIASES[key]?.let { return it }
    return TEAM_CODES_BY_NAME[key] ?: key
}

fun teamFullName(abbr: String): String = TEAM_NAMES[normalizedTeamAbbreviation(abbr)] ?: abbr

private val MULTI_WORD_CITIES = listOf(
    "New Orleans/Oklahoma City", "Oklahoma City", "Golden State", "Los Angeles", "New Orleans",
    "New Jersey", "New York", "San Antonio",
)

/** Short team name for tight columns: "Celtics", "Trail Blazers". */
fun teamNickname(abbr: String): String {
    val full = teamFullName(abbr)
    for (city in MULTI_WORD_CITIES) if (full.startsWith("$city ")) return full.drop(city.length + 1)
    if (full.startsWith("Portland ")) return full.removePrefix("Portland ")
    val parts = full.split(" ", limit = 2)
    return parts.lastOrNull() ?: full
}

private fun isUnsignedTeam(abbr: String): Boolean {
    val trimmed = abbr.trim().uppercase()
    return trimmed.isEmpty() || trimmed == "TBD" || trimmed == "—" || trimmed == "-"
}

fun displayTeamAbbr(abbr: String): String = if (isUnsignedTeam(abbr)) "FA" else abbr

fun displayTeamFullName(abbr: String): String = if (isUnsignedTeam(abbr)) "Free Agent" else teamFullName(abbr)
