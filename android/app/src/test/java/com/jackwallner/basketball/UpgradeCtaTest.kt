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

    @Test
    fun knownProductsMapToPurchasePackages() {
        assertEquals(PackageKind.YEARLY, PackageKind.fromIdentifiers(StatScoutProduct.YEARLY))
        assertEquals(PackageKind.MONTHLY, PackageKind.fromIdentifiers(StatScoutProduct.MONTHLY))
        assertEquals(PackageKind.LIFETIME, PackageKind.fromIdentifiers(StatScoutProduct.LIFETIME))
        assertEquals(PackageKind.OTHER, PackageKind.fromIdentifiers("unknown"))
    }
}
