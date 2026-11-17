// SPDX-License-Identifier: AGPL-3.0-only
#include "zgtasa_native_audio.h"
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdint.h>
int main(int argc,char**argv){
 if(argc!=6)return 2;
 int fd=open(argv[1],O_RDONLY);zgta_radio_decoder*d=NULL;zgta_radio_info info;
 zgta_radio_status status=zgta_radio_create(fd,strtoull(argv[2],NULL,10),strtoull(argv[3],NULL,10),&d);if(fd>=0)close(fd);
 if(!status)status=zgta_radio_prepare(d,&info);
 uint32_t count=(uint32_t)strtoul(argv[5],NULL,10),written=0;float out[ZGTA_RADIO_MAX_WINDOW_FRAMES*2];
 if(!status)status=zgta_radio_read(d,strtoull(argv[4],NULL,10),count,out,ZGTA_RADIO_MAX_WINDOW_FRAMES*2,&written);
 if(status){zgta_radio_stats stats={0};if(d)zgta_radio_get_stats(d,&stats);fprintf(stderr,"{\"status\":%d,\"name\":\"%s\",\"heapBytes\":%llu,\"peakHeapBytes\":%llu}\n",status,zgta_radio_status_name(status),(unsigned long long)stats.current_heap_bytes,(unsigned long long)stats.peak_heap_bytes);zgta_radio_destroy(d);return 1;}
 uint64_t header[5]={info.frames,info.sample_rate,info.source_channels,info.output_channels,written};
 fwrite(header,sizeof(header),1,stdout);fwrite(out,sizeof(float),written*2,stdout);zgta_radio_destroy(d);return 0;
}
