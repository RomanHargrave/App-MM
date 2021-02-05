#ifndef __OGG_CRC32_H
#define __OGG_CRC32_H

#ifdef _WIN32
#  define export __declspec(dllexport)
#else
#  define export extern
#endif

export uint32_t ogg_crc32(uint32_t, uint8_t*, size_t);

#endif
