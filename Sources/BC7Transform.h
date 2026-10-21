#ifndef RETINALINK_BC7_TRANSFORM_H
#define RETINALINK_BC7_TRANSFORM_H
#include <stddef.h>
#include <stdint.h>
// Lossless, stateless tile transform. Buffers must be distinct and length bytes.
// Supported tile lengths are positive multiples of 128, up to 128 * 128 bytes.
int retinalink_bc7_transform(const uint8_t *source, uint8_t *destination, size_t length, int inverse);
#endif
