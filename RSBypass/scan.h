#ifndef RSBYPASS_SCAN_H
#define RSBYPASS_SCAN_H

#include <stddef.h>
#include <stdint.h>
#include <string.h>

/* Song signature check in the current Remastered x86_64 build:
 *   test r14b, r14b
 *   jz   +0xacf
 * NOPing the whole instruction lets execution fall through, which is the
 * same bypass the previous patch applied.
 */
static const uint8_t rs_pat_current[] = {
    0x45, 0x84, 0xF6, 0x0F, 0x84, 0xCF, 0x0A, 0x00, 0x00
};

/* Older Remastered builds used 84 db 0f 84 de 0a 00 00. That sequence is
 * short enough to match unrelated code, so it is not applied.
 */

/* Return a pointer to the first match, or NULL. Does not read past len. */
static inline const uint8_t *rs_find_bytes(const uint8_t *start, size_t len,
                                           const uint8_t *pat, size_t pat_len) {
    size_t i;
    if (start == NULL || pat == NULL || pat_len == 0 || len < pat_len)
        return NULL;
    for (i = 0; i + pat_len <= len; i++) {
        if (memcmp(start + i, pat, pat_len) == 0)
            return start + i;
    }
    return NULL;
}

#endif
