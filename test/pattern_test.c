#include <stdio.h>
#include <string.h>

#include "../RSBypass/scan.h"

static int g_failed = 0;

static void expect(int cond, const char *msg) {
    if (!cond) {
        fprintf(stderr, "FAIL: %s\n", msg);
        g_failed = 1;
    }
}

int main(void) {
    uint8_t buf[64];
    const uint8_t *found;

    memset(buf, 0x11, sizeof buf);
    expect(rs_find_bytes(buf, sizeof buf, rs_pat_current, sizeof rs_pat_current) == NULL,
           "absent pattern");

    memcpy(buf + 7, rs_pat_current, sizeof rs_pat_current);
    found = rs_find_bytes(buf, sizeof buf, rs_pat_current, sizeof rs_pat_current);
    expect(found == buf + 7, "pattern at offset 7");

    memset(buf, 0x22, sizeof buf);
    memcpy(buf + sizeof buf - sizeof rs_pat_current, rs_pat_current, sizeof rs_pat_current);
    found = rs_find_bytes(buf, sizeof buf, rs_pat_current, sizeof rs_pat_current);
    expect(found == buf + sizeof buf - sizeof rs_pat_current, "pattern at end");
    expect(rs_find_bytes(buf, sizeof buf - 1, rs_pat_current, sizeof rs_pat_current) == NULL,
           "truncated tail is not a match");

    buf[sizeof buf - 1] ^= 0xff;
    expect(rs_find_bytes(buf, sizeof buf, rs_pat_current, sizeof rs_pat_current) == NULL,
           "one-byte difference");

    expect(sizeof rs_pat_current == 9, "current pattern is 9 bytes");
    expect(rs_find_bytes(NULL, 9, rs_pat_current, 9) == NULL, "null buffer");

    if (g_failed)
        return 1;
    printf("pattern tests ok\n");
    return 0;
}
