package com.jackwallner.basketball

import com.jackwallner.basketball.data.PackageKind
import com.jackwallner.basketball.data.PriceCopy
import com.jackwallner.basketball.data.StatScoutProduct
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class UpgradeCtaTest {
    @Test
    fun saysTryFreeWhenATrialIsAvailable() {
        assertEquals("Try Free", PriceCopy.upgradeCTALabel(true))
    }

    @Test
    fun fallsBackToUpgradeWithoutATrial() {
        assertEquals("Upgrade", PriceCopy.upgradeCTALabel(false))
    }

    @Test
    fun oneLabelFitsEveryEntryPoint() {
        for (trialAvailable in listOf(true, false)) {
            val label = PriceCopy.upgradeCTALabel(trialAvailable)
            assertFalse(label.isEmpty())
            assertTrue(label.length <= 12)
        }
    }

    /** Upsell cards only navigate, so they name neither a price nor a trial (iOS 30ef703). */
    @Test
    fun upsellCardsNameNoPriceOrTrial() {
        val label = PriceCopy.UPSELL_CARD_LABEL
        assertEquals("See StatScout+ Plans", label)
        assertFalse(label.contains("free", ignoreCase = true))
        assertFalse(label.contains("trial", ignoreCase = true))
        assertFalse(label.any { it.isDigit() })
    }

    @Test
    fun knownProductsMapToPurchasePackages() {
        assertEquals(PackageKind.YEARLY, PackageKind.fromIdentifiers(StatScoutProduct.YEARLY))
        assertEquals(PackageKind.MONTHLY, PackageKind.fromIdentifiers(StatScoutProduct.MONTHLY))
        assertEquals(PackageKind.LIFETIME, PackageKind.fromIdentifiers(StatScoutProduct.LIFETIME))
        assertEquals(PackageKind.OTHER, PackageKind.fromIdentifiers("unknown"))
    }
}
