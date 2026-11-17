// SPDX-License-Identifier: AGPL-3.0-only
// Independently authored bounded owner-stream adapter. Codec source is unchanged
// Xiph BSD3 source in vendor/; this file contains no original game implementation.
#include "zgtasa_native_audio.h"
#include <vorbis/vorbisfile.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <limits.h>
#include <math.h>
#include <setjmp.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#ifndef ZGTA_RADIO_SOURCE_STAMP
#define ZGTA_RADIO_SOURCE_STAMP "unbuilt"
#endif
#define MAX_PACKET (1024u*1024u)
#define MAX_PAGE (27u+255u+255u*255u)
#define MAX_FRAMES (86400ull*32000ull)
#define MAX_HANDLES 8u
#define MAX_STACK_SINGLE (256u*1024u)
#define MAX_STACK_OPERATION (2u*1024u*1024u)
static const uint8_t key[16]={234,58,196,161,154,168,20,243,72,176,215,35,157,232,255,241};
typedef union allocation allocation;
union allocation {
 struct { allocation *before,*after; struct zgta_radio_decoder *owner; size_t bytes; } a;
 max_align_t alignment;
};
struct zgta_radio_decoder {
 int fd, opened, prepared, poisoned, trapping;
 uint64_t base, length, cursor, operation_bytes, stack_bytes, operation_allocations;
 struct stat source;
 atomic_bool cancelled;
 zgta_radio_status failure;
 jmp_buf jump;
 allocation *allocations;
 zgta_radio_stats stats;
 zgta_radio_info info;
 OggVorbis_File vorbis;
};
static atomic_uint handles=0;
static _Thread_local zgta_radio_decoder *active;
static uint32_t u32(const uint8_t*p){return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static uint64_t u64(const uint8_t*p){return u32(p)|(uint64_t)u32(p+4)<<32;}
static zgta_radio_status cancelled(const zgta_radio_decoder*d){return atomic_load_explicit(&d->cancelled,memory_order_relaxed)?ZGTA_RADIO_CANCELLED:ZGTA_RADIO_OK;}
static int same_file(const struct stat*a,const struct stat*b){
 if(a->st_dev!=b->st_dev||a->st_ino!=b->st_ino||a->st_size!=b->st_size||!S_ISREG(b->st_mode))return 0;
#ifdef __APPLE__
 return a->st_mtimespec.tv_sec==b->st_mtimespec.tv_sec&&a->st_mtimespec.tv_nsec==b->st_mtimespec.tv_nsec&&a->st_ctimespec.tv_sec==b->st_ctimespec.tv_sec&&a->st_ctimespec.tv_nsec==b->st_ctimespec.tv_nsec;
#else
 return a->st_mtim.tv_sec==b->st_mtim.tv_sec&&a->st_mtim.tv_nsec==b->st_mtim.tv_nsec&&a->st_ctim.tv_sec==b->st_ctim.tv_nsec&&a->st_ctim.tv_nsec==b->st_ctim.tv_nsec;
#endif
}
static zgta_radio_status source_check(zgta_radio_decoder*d){
 if(cancelled(d))return ZGTA_RADIO_CANCELLED;
 struct stat s;if(fstat(d->fd,&s))return ZGTA_RADIO_IO;
 return same_file(&d->source,&s)?ZGTA_RADIO_OK:ZGTA_RADIO_CHANGED;
}
static void trap(zgta_radio_decoder*d,zgta_radio_status status){
 d->failure=status;
 if(d->trapping)longjmp(d->jump,1);
 abort(); /* Internal misuse only: codec allocators run within a guarded call. */
}
void *zgta_radio_codec_malloc(size_t bytes){
 zgta_radio_decoder*d=active;if(!d)return NULL;
 if(cancelled(d))trap(d,ZGTA_RADIO_CANCELLED);
 if(++d->operation_allocations>50000||bytes>ZGTA_RADIO_MAX_HEAP_BYTES-sizeof(allocation))trap(d,ZGTA_RADIO_LIMIT);
 size_t charged=sizeof(allocation)+(bytes?bytes:1);
 if(d->stats.current_heap_bytes>ZGTA_RADIO_MAX_HEAP_BYTES-charged)trap(d,ZGTA_RADIO_LIMIT);
 allocation*a=malloc(sizeof(*a)+(bytes?bytes:1));if(!a)trap(d,ZGTA_RADIO_MEMORY);
 a->a=(typeof(a->a)){NULL,d->allocations,d,bytes};if(d->allocations)d->allocations->a.before=a;d->allocations=a;
 d->stats.current_heap_bytes+=charged;if(d->stats.current_heap_bytes>d->stats.peak_heap_bytes)d->stats.peak_heap_bytes=d->stats.current_heap_bytes;d->stats.allocation_calls++;
 return a+1;
}
void *zgta_radio_codec_calloc(size_t count,size_t bytes){
 if(bytes&&count>SIZE_MAX/bytes)trap(active,ZGTA_RADIO_LIMIT);
 size_t size=count*bytes;void*p=zgta_radio_codec_malloc(size);memset(p,0,size);return p;
}
void zgta_radio_codec_free(void*p){
 if(!p)return;allocation*a=(allocation*)p-1;zgta_radio_decoder*d=a->a.owner;
 if(a->a.before)a->a.before->a.after=a->a.after;else d->allocations=a->a.after;
 if(a->a.after)a->a.after->a.before=a->a.before;
 d->stats.current_heap_bytes-=sizeof(allocation)+(a->a.bytes?a->a.bytes:1);free(a);
}
void *zgta_radio_codec_realloc(void*p,size_t bytes){
 if(!p)return zgta_radio_codec_malloc(bytes);
 allocation*a=(allocation*)p-1;zgta_radio_decoder*d=a->a.owner;
 if(cancelled(d))trap(d,ZGTA_RADIO_CANCELLED);
 if(++d->operation_allocations>50000||active!=d||bytes>ZGTA_RADIO_MAX_HEAP_BYTES-sizeof(allocation))trap(d,ZGTA_RADIO_LIMIT);
 size_t old=sizeof(allocation)+(a->a.bytes?a->a.bytes:1),charged=sizeof(allocation)+(bytes?bytes:1);
 if(d->stats.current_heap_bytes-old>ZGTA_RADIO_MAX_HEAP_BYTES-charged)trap(d,ZGTA_RADIO_LIMIT);
 allocation*b=realloc(a,charged);if(!b)trap(d,ZGTA_RADIO_MEMORY);
 if(b->a.before)b->a.before->a.after=b;else d->allocations=b;if(b->a.after)b->a.after->a.before=b;b->a.bytes=bytes;
 d->stats.current_heap_bytes=d->stats.current_heap_bytes-old+charged;if(d->stats.current_heap_bytes>d->stats.peak_heap_bytes)d->stats.peak_heap_bytes=d->stats.current_heap_bytes;d->stats.allocation_calls++;
 return b+1;
}
size_t zgta_radio_codec_stack(size_t bytes){
 zgta_radio_decoder*d=active;if(!d)return 0;
 if(bytes>MAX_STACK_SINGLE||d->stack_bytes>MAX_STACK_OPERATION-bytes)trap(d,ZGTA_RADIO_LIMIT);
 d->stack_bytes+=bytes;return bytes;
}
static void release_allocations(zgta_radio_decoder*d){while(d->allocations)zgta_radio_codec_free(d->allocations+1);}
static zgta_radio_status read_bytes(zgta_radio_decoder*d,uint64_t at,uint8_t*out,size_t count){
 zgta_radio_status status=source_check(d);if(status)return status;
 if(count>65536||at>d->length||count>d->length-at)return ZGTA_RADIO_RANGE;
 uint64_t budget=3*d->length+2*1024*1024;
 if(d->operation_bytes>budget-count)return ZGTA_RADIO_LIMIT;
 size_t done=0;while(done<count){
  if(cancelled(d))return ZGTA_RADIO_CANCELLED;
  ssize_t n=pread(d->fd,out+done,count-done,(off_t)(d->base+at+done));
  if(n<0&&errno==EINTR)continue;
  if(n<=0)return n<0?ZGTA_RADIO_IO:ZGTA_RADIO_CHANGED;
  done+=(size_t)n;
 }
 for(size_t n=0;n<count;n++)out[n]^=key[(d->base+at+n)&15];
 d->operation_bytes+=count;d->stats.bytes_read+=count;d->stats.read_calls++;if(count>d->stats.maximum_read_bytes)d->stats.maximum_read_bytes=count;
 return source_check(d);
}
static uint32_t crc_page(const uint8_t*p,size_t size){
 uint32_t crc=0;for(size_t i=0;i<size;i++){uint8_t b=(i>=22&&i<26)?0:p[i];crc^=(uint32_t)b<<24;for(int bit=0;bit<8;bit++)crc=(crc<<1)^((crc&0x80000000)?0x04c11db7:0);}return crc;
}
static int comment_valid(const uint8_t*p,size_t bytes){
 if(bytes<12)return 0;size_t cursor=7;uint32_t vendor=u32(p+cursor);cursor+=4;
 if(vendor>65536||vendor>bytes-cursor)return 0;cursor+=vendor;if(bytes-cursor<4)return 0;
 uint32_t count=u32(p+cursor);cursor+=4;if(count>4096)return 0;
 for(uint32_t i=0;i<count;i++){if(bytes-cursor<4)return 0;uint32_t n=u32(p+cursor);cursor+=4;if(n>65536||n>bytes-cursor)return 0;cursor+=n;}
 return cursor<bytes&&p[cursor]==1&&cursor+1==bytes;
}
static zgta_radio_status preflight(zgta_radio_decoder*d){
 uint8_t*page=malloc(MAX_PAGE),*packet=malloc(MAX_PACKET);if(!page||!packet){free(page);free(packet);return ZGTA_RADIO_MEMORY;}
 uint64_t at=0,granule=0;uint32_t serial=0,pages=0,packets=0;size_t pending=0;int ended=0;zgta_radio_status status=ZGTA_RADIO_OGG;
 while(at<d->length){
  if(pages>=100000){status=ZGTA_RADIO_LIMIT;goto done;}
  if(d->length-at<27)goto done;
  status=read_bytes(d,at,page,27);if(status)goto done;status=ZGTA_RADIO_OGG;
  if(memcmp(page,"OggS",4)||page[4]!=0||(page[5]&~7)||u32(page+18)!=pages)goto done;
  if(!pages){if(page[5]!=2){goto done;}serial=u32(page+14);}else if(u32(page+14)!=serial||(page[5]&2))goto done;
  if(((page[5]&1)!=0)!=(pending!=0))goto done;
  uint8_t segments=page[26];if(!segments)goto done;
  if(d->length-at<27u+segments)goto done;
  status=read_bytes(d,at+27,page+27,segments);if(status)goto done;status=ZGTA_RADIO_OGG;
  size_t body=0;for(unsigned i=0;i<segments;i++)body+=page[27+i];size_t bytes=27u+segments+body;
  if(bytes>d->length-at)goto done;
  status=read_bytes(d,at+27+segments,page+27+segments,body);if(status)goto done;status=ZGTA_RADIO_OGG;
  if(crc_page(page,bytes)!=u32(page+22))goto done;
  if(!pages&&(segments!=1||body!=30||page[27]!=30))goto done;
  size_t cursor=27u+segments;
  for(unsigned i=0;i<segments;i++){
   unsigned n=page[27+i];if(pending>MAX_PACKET-n){status=ZGTA_RADIO_LIMIT;goto done;}
   if(packets<3)memcpy(packet+pending,page+cursor,n);pending+=n;cursor+=n;
   if(n<255){
    if(packets<3){
     const uint8_t type=(uint8_t)(1+packets*2);
     if(pending<7||packet[0]!=type||memcmp(packet+1,"vorbis",6))goto done;
     if(packets==0){
      if(pending!=30||u32(packet+7)!=0||(packet[11]!=1&&packet[11]!=2)||u32(packet+12)!=32000||packet[29]!=1){status=ZGTA_RADIO_FORMAT;goto done;}
      unsigned lo=packet[28]&15,hi=packet[28]>>4;if(lo<6||hi>13||hi<lo){status=ZGTA_RADIO_FORMAT;goto done;}
      d->info.source_channels=packet[11];
     }else if(packets==1&&!comment_valid(packet,pending))goto done;
    }
    if(packets>=200000){status=ZGTA_RADIO_LIMIT;goto done;}packets++;pending=0;
   }
  }
  uint64_t g=u64(page+6);if(g!=UINT64_MAX){if(g<granule||g>MAX_FRAMES)goto done;granule=g;}
  pages++;at+=bytes;
  if(page[5]&4){if(at!=d->length||pending||packets<4||g==UINT64_MAX||g==0)goto done;ended=1;break;}
 }
 if(ended){d->info.frames=granule;status=ZGTA_RADIO_OK;}
 done:free(page);free(packet);return status;
}
static size_t cb_read(void*buffer,size_t size,size_t count,void*opaque){
 zgta_radio_decoder*d=opaque;if(!size||!count)return 0;
 if(size>65536||count>SIZE_MAX/size){d->failure=ZGTA_RADIO_LIMIT;errno=EOVERFLOW;return 0;}
 size_t items=count;if(items>65536/size)items=65536/size;
 uint64_t available=d->length-d->cursor;if(items>available/size)items=(size_t)(available/size);
 size_t bytes=items*size;if(!bytes)return 0;
 zgta_radio_status s=read_bytes(d,d->cursor,buffer,bytes);if(s){d->failure=s;errno=EIO;return 0;}
 d->cursor+=bytes;return items;
}
static int cb_seek(void*opaque,ogg_int64_t offset,int whence){
 zgta_radio_decoder*d=opaque;uint64_t base;
 if(cancelled(d)){d->failure=ZGTA_RADIO_CANCELLED;errno=ECANCELED;return -1;}
 if(whence==SEEK_SET)base=0;else if(whence==SEEK_CUR)base=d->cursor;else if(whence==SEEK_END)base=d->length;else return -1;
 uint64_t next;if(offset<0){uint64_t magnitude=(uint64_t)(-(offset+1))+1;if(magnitude>base)return -1;next=base-magnitude;}else{if((uint64_t)offset>d->length-base)return -1;next=base+(uint64_t)offset;}
 if(next>d->length)return -1;d->cursor=next;return 0;
}
static long cb_tell(void*opaque){zgta_radio_decoder*d=opaque;return (long)d->cursor;}
static void begin(zgta_radio_decoder*d){d->operation_bytes=0;d->stack_bytes=0;d->operation_allocations=0;d->failure=ZGTA_RADIO_OK;d->trapping=1;active=d;}
static void finish(zgta_radio_decoder*d){d->trapping=0;active=NULL;}
static zgta_radio_status abort_codec(zgta_radio_decoder*d,zgta_radio_status status){
 finish(d);d->poisoned=1;d->prepared=0;d->opened=0;release_allocations(d);memset(&d->vorbis,0,sizeof(d->vorbis));return status;
}
zgta_radio_status zgta_radio_create(int fd,uint64_t offset,uint64_t bytes,zgta_radio_decoder**out){
 if(!out)return ZGTA_RADIO_ARGUMENT;*out=NULL;
 if(fd<0)return ZGTA_RADIO_ARGUMENT;
 if(bytes<=ZGTA_RADIO_HEADER_BYTES||bytes-ZGTA_RADIO_HEADER_BYTES>ZGTA_RADIO_MAX_PAYLOAD_BYTES||offset>INT64_MAX||bytes>(uint64_t)INT64_MAX-offset)return ZGTA_RADIO_RANGE;
 struct stat stat;if(fstat(fd,&stat)||!S_ISREG(stat.st_mode)||stat.st_size<0)return ZGTA_RADIO_SOURCE;
 int flags=fcntl(fd,F_GETFL);if(flags<0||(flags&O_ACCMODE)==O_WRONLY)return ZGTA_RADIO_SOURCE;
 if(offset+bytes>(uint64_t)stat.st_size)return ZGTA_RADIO_RANGE;
 unsigned before=atomic_fetch_add(&handles,1);if(before>=MAX_HANDLES){atomic_fetch_sub(&handles,1);return ZGTA_RADIO_LIMIT;}
 zgta_radio_decoder*d=calloc(1,sizeof(*d));if(!d){atomic_fetch_sub(&handles,1);return ZGTA_RADIO_MEMORY;}
 d->fd=fcntl(fd,F_DUPFD_CLOEXEC,0);if(d->fd<0){free(d);atomic_fetch_sub(&handles,1);return ZGTA_RADIO_IO;}
 d->base=offset+ZGTA_RADIO_HEADER_BYTES;d->length=bytes-ZGTA_RADIO_HEADER_BYTES;d->source=stat;atomic_init(&d->cancelled,false);
 d->info=(zgta_radio_info){ZGTA_RADIO_ABI_VERSION,32000,0,2,0,d->length};*out=d;return ZGTA_RADIO_OK;
}
zgta_radio_status zgta_radio_prepare(zgta_radio_decoder*d,zgta_radio_info*out){
 if(!d||!out)return ZGTA_RADIO_ARGUMENT;memset(out,0,sizeof(*out));if(cancelled(d))return ZGTA_RADIO_CANCELLED;if(d->poisoned||d->prepared)return ZGTA_RADIO_STATE;
 d->operation_bytes=0;zgta_radio_status status=preflight(d);if(status)return status;
 begin(d);if(setjmp(d->jump)){status=d->failure;return abort_codec(d,status);}
 // Seed the documented initial-data path. The release's empty ogg_sync_state
 // otherwise computes NULL+0 before testing its byte count (UBSan). Supplying
 // actual bounded prefix bytes initializes the upstream buffer without a
 // vendor patch, sanitizer exemption, or read beyond this record.
 uint8_t initial[2048];size_t initial_bytes=d->length<sizeof(initial)?(size_t)d->length:sizeof(initial);
 status=read_bytes(d,0,initial,initial_bytes);if(status)return abort_codec(d,status);d->cursor=initial_bytes;
 ov_callbacks callbacks={cb_read,cb_seek,NULL,cb_tell};int opened=ov_open_callbacks(d,&d->vorbis,(char*)initial,(long)initial_bytes,callbacks);
 if(opened<0){status=d->failure?d->failure:ZGTA_RADIO_CODEC;return abort_codec(d,status);}d->opened=1;
 vorbis_info*info=ov_info(&d->vorbis,-1);ogg_int64_t frames=ov_pcm_total(&d->vorbis,-1);
 if(d->failure||!info||ov_streams(&d->vorbis)!=1||!ov_seekable(&d->vorbis)||info->rate!=32000||info->channels!=(int)d->info.source_channels||frames!=(ogg_int64_t)d->info.frames){status=d->failure?d->failure:ZGTA_RADIO_FORMAT;return abort_codec(d,status);}
 finish(d);d->prepared=1;*out=d->info;return ZGTA_RADIO_OK;
}
zgta_radio_status zgta_radio_read(zgta_radio_decoder*d,uint64_t first,uint32_t frames,float*out,size_t capacity,uint32_t*written){
 if(!written)return ZGTA_RADIO_ARGUMENT;*written=0;
 if(!d||!out||!frames||frames>ZGTA_RADIO_MAX_WINDOW_FRAMES||capacity<(size_t)frames*2)return ZGTA_RADIO_ARGUMENT;
 if(cancelled(d))return ZGTA_RADIO_CANCELLED;if(!d->prepared||d->poisoned)return ZGTA_RADIO_STATE;if(first>d->info.frames)return ZGTA_RADIO_RANGE;
 zgta_radio_status status=source_check(d);if(status)return status;
 begin(d);if(setjmp(d->jump)){status=d->failure;return abort_codec(d,status);}
 if(ov_pcm_tell(&d->vorbis)!=(ogg_int64_t)first&&ov_pcm_seek(&d->vorbis,(ogg_int64_t)first)){status=d->failure?d->failure:ZGTA_RADIO_CODEC;return abort_codec(d,status);}
 uint32_t received=0;uint64_t wanted=d->info.frames-first;if(wanted>frames)wanted=frames;
 while(received<wanted){
  if(cancelled(d))return abort_codec(d,ZGTA_RADIO_CANCELLED);
  float**channels=NULL;int section=-1;long n=ov_read_float(&d->vorbis,&channels,(int)(wanted-received),&section);
  if(d->failure||n<=0||section!=0||!channels||(uint64_t)n>wanted-received){status=d->failure?d->failure:ZGTA_RADIO_CODEC;return abort_codec(d,status);}
  for(long i=0;i<n;i++){
   float left=channels[0][i],right=channels[d->info.source_channels==1?0:1][i];
   if(!isfinite(left)||!isfinite(right))return abort_codec(d,ZGTA_RADIO_NONFINITE);
   out[(received+(uint32_t)i)*2]=left;out[(received+(uint32_t)i)*2+1]=right;
  }
  received+=(uint32_t)n;
 }
 status=source_check(d);if(status)return abort_codec(d,status);
 finish(d);*written=received;return ZGTA_RADIO_OK;
}
void zgta_radio_cancel(zgta_radio_decoder*d){if(d)atomic_store_explicit(&d->cancelled,true,memory_order_relaxed);}
void zgta_radio_destroy(zgta_radio_decoder*d){
 if(!d)return;
 /* All library allocations are tracked, including partially opened/aborted
  * states. Freeing the list directly avoids invoking partial codec destructors
  * after an allocation/stack budget longjmp. No codec-owned external FD exists. */
 release_allocations(d);if(d->fd>=0)close(d->fd);free(d);atomic_fetch_sub(&handles,1);
}
zgta_radio_status zgta_radio_get_stats(const zgta_radio_decoder*d,zgta_radio_stats*out){if(!d||!out)return ZGTA_RADIO_ARGUMENT;*out=d->stats;return ZGTA_RADIO_OK;}
const char*zgta_radio_source_stamp(void){return ZGTA_RADIO_SOURCE_STAMP;}
const char*zgta_radio_status_name(zgta_radio_status s){static const char*names[]={"ok","argument","range","source","source-changed","ogg","format","codec","cancelled","memory","nonfinite","state","limit","io"};return (unsigned)s<sizeof(names)/sizeof(*names)?names[s]:"unknown";}
