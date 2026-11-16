// SPDX-License-Identifier: AGPL-3.0-only
package main

/*
#include <stdint.h>
*/
import "C"

import "unsafe"

//export zgtasa_samp_abi_version
func zgtasa_samp_abi_version() C.uint32_t { return 1 }

//export zgtasa_samp_open
func zgtasa_samp_open(address *C.char, addressLength C.uint32_t, password *C.uint8_t, passwordLength C.uint32_t, timeoutMS C.uint32_t) C.uint64_t {
	if address == nil || addressLength == 0 || addressLength > 512 || passwordLength > 128 || (passwordLength > 0 && password == nil) {
		return 0
	}
	a := C.GoStringN(address, C.int(addressLength))
	p := ""
	if passwordLength > 0 {
		p = string(C.GoBytes(unsafe.Pointer(password), C.int(passwordLength)))
	}
	return C.uint64_t(bridge.open(a, p, uint32(timeoutMS)))
}

//export zgtasa_samp_send
func zgtasa_samp_send(handle C.uint64_t, data *C.uint8_t, length C.uint32_t, reliability C.uint32_t, channel C.uint32_t) C.int32_t {
	if data == nil || length == 0 || length > maxSendBytes {
		return errInput
	}
	return C.int32_t(bridge.send(uint64(handle), C.GoBytes(unsafe.Pointer(data), C.int(length)), uint32(reliability), uint32(channel)))
}
func copyResult(kind int, data []byte, length int, out *C.uint8_t, capacity C.uint32_t, required *C.uint32_t) C.int32_t {
	*required = C.uint32_t(length)
	if kind > 0 && length > 0 {
		copy(unsafe.Slice((*byte)(unsafe.Pointer(out)), int(capacity)), data)
	}
	return C.int32_t(kind)
}

//export zgtasa_samp_poll
func zgtasa_samp_poll(handle C.uint64_t, out *C.uint8_t, capacity C.uint32_t, required *C.uint32_t) C.int32_t {
	if required == nil || capacity > maxEventBytes || (capacity > 0 && out == nil) {
		return errInput
	}
	kind, data, length := bridge.poll(uint64(handle), int(capacity))
	return copyResult(kind, data, length, out, capacity, required)
}

//export zgtasa_samp_accepted
func zgtasa_samp_accepted(handle C.uint64_t, out *C.uint8_t, capacity C.uint32_t, required *C.uint32_t) C.int32_t {
	if required == nil || capacity > maxEventBytes || (capacity > 0 && out == nil) {
		return errInput
	}
	kind, data, length := bridge.accepted(uint64(handle), int(capacity))
	return copyResult(kind, data, length, out, capacity, required)
}

//export zgtasa_samp_close
func zgtasa_samp_close(handle C.uint64_t) { bridge.close(uint64(handle)) }
func main()                               {}
