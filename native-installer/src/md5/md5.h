/* SPDX-License-Identifier: AGPL-3.0-only
 * MD5 is required by the cabinet format, not used as a security identity.
 * Strong prepared-resource identity is verified separately by SHA-256. */
#ifndef ZGTA_MD5_COMPAT_H
#define ZGTA_MD5_COMPAT_H
#include <CommonCrypto/CommonDigest.h>
typedef CC_MD5_CTX MD5_CTX;
static inline void MD5Init(MD5_CTX *ctx){CC_MD5_Init(ctx);}
static inline void MD5Update(MD5_CTX *ctx,const unsigned char *data,unsigned int size){CC_MD5_Update(ctx,data,(CC_LONG)size);}
static inline void MD5Final(unsigned char *digest,MD5_CTX *ctx){CC_MD5_Final(digest,ctx);}
#endif
