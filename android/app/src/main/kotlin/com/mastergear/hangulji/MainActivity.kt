package com.mastergear.hangulji

import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.view.inputmethod.InputMethodManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                var testInput by remember { mutableStateOf("") }
                Column(
                    Modifier.fillMaxSize().padding(20.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Text("한글지 설치", style = MaterialTheme.typography.headlineSmall)
                    Text("1. 키보드 활성화: 설정 → 시스템 → 키보드 → 화면 키보드 관리 → 한글지 켜기")
                    Button(onClick = {
                        startActivity(Intent(Settings.ACTION_INPUT_METHOD_SETTINGS))
                    }) { Text("키보드 설정 열기") }
                    Text("2. 키보드 전환: 아래 버튼 또는 입력 중 🌐 키")
                    Button(onClick = {
                        (getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager)
                            .showInputMethodPicker()
                    }) { Text("키보드 선택창 열기") }
                    Text("3. 테스트: 토우쿄우(xhdnzydn) → 변환·스페이스 → 東京")
                    OutlinedTextField(
                        value = testInput, onValueChange = { testInput = it },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("타이핑 테스트") },
                    )
                    Text("입력 규칙: 카=か 가=が (위치 무관) · 받침ㅅ=っ · 받침ㄴ=ん · 장음은 ー 키 또는 철자대로(토우쿄우)")
                }
            }
        }
    }
}
