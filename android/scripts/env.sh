# 모든 android 스크립트와 수동 gradle/adb 호출 전에 source 할 것.
# (jenv 기본 java가 11이라 JAVA_HOME 명시가 필수)
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export JAVA_HOME="${JAVA_HOME:-$(/usr/libexec/java_home -v 17 2>/dev/null \
  || /usr/libexec/java_home -v 21 2>/dev/null)}"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
