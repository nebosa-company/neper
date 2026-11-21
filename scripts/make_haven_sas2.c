// Writes the SAS7BDAT test files of tests/data/haven that no real SAS file covers: row-compressed (SASYZCRL) 64-bit and 32-bit
// files, an uncompressed 64-bit file. It is ReadStat's own writer (the source vendored in haven's tarball),
// so haven's reader is the oracle for what comes out. Build and run (zig cc, iconv stubbed because the writer converts nothing):
//   zig cc -O1 -I<stub dir with an iconv.h that only declares iconv_t> -I<haven>/src/readstat scripts/make_haven_sas2.c
//     <haven>/src/readstat/{readstat_writer,readstat_variable,readstat_value,readstat_error,readstat_malloc,readstat_metadata,
//     readstat_convert,readstat_bits,CKHashTable}.c <haven>/src/readstat/sas/{readstat_sas,readstat_sas7bdat_write,
//     readstat_sas_rle}.c -o make_haven_sas2.exe
//   make_haven_sas2.exe tests/data/haven
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "readstat.h"

static ssize_t write_cb(const void *data, size_t len, void *ctx) { return fwrite(data, 1, len, (FILE *)ctx); }

#define N 300

static void fill_text(char *s, int width, int i) {
    memset(s, 0, 512);
    int m = i % 8;
    if (m == 0) { memset(s, 'a', width); }
    else if (m == 1) { strcpy(s, "hello world"); }
    else if (m == 2) { memset(s, ' ', 20); memset(s + 20, 'q', 30); if (width > 80) { memset(s + 50, '@', 5); strcpy(s + 55, "tail"); } }
    else if (m == 3) { strcpy(s, ""); }
    else if (m == 4) { for (int k = 0; k < width && k < 90; k++) s[k] = "abcabcabcxyz"[k % 12]; }
    else if (m == 5) { memset(s, 'z', 3); strcpy(s + 3, "-abc-"); memset(s + 8, 'z', 40); }
    else if (m == 6) { memset(s, '0', 17); memset(s + 17, 'b', 130 < width ? 130 : width - 17); }
    else { snprintf(s, 40, "row %d value", i); }
    if ((int)strlen(s) > width) s[width] = 0;
}

static void write_data(const char *path, readstat_compress_t comp, int is64, readstat_label_set_t **sets_out, int with_sets) {
    FILE *fp = fopen(path, "wb");
    readstat_writer_t *w = readstat_writer_init();
    readstat_set_data_writer(w, write_cb);
    readstat_writer_set_compression(w, comp);
    readstat_writer_set_file_format_is_64bit(w, is64);
    readstat_writer_set_table_name(w, "TESTDATA");
    readstat_writer_set_file_label(w, "ReadStat test");
    readstat_writer_set_file_timestamp(w, 1700000000);
    readstat_variable_t *vid = readstat_add_variable(w, "id", READSTAT_TYPE_DOUBLE, 0);
    readstat_variable_set_label(vid, "Row id");
    readstat_variable_t *vx = readstat_add_variable(w, "x", READSTAT_TYPE_DOUBLE, 0);
    readstat_variable_set_format(vx, "BEST12.");
    readstat_variable_t *vz = readstat_add_variable(w, "zeros", READSTAT_TYPE_DOUBLE, 0);
    readstat_variable_t *vb = readstat_add_variable(w, "big", READSTAT_TYPE_DOUBLE, 0);
    readstat_variable_set_format(vb, "COMMA20.2");
    readstat_variable_t *v3 = readstat_add_variable(w, "s3", READSTAT_TYPE_STRING, 3);
    readstat_variable_t *v60 = readstat_add_variable(w, "s60", READSTAT_TYPE_STRING, 60);
    readstat_variable_set_label(v60, "Sixty wide text");
    readstat_variable_t *v300 = readstat_add_variable(w, "s300", READSTAT_TYPE_STRING, 300);
    readstat_variable_t *vd = readstat_add_variable(w, "d", READSTAT_TYPE_DOUBLE, 0);
    readstat_variable_set_format(vd, "DATE9.");
    readstat_variable_set_label(vd, "A date");
    readstat_variable_t *vl = readstat_add_variable(w, "lev", READSTAT_TYPE_DOUBLE, 0);
    readstat_variable_set_format(vl, "LEVF");
    readstat_variable_t *vc = readstat_add_variable(w, "chr", READSTAT_TYPE_STRING, 4);
    readstat_variable_set_format(vc, "$CHRF");
    readstat_begin_writing_sas7bdat(w, fp, N);
    char buf[512];
    for (int i = 1; i <= N; i++) {
        readstat_begin_row(w);
        readstat_insert_double_value(w, vid, i);
        if (i % 17 == 0) readstat_insert_missing_value(w, vx); else readstat_insert_double_value(w, vx, round(sin(i * 0.37) * 100000.0) / 100.0);
        if (i % 29 == 0) readstat_insert_double_value(w, vz, i); else readstat_insert_double_value(w, vz, 0.0);
        readstat_insert_double_value(w, vb, i * 1e9 + 0.5);
        const char *three[] = {"abc", "", "xyz"};
        readstat_insert_string_value(w, v3, three[i % 3]);
        fill_text(buf, 60, i);
        readstat_insert_string_value(w, v60, buf);
        fill_text(buf, 300, i);
        readstat_insert_string_value(w, v300, buf);
        readstat_insert_double_value(w, vd, 20000 + i * 3);
        if (i % 11 == 0) readstat_insert_tagged_missing_value(w, vl, 'B'); else readstat_insert_double_value(w, vl, 1 + i % 3);
        const char *cs[] = {"a", "b", "ccc", "zz"};
        readstat_insert_string_value(w, vc, cs[i % 4]);
        readstat_end_row(w);
    }
    readstat_end_writing(w);
    readstat_writer_free(w);
    fclose(fp);
}

int main(int argc, char **argv) {
    const char *dir = argc > 1 ? argv[1] : ".";
    char p[1024];
    snprintf(p, sizeof p, "%s/rle64.sas7bdat", dir);
    write_data(p, READSTAT_COMPRESS_ROWS, 1, NULL, 0);
    snprintf(p, sizeof p, "%s/rle32.sas7bdat", dir);
    write_data(p, READSTAT_COMPRESS_ROWS, 0, NULL, 0);
    snprintf(p, sizeof p, "%s/raw64.sas7bdat", dir);
    write_data(p, READSTAT_COMPRESS_NONE, 1, NULL, 0);
    return 0;
}
