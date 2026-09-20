#define MINIMP3_IMPLEMENTATION
#define MINIMP3_NO_SIMD
#include "minimp3.h"
#include <stdio.h>
#include <stdlib.h>
/* decode a whole file to raw s16le; usage: refdec in.mp3 out.pcm */
int main(int argc, char **argv) {
    FILE *f = fopen(argv[1], "rb"); fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    unsigned char *buf = malloc(n); fread(buf, 1, n, f); fclose(f);
    FILE *o = fopen(argv[2], "wb");
    mp3dec_t dec; mp3dec_init(&dec); mp3dec_frame_info_t info; short pcm[MINIMP3_MAX_SAMPLES_PER_FRAME];
    long at = 0; int frames = 0;
    while (at < n) {
        int samples = mp3dec_decode_frame(&dec, buf + at, (int)(n - at), pcm, &info);
        if (info.frame_bytes == 0) break;
        at += info.frame_bytes;
        if (samples) { fwrite(pcm, 2, samples * info.channels, o); frames++; }
    }
    fprintf(stderr, "frames %d hz %d ch %d\n", frames, info.hz, info.channels);
    fclose(o); return 0;
}
