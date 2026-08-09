#ifndef MGBA_NATIVE_BRIDGE_H
#define MGBA_NATIVE_BRIDGE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct MGBANativeCore MGBANativeCore;

MGBANativeCore* MGBANativeCoreCreate(
    const char* romPath,
    const char* savePath,
    char* errorBuffer,
    size_t errorBufferSize
);

void MGBANativeCoreDestroy(MGBANativeCore* nativeCore);
void MGBANativeCoreRunFrame(MGBANativeCore* nativeCore);
void MGBANativeCoreSetKeys(MGBANativeCore* nativeCore, uint32_t keys);

unsigned MGBANativeCoreWidth(const MGBANativeCore* nativeCore);
unsigned MGBANativeCoreHeight(const MGBANativeCore* nativeCore);
size_t MGBANativeCoreStride(const MGBANativeCore* nativeCore);
double MGBANativeCoreFrameRate(const MGBANativeCore* nativeCore);
unsigned MGBANativeCoreAudioSampleRate(const MGBANativeCore* nativeCore);
size_t MGBANativeCoreReadAudio(
    MGBANativeCore* nativeCore,
    int16_t* interleavedStereo,
    size_t capacityFrames
);
bool MGBANativeCoreSaveState(MGBANativeCore* nativeCore, const char* statePath);
bool MGBANativeCoreLoadState(MGBANativeCore* nativeCore, const char* statePath);
const uint32_t* MGBANativeCorePixels(const MGBANativeCore* nativeCore);
const char* MGBANativeCoreGameTitle(const MGBANativeCore* nativeCore);

#ifdef __cplusplus
}
#endif

#endif
