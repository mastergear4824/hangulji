// JNI ↔ libHanguljiEngine.so C ABI 글루.
// 반환 문자열은 jbyteArray(UTF-8 원본 바이트)로 넘긴다 — NewStringUTF는 modified UTF-8이라
// 보충면(4바이트) 한자 후보에서 깨질 수 있다. 디코딩은 Kotlin 쪽 String(bytes, UTF_8).
#include <jni.h>
#include <stdint.h>
#include <string.h>

extern void *hangulji_converter_init(const char *dictionary_path);
extern char *hangulji_converter_convert(void *converter, const char *reading,
                                        int32_t max_candidates);
extern void hangulji_string_free(char *str);
extern void hangulji_converter_free(void *converter);

JNIEXPORT jlong JNICALL
Java_com_mastergear_hangulji_engine_KanjiConverterNative_nativeInit(
    JNIEnv *env, jclass clazz, jstring dictionary_path) {
    const char *path = (*env)->GetStringUTFChars(env, dictionary_path, NULL);
    if (path == NULL) return 0;
    void *handle = hangulji_converter_init(path);   /* 경로는 ASCII — modified UTF-8 무해 */
    (*env)->ReleaseStringUTFChars(env, dictionary_path, path);
    return (jlong)(intptr_t)handle;
}

JNIEXPORT jbyteArray JNICALL
Java_com_mastergear_hangulji_engine_KanjiConverterNative_nativeConvert(
    JNIEnv *env, jclass clazz, jlong handle, jbyteArray reading_utf8, jint max_candidates) {
    if (handle == 0) return NULL;
    jsize reading_len = (*env)->GetArrayLength(env, reading_utf8);
    char reading[1024];
    if (reading_len <= 0 || reading_len >= (jsize)sizeof(reading)) return NULL;
    (*env)->GetByteArrayRegion(env, reading_utf8, 0, reading_len, (jbyte *)reading);
    reading[reading_len] = '\0';

    char *joined = hangulji_converter_convert((void *)(intptr_t)handle, reading,
                                              (int32_t)max_candidates);
    if (joined == NULL) return NULL;
    size_t len = strlen(joined);
    jbyteArray result = (*env)->NewByteArray(env, (jsize)len);
    if (result != NULL) {
        (*env)->SetByteArrayRegion(env, result, 0, (jsize)len, (const jbyte *)joined);
    }
    hangulji_string_free(joined);
    return result;
}

JNIEXPORT void JNICALL
Java_com_mastergear_hangulji_engine_KanjiConverterNative_nativeFree(
    JNIEnv *env, jclass clazz, jlong handle) {
    if (handle != 0) hangulji_converter_free((void *)(intptr_t)handle);
}
