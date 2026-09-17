package com.ankit.dailymint.prototype

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

@Composable
fun AndroidSMSOnboarding(
    onAllow: () -> Unit,
    onOpenSettings: () -> Unit,
    showSettings: Boolean,
    onContinue: () -> Unit
) {
    Column(
        Modifier.fillMaxSize().background(Paper).padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp)
    ) {
        Spacer(Modifier.height(18.dp))
        BrandHeader("Set up DailyMint")
        Text("Bank transactions can appear automatically when SMS access is enabled.", color = InkSoft)
        RaisedCard {
            Text("Your messages stay on this device", color = Ink, fontWeight = FontWeight.Bold)
            Text(
                "DailyMint checks incoming messages for transactions on this device. Only recognized transactions affect your totals. You can still add entries manually without SMS access.",
                color = InkSoft
            )
        }
        Spacer(Modifier.weight(1f))
        Button(
            onClick = if (showSettings) onOpenSettings else onAllow,
            modifier = Modifier.fillMaxWidth().testTag("allowSms")
        ) {
            Text(if (showSettings) "Open app settings" else "Allow SMS access")
        }
        TextButton(onClick = onContinue, modifier = Modifier.fillMaxWidth().testTag("skipSms")) {
            Text("Continue without SMS")
        }
    }
}
