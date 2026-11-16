/* SPDX-License-Identifier: AGPL-3.0-only */
#include "zgtasa_samp.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
int main(void) {
    assert(zgtasa_samp_abi_version()==1);
    assert(zgtasa_samp_open(NULL,0,NULL,0,100)==0);
    uint32_t required=123;
    assert(zgtasa_samp_poll(0,NULL,0,&required)==-1 && required==0);
    assert(zgtasa_samp_poll(0,NULL,1,&required)==-3);
    const char *address="127.0.0.1:1";
    uint64_t handle=zgtasa_samp_open(address,(uint32_t)strlen(address),NULL,0,100);
    assert(handle!=0);
    assert(zgtasa_samp_accepted(handle,NULL,0,&required)==0 && required==0);
    uint8_t data=1;
    assert(zgtasa_samp_send(handle,&data,1,11,0)==-3);
    int32_t status=0;
    for(unsigned i=0;i<3000 && status==0;i++){status=zgtasa_samp_poll(handle,NULL,0,&required);if(status==0)usleep(1000);}
    assert(status==-2 && required>0 && required<=4096);
    uint8_t *buffer=(uint8_t*)malloc(required+1);assert(buffer!=NULL);
    uint32_t capacity=required;buffer[capacity]=0xa5;
    assert(zgtasa_samp_poll(handle,buffer,capacity,&required)==3 && required==capacity);
    assert(buffer[capacity]==0xa5);
    free(buffer);
    zgtasa_samp_close(handle);
    assert(zgtasa_samp_poll(handle,NULL,0,&required)==-1);
    zgtasa_samp_close(handle);
    puts("PASS actual native C ABI version, bounds, async failure, size probe, copy and close");
    return 0;
}
