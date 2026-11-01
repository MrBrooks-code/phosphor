#include "AudioIngress.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <mach/mach_time.h>
#include <math.h>
#define CAPACITY 65536
struct AudioIngress {
    StereoFrame frames[CAPACITY];
    _Atomic uint64_t writeIndex, readIndex, dropped;
    uint64_t sequence;
    double ticksPerFrame;
};
AudioIngress *ingress_create(void) { return calloc(1, sizeof(AudioIngress)); }
void ingress_destroy(AudioIngress *q) { free(q); }
void ingress_set_rate(AudioIngress *q, double rate) {
    mach_timebase_info_data_t base; mach_timebase_info(&base);
    q->ticksPerFrame = 1e9 * base.denom / base.numer / rate;
}
void ingress_push(AudioIngress *q, float l, float r, uint64_t time) {
    uint64_t w = atomic_load_explicit(&q->writeIndex, memory_order_relaxed);
    uint64_t sequence = q->sequence++;
    if (w - atomic_load_explicit(&q->readIndex, memory_order_acquire) == CAPACITY) {
        atomic_fetch_add_explicit(&q->dropped, 1, memory_order_relaxed); return;
    }
    q->frames[w % CAPACITY] = (StereoFrame){isfinite(l) ? l : 0, isfinite(r) ? r : 0, time, sequence};
    atomic_store_explicit(&q->writeIndex, w + 1, memory_order_release);
}
uint32_t ingress_read(AudioIngress *q, StereoFrame *frames, uint32_t count) {
    uint64_t r = atomic_load_explicit(&q->readIndex, memory_order_relaxed);
    uint64_t w = atomic_load_explicit(&q->writeIndex, memory_order_acquire);
    uint32_t n = (uint32_t)((w-r) < count ? (w-r) : count);
    for (uint32_t i=0; i<n; ++i) frames[i] = q->frames[(r+i)%CAPACITY];
    atomic_store_explicit(&q->readIndex, r+n, memory_order_release); return n;
}
uint64_t ingress_dropped(AudioIngress *q) { return atomic_load(&q->dropped); }
// Copy stereo samples only. The callback does not allocate, lock, or analyse audio.
OSStatus ingress_callback(AudioObjectID device, const AudioTimeStamp *now,
    const AudioBufferList *input, const AudioTimeStamp *inputTime,
    AudioBufferList *output, const AudioTimeStamp *outputTime, void *context) {
    AudioIngress *q = context;
    if (!input || !input->mNumberBuffers) return noErr;
    const AudioBuffer *a = &input->mBuffers[0];
    if (!a->mData || !a->mNumberChannels) return noErr;
    uint32_t n = a->mDataByteSize / (sizeof(float) * a->mNumberChannels);
    const float *l = a->mData;
    const float *r = l;
    uint32_t strideR = a->mNumberChannels;
    if (a->mNumberChannels > 1) r++;
    else if (input->mNumberBuffers > 1 && input->mBuffers[1].mData) {
        const AudioBuffer *b = &input->mBuffers[1]; r = b->mData; strideR = b->mNumberChannels;
        uint32_t rn = b->mDataByteSize / (sizeof(float)*strideR); if (rn < n) n = rn;
    }
    uint64_t start = (inputTime->mFlags & kAudioTimeStampHostTimeValid) ? inputTime->mHostTime : mach_absolute_time();
    for (uint32_t i=0; i<n; ++i)
        ingress_push(q, l[i*a->mNumberChannels], r[i*strideR], start + (uint64_t)(i*q->ticksPerFrame));
    return noErr;
}
