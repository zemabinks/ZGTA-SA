#ifndef ZGTASA_SAMP_H
#define ZGTASA_SAMP_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/* ABI 1. All calls return promptly; network work runs on Go workers.
 * Inputs are copied during the call. No caller buffers or callbacks are retained.
 * Handles never repeat during a process lifetime. close removes a handle and
 * cancels it immediately; its background socket close is asynchronous.
 * One consumer should poll each handle. Event data is copied to caller memory.
 */
uint32_t zgtasa_samp_abi_version(void);
/* IPv4 hostname:port or IPv4:port, 1..512 UTF-8 bytes; password 0..128 bytes.
 * timeout:0 selects15s, otherwise100..60000ms for DNS/offline/accepted handshake.
 * Returns0 for invalid input/64-handle limit, otherwise an asynchronous handle.
 */
uint64_t zgtasa_samp_open(const char *address,uint32_t address_length,
                        const uint8_t *password,uint32_t password_length,uint32_t timeout_ms);
/* reliability6=unreliable,7=unreliable-sequenced,8=reliable,
 *9=reliable-ordered,10=reliable-sequenced. channel0..31, length1..8191.
 *0 queued; -1 invalid/terminal handle; -3 bad input; -4 full128-send queue.
 */
int32_t zgtasa_samp_send(uint64_t handle,const uint8_t *data,uint32_t length,
                       uint32_t reliability,uint32_t channel);
/*0 no event;1 accepted(raw ID34 packet);2 raw application packet, including
 * pre-accept auth(ID12) and RPC(ID20);3 terminal error(UTF-8, no trailing NUL).
 * -1 invalid handle;-2 insufficient capacity(event retained, required set);
 * -3 invalid input. required is mandatory; capacity0/out=NULL can query size.
 * Capacity/event maximum1MiB; queues bounded256events/4MiB, overflow is terminal.
 * An accepted event means RakNet accepted, not authenticated/spawned gameplay.
 */
int32_t zgtasa_samp_poll(uint64_t handle,uint8_t *out,uint32_t capacity,uint32_t *required);
/* Same buffer rules, snapshot retained:0 not accepted,1 available. */
int32_t zgtasa_samp_accepted(uint64_t handle,uint8_t *out,uint32_t capacity,uint32_t *required);
void zgtasa_samp_close(uint64_t handle);
#ifdef __cplusplus
}
#endif
#endif
