package com.ankit.dailymint.prototype

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
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

val Paper = Color(0xffeef0e6)
val PaperRaised = Color(0xfff8f9f3)
val Ink = Color(0xff17261f)
val InkSoft = Color(0xff4b594e)
val InkFaint = Color(0xff8b968b)
val Hairline = Color(0xffd8dbcc)
val Flow = Color(0xff1f6f78)
val IncomeGreen = Color(0xff3f8f5f)
val SpendRed = Color(0xffc1594a)
val InvestGold = Color(0xffc99a3d)

@Composable
fun RaisedCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(18.dp),
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
fun BrandHeader(title: String, subtitle: String = "Know your flow") {
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

fun categoryColor(name: String): Color = when (name.lowercase()) {
    "home", "house" -> Color(0xff5e7fa3)
    "groceries" -> Color(0xff7c8f3f)
    "food" -> IncomeGreen
    "fun" -> SpendRed
    "gym" -> Color(0xff7b5aa6)
    "self" -> Color(0xff2e8f8a)
    "investment", "investments" -> InvestGold
    else -> Color(0xff8a8a7e)
}
