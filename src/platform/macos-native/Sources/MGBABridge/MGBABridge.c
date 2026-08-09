#include "MGBABridge.h"

#include <mgba/core/core.h>
#include <mgba/core/config.h>
#include <mgba/core/interface.h>
#include <mgba/core/serialize.h>
#include <mgba-util/audio-buffer.h>
#include <mgba-util/image.h>
#include <mgba-util/vfs.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct MGBANativeCore {
    struct mCore* core;
    mColor* pixels;
    unsigned width;
    unsigned height;
    unsigned bufferWidth;
    unsigned bufferHeight;
    size_t stride;
    char title[17];
    bool configInitialized;
};

static void _writeError(char* buffer, size_t bufferSize, const char* message) {
    if (!buffer || !bufferSize) {
        return;
    }
    snprintf(buffer, bufferSize, "%s", message);
}

static void _destroyPartial(MGBANativeCore* nativeCore) {
    if (!nativeCore) {
        return;
    }
    free(nativeCore->pixels);
    if (nativeCore->core) {
        if (nativeCore->configInitialized) {
            mCoreConfigDeinit(&nativeCore->core->config);
        }
        nativeCore->core->deinit(nativeCore->core);
    }
    free(nativeCore);
}

MGBANativeCore* MGBANativeCoreCreate(
    const char* romPath,
    const char* savePath,
    char* errorBuffer,
    size_t errorBufferSize
) {
    if (!romPath || !romPath[0]) {
        _writeError(errorBuffer, errorBufferSize, "No ROM path was provided.");
        return NULL;
    }

    MGBANativeCore* nativeCore = calloc(1, sizeof(*nativeCore));
    if (!nativeCore) {
        _writeError(errorBuffer, errorBufferSize, "Could not allocate the emulator core.");
        return NULL;
    }

    nativeCore->core = mCoreFind(romPath);
    if (!nativeCore->core) {
        _writeError(errorBuffer, errorBufferSize, "The selected file is not a supported Game Boy ROM.");
        _destroyPartial(nativeCore);
        return NULL;
    }

    if (!nativeCore->core->init(nativeCore->core)) {
        _writeError(errorBuffer, errorBufferSize, "The emulator core could not be initialized.");
        _destroyPartial(nativeCore);
        return NULL;
    }

    mCoreInitConfig(nativeCore->core, "macos-native");
    nativeCore->configInitialized = true;
    mCoreLoadConfig(nativeCore->core);
    // The native frontend controls mute and volume after Core Audio output.
    // mCore options are otherwise zero-initialized here, which sets the
    // emulated master mixer to zero and produces correctly sized silence.
    nativeCore->core->opts.volume = 0x100;
    nativeCore->core->opts.mute = false;
    nativeCore->core->loadConfig(nativeCore->core, &nativeCore->core->config);
    nativeCore->core->setAudioBufferSize(nativeCore->core, 4096);

    nativeCore->core->baseVideoSize(
        nativeCore->core,
        &nativeCore->bufferWidth,
        &nativeCore->bufferHeight
    );
    nativeCore->width = nativeCore->bufferWidth;
    nativeCore->height = nativeCore->bufferHeight;
    nativeCore->stride = nativeCore->bufferWidth;
    nativeCore->pixels = calloc(
        nativeCore->stride * nativeCore->bufferHeight,
        sizeof(*nativeCore->pixels)
    );
    if (!nativeCore->pixels) {
        _writeError(errorBuffer, errorBufferSize, "Could not allocate the video buffer.");
        _destroyPartial(nativeCore);
        return NULL;
    }
    nativeCore->core->setVideoBuffer(
        nativeCore->core,
        nativeCore->pixels,
        nativeCore->stride
    );

    if (!mCoreLoadFile(nativeCore->core, romPath)) {
        _writeError(errorBuffer, errorBufferSize, "The ROM could not be loaded.");
        _destroyPartial(nativeCore);
        return NULL;
    }

    if (savePath && savePath[0] && !mCoreLoadSaveFile(nativeCore->core, savePath, false)) {
        _writeError(errorBuffer, errorBufferSize, "The battery save file could not be opened.");
        _destroyPartial(nativeCore);
        return NULL;
    }

    nativeCore->core->reset(nativeCore->core);
    nativeCore->core->currentVideoSize(
        nativeCore->core,
        &nativeCore->width,
        &nativeCore->height
    );

    struct mGameInfo info = {0};
    nativeCore->core->getGameInfo(nativeCore->core, &info);
    snprintf(nativeCore->title, sizeof(nativeCore->title), "%.16s", info.title);
    return nativeCore;
}

void MGBANativeCoreDestroy(MGBANativeCore* nativeCore) {
    _destroyPartial(nativeCore);
}

void MGBANativeCoreRunFrame(MGBANativeCore* nativeCore) {
    if (nativeCore && nativeCore->core) {
        nativeCore->core->runFrame(nativeCore->core);
        nativeCore->core->currentVideoSize(
            nativeCore->core,
            &nativeCore->width,
            &nativeCore->height
        );
    }
}

void MGBANativeCoreSetKeys(MGBANativeCore* nativeCore, uint32_t keys) {
    if (nativeCore && nativeCore->core) {
        nativeCore->core->setKeys(nativeCore->core, keys);
    }
}

unsigned MGBANativeCoreWidth(const MGBANativeCore* nativeCore) {
    return nativeCore ? nativeCore->width : 0;
}

unsigned MGBANativeCoreHeight(const MGBANativeCore* nativeCore) {
    return nativeCore ? nativeCore->height : 0;
}

size_t MGBANativeCoreStride(const MGBANativeCore* nativeCore) {
    return nativeCore ? nativeCore->stride : 0;
}

double MGBANativeCoreFrameRate(const MGBANativeCore* nativeCore) {
    if (!nativeCore || !nativeCore->core) {
        return 60.0;
    }
    int32_t frameCycles = nativeCore->core->frameCycles(nativeCore->core);
    int32_t frequency = nativeCore->core->frequency(nativeCore->core);
    if (frameCycles <= 0 || frequency <= 0) {
        return 60.0;
    }
    return (double) frequency / (double) frameCycles;
}

unsigned MGBANativeCoreAudioSampleRate(const MGBANativeCore* nativeCore) {
    if (!nativeCore || !nativeCore->core) {
        return 0;
    }
    return nativeCore->core->audioSampleRate(nativeCore->core);
}

size_t MGBANativeCoreReadAudio(
    MGBANativeCore* nativeCore,
    int16_t* interleavedStereo,
    size_t capacityFrames
) {
    if (!nativeCore || !nativeCore->core || !interleavedStereo || !capacityFrames) {
        return 0;
    }
    struct mAudioBuffer* audio = nativeCore->core->getAudioBuffer(nativeCore->core);
    if (!audio) {
        return 0;
    }
    size_t available = mAudioBufferAvailable(audio);
    if (available > capacityFrames) {
        available = capacityFrames;
    }
    return mAudioBufferRead(audio, interleavedStereo, available);
}

bool MGBANativeCoreSaveState(MGBANativeCore* nativeCore, const char* statePath) {
    if (!nativeCore || !nativeCore->core || !statePath || !statePath[0]) {
        return false;
    }
    struct VFile* vf = VFileOpen(statePath, O_CREAT | O_TRUNC | O_RDWR);
    if (!vf) {
        return false;
    }
    bool success = mCoreSaveStateNamed(
        nativeCore->core,
        vf,
        SAVESTATE_SAVEDATA | SAVESTATE_RTC | SAVESTATE_METADATA
    );
    vf->close(vf);
    return success;
}

bool MGBANativeCoreLoadState(MGBANativeCore* nativeCore, const char* statePath) {
    if (!nativeCore || !nativeCore->core || !statePath || !statePath[0]) {
        return false;
    }
    struct VFile* vf = VFileOpen(statePath, O_RDONLY);
    if (!vf) {
        return false;
    }
    bool success = mCoreLoadStateNamed(
        nativeCore->core,
        vf,
        SAVESTATE_SAVEDATA | SAVESTATE_RTC
    );
    vf->close(vf);
    if (success) {
        nativeCore->core->currentVideoSize(
            nativeCore->core,
            &nativeCore->width,
            &nativeCore->height
        );
        struct mAudioBuffer* audio = nativeCore->core->getAudioBuffer(nativeCore->core);
        if (audio) {
            mAudioBufferClear(audio);
        }
    }
    return success;
}

const uint32_t* MGBANativeCorePixels(const MGBANativeCore* nativeCore) {
    return nativeCore ? nativeCore->pixels : NULL;
}

const char* MGBANativeCoreGameTitle(const MGBANativeCore* nativeCore) {
    return nativeCore ? nativeCore->title : "";
}
