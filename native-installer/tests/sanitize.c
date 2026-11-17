/* SPDX-License-Identifier: AGPL-3.0-only */
#include "zgtasa_installer.h"
#include <assert.h>
#include <dirent.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
static int cancelled(void *p){return *(int*)p;}
static void progress(void *p,const char *path,uint64_t bytes,uint64_t total,uint32_t files,uint32_t count){(void)path;(void)total;(void)files;(void)count;if(bytes)*(int*)p=1;}
int main(int argc,char **argv){
    assert(argc==3);char error[512],stage[4096];uint32_t chosen[5],selected=0;int stop=0;
    zgta_installer *h=zgta_installer_open_iso(argv[1],NULL,cancelled,&stop,error,sizeof(error));assert(h);
    for(uint32_t i=0;i<zgta_installer_entry_count(h);i++){
        zgta_installer_entry entry;assert(zgta_installer_get_entry(h,i,&entry));
        if(!strcmp(entry.path,"anim/ped.ifp")||!strcmp(entry.path,"data/weapon.dat")||!strcmp(entry.path,"data/gta.dat")||!strcmp(entry.path,"data/handling.cfg")||!strcmp(entry.path,"data/peds.ide")){assert(selected<5);chosen[selected++]=i;}
    }assert(selected==5);snprintf(stage,sizeof(stage),"%s/sanitized-stage",argv[2]);assert(zgta_installer_extract(h,chosen,5,stage,NULL,NULL)==0);
    assert(zgta_installer_extract(h,chosen,5,stage,NULL,NULL)==ZGTA_INSTALLER_FAILED);
    snprintf(stage,sizeof(stage),"%s/sanitized-cancelled",argv[2]);assert(zgta_installer_extract(h,chosen,1,stage,progress,&stop)==ZGTA_INSTALLER_CANCELLED);
    struct stat info;assert(stat(stage,&info)!=0);zgta_installer_close(h);
    DIR *directory=opendir(argv[2]);assert(directory);struct dirent *entry;unsigned refused=0;
    while((entry=readdir(directory))){size_t length=strlen(entry->d_name);if(length<4||strcmp(entry->d_name+length-4,".iso"))continue;
        char path[4096];snprintf(path,sizeof(path),"%s/%s",argv[2],entry->d_name);h=zgta_installer_open_iso(path,NULL,NULL,NULL,error,sizeof(error));
        if(!strcmp(entry->d_name,"truncated-cabinets.iso")){
            assert(h);uint32_t weapon=UINT32_MAX;
            for(uint32_t i=0;i<zgta_installer_entry_count(h);i++){zgta_installer_entry value;zgta_installer_get_entry(h,i,&value);if(!strcmp(value.path,"data/weapon.dat"))weapon=i;}
            assert(weapon!=UINT32_MAX);snprintf(stage,sizeof(stage),"%s/sanitized-malformed",argv[2]);
            for(unsigned n=0;n<20;n++){assert(zgta_installer_extract(h,&weapon,1,stage,NULL,NULL)!=0);assert(stat(stage,&info)!=0);}zgta_installer_close(h);
        }else{assert(!h);refused++;}
    }closedir(directory);assert(refused>=8);
    printf("PASS ASan/UBSan C boundaries: actual5-file extraction, cancel/existing-stage, %u malformed metadata cases and20 malformed-cabinet retries\n",refused);return 0;
}
