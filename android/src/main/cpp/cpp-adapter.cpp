#include <jni.h>
#include "NitroClientOnLoad.hpp"

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
  return margelo::nitro::client::initialize(vm);
}
