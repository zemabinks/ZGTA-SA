// SPDX-License-Identifier: AGPL-3.0-only
#include "zgtasa_native_audio.h"
#include <assert.h>
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <stdlib.h>
#include <pthread.h>
#include <math.h>
#ifndef EXPECTED_SOURCE_STAMP
#error "Test must bind the exact independently recorded library source stamp"
#endif
static unsigned checks=0;
#define CHECK(v) do{checks++;if(!(v)){fprintf(stderr,"API_CHECK_FAILED line%d\n",__LINE__);abort();}}while(0)
static int descriptors(void){int n=0;for(int fd=0;fd<4096;fd++)if(fcntl(fd,F_GETFD)>=0)n++;return n;}
struct work {zgta_radio_decoder*d;pthread_mutex_t mutex;pthread_cond_t condition;int started;zgta_radio_status status;};
static void*reader(void*opaque){struct work*w=opaque;pthread_mutex_lock(&w->mutex);w->started=1;pthread_cond_signal(&w->condition);pthread_mutex_unlock(&w->mutex);float out[16000];uint32_t written;
 for(unsigned i=0;i<1000;i++){w->status=zgta_radio_read(w->d,(i*17)%8000,8000,out,16000,&written);if(w->status)break;}return NULL;}
int main(int argc,char**argv){
 CHECK(argc==5);uint64_t bytes=strtoull(argv[2],NULL,10),offset=strtoull(argv[3],NULL,10);int initial=descriptors();
 CHECK(strlen(zgta_radio_source_stamp())==64&&strcmp(zgta_radio_source_stamp(),EXPECTED_SOURCE_STAMP)==0);
 int fd=open(argv[1],O_RDONLY);CHECK(fd>=0);CHECK(lseek(fd,17,SEEK_SET)==17);
 zgta_radio_decoder*d=NULL;zgta_radio_info info;zgta_radio_stats stats;uint32_t written=999;float output[16002];
 CHECK(zgta_radio_create(fd,offset,bytes,&d)==ZGTA_RADIO_OK);CHECK(lseek(fd,0,SEEK_CUR)==17);
 CHECK(zgta_radio_read(d,0,1,output,2,&written)==ZGTA_RADIO_STATE&&written==0);
 CHECK(zgta_radio_prepare(d,&info)==ZGTA_RADIO_OK);CHECK(info.frames==16000&&info.sample_rate==32000&&info.output_channels==2);
 CHECK(zgta_radio_prepare(d,&info)==ZGTA_RADIO_STATE);
 for(unsigned i=0;i<80;i++){
  output[0]=1234;output[16001]=5678;
  CHECK(zgta_radio_read(d,(i*197)%16000,8000,output+1,16000,&written)==ZGTA_RADIO_OK);
  CHECK(written>0&&written<=8000&&output[0]==1234&&output[16001]==5678);
  for(unsigned n=0;n<written*2;n++)CHECK(isfinite(output[n+1]));
 }
 CHECK(lseek(fd,0,SEEK_CUR)==17);close(fd);fd=-1;
 CHECK(zgta_radio_read(d,0,8000,output,16000,&written)==ZGTA_RADIO_OK&&written==8000);
 CHECK(zgta_radio_read(d,16000,1,output,2,&written)==ZGTA_RADIO_OK&&written==0);
 CHECK(zgta_radio_read(d,16001,1,output,2,&written)==ZGTA_RADIO_RANGE&&written==0);
 CHECK(zgta_radio_read(d,UINT64_MAX,1,output,2,&written)==ZGTA_RADIO_RANGE);
 CHECK(zgta_radio_read(d,0,8001,output,16000,&written)==ZGTA_RADIO_ARGUMENT);
 CHECK(zgta_radio_read(d,0,0,output,16000,&written)==ZGTA_RADIO_ARGUMENT);
 CHECK(zgta_radio_read(d,0,8,output,15,&written)==ZGTA_RADIO_ARGUMENT);
 CHECK(zgta_radio_read(d,0,8,NULL,16,&written)==ZGTA_RADIO_ARGUMENT);
 CHECK(zgta_radio_read(d,0,8,output,16,NULL)==ZGTA_RADIO_ARGUMENT);
 CHECK(zgta_radio_read(d,0,1,output,2,&written)==ZGTA_RADIO_OK);
 CHECK(zgta_radio_get_stats(d,&stats)==ZGTA_RADIO_OK);CHECK(stats.maximum_read_bytes<=65536&&stats.peak_heap_bytes<=ZGTA_RADIO_MAX_HEAP_BYTES&&stats.current_heap_bytes>0);
 struct work w={.d=d,.mutex=PTHREAD_MUTEX_INITIALIZER,.condition=PTHREAD_COND_INITIALIZER};pthread_t thread;
 CHECK(pthread_create(&thread,NULL,reader,&w)==0);pthread_mutex_lock(&w.mutex);while(!w.started)pthread_cond_wait(&w.condition,&w.mutex);pthread_mutex_unlock(&w.mutex);
 zgta_radio_cancel(d);CHECK(pthread_join(thread,NULL)==0);CHECK(w.status==ZGTA_RADIO_CANCELLED);CHECK(zgta_radio_read(d,0,1,output,2,&written)==ZGTA_RADIO_CANCELLED);
 pthread_mutex_destroy(&w.mutex);pthread_cond_destroy(&w.condition);zgta_radio_destroy(d);d=NULL;
 CHECK(zgta_radio_create(-1,0,9000,&d)==ZGTA_RADIO_ARGUMENT&&d==NULL);
 fd=open(argv[1],O_RDONLY);CHECK(zgta_radio_create(fd,UINT64_MAX,9000,&d)==ZGTA_RADIO_RANGE&&d==NULL);
 CHECK(zgta_radio_create(fd,0,8068,&d)==ZGTA_RADIO_RANGE);CHECK(zgta_radio_create(fd,offset,UINT64_MAX,&d)==ZGTA_RADIO_RANGE);
 CHECK(zgta_radio_create(fd,offset,bytes+100000,&d)==ZGTA_RADIO_RANGE);CHECK(zgta_radio_create(fd,offset,bytes,NULL)==ZGTA_RADIO_ARGUMENT);
 CHECK(zgta_radio_create(fd,offset,bytes,&d)==ZGTA_RADIO_OK);zgta_radio_cancel(d);CHECK(zgta_radio_prepare(d,&info)==ZGTA_RADIO_CANCELLED);zgta_radio_destroy(d);
 for(unsigned i=0;i<100;i++){CHECK(zgta_radio_create(fd,offset,bytes,&d)==ZGTA_RADIO_OK);CHECK(zgta_radio_prepare(d,&info)==ZGTA_RADIO_OK);CHECK(zgta_radio_read(d,15000,1000,output,2000,&written)==ZGTA_RADIO_OK&&written==1000);zgta_radio_destroy(d);}
 zgta_radio_decoder*many[8]={0};for(unsigned i=0;i<8;i++)CHECK(zgta_radio_create(fd,offset,bytes,&many[i])==ZGTA_RADIO_OK);
 CHECK(zgta_radio_create(fd,offset,bytes,&d)==ZGTA_RADIO_LIMIT&&d==NULL);for(unsigned i=0;i<8;i++)zgta_radio_destroy(many[i]);
 close(fd);
 fd=open(argv[1],O_RDONLY);CHECK(zgta_radio_create(fd,offset,bytes,&d)==ZGTA_RADIO_OK);CHECK(zgta_radio_prepare(d,&info)==ZGTA_RADIO_OK);close(fd);
 int writer=open(argv[1],O_RDWR);unsigned char old=0,toggled=1;CHECK(writer>=0&&pread(writer,&old,1,0)==1);toggled=old^1;CHECK(pwrite(writer,&toggled,1,0)==1);
 CHECK(zgta_radio_read(d,0,1,output,2,&written)==ZGTA_RADIO_CHANGED&&written==0);CHECK(pwrite(writer,&old,1,0)==1);close(writer);zgta_radio_destroy(d);
 int pipefds[2];CHECK(pipe(pipefds)==0);CHECK(zgta_radio_create(pipefds[0],0,9000,&d)==ZGTA_RADIO_SOURCE);close(pipefds[0]);close(pipefds[1]);
 int directory=open(argv[4],O_RDONLY);CHECK(directory>=0);CHECK(zgta_radio_create(directory,0,9000,&d)==ZGTA_RADIO_SOURCE);close(directory);
 CHECK(zgta_radio_prepare(NULL,&info)==ZGTA_RADIO_ARGUMENT);CHECK(zgta_radio_get_stats(NULL,&stats)==ZGTA_RADIO_ARGUMENT);zgta_radio_cancel(NULL);zgta_radio_destroy(NULL);
 CHECK(descriptors()==initial);printf("RADIO_API_PASS %u actual C ABI checks; no audio hardware\n",checks);return 0;
}
