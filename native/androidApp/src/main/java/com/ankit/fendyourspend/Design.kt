package com.ankit.fendyourspend

import androidx.compose.foundation.background
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable private fun adaptive(light: Long, dark: Long) = Color((if (isSystemInDarkTheme()) dark else light).toInt())
val Paper: Color @Composable get() = adaptive(0xfff3f6f4, 0xff101a18)
val PaperRaised: Color @Composable get() = adaptive(0xffffffff, 0xff1b2824)
val Ink: Color @Composable get() = adaptive(0xff14241e, 0xfff4f8f5)
val InkSoft: Color @Composable get() = adaptive(0xff40564c, 0xffc6d5cd)
val InkFaint: Color @Composable get() = adaptive(0xff687a71, 0xff9eb2a8)
val Hairline: Color @Composable get() = adaptive(0xffd8e2dc, 0xff384b43)
val Flow: Color @Composable get() = adaptive(0xff2f7c82, 0xff84d1d3)
val FlowSoft: Color @Composable get() = adaptive(0xffe1f2f2, 0xff253f3d)
val IncomeGreen: Color @Composable get() = adaptive(0xff4b9e70, 0xff72c896)
val SpendRed: Color @Composable get() = adaptive(0xffc75248, 0xffff7b6e)
val InvestGold: Color @Composable get() = adaptive(0xffa87518, 0xffe6b865)
val NavColor = Color(0xff1b2824)
val NavSelected = Color(0xff84d1d3)
val HeroText = Color(0xfff4f8f5)

@Composable
fun RaisedCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = PaperRaised),
        border = BorderStroke(1.dp, Hairline)
    ) {
        Column(Modifier.padding(16.dp), content = content)
    }
}

@Composable
fun SectionTitle(title: String, modifier: Modifier = Modifier, trailing: String? = null) {
    Row(
        modifier = modifier.fillMaxWidth().padding(top = 8.dp, bottom = 2.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(title, color = Ink, fontWeight = FontWeight.Bold, fontSize = 16.sp)
        Spacer(Modifier.weight(1f))
        if (trailing != null) Text(trailing, color = Flow, fontWeight = FontWeight.SemiBold, fontSize = 12.sp)
    }
}

@Composable
fun BrandHeader(title: String, subtitle: String = "Money made clear") {
    Text(subtitle, color = InkFaint, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
    Text(
        title,
        color = Ink,
        fontSize = 30.sp,
        lineHeight = 34.sp,
        fontWeight = FontWeight.SemiBold,
        fontFamily = FontFamily.Serif,
        modifier = Modifier.padding(top = 2.dp, bottom = 10.dp)
    )
}

@Composable
fun StatPill(label: String, value: String, color: Color) {
    Column {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Spacer(Modifier.width(9.dp).height(9.dp).background(color, RoundedCornerShape(99.dp)))
            Spacer(Modifier.width(6.dp))
            Text(label, color = InkFaint, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
        }
        Text(value, color = Ink, fontWeight = FontWeight.Bold, fontSize = 14.sp, modifier = Modifier.padding(top = 2.dp))
    }
}

@Composable
fun CategoryDot(name: String, size: Int = 10) {
    Spacer(Modifier.size(size.dp).background(categoryColor(name), CircleShape))
}

@Composable
fun IconBubble(category: String) {
    Box(
        modifier = Modifier
            .size(34.dp)
            .background(categoryColor(category).copy(alpha = 0.14f), RoundedCornerShape(10.dp)),
        contentAlignment = Alignment.Center
    ) {
        CategoryDot(category, 11)
    }
}

@Composable
fun CategoryChip(name: String, removable: Boolean = false, onDelete: () -> Unit = {}) {
    val color = categoryColor(name)
    AssistChip(
        onClick = { if (removable) onDelete() },
        label = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                CategoryDot(name, 9)
                Spacer(Modifier.width(7.dp))
                Text(name, color = color, fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
                if (removable) {
                    Spacer(Modifier.width(7.dp))
                    Text("x", color = color, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                }
            }
        },
        colors = AssistChipDefaults.assistChipColors(containerColor = PaperRaised, labelColor = color),
        border = BorderStroke(1.dp, color),
        shape = RoundedCornerShape(20.dp)
    )
}

@Composable fun categoryColor(name: String): Color = when (name.lowercase()) {
    "home", "house" -> Color(0xff5e7fa3)
    "groceries" -> Color(0xff7c8f3f)
    "food" -> IncomeGreen
    "fun" -> SpendRed
    "gym" -> Color(0xff7b5aa6)
    "self" -> Color(0xff2e8f8a)
    "investment", "investments" -> InvestGold
    else -> Color(0xff8a8a7e)
}
