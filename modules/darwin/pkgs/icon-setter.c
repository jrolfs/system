#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/xattr.h>
#include <unistd.h>

static void put32(unsigned char *pointer, uint32_t value) {
    pointer[0] = (value >> 24) & 0xff;
    pointer[1] = (value >> 16) & 0xff;
    pointer[2] = (value >>  8) & 0xff;
    pointer[3] =  value        & 0xff;
}

static void put16(unsigned char *pointer, uint16_t value) {
    pointer[0] = (value >> 8) & 0xff;
    pointer[1] =  value       & 0xff;
}

/* Clear kHasCustomIcon (0x0400) in FinderInfo.  Used on failure paths so a
 * bundle is never left advertising a custom icon it no longer has — that
 * combination is what makes Finder fall back to the generic folder icon. */
static void clear_custom_icon_flag(const char *app_path) {
    unsigned char finder_info[32] = {0};
    if (getxattr(app_path, "com.apple.FinderInfo", finder_info, 32, 0, 0) > 0 &&
        (finder_info[8] & 0x04)) {
        finder_info[8] &= ~0x04;
        setxattr(app_path, "com.apple.FinderInfo", finder_info, 32, 0, 0);
    }
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: icon-setter APP_PATH ICON_PATH\n");
        return 1;
    }

    const char *app_path  = argv[1];
    const char *icon_path = argv[2];

    fprintf(stdout, "icon_path: %s\n", icon_path);
    fprintf(stdout, "app_path: %s\n", app_path);

  /* Verify app bundle exists */
    struct stat status;

    if (stat(app_path, &status) != 0 || !S_ISDIR(status.st_mode)) {
        fprintf(stderr, "not a directory: %s\n", app_path);
        return 1;
    }

    /* Read icon file */
    FILE *file = fopen(icon_path, "rb");
    if (!file) {
        fprintf(stderr, "cannot open: %s (%s)\n", icon_path, strerror(errno));
        return 1;
    }

    fseek(file, 0, SEEK_END);
    long raw_size = ftell(file);
    fseek(file, 0, SEEK_SET);

    if (raw_size < 8) {
        fprintf(stderr, "icon too small: %s\n", icon_path);
        fclose(file);
        return 1;
    }

    unsigned char *raw_data = malloc(raw_size);

    if (!raw_data || fread(raw_data, 1, raw_size, file) != (size_t)raw_size) {
        fprintf(stderr, "read failed: %s (%s)\n", icon_path, strerror(errno));
        fclose(file); free(raw_data);
        return 1;
    }

    fclose(file);

    /* Determine format and get icns data.
     * - .icns files are used directly.
     * - .png  files are wrapped in a minimal icns container (one ic10
     *   entry) so macOS can render them at any size.
     */
    unsigned char *icns_data;
    size_t icns_size;

    if (raw_size >= 4 && memcmp(raw_data, "icns", 4) == 0) {
        icns_data = raw_data;
        icns_size = (size_t)raw_size;
    } else if (raw_size >= 8 &&
               raw_data[0] == 0x89 && raw_data[1] == 0x50 &&
               raw_data[2] == 0x4e && raw_data[3] == 0x47) {
        /* PNG: wrap in icns container with ic10 type */
        uint32_t entry_length = 8 + (uint32_t)raw_size;

        icns_size = 8 + entry_length;
        icns_data = malloc(icns_size);

        if (!icns_data) { free(raw_data); return 1; }

        memcpy(icns_data,      "icns", 4);
        put32(icns_data + 4,   (uint32_t)icns_size);
        memcpy(icns_data + 8,  "ic10", 4);
        put32(icns_data + 12,  entry_length);
        memcpy(icns_data + 16, raw_data, raw_size);

        free(raw_data);
    } else {
        fprintf(stderr, "unsupported format: %s\n", icon_path);
        free(raw_data);
        return 1;
    }

    /* Build paths for Icon\r and its resource fork */
    size_t app_length = strlen(app_path);
    char *icon_file_path = malloc(app_length + 8);
    char *resource_fork_path = malloc(app_length + 32);

    sprintf(icon_file_path, "%s/Icon\r", app_path);
    sprintf(resource_fork_path, "%s/Icon\r/..namedfork/rsrc", app_path);

    /*
     * Create (or truncate) Icon\r.  We deliberately do NOT unlink first.
     *
     * Deleting the existing icon and only then discovering we cannot
     * rewrite it is exactly what leaves a bundle with kHasCustomIcon set
     * but no Icon\r — the generic folder icon.  That happens on
     * com.apple.macl'd bundles when the process lacks Full Disk Access:
     * the unlink succeeds but the recreate fails with EPERM.
     *
     * Opening with O_TRUNC is non-destructive on failure — if it fails we
     * bail with the existing icon intact.  The one case O_TRUNC can't
     * handle is an Icon\r left root-owned by the old root LaunchDaemon,
     * which fails with EACCES; there, removing and recreating IS safe
     * because the bundle directory itself is user-writable.
     */
    int fd = open(icon_file_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0 && errno == EACCES && unlink(icon_file_path) == 0) {
        fd = open(icon_file_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    }
    if (fd < 0) {
        fprintf(stderr, "cannot create Icon\\r in %s: %s\n",
                app_path, strerror(errno));
        free(icns_data); free(icon_file_path); free(resource_fork_path);
        return 1;
    }
    close(fd);

    /*
     * Build the resource fork for a single 'icns' resource (ID -16455).
     *
     * Layout:  256-byte header  |  data section  |  resource map
     *
     * Data section : 4-byte big-endian length + raw icns bytes
     * Resource map (50 bytes):
     *   0-15   copy of header
     *  16-19   reserved handle
     *  20-21   file reference number
     *  22-23   attributes
     *  24-25   type list offset from map start  (28)
     *  26-27   name list offset from map start  (50)
     *  28-29   type count - 1                   (0)
     *  30-33   type  'icns'
     *  34-35   resource count - 1               (0)
     *  36-37   ref list offset from type list   (10)
     *  38-39   resource ID                      (-16455 / 0xBFB9)
     *  40-41   name offset                      (0xFFFF = none)
     *  42      attributes                       (0)
     *  43-45   data offset from data section    (0)
     *  46-49   reserved                         (0)
     */
    uint32_t data_offset = 256;
    uint32_t data_length = (uint32_t)icns_size + 4;
    uint32_t map_offset = data_offset + data_length;
    uint32_t map_length = 50;
    size_t   total_size = data_offset + data_length + map_length;

    unsigned char *buffer = calloc(1, total_size);
    if (!buffer) {
        free(icns_data); free(icon_file_path); free(resource_fork_path);
        return 1;
    }

    /* Header */
    put32(buffer + 0,  data_offset);
    put32(buffer + 4,  map_offset);
    put32(buffer + 8,  data_length);
    put32(buffer + 12, map_length);

    /* Data section */
    put32(buffer + data_offset, (uint32_t)icns_size);
    memcpy(buffer + data_offset + 4, icns_data, icns_size);
    free(icns_data);

    /* Resource map */
    unsigned char *map = buffer + map_offset;
    memcpy(map, buffer, 16);           /* reserved header copy  */
    put16(map + 24, 28);              /* type list offset      */
    put16(map + 26, map_length);      /* name list offset      */
    put16(map + 28, 0);               /* 1 type  - 1           */
    map[30]='i'; map[31]='c'; map[32]='n'; map[33]='s';
    put16(map + 34, 0);               /* 1 resource - 1        */
    put16(map + 36, 10);              /* ref list from tl      */
    put16(map + 38, 0xBFB9);          /* ID = -16455           */
    put16(map + 40, 0xFFFF);          /* no name               */

    /* Write resource fork */
    fd = open(resource_fork_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);

    if (fd < 0) {
        fprintf(stderr, "cannot write resource fork for %s: %s\n",
                app_path, strerror(errno));
        unlink(icon_file_path);
        clear_custom_icon_flag(app_path);
        free(buffer); free(icon_file_path); free(resource_fork_path);
        return 1;
    }

    if (write(fd, buffer, total_size) != (ssize_t)total_size) {
        fprintf(stderr, "short write for %s: %s\n",
                app_path, strerror(errno));
        close(fd);
        unlink(icon_file_path);
        clear_custom_icon_flag(app_path);
        free(buffer); free(icon_file_path); free(resource_fork_path);
        return 1;
    }

    close(fd);
    free(buffer);

    /* Hide Icon\r */
    if (stat(icon_file_path, &status) == 0)
        chflags(icon_file_path, status.st_flags | UF_HIDDEN);
    free(icon_file_path);
    free(resource_fork_path);

    /* Set kHasCustomIcon (0x0400) in FinderInfo */
    unsigned char finder_info[32] = {0};
    getxattr(app_path, "com.apple.FinderInfo", finder_info, 32, 0, 0);
    finder_info[8] |= 0x04;
    if (setxattr(app_path, "com.apple.FinderInfo", finder_info, 32, 0, 0) != 0) {
        fprintf(stderr, "cannot set FinderInfo for %s: %s\n",
                app_path, strerror(errno));
        return 1;
    }

    /* Touch the app so Finder refreshes */
    utimes(app_path, NULL);

    return 0;
}
