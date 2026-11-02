#include "AudioRing.h"
#include <stdatomic.h>
#include <stdlib.h>
struct SayRing { float *samples; size_t capacity; unsigned channels; int interleaved; int selectedChannel;
 _Atomic size_t read; _Atomic size_t write; _Atomic int overflow; _Atomic size_t maxFrames; _Atomic size_t maxDeclared; };
SayRing *say_ring_create(size_t capacity, unsigned channels, int interleaved) {
 SayRing *r=calloc(1,sizeof(SayRing)); if(!r) return NULL;
 r->samples=calloc(capacity,sizeof(float)); if(!r->samples){free(r);return NULL;}
 r->capacity=capacity; r->channels=channels; r->interleaved=interleaved; r->selectedChannel=-1; return r;
}
SayRing *say_ring_create_channel(size_t capacity,unsigned channels,int interleaved,unsigned selectedChannel){
 if(selectedChannel>=channels)return NULL;
 SayRing *r=say_ring_create(capacity,channels,interleaved);
 if(r)r->selectedChannel=(int)selectedChannel;
 return r;
}
void say_ring_destroy(SayRing *r){if(r){free(r->samples);free(r);}}
int say_ring_overflow(SayRing *r){return atomic_load(&r->overflow);}
void say_ring_discard(SayRing *r){
 size_t wr=atomic_load_explicit(&r->write,memory_order_acquire);
 atomic_store_explicit(&r->read,wr,memory_order_release);
 atomic_store(&r->overflow,0);
}
size_t say_ring_read(SayRing *r,float *dst,size_t cap){
 size_t rd=atomic_load_explicit(&r->read,memory_order_relaxed);
 size_t wr=atomic_load_explicit(&r->write,memory_order_acquire);
 size_t n=wr-rd; if(n>cap)n=cap;
 for(size_t i=0;i<n;i++)dst[i]=r->samples[(rd+i)%r->capacity];
 atomic_store_explicit(&r->read,rd+n,memory_order_release); return n;
}
size_t say_ring_max_callback_frames(SayRing *r){return atomic_load(&r->maxFrames);}
size_t say_ring_max_declared_frames(SayRing *r){return atomic_load(&r->maxDeclared);}
void say_ring_write_frames(SayRing *r,const AudioBufferList *in,size_t limit){
 if(!r||!in||!in->mNumberBuffers)return;
 unsigned ch=r->channels; if(!ch)return;
 unsigned needed=r->interleaved?1:ch;
 if(in->mNumberBuffers<needed)return;
 unsigned offset=in->mNumberBuffers-needed;
 size_t n=in->mBuffers[offset].mDataByteSize/sizeof(float)/(r->interleaved?ch:1);
 if(n>atomic_load(&r->maxDeclared))atomic_store(&r->maxDeclared,n);
 if(limit<n)n=limit;
 if(n>atomic_load(&r->maxFrames))atomic_store(&r->maxFrames,n);
 size_t wr=atomic_load_explicit(&r->write,memory_order_relaxed);
 size_t rd=atomic_load_explicit(&r->read,memory_order_acquire);
 if(n>r->capacity-(wr-rd)){atomic_store(&r->overflow,1);return;}
 for(size_t i=0;i<n;i++){
  float v=0;
  for(unsigned c=0;c<ch;c++){
   if(r->selectedChannel>=0 && c!=(unsigned)r->selectedChannel)continue;
   unsigned b=offset+(r->interleaved?0:c);
   if(b>=in->mNumberBuffers||!in->mBuffers[b].mData)continue;
   size_t k=r->interleaved?i*ch+c:i;
   if((k+1)*sizeof(float)<=in->mBuffers[b].mDataByteSize)v+=((float*)in->mBuffers[b].mData)[k];
  }
  r->samples[(wr+i)%r->capacity]=r->selectedChannel>=0?v:v/ch;
 }
 atomic_store_explicit(&r->write,wr+n,memory_order_release);return;
}

OSStatus say_audio_callback(AudioObjectID device,const AudioTimeStamp *now,
 const AudioBufferList *in,const AudioTimeStamp *it,AudioBufferList *out,const AudioTimeStamp *ot,void *ctx){
 say_ring_write_frames(ctx,in,SIZE_MAX);return noErr;
}
