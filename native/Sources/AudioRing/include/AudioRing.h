#pragma once
#include <CoreAudio/CoreAudio.h>
#include <stddef.h>
typedef struct SayRing SayRing;
SayRing *say_ring_create(size_t capacity, unsigned channels, int interleaved);
SayRing *say_ring_create_channel(size_t capacity, unsigned channels, int interleaved, unsigned selectedChannel);
void say_ring_destroy(SayRing *ring);
size_t say_ring_read(SayRing *ring, float *destination, size_t capacity);
int say_ring_overflow(SayRing *ring);
void say_ring_discard(SayRing *ring);
void say_ring_write_frames(SayRing *ring, const AudioBufferList *input, size_t frames);
size_t say_ring_max_callback_frames(SayRing *ring);
size_t say_ring_max_declared_frames(SayRing *ring);
OSStatus say_audio_callback(AudioObjectID device, const AudioTimeStamp * _Nonnull now,
 const AudioBufferList * _Nonnull input, const AudioTimeStamp * _Nonnull inputTime,
 AudioBufferList * _Nonnull output, const AudioTimeStamp * _Nonnull outputTime, void * _Nullable context);
