#include <jni.h>
#include <fbjni/fbjni.h>
#include "NitroClientOnLoad.hpp"

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
  return facebook::jni::initialize(vm, []() {
    margelo::nitro::client::registerAllNatives();
  });
}
