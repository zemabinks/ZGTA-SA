/* SPDX-License-Identifier: AGPL-3.0-only */
#ifndef ZGTASA_INSTALLER_H
#define ZGTASA_INSTALLER_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct zgta_installer zgta_installer;
typedef int (*zgta_installer_cancelled)(void *context);
typedef void (*zgta_installer_progress)(void *context,const char *relative_path,uint64_t completed_bytes,uint64_t total_bytes,uint32_t completed_files,uint32_t total_files);
typedef struct {
    uint32_t max_entries,max_directories,max_metadata_bytes;
    uint64_t max_file_bytes,max_output_bytes,max_input_bytes;
} zgta_installer_limits;
typedef struct {const char *path;const char *group;uint64_t bytes;int source;} zgta_installer_entry;
typedef struct {uint64_t iso_bytes_read,output_bytes_written,max_read_request;} zgta_installer_statistics;
enum {ZGTA_INSTALLER_CAB=1,ZGTA_INSTALLER_LOOSE=2};
enum {ZGTA_INSTALLER_OK=0,ZGTA_INSTALLER_FAILED=-1,ZGTA_INSTALLER_CANCELLED=-2};
zgta_installer_limits zgta_installer_default_limits(void);
/* Metadata only; source is opened O_RDONLY. Call serially per handle. The
 * cancellation callback/zgta_installer_cancel may run on another thread. */
zgta_installer *zgta_installer_open_iso(const char *iso_path,const zgta_installer_limits *limits,zgta_installer_cancelled cancelled,void *context,char *error,size_t error_capacity);
void zgta_installer_close(zgta_installer *handle);
void zgta_installer_cancel(zgta_installer *handle);
uint32_t zgta_installer_entry_count(const zgta_installer *handle);
int zgta_installer_get_entry(const zgta_installer *handle,uint32_t index,zgta_installer_entry *entry);
/* Creates a NEW stage directory; it refuses existing destinations. Only the
 * selected catalogue paths can be written. No active installation is touched.
 * Failure/cancellation removes this new stage; extraction is NOT conversion. */
int zgta_installer_extract(zgta_installer *handle,const uint32_t *indices,uint32_t count,const char *new_stage_directory,zgta_installer_progress progress,void *context);
const char *zgta_installer_error(const zgta_installer *handle);
zgta_installer_statistics zgta_installer_stats(const zgta_installer *handle);
/* The same strict path check used for archive member destination preflight. */
int zgta_installer_valid_relative_path(const char *path);
#ifdef __cplusplus
}
#endif
#endif
