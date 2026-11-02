#pragma once
#include <CoreAudio/CoreAudio.h>
#include <stdint.h>

typedef struct AudioIngress AudioIngress;
typedef struct { float left; float right; uint64_t hostTime; uint64_t sequence; } StereoFrame;
// This queue has one audio writer and one analysis reader.
AudioIngress * _Nullable ingress_create(void);
void ingress_destroy(AudioIngress * _Nonnull queue);
void ingress_push(AudioIngress * _Nonnull queue, float left, float right, uint64_t hostTime);
uint32_t ingress_read(AudioIngress * _Nonnull queue, StereoFrame * _Nonnull frames, uint32_t capacity);
uint64_t ingress_dropped(AudioIngress * _Nonnull queue);
void ingress_set_rate(AudioIngress * _Nonnull queue, double rate);
OSStatus ingress_callback(AudioObjectID device, const AudioTimeStamp * _Nonnull now,
    const AudioBufferList * _Nonnull input, const AudioTimeStamp * _Nonnull inputTime,
    AudioBufferList * _Nonnull output, const AudioTimeStamp * _Nonnull outputTime, void * _Nullable context);
