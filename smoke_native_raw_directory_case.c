/* SPDX-License-Identifier: AGPL-3.0-only */
#define _DARWIN_C_SOURCE 1
#include <sys/stat.h>
#include <sys/types.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
/* Replay the observed split between an existing directory and an alternate-
 * case descriptor lookup, with authored names only. Other calls use real FDs. */
static int fixture_mode,scans,duplicate_pending,checks;
static int fixture_mkdirat(int parent,const char *name,mode_t mode){
 if(!strcmp(name,"ASSET")&&fixture_mode){errno=fixture_mode==3?EACCES:EEXIST;return -1;}
 return mkdirat(parent,name,mode);
}
static int fixture_openat(int parent,const char *name,int flags,...){
 mode_t mode=0;if(flags&O_CREAT){va_list args;va_start(args,flags);mode=(mode_t)va_arg(args,int);va_end(args);}
 if(!strcmp(name,".")&&(flags&O_DIRECTORY))scans++;
 if(!strcmp(name,"ASSET")&&fixture_mode){errno=fixture_mode==2?EACCES:ENOENT;return -1;}
 return flags&O_CREAT?openat(parent,name,flags,mode):openat(parent,name,flags);
}
static struct dirent *fixture_readdir(DIR *directory){
 static struct dirent invented;
 if(duplicate_pending){duplicate_pending=0;memset(&invented,0,sizeof(invented));strcpy(invented.d_name,"aSsEt");return &invented;}
 struct dirent *entry=readdir(directory);
 if(fixture_mode==4&&entry&&!strcmp(entry->d_name,"asset"))duplicate_pending=1;
 return entry;
}
#define mkdirat fixture_mkdirat
#define openat fixture_openat
#define readdir fixture_readdir
#ifdef HISTORICAL
#define create_parent historical_create_parent
#endif
#include "production.c"
#ifdef HISTORICAL
#undef create_parent
/* Interface only. The old traversal still receives no alias recovery. */
static int create_parent(int root,const char *path,char **leaf,uint32_t limit){(void)limit;return historical_create_parent(root,path,leaf);}
static int open_existing_child_directory(int root,const char *name,int existed,uint32_t limit){(void)existed;(void)limit;return fixture_openat(root,name,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);}
#endif
#undef mkdirat
#undef openat
#undef readdir
static void check(int value,const char *message){checks++;if(!value){fprintf(stderr,"FAIL %d %s (errno=%d)\n",checks,message,errno);exit(2);}}
static int fd_count(void){int result=0;for(int fd=0;fd<512;fd++)if(fcntl(fd,F_GETFD)>=0)result++;return result;}
static int child(int root,const char *path,uint32_t limit){char *leaf=NULL;duplicate_pending=0;int fd=create_parent(root,path,&leaf,limit);if(fd>=0)check(leaf&&!strcmp(leaf,"child.txt"),"leaf identity changed");free(leaf);return fd;}
int main(int argc,char **argv){
 check(argc==2,"authored temporary root required");
 check(mkdir(argv[1],0700)==0,"exclusive test root");
 int root=open(argv[1],O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);check(root>=0,"test root descriptor");
 check(mkdirat(root,"asset",0700)==0,"authored lower-case directory");
 int baseline=fd_count();fixture_mode=1;scans=0;
 int result=child(root,"ASSET/child.txt",1000);check(result>=0,"existing case alias was rejected");
 struct stat expected,actual;check(fstatat(root,"asset",&expected,AT_SYMLINK_NOFOLLOW)==0&&fstat(result,&actual)==0&&expected.st_dev==actual.st_dev&&expected.st_ino==actual.st_ino,"alias did not name exact existing directory");close(result);
 check(scans>0,"observed alternate-case failure was not exercised");
 for(int i=0;i<64;i++){result=child(root,"ASSET/child.txt",1000);check(result>=0,"repeated alias admission failed");close(result);}
 check(fd_count()==baseline,"directory scan leaked descriptors");
 fixture_mode=2;scans=0;result=child(root,"ASSET/child.txt",1000);check(result<0&&errno==EACCES&&scans==0,"permission failure became alias recovery");
 fixture_mode=3;scans=0;result=child(root,"ASSET/child.txt",1000);check(result<0&&errno==EACCES&&scans==0,"mkdir permission failure became recovery");
 fixture_mode=4;result=child(root,"ASSET/child.txt",1000);check(result<0&&errno==EEXIST,"ambiguous authored directory enumeration admitted");
 fixture_mode=1;result=child(root,"ASSET/child.txt",1);check(result<0&&errno==E2BIG,"directory scan limit ignored");
 scans=0;result=open_existing_child_directory(root,"ASSET",0,1000);check(result<0&&errno==ENOENT&&scans==0,"new-directory failure silently borrowed alias");
 result=open_existing_child_directory(root,"UNKNOWN",1,1000);check(result<0&&errno==ENOENT,"absent alias invented a directory");
 check(renameat(root,"asset",root,"kept-asset")==0,"retain authored directory");
 int file=openat(root,"asset",O_CREAT|O_EXCL|O_WRONLY|O_NOFOLLOW,0600);check(file>=0,"authored regular file");close(file);
 result=child(root,"ASSET/child.txt",1000);check(result<0&&errno==ENOTDIR,"regular file admitted as directory");
 check(unlinkat(root,"asset",0)==0,"remove authored regular file");check(mkdirat(root,"outside",0700)==0,"authored forbidden target");
 check(symlinkat("outside",root,"asset")==0,"authored linked alias");
 result=child(root,"ASSET/child.txt",1000);check(result<0&&(errno==ELOOP||errno==ENOTDIR),"case alias followed a symlink");
 check(unlinkat(root,"asset",0)==0&&renameat(root,"kept-asset",root,"asset")==0,"restore authored directory");
 fixture_mode=0;scans=0;result=child(root,"new/fresh/child.txt",1000);check(result>=0&&scans==0,"ordinary exact-case creation changed");close(result);
 result=child(root,"asset/child.txt",1000);check(result>=0&&scans==0,"ordinary existing-directory lookup changed");close(result);
 check(fd_count()==baseline,"failure path leaked descriptors");close(root);
 printf("PASS %d authored descriptor/case/symlink/permission/ambiguity/bound checks; no original files or app state\n",checks);return 0;
}
