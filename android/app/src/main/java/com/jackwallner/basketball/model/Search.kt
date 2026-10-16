package com.jackwallner.basketball.model

import java.text.Normalizer

private val COMBINING_MARKS = Regex("\\p{Mn}+")

private fun folded(text: String): String =
    COMBINING_MARKS.replace(Normalizer.normalize(text, Normalizer.Form.NFD), "").lowercase()

/** Case- and accent-blind search, so "doncic" finds "Dončić" and "jokic" finds "Jokić". */
fun String.searchMatches(query: String): Boolean = folded(this).contains(folded(query))

/** Drops the punctuation fans skip when typing a name: "tj mcconnell" finds "T.J. McConnell". */
private fun searchKey(text: String): String =
    text.trim().replace(".", "").replace("'", "").replace("’", "")

/**
 * Name or team search that ignores case, accents and punctuation ("deaaron"
 * finds "De'Aaron") and knows a team by name as well as code ("Lakers").
 */
fun Player.matchesSearch(query: String, includingTeam: Boolean = true): Boolean {
    val text = searchKey(query)
    if (text.isEmpty()) return true
    return searchKey(name).searchMatches(text) ||
        (includingTeam && team.searchMatches(text)) ||
        (includingTeam && teamFullName(team).searchMatches(text))
}
