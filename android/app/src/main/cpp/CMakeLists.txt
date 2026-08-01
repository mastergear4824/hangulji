cmake_minimum_required(VERSION 3.22)
project(hangulji_jni C)

set(JNILIBS_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${ANDROID_ABI})

add_library(hangulji-engine SHARED IMPORTED)
# libHanguljiEngine.so(Swift 크로스컴파일 산출물)는 DT_SONAME이 없다(swift build가 Android
# 타깃엔 soname을 안 심음 — 실측, nm/readelf로 확인). IMPORTED_NO_SONAME 없이는 CMake/lld가
# 이 라이브러리의 NEEDED 엔트리에 호스트 빌드머신의 절대경로(IMPORTED_LOCATION 그대로)를
# 박아 넣어 기기에서 "library "/Users/.../jniLibs/..." not found" dlopen 실패가 난다
# (Android NDK CMake 가이드에 문서화된 알려진 함정). NO_SONAME을 켜면 CMake가 대신
# 파일명만(libHanguljiEngine.so) NEEDED로 기록 — 같은 APK lib/<abi>/ 디렉터리에 나란히
# 설치되므로 앱 네이티브 링커 네임스페이스가 정상적으로 찾는다.
set_target_properties(hangulji-engine PROPERTIES
    IMPORTED_LOCATION ${JNILIBS_DIR}/libHanguljiEngine.so
    IMPORTED_NO_SONAME TRUE)

add_library(hangulji_jni SHARED hangulji_jni.c)
target_link_libraries(hangulji_jni hangulji-engine)
