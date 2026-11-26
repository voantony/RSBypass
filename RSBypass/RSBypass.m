#include <errno.h>
#include <sys/mman.h>
#include <unistd.h>

#include <mach/mach.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>

#import "RSBypass.h"
#include "scan.h"

/* Rocksmith 2014 is an x86_64 process, including under Rosetta 2.
 * _dyld_get_image_header() is the supported way to find that image.
 * task_info(TASK_DYLD_INFO) plus dyld_all_image_infos->aotInfoArray is not:
 * aotInfoArray is the Rosetta translation table, it is often NULL, and on
 * current dyld the legacy infoArray can be NULL as well. Dereferencing it
 * crashed the game (segfault on launch). The old scan length 0x013CE9BC1
 * was also one nibble too long and walked off the mapped image.
 */

static int rs_make_writable(void *addr, size_t len) {
    long page = sysconf(_SC_PAGESIZE);
    uintptr_t start;
    uintptr_t end;
    vm_address_t region;
    vm_size_t size;
    kern_return_t kr;

    if (page < 4096)
        page = 4096;
    start = (uintptr_t)addr & ~((uintptr_t)page - 1);
    end = ((uintptr_t)addr + len + (uintptr_t)page - 1) & ~((uintptr_t)page - 1);
    region = (vm_address_t)start;
    size = (vm_size_t)(end - start);

    /* VM_PROT_COPY detaches a signed page so it can be written.
     * W^X means the page must not be executable at the same time.
     */
    kr = vm_protect(mach_task_self(), region, size, FALSE,
                    VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    if (kr == KERN_SUCCESS)
        return 1;
    if (mprotect((void *)start, (size_t)size, PROT_READ | PROT_WRITE) == 0)
        return 1;

    NSLog(@"RSBypass: cannot make %p (%lu bytes) writable: vm_protect %d, mprotect %s",
          addr, (unsigned long)len, kr, strerror(errno));
    return 0;
}

static void rs_make_executable(void *addr, size_t len) {
    long page = sysconf(_SC_PAGESIZE);
    uintptr_t start;
    uintptr_t end;
    vm_size_t size;

    if (page < 4096)
        page = 4096;
    start = (uintptr_t)addr & ~((uintptr_t)page - 1);
    end = ((uintptr_t)addr + len + (uintptr_t)page - 1) & ~((uintptr_t)page - 1);
    size = (vm_size_t)(end - start);

    if (mprotect((void *)start, (size_t)size, PROT_READ | PROT_EXEC) != 0) {
        NSLog(@"RSBypass: mprotect RX failed (%s); trying vm_protect", strerror(errno));
        vm_protect(mach_task_self(), (vm_address_t)start, size, FALSE,
                   VM_PROT_READ | VM_PROT_EXECUTE);
    }
}

static int rs_patch_at(uint8_t *site, size_t len) {
    if (!rs_make_writable(site, len))
        return 0;
    NSLog(@"RSBypass: bypassing signature check at %p (%lu bytes)", site, (unsigned long)len);
    memset(site, 0x90, len);
    msync(site, len, MS_SYNC);
    rs_make_executable(site, len);
    return 1;
}

static const struct mach_header_64 *rs_game_header(uint32_t *index_out) {
    uint32_t count = _dyld_image_count();
    uint32_t i;
    const struct mach_header_64 *fallback = NULL;
    uint32_t fallback_index = 0;

    for (i = 0; i < count; i++) {
        const struct mach_header *header = _dyld_get_image_header(i);
        const char *name;

        if (header == NULL || header->magic != MH_MAGIC_64)
            continue;
        if (fallback == NULL) {
            fallback = (const struct mach_header_64 *)header;
            fallback_index = i;
        }
        name = _dyld_get_image_name(i);
        if (name != NULL && strstr(name, "Rocksmith2014") != NULL &&
            strstr(name, "RSBypass") == NULL) {
            NSLog(@"RSBypass: game image %s", name);
            if (index_out)
                *index_out = i;
            return (const struct mach_header_64 *)header;
        }
    }

    if (fallback != NULL) {
        const char *name = _dyld_get_image_name(fallback_index);
        NSLog(@"RSBypass: Rocksmith2014 image not named; scanning %s",
              name != NULL ? name : "(unknown)");
        if (index_out)
            *index_out = fallback_index;
    }
    return fallback;
}

static int rs_scan_image(const struct mach_header_64 *header, intptr_t slide,
                         const uint8_t *pat, size_t pat_len) {
    const uint8_t *cmds;
    const uint8_t *cmds_end;
    uint32_t i;

    if (header->sizeofcmds == 0 || header->sizeofcmds > (1u << 20) || header->ncmds > 4096)
        return 0;

    cmds = (const uint8_t *)header + sizeof(*header);
    cmds_end = cmds + header->sizeofcmds;

    for (i = 0; i < header->ncmds; i++) {
        const struct load_command *lc;
        const struct segment_command_64 *seg;
        const uint8_t *start;
        const uint8_t *found;

        if (cmds + sizeof(struct load_command) > cmds_end)
            break;
        lc = (const struct load_command *)cmds;
        if (lc->cmdsize < sizeof(struct load_command) || cmds + lc->cmdsize > cmds_end)
            break;

        if (lc->cmd == LC_SEGMENT_64) {
            seg = (const struct segment_command_64 *)lc;
            /* Executable segments only. filesize is the mapped initialized
             * range; vmsize can extend into unmapped zero-fill.
             */
            if ((seg->initprot & VM_PROT_EXECUTE) != 0 &&
                seg->filesize >= pat_len &&
                seg->filesize <= (96ull << 20)) {
                start = (const uint8_t *)((uintptr_t)seg->vmaddr + (uintptr_t)slide);
                found = rs_find_bytes(start, (size_t)seg->filesize, pat, pat_len);
                if (found != NULL)
                    return rs_patch_at((uint8_t *)found, pat_len);
            }
        }
        cmds += lc->cmdsize;
    }
    return 0;
}

static int rs_try_patch(void) {
    uint32_t index = 0;
    const struct mach_header_64 *header = rs_game_header(&index);
    intptr_t slide;

    if (header == NULL) {
        NSLog(@"RSBypass: no 64-bit image to scan");
        return 0;
    }

    slide = _dyld_get_image_vmaddr_slide(index);
    NSLog(@"RSBypass: header %p slide %ld", header, (long)slide);

    if (rs_scan_image(header, slide, rs_pat_current, sizeof rs_pat_current)) {
        NSLog(@"RSBypass: patched");
        return 1;
    }

    NSLog(@"RSBypass: signature check pattern not found. The game binary may have changed.");
    return 0;
}

static void rsbypass_apply(void) {
    static int patched = 0;
    if (patched)
        return;
    NSLog(@"RSBypass: load()");
    if (rs_try_patch())
        patched = 1;
}

@implementation RSBypass
+ (void)load
{
    rsbypass_apply();
}
@end

__attribute__((constructor))
static void rsbypass_constructor(void) {
    rsbypass_apply();
}
