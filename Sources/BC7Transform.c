#include "BC7Transform.h"
#include <string.h>

// Transpose an 8x8 bit matrix. Applying this permutation twice is the identity.
static uint64_t transpose(uint64_t x) {
    uint64_t t = (x ^ (x >> 7)) & UINT64_C(0x00AA00AA00AA00AA); x ^= t ^ (t << 7);
    t = (x ^ (x >> 14)) & UINT64_C(0x0000CCCC0000CCCC); x ^= t ^ (t << 14);
    t = (x ^ (x >> 28)) & UINT64_C(0x00000000F0F0F0F0); x ^= t ^ (t << 28);
    return x;
}

int retinalink_bc7_transform(const uint8_t *source, uint8_t *destination, size_t length, int inverse) {
    if (!source || !destination || source == destination || !length || length > 16384 || length % 128) return 0;
    uint8_t delta[16384];
    const size_t blocks = length / 16, plane = blocks / 8;
    if (!inverse) {
        // BC7 blocks have two 64-bit words. Modulo differences retain every bit,
        // including modes, alpha and palette indices; no BC7 mode is assumed.
        uint64_t previous[2] = {0, 0};
        for (size_t i = 0; i < blocks; ++i) {
            for (size_t word = 0; word < 2; ++word) {
                uint64_t value, difference;
                memcpy(&value, source + i * 16 + word * 8, 8);
                difference = value - previous[word]; previous[word] = value;
                memcpy(delta + i * 16 + word * 8, &difference, 8);
            }
        }
        // Give LZ4 contiguous bit planes instead of interleaved BC7 fields.
        for (size_t byte = 0; byte < 16; ++byte) {
            for (size_t i = 0; i < blocks; i += 8) {
                uint64_t matrix = 0;
                for (size_t j = 0; j < 8; ++j) matrix |= (uint64_t)delta[(i + j) * 16 + byte] << (j * 8);
                matrix = transpose(matrix);
                for (size_t bit = 0; bit < 8; ++bit) destination[(byte * 8 + bit) * plane + i / 8] = (uint8_t)(matrix >> (bit * 8));
            }
        }
    } else {
        for (size_t byte = 0; byte < 16; ++byte) {
            for (size_t i = 0; i < blocks; i += 8) {
                uint64_t matrix = 0;
                for (size_t bit = 0; bit < 8; ++bit) matrix |= (uint64_t)source[(byte * 8 + bit) * plane + i / 8] << (bit * 8);
                matrix = transpose(matrix);
                for (size_t j = 0; j < 8; ++j) delta[(i + j) * 16 + byte] = (uint8_t)(matrix >> (j * 8));
            }
        }
        uint64_t previous[2] = {0, 0};
        for (size_t i = 0; i < blocks; ++i) {
            for (size_t word = 0; word < 2; ++word) {
                uint64_t difference;
                memcpy(&difference, delta + i * 16 + word * 8, 8);
                previous[word] += difference;
                memcpy(destination + i * 16 + word * 8, &previous[word], 8);
            }
        }
    }
    return 1;
}
