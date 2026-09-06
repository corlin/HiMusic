#!/bin/sh
set -eu
TASK_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export GRADLE_USER_HOME="$TASK_ROOT/.tooling/gradle"
if [ -d "$TASK_ROOT/.tooling/android-sdk" ]; then
  export ANDROID_HOME="$TASK_ROOT/.tooling/android-sdk"
fi
if [ -d '/Applications/Android Studio.app/Contents/jbr/Contents/Home' ]; then
  export JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home'
fi
exec "$TASK_ROOT/.tooling/flutter/bin/flutter" "$@"
