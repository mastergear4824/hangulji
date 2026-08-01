package com.mastergear.hangulji.keyboard

import android.inputmethodservice.InputMethodService
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import androidx.compose.ui.platform.ComposeView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.savedstate.SavedStateRegistry
import androidx.savedstate.SavedStateRegistryController
import androidx.savedstate.SavedStateRegistryOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import com.mastergear.hangulji.engine.DictionaryInstaller
import com.mastergear.hangulji.engine.KanjiConverter
import kotlin.concurrent.thread

/** InputMethodService + ComposeView 호스팅.
 *  IMS는 LifecycleOwner가 아니므로 직접 소유해야 Compose가 붙는다(FlorisBoard 패턴 —
 *  Apache-2.0이라 구조 인용 가능). setContent 전에 ViewTree 오너 지정이 필수. */
class HanguljiInputMethodService :
    InputMethodService(), LifecycleOwner, SavedStateRegistryOwner, TextOutput {

    private val lifecycleRegistry = LifecycleRegistry(this)
    private val savedStateRegistryController = SavedStateRegistryController.create(this)

    override val lifecycle: Lifecycle get() = lifecycleRegistry
    override val savedStateRegistry: SavedStateRegistry
        get() = savedStateRegistryController.savedStateRegistry

    private lateinit var model: KeyboardModel
    @Volatile private var converter: KanjiConverter? = null

    override fun onCreate() {
        super.onCreate()
        savedStateRegistryController.performRestore(null)
        lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_CREATE)
        lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_START)
        lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_RESUME)

        model = KeyboardModel(CandidateSource { reading, max ->
            converter?.takeIf { it.isAvailable }?.candidateList(reading, max) ?: emptyList()
        })
        model.output = this

        // 사전 복사(최초 ~35MB) + 컨버터 로드는 무거움 — 백그라운드 1회.
        // 로드 완료 전 변환 시도는 빈 목록 → 가나 그대로 확정(그레이스풀 디그레이드)
        thread(name = "hangulji-engine-init") {
            val dictionary = DictionaryInstaller.ensureInstalled(this)
            converter = KanjiConverter(dictionary.absolutePath)
        }
    }

    override fun onCreateInputView(): View {
        val view = ComposeView(this)
        window?.window?.decorView?.let {
            it.setViewTreeLifecycleOwner(this)
            it.setViewTreeSavedStateRegistryOwner(this)
        }
        view.setViewTreeLifecycleOwner(this)
        view.setViewTreeSavedStateRegistryOwner(this)
        view.setContent {
            KeyboardScreen(model = model, onSwitchKeyboard = ::showImePicker)
        }
        return view
    }

    override fun onStartInput(attribute: EditorInfo?, restarting: Boolean) {
        super.onStartInput(attribute, restarting)
        if (!restarting) model.discardComposition()   // 새 필드 — 이전 조합 상태를 끌고 가지 않음
    }

    override fun onFinishInputView(finishingInput: Boolean) {
        model.commitAll()   // 포커스 이탈 — 조합 영역을 그대로 확정 (IC가 아직 유효한 시점)
        super.onFinishInputView(finishingInput)
    }

    override fun onDestroy() {
        lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_DESTROY)
        converter?.close()
        super.onDestroy()
    }

    private fun showImePicker() {
        (getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager).showInputMethodPicker()
    }

    // MARK: TextOutput — InputConnection 대응 (iOS 프록시보다 단순: 동기적 조합 영역 API)
    override fun setMarkedText(s: String) { currentInputConnection?.setComposingText(s, 1) }
    override fun commitText(s: String) { currentInputConnection?.commitText(s, 1) }
    override fun clearMarkedText() {
        currentInputConnection?.apply {
            setComposingText("", 1)   // 조합 영역 삭제
            finishComposingText()
        }
    }
    override fun insertText(s: String) { currentInputConnection?.commitText(s, 1) }
    override fun deleteBackward() {
        // deleteSurroundingText(1,0)는 서로게이트 쌍을 반쪽만 지울 수 있어 KEYCODE_DEL 사용
        sendDownUpKeyEvents(KeyEvent.KEYCODE_DEL)
    }
}
