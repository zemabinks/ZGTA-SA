/* SPDX-License-Identifier: AGPL-3.0-only */
#define _DARWIN_C_SOURCE 1
#include "zgtasa_installer.h"
#include "libunshield.h"
#include <sys/stat.h>
#include <sys/types.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>

#define SECTOR 2048U
#define PATH_LIMIT 1024U
#define HDR_LIMIT (32U*1024U*1024U)
#define DIRECTORY_LIMIT (4U*1024U*1024U)
#define FILE_DESCRIPTOR_SIZE 0x57U

typedef struct {char *path;uint64_t offset,bytes;} IsoFile;
typedef struct {char *path,*group;uint64_t bytes;int source,index;} Entry;
typedef struct {uint64_t offset,bytes;char *path;uint32_t depth;} IsoDirectory;
struct zgta_installer {
    int iso_fd;uint64_t iso_size,volume_size;
    zgta_installer_limits limits;zgta_installer_cancelled cancelled;void *cancel_context;
    atomic_bool stop;char error[512];
    IsoFile *iso;uint32_t iso_count;char *cab_directory;
    Entry *entries;uint32_t count;
    unsigned char *header;size_t header_size;
    Unshield *unshield;
    struct VirtualFile *streams;
    zgta_installer_statistics stats;
    int output_fd;uint64_t current_written,current_expected,job_written,job_expected;
    uint32_t job_done,job_count;const char *current_path;
    zgta_installer_progress progress;void *progress_context;
};
typedef struct VirtualFile {zgta_installer *owner;const IsoFile *source;uint64_t position;int header,output;struct VirtualFile *next;} VirtualFile;
typedef struct {zgta_installer *owner;uint32_t index;struct dirent entry;} VirtualDirectory;
static int fail(zgta_installer *h,const char *format,...){if(!h->error[0]){va_list ap;va_start(ap,format);vsnprintf(h->error,sizeof(h->error),format,ap);va_end(ap);}return 0;}
static int stopped(zgta_installer *h){if(atomic_load(&h->stop)||(h->cancelled&&h->cancelled(h->cancel_context))){atomic_store(&h->stop,true);fail(h,"Extraction cancelled; active installations are unchanged");return 1;}return 0;}
static uint16_t le16(const unsigned char *p){return (uint16_t)(p[0]|(uint16_t)p[1]<<8);}
static uint32_t le32(const unsigned char *p){return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static uint64_t le64(const unsigned char *p){return le32(p)|(uint64_t)le32(p+4)<<32;}
static uint32_t be32(const unsigned char *p){return (uint32_t)p[3]|(uint32_t)p[2]<<8|(uint32_t)p[1]<<16|(uint32_t)p[0]<<24;}
static int range(size_t size,uint64_t offset,uint64_t length){return offset<=size&&length<=size-offset;}
static int read_at(zgta_installer *h,void *out,size_t length,uint64_t offset){
    if(stopped(h))return 0;
    if(!range((size_t)h->iso_size,offset,length)||length>h->limits.max_input_bytes-h->stats.iso_bytes_read)return fail(h,"ISO read extent or total input budget exceeded");
    size_t done=0;if(length>h->stats.max_read_request)h->stats.max_read_request=length;
    while(done<length){if(stopped(h))return 0;ssize_t n=pread(h->iso_fd,(char*)out+done,length-done,(off_t)(offset+done));if(n<0&&errno==EINTR)continue;if(n<=0)return fail(h,"Cannot read complete ISO extent");done+=(size_t)n;h->stats.iso_bytes_read+=(uint64_t)n;}
    return 1;
}
int zgta_installer_valid_relative_path(const char *path){
    if(!path||!*path||strlen(path)>PATH_LIMIT||path[0]=='/'||path[strlen(path)-1]=='/')return 0;
    const char *start=path;
    for(const unsigned char *p=(const unsigned char*)path;;p++){
        if(*p&&(*p<32||*p>126||*p=='\\'||*p==':'))return 0;
        if(*p=='/'||!*p){size_t n=(const char*)p-start;if(!n||n>255||(n==1&&start[0]=='.')||(n==2&&start[0]=='.'&&start[1]=='.'))return 0;start=(const char*)p+1;if(!*p)break;}
    }return 1;
}
static char *joined(zgta_installer *h,const char *a,const char *b,const char *c){
    char result[PATH_LIMIT+1];int n=snprintf(result,sizeof(result),"%s%s%s%s%s",a,*a&&*b?"/":"",b,(*a||*b)&&*c?"/":"",c);
    if(n<0||(size_t)n>=sizeof(result)){fail(h,"Archive path exceeds supported length");return NULL;}
    for(char *p=result;*p;p++)if(*p=='\\')*p='/';
    if(!zgta_installer_valid_relative_path(result)){fail(h,"Unsafe archive member path");return NULL;}return strdup(result);
}
static int add_iso(zgta_installer *h,const char *path,uint64_t offset,uint64_t bytes){
    if(h->iso_count>=h->limits.max_entries)return fail(h,"ISO file count exceeds limit");
    IsoFile *next=realloc(h->iso,(h->iso_count+1)*sizeof(*next));if(!next)return fail(h,"ISO index allocation failed");h->iso=next;
    char *copy=strdup(path);if(!copy)return fail(h,"ISO path allocation failed");h->iso[h->iso_count++]=(IsoFile){copy,offset,bytes};return 1;
}
static int iso_record(zgta_installer *h,const unsigned char *p,size_t available,uint64_t *offset,uint64_t *bytes,int *directory,char *name){
    if(available<34||p[0]<34||p[0]>available||!p[32]||(size_t)33+p[32]>p[0]||p[1]||p[26]||p[27]||(p[25]&128))return fail(h,"Unsupported ISO directory record");
    uint64_t extent=le32(p+2),length=le32(p+10);
    if(extent!=be32(p+6)||length!=be32(p+14)||extent>h->volume_size/SECTOR||length>h->volume_size-extent*SECTOR)return fail(h,"ISO record has inconsistent or out-of-volume extents");
    *offset=extent*SECTOR;*bytes=length;*directory=(p[25]&2)!=0;name[0]=0;
    if(p[32]==1&&(p[33]==0||p[33]==1))return 1;
    size_t n=0;for(unsigned i=0;i<p[32]&&p[33+i]!=';';i++){unsigned char ch=p[33+i];if(ch<32||ch>126||ch=='/'||ch=='\\')return fail(h,"Unsafe ISO identifier");name[n++]=(char)ch;}name[n]=0;
    if(!zgta_installer_valid_relative_path(name))return fail(h,"Unsafe ISO identifier");return 1;
}
static int compare_iso(const void *a,const void *b){return strcasecmp(((const IsoFile*)a)->path,((const IsoFile*)b)->path);}
static int scan_iso(zgta_installer *h){
    unsigned char descriptor[SECTOR],primary[SECTOR];int found=0,ended=0;
    for(uint32_t i=16;i<80;i++){if(!read_at(h,descriptor,SECTOR,(uint64_t)i*SECTOR))return 0;if(memcmp(descriptor+1,"CD001",5)||descriptor[6]!=1)return fail(h,"No supported ISO9660 descriptor set");if(descriptor[0]==1&&!found){memcpy(primary,descriptor,SECTOR);found=1;}if(descriptor[0]==255){ended=1;break;}}
    if(!found||!ended||le16(primary+128)!=SECTOR||((uint16_t)primary[130]<<8|primary[131])!=SECTOR)return fail(h,"Complete 2048-byte primary ISO volume required");
    uint64_t blocks=le32(primary+80);if(blocks!=be32(primary+84)||!blocks||blocks>h->iso_size/SECTOR)return fail(h,"ISO volume bounds are inconsistent");h->volume_size=blocks*SECTOR;
    IsoDirectory *queue=calloc(h->limits.max_directories,sizeof(*queue));if(!queue)return fail(h,"ISO directory index allocation failed");
    uint64_t offset,length;int directory;char name[256];int ok=0;uint32_t count=1;uint64_t metadata=0;
    if(!iso_record(h,primary+156,SECTOR-156,&offset,&length,&directory,name)||!directory)goto done;
    queue[0]=(IsoDirectory){offset,length,strdup(""),0};if(!queue[0].path){fail(h,"ISO root allocation failed");goto done;}
    for(uint32_t index=0;index<count;index++){
        IsoDirectory *d=&queue[index];if(stopped(h))goto done;
        if(d->depth>12||d->bytes>DIRECTORY_LIMIT||d->bytes>h->limits.max_metadata_bytes-metadata){fail(h,"ISO directory metadata/nesting limit exceeded");goto done;}metadata+=d->bytes;
        unsigned char *data=malloc((size_t)d->bytes?:1);if(!data){fail(h,"ISO directory allocation failed");goto done;}
        if(!read_at(h,data,(size_t)d->bytes,d->offset)){free(data);goto done;}
        for(size_t at=0;at<d->bytes;){
            if(!data[at]){at=(at/SECTOR+1)*SECTOR;continue;}
            size_t n=data[at];if(at%SECTOR+n>SECTOR||!iso_record(h,data+at,(size_t)d->bytes-at,&offset,&length,&directory,name)){free(data);goto done;}at+=n;if(!*name)continue;
            char *path=*d->path?joined(h,d->path,name,""):strdup(name);if(!path){free(data);goto done;}
            if(directory){
                if(count>=h->limits.max_directories){free(path);free(data);fail(h,"ISO directory count exceeded");goto done;}
                for(uint32_t j=0;j<count;j++)if(queue[j].offset==offset){free(path);free(data);fail(h,"ISO directory cycle/alias refused");goto done;}
                queue[count++]=(IsoDirectory){offset,length,path,d->depth+1};
            }else{int added=add_iso(h,path,offset,length);free(path);if(!added){free(data);goto done;}}
        }free(data);
    }qsort(h->iso,h->iso_count,sizeof(*h->iso),compare_iso);
    for(uint32_t i=1;i<h->iso_count;i++)if(!strcasecmp(h->iso[i-1].path,h->iso[i].path)){fail(h,"Duplicate ISO file identity");goto done;}
    ok=1;
done:for(uint32_t i=0;i<count;i++)free(queue[i].path);free(queue);return ok;
}
static const char *base_name(const char *path){const char *p=strrchr(path,'/');return p?p+1:path;}
static const IsoFile *cab_file(zgta_installer *h,const char *name){
    for(uint32_t i=0;i<h->iso_count;i++){
        const char *base=base_name(h->iso[i].path);size_t prefix=(size_t)(base-h->iso[i].path);
        if(!strcasecmp(base,name)&&prefix==strlen(h->cab_directory)&&!strncasecmp(h->iso[i].path,h->cab_directory,prefix))return &h->iso[i];
    }return NULL;
}
static const char *header_string(zgta_installer *h,size_t offset){
    if(offset>=h->header_size)return NULL;size_t remaining=h->header_size-offset;if(remaining>PATH_LIMIT+1)remaining=PATH_LIMIT+1;const unsigned char *p=h->header+offset,*end=memchr(p,0,remaining);if(!end||(size_t)(end-p)>PATH_LIMIT)return NULL;
    for(const unsigned char *q=p;q<end;q++)if(*q<32||*q>126)return NULL;return (const char*)p;
}
static int add_entry(zgta_installer *h,char *path,const char *group,uint64_t bytes,int source,int index){
    if(!path)return fail(h,"Member path allocation failed");
    if(h->count>=h->limits.max_entries){free(path);return fail(h,"Combined member count exceeds limit");}
    Entry *next=realloc(h->entries,(h->count+1)*sizeof(*next));if(!next){free(path);return fail(h,"Member index allocation failed");}h->entries=next;
    char *group_copy=strdup(group?group:"");if(!group_copy){free(path);return fail(h,"Member group allocation failed");}h->entries[h->count++]=(Entry){path,group_copy,bytes,source,index};return 1;
}
/* Preflight every offset/string/file/link used by the decoder. Components are
 * never used. File groups are read here with bounded visited/range checks to
 * preserve their directory identities, then both decoder table-head arrays are
 * zeroed only in this RAM view. The on-disc HDR and vendored source stay intact. */
static int prepare_header(zgta_installer *h){
    const IsoFile *hdr=NULL;for(uint32_t i=0;i<h->iso_count;i++)if(!strcasecmp(base_name(h->iso[i].path),"DATA1.HDR")){if(hdr)return fail(h,"Ambiguous installer header source");hdr=&h->iso[i];}
    if(!hdr||hdr->bytes<20||hdr->bytes>HDR_LIMIT||hdr->bytes>h->limits.max_metadata_bytes)return fail(h,"A bounded DATA1.HDR installer header is required");
    size_t prefix=(size_t)(base_name(hdr->path)-hdr->path);h->cab_directory=strndup(hdr->path,prefix);if(!h->cab_directory)return fail(h,"Installer directory allocation failed");
    h->header_size=(size_t)hdr->bytes;h->header=malloc(h->header_size);if(!h->header)return fail(h,"Installer header allocation failed");
    if(!read_at(h,h->header,h->header_size,hdr->offset))return 0;
    const unsigned char *data=h->header;uint32_t version=le32(data+4),major=(version>>24)==1?(version>>12)&15:(version&65535)/100;
    uint32_t descriptor=le32(data+12),descriptor_size=le32(data+16);
    if(le32(data)!=0x28635349||!((version>>24)==1||(version>>24)==2||(version>>24)==4)||major<6||major>13||!range(h->header_size,descriptor,descriptor_size)||descriptor_size<0x276)return fail(h,"Unsupported or malformed InstallShield6–13 header");
    uint64_t table=(uint64_t)descriptor+le32(data+descriptor+12),directories=le32(data+descriptor+28),files=le32(data+descriptor+40),second=le32(data+descriptor+44);
    if(!directories||directories>h->limits.max_directories||!files||files>h->limits.max_entries||!range(h->header_size,table,(directories+files)*4)||!range(h->header_size,table+second,files*FILE_DESCRIPTOR_SIZE))return fail(h,"Installer file table exceeds bounds");
    char **groups=calloc((size_t)files,sizeof(*groups));unsigned char *visited=calloc(h->header_size,1);if(!groups||!visited){free(groups);free(visited);return fail(h,"Installer preflight allocation failed");}int ok=0;uint32_t group_nodes=0;
    for(uint32_t bucket=0;bucket<71;bucket++){
        uint32_t next=le32(data+descriptor+0x3e + bucket*4);
        while(next){
            uint64_t node=(uint64_t)descriptor+next;
            if(stopped(h))goto done;
            if(++group_nodes>1024||!range(h->header_size,node,12)||visited[node]){fail(h,"Installer group list cycle/bounds refused");goto done;}visited[node]=1;
            uint64_t group=(uint64_t)descriptor+le32(data+node+4);next=le32(data+node+8);
            if(!range(h->header_size,group,30)){fail(h,"Installer group descriptor out of bounds");goto done;}
            const char *name=header_string(h,(size_t)descriptor+le32(data+group));int32_t first=(int32_t)le32(data+group+22),last=(int32_t)le32(data+group+26);
            if(!name){fail(h,"Installer group name out of bounds");goto done;}if(first==-1&&last==-1)continue;
            if(first<0||last<first||(uint64_t)last>=files){fail(h,"Installer group member range refused");goto done;}
            for(int32_t i=first;i<=last;i++){if(groups[i]){fail(h,"Overlapping installer group identities refused");goto done;}if(!groups[i]){groups[i]=strdup(name);if(!groups[i]){fail(h,"Installer group allocation failed");goto done;}}}
        }
    }
    for(uint32_t i=0;i<directories;i++)if(!header_string(h,(size_t)(table+le32(data+table+i*4)))){fail(h,"Installer directory string out of bounds");goto done;}
    for(uint32_t i=0;i<files;i++){
        if(stopped(h))goto done;const unsigned char *fd=data+table+second+i*FILE_DESCRIPTOR_SIZE;uint16_t flags=le16(fd),dir=le16(fd+62);uint64_t expanded=le64(fd+2),compressed=le64(fd+10),position=le64(fd+18);uint32_t name_offset=le32(fd+58);
        if(dir>=directories||expanded>h->limits.max_file_bytes||expanded>UINT32_MAX||compressed>UINT32_MAX||(fd[84]&~3)){fail(h,"Unsupported installer member size/directory/link flags");goto done;}
        for(uint32_t current=i,depth=0;;){const unsigned char *link=data+table+second+current*FILE_DESCRIPTOR_SIZE;if(!(link[84]&1))break;uint32_t previous=le32(link+76);if(previous>=files||previous==current||++depth>64){fail(h,"Installer member-link cycle or depth refused");goto done;}current=previous;}
        if((fd[84]&2)&&le32(fd+80)>=files){fail(h,"Installer next-member link out of bounds");goto done;}
        if((flags&8)||!name_offset||!position)continue;
        const char *name=header_string(h,(size_t)(table+name_offset)),*dir_name=header_string(h,(size_t)(table+le32(data+table+dir*4)));
        if(!name||!*name||strchr(name,'/')||strchr(name,'\\')){fail(h,"Installer filename refused");goto done;}
        char *path=joined(h,groups[i]?groups[i]:"",dir_name,name);if(!path||!add_entry(h,path,groups[i],expanded,ZGTA_INSTALLER_CAB,(int)i))goto done;
    }
    memset(h->header+descriptor+0x3e,0,71*4*2);ok=1;
done:for(uint32_t i=0;i<files;i++)free(groups[i]);free(groups);free(visited);return ok;
}
static void *io_open(const char *path,const char *mode,void *context){
    zgta_installer *h=context;if(stopped(h))return NULL;VirtualFile *file=calloc(1,sizeof(*file));if(!file){fail(h,"Decoder I/O allocation failed");return NULL;}file->owner=h;
    if(!strcmp(mode,"wb")&&!strcmp(path,"/output")&&h->output_fd>=0){file->output=1;file->next=h->streams;h->streams=file;return file;}
    if(strcmp(mode,"rb")||strncmp(path,"/iso/",5)||strchr(path+5,'/')){free(file);return NULL;}
    file->source=cab_file(h,path+5);if(!file->source){free(file);return NULL;}file->header=!strcasecmp(path+5,"DATA1.HDR");file->next=h->streams;h->streams=file;return file;
}
static int io_seek(void *pointer,long offset,int whence,void *context){
    (void)context;VirtualFile *file=pointer;if(!file||file->output)return -1;uint64_t size=file->source->bytes;int64_t base=whence==SEEK_SET?0:whence==SEEK_CUR?(int64_t)file->position:whence==SEEK_END?(int64_t)size:-1;
    if(base<0||(offset<0&&(int64_t)offset < -base)||(offset>0&&(uint64_t)offset>size-(uint64_t)base))return -1;int64_t next=base+offset;if(next<0||(uint64_t)next>size)return -1;file->position=(uint64_t)next;return 0;
}
static long io_tell(void *pointer,void *context){(void)context;VirtualFile *file=pointer;return file?(long)file->position:-1;}
static size_t io_read(void *output,size_t size,size_t count,void *pointer,void *context){
    zgta_installer *h=context;VirtualFile *file=pointer;if(!file||file->output||!size||stopped(h)||count>SIZE_MAX/size)return 0;
    uint64_t available=file->source->bytes-file->position;if(count>available/size)count=(size_t)(available/size);size_t bytes=size*count;if(!bytes)return 0;
    if(file->header)memcpy(output,h->header+file->position,bytes);else if(!read_at(h,output,bytes,file->source->offset+file->position))return 0;
    file->position+=bytes;return count;
}
static size_t io_write(const void *input,size_t size,size_t count,void *pointer,void *context){
    zgta_installer *h=context;VirtualFile *file=pointer;if(!file||!file->output||!size||stopped(h)||count>SIZE_MAX/size)return 0;size_t bytes=size*count;
    if(bytes>h->current_expected-h->current_written||bytes>h->limits.max_output_bytes-h->job_written){fail(h,"Decoder output exceeded declared member/job bound");return 0;}
    size_t written=0;while(written<bytes){if(stopped(h))return written/size;ssize_t n=write(h->output_fd,(const char*)input+written,bytes-written);if(n<0&&errno==EINTR)continue;if(n<=0){fail(h,"Cannot write staged original resource");return written/size;}written+=(size_t)n;h->current_written+=(uint64_t)n;h->job_written+=(uint64_t)n;h->stats.output_bytes_written+=(uint64_t)n;}
    if(h->progress)h->progress(h->progress_context,h->current_path,h->job_written,h->job_expected,h->job_done,h->job_count);return count;
}
static int io_close(void *pointer,void *context){zgta_installer *h=context;VirtualFile **link=&h->streams;while(*link&&*link!=pointer)link=&(*link)->next;if(*link){VirtualFile *file=*link;*link=file->next;free(file);}return 0;}
/* A decoder failure can abandon its just-opened reader before returning it.
 * The shared ISO descriptor remains ours; release orphan callback objects at
 * each completed call boundary, without relying on upstream error cleanup. */
static void clear_streams(zgta_installer *h){while(h->streams){VirtualFile *next=h->streams->next;free(h->streams);h->streams=next;}}
static void *io_opendir(const char *path,void *context){if(strcmp(path,"/iso"))return NULL;VirtualDirectory *directory=calloc(1,sizeof(*directory));if(directory)directory->owner=context;return directory;}
static struct dirent *io_readdir(void *pointer,void *context){
    (void)context;VirtualDirectory *directory=pointer;zgta_installer *h=directory->owner;
    while(directory->index<h->iso_count){const IsoFile *file=&h->iso[directory->index++];const char *name=base_name(file->path);size_t prefix=(size_t)(name-file->path);if(prefix!=strlen(h->cab_directory)||strncasecmp(file->path,h->cab_directory,prefix))continue;
        memset(&directory->entry,0,sizeof(directory->entry));if(strlen(name)>=sizeof(directory->entry.d_name))continue;strcpy(directory->entry.d_name,name);
#ifdef __APPLE__
        directory->entry.d_namlen=(uint16_t)strlen(name);
#endif
        return &directory->entry;
    }return NULL;
}
static int io_closedir(void *pointer,void *context){(void)context;free(pointer);return 0;}
static const UnshieldIoCallbacks callbacks={io_open,io_seek,io_tell,io_read,io_write,io_close,io_opendir,io_closedir,io_readdir};
static pthread_once_t logging_once=PTHREAD_ONCE_INIT;
static void quiet_decoder(void){unshield_set_log_level(0);}
zgta_installer_limits zgta_installer_default_limits(void){return (zgta_installer_limits){10000,4096,HDR_LIMIT,UINT32_MAX,32ULL*1024*1024*1024,64ULL*1024*1024*1024};}
zgta_installer *zgta_installer_open_iso(const char *path,const zgta_installer_limits *limits,zgta_installer_cancelled cancel,void *context,char *error,size_t capacity){
    zgta_installer *h=calloc(1,sizeof(*h));if(!h){if(error&&capacity)snprintf(error,capacity,"Extractor allocation failed");return NULL;}h->iso_fd=-1;h->output_fd=-1;atomic_init(&h->stop,false);h->limits=limits?*limits:zgta_installer_default_limits();h->cancelled=cancel;h->cancel_context=context;
    if(!path||!h->limits.max_entries||h->limits.max_entries>100000||!h->limits.max_directories||h->limits.max_directories>4096||!h->limits.max_metadata_bytes||h->limits.max_metadata_bytes>HDR_LIMIT||!h->limits.max_file_bytes||h->limits.max_file_bytes>UINT32_MAX||!h->limits.max_output_bytes||h->limits.max_output_bytes>256ULL*1024*1024*1024||!h->limits.max_input_bytes||h->limits.max_input_bytes>1024ULL*1024*1024*1024){fail(h,"Extractor limits invalid");goto failed;}
    h->iso_fd=open(path,O_RDONLY|O_CLOEXEC|O_NOFOLLOW);struct stat info;if(h->iso_fd<0||fstat(h->iso_fd,&info)||!S_ISREG(info.st_mode)||info.st_size<18*SECTOR){fail(h,"Readable regular ISO file required");goto failed;}h->iso_size=(uint64_t)info.st_size;
    if(!scan_iso(h)||!prepare_header(h))goto failed;
    pthread_once(&logging_once,quiet_decoder);h->unshield=unshield_open2("/iso/DATA1.CAB",&callbacks,h);if(!h->unshield){fail(h,"InstallShield decoder refused the validated metadata");goto failed;}
    for(uint32_t i=0;i<h->iso_count;i++){char *name=strdup(h->iso[i].path);if(!add_entry(h,name,"",h->iso[i].bytes,ZGTA_INSTALLER_LOOSE,(int)i))goto failed;}
    if(error&&capacity)error[0]=0;return h;
failed:if(error&&capacity)snprintf(error,capacity,"%s",h->error[0]?h->error:"Unsupported installer source");zgta_installer_close(h);return NULL;
}
void zgta_installer_cancel(zgta_installer *h){if(h)atomic_store(&h->stop,true);}
uint32_t zgta_installer_entry_count(const zgta_installer *h){return h?h->count:0;}
int zgta_installer_get_entry(const zgta_installer *h,uint32_t index,zgta_installer_entry *value){if(!h||!value||index>=h->count)return 0;const Entry *entry=&h->entries[index];*value=(zgta_installer_entry){entry->path,entry->group,entry->bytes,entry->source};return 1;}
const char *zgta_installer_error(const zgta_installer *h){return h?h->error:"No extractor handle";}
zgta_installer_statistics zgta_installer_stats(const zgta_installer *h){return h?h->stats:(zgta_installer_statistics){0};}
void zgta_installer_close(zgta_installer *h){if(!h)return;if(h->unshield)unshield_close(h->unshield);clear_streams(h);if(h->iso_fd>=0)close(h->iso_fd);if(h->output_fd>=0)close(h->output_fd);for(uint32_t i=0;i<h->iso_count;i++)free(h->iso[i].path);for(uint32_t i=0;i<h->count;i++){free(h->entries[i].path);free(h->entries[i].group);}free(h->iso);free(h->entries);free(h->cab_directory);free(h->header);free(h);}

/* All destination traversal uses directory descriptors and O_NOFOLLOW. */
/* The parent is a caller-owned Application Support/staging directory, never
 * derived from an archive member. Do not open filesystem ancestors outside the
 * app's sandbox merely to reach it. Reject noncanonical/symlink parent names;
 * every archive-controlled descendant is then opened relative to this FD. */
static int open_directory(const char *absolute){
    if(!absolute||absolute[0]!='/'||strlen(absolute)>4096)return -1;
    char *canonical=realpath(absolute,NULL);if(!canonical)return -1;
    if(strcmp(canonical,absolute)){free(canonical);return -1;}
    int fd=open(canonical,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);free(canonical);return fd;
}
/* A case-insensitive host may report EEXIST for a differently cased folder,
 * while the Simulator's descriptor lookup rejects that spelling. Resolve only
 * that observed combination, using one unambiguous real directory entry. The
 * retry retains O_DIRECTORY/O_NOFOLLOW; it never follows a linked alias. */
static int open_existing_child_directory(int parent,const char *name,int existed,uint32_t scan_limit){
    const int flags=O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC;
    int result=openat(parent,name,flags);
    if(result>=0||errno!=ENOENT||!existed)return result;
    int scan=openat(parent,".",flags);if(scan<0)return -1;
    DIR *directory=fdopendir(scan);if(!directory){int saved=errno;close(scan);errno=saved;return -1;}
    char actual[NAME_MAX+1]={0};uint32_t visited=0,matches=0;int failure=0;
    while(1){
        errno=0;struct dirent *entry=readdir(directory);
        if(!entry){if(errno)failure=errno;break;}
        if(++visited>scan_limit){failure=E2BIG;break;}
        if(strcasecmp(entry->d_name,name))continue;
        if(++matches>1){failure=EEXIST;break;}
        size_t length=strnlen(entry->d_name,sizeof(actual));
        if(length>=sizeof(actual)){failure=ENAMETOOLONG;break;}
        memcpy(actual,entry->d_name,length+1);
    }
    closedir(directory);
    if(failure){errno=failure;return -1;}
    if(matches!=1||!strcmp(actual,name)){errno=ENOENT;return -1;}
    return openat(parent,actual,flags);
}
static int create_parent(int root,const char *path,char **leaf,uint32_t scan_limit){
    char *parts=strdup(path),*cursor=parts,*item;if(!parts)return -1;int fd=dup(root);if(fd<0){free(parts);return -1;}
    while((item=strsep(&cursor,"/"))){if(!cursor){*leaf=strdup(item);free(parts);if(!*leaf){close(fd);return -1;}return fd;}int made=mkdirat(fd,item,0700),make_error=errno;if(made&&make_error!=EEXIST){close(fd);free(parts);errno=make_error;return -1;}int next=open_existing_child_directory(fd,item,made!=0,scan_limit),saved=errno;close(fd);if(next<0){free(parts);errno=saved;return -1;}fd=next;}free(parts);close(fd);return -1;
}
static void clear_directory(int fd){
    DIR *directory=fdopendir(dup(fd));if(!directory)return;struct dirent *item;
    while((item=readdir(directory))){if(!strcmp(item->d_name,".")||!strcmp(item->d_name,".."))continue;struct stat info;if(fstatat(fd,item->d_name,&info,AT_SYMLINK_NOFOLLOW))continue;
        if(S_ISDIR(info.st_mode)){int child=openat(fd,item->d_name,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);if(child>=0){clear_directory(child);close(child);}unlinkat(fd,item->d_name,AT_REMOVEDIR);}else unlinkat(fd,item->d_name,0);
    }closedir(directory);
}
int zgta_installer_extract(zgta_installer *h,const uint32_t *indices,uint32_t count,const char *destination,zgta_installer_progress progress,void *context){
    if(!h)return ZGTA_INSTALLER_FAILED;h->error[0]=0;if(stopped(h))return ZGTA_INSTALLER_CANCELLED;
    if(!indices||!count||count>h->limits.max_entries||!destination||destination[0]!='/'||strlen(destination)>4096)return fail(h,"A bounded selection and new absolute staging directory are required"),ZGTA_INSTALLER_FAILED;
    uint64_t total=0;for(uint32_t i=0;i<count;i++){
        if(indices[i]>=h->count)return fail(h,"Selected member index out of range"),ZGTA_INSTALLER_FAILED;Entry *entry=&h->entries[indices[i]];
        if(!zgta_installer_valid_relative_path(entry->path)||entry->bytes>h->limits.max_file_bytes||entry->bytes>h->limits.max_output_bytes-total)return fail(h,"Selected resource byte/path bound exceeded"),ZGTA_INSTALLER_FAILED;total+=entry->bytes;
        for(uint32_t j=0;j<i;j++)if(!strcasecmp(entry->path,h->entries[indices[j]].path))return fail(h,"Duplicate selected destination refused"),ZGTA_INSTALLER_FAILED;
    }
    char *parent=strdup(destination);if(!parent)return fail(h,"Staging path allocation failed"),ZGTA_INSTALLER_FAILED;char *slash=strrchr(parent,'/');const char *name=slash+1;
    if(!*name||!strcmp(name,".")||!strcmp(name,"..")){free(parent);return fail(h,"Unsafe staging directory name"),ZGTA_INSTALLER_FAILED;}
    char *leaf=strdup(name);if(!leaf){free(parent);return fail(h,"Staging name allocation failed"),ZGTA_INSTALLER_FAILED;}if(slash==parent)slash[1]=0;else *slash=0;int parent_fd=open_directory(parent);free(parent);
    if(parent_fd<0){free(leaf);return fail(h,"Staging parent must be an existing canonical app-owned directory without symlinks"),ZGTA_INSTALLER_FAILED;}
    if(mkdirat(parent_fd,leaf,0700)){close(parent_fd);free(leaf);return fail(h,"Staging destination already exists or cannot be created"),ZGTA_INSTALLER_FAILED;}
    int stage=openat(parent_fd,leaf,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC),result=ZGTA_INSTALLER_FAILED;
    if(stage<0){fail(h,"Cannot open newly created stage");goto cleanup;}
    h->job_written=0;h->job_expected=total;h->job_done=0;h->job_count=count;h->progress=progress;h->progress_context=context;
    for(uint32_t i=0;i<count;i++){
        if(stopped(h))goto cleanup;Entry *entry=&h->entries[indices[i]];char *file_leaf=NULL;int output_parent=create_parent(stage,entry->path,&file_leaf,h->limits.max_entries+h->limits.max_directories+2);if(output_parent<0){int saved=errno;fail(h,"Cannot create safe staged member directory: %s (errno %d: %s)",entry->path,saved,strerror(saved));goto cleanup;}
        char temp[64];snprintf(temp,sizeof(temp),".zgta-part-%u",i);h->output_fd=openat(output_parent,temp,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);
        if(h->output_fd<0){free(file_leaf);close(output_parent);fail(h,"Cannot create new staged member");goto cleanup;}
        h->current_written=0;h->current_expected=entry->bytes;h->current_path=entry->path;int extracted=0;
        if(entry->source==ZGTA_INSTALLER_CAB){extracted=unshield_file_save(h->unshield,entry->index,"/output");clear_streams(h);}
        else {
            const IsoFile *file=&h->iso[entry->index];unsigned char buffer[65536];VirtualFile output={.owner=h,.output=1};extracted=1;
            for(uint64_t at=0;at<file->bytes;){size_t n=(size_t)(file->bytes-at);if(n>sizeof(buffer))n=sizeof(buffer);if(!read_at(h,buffer,n,file->offset+at)||io_write(buffer,1,n,&output,h)!=n){extracted=0;break;}at+=n;}
        }
        if(!extracted||stopped(h)||h->current_written!=entry->bytes||fsync(h->output_fd)){if(!h->error[0])fail(h,"Resource decompression/checksum/write failed: %s",entry->path);close(h->output_fd);h->output_fd=-1;unlinkat(output_parent,temp,0);free(file_leaf);close(output_parent);goto cleanup;}
        close(h->output_fd);h->output_fd=-1;
        if(renameat(output_parent,temp,output_parent,file_leaf)){fail(h,"Cannot commit staged member");unlinkat(output_parent,temp,0);free(file_leaf);close(output_parent);goto cleanup;}
        free(file_leaf);close(output_parent);h->job_done++;
        if(progress)progress(context,entry->path,h->job_written,total,h->job_done,count);
    }if(stopped(h))goto cleanup;result=ZGTA_INSTALLER_OK;
cleanup:h->progress=NULL;h->progress_context=NULL;h->current_path=NULL;if(h->output_fd>=0){close(h->output_fd);h->output_fd=-1;}if(stage>=0){if(result!=ZGTA_INSTALLER_OK)clear_directory(stage);close(stage);}if(result!=ZGTA_INSTALLER_OK)unlinkat(parent_fd,leaf,AT_REMOVEDIR);close(parent_fd);free(leaf);return atomic_load(&h->stop)?ZGTA_INSTALLER_CANCELLED:result;
}
