// C Testbench for Stencil Computation 2020-03-13 Naoki F., AIT
// ライセンス条件は LICENSE.txt を参照してください

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include "xparameters.h"
#include "xil_printf.h"
#include "xil_cache.h"
#include "xtime_l.h"

#define N 512
#define ITER 100
unsigned int buf1[N][N], buf2[N][N];

// IPのメモリマップドレジスタ
#define STENCIL_GO      (*(volatile unsigned int *) (XPAR_STENCIL_TOP_0_BASEADDR + 0x0))
#define STENCIL_DONE    (*(volatile unsigned int *) (XPAR_STENCIL_TOP_0_BASEADDR + 0x0))
#define STENCIL_SIZE    (*(volatile unsigned int *) (XPAR_STENCIL_TOP_0_BASEADDR + 0x4))
#define STENCIL_SRC_PTR (*(volatile unsigned int *) (XPAR_STENCIL_TOP_0_BASEADDR + 0x8))
#define STENCIL_DST_PTR (*(volatile unsigned int *) (XPAR_STENCIL_TOP_0_BASEADDR + 0xc))

// 現在の実行クロック数を秒単位で返す
double getclock ()
{
    XTime tm;
    XTime_GetTime(&tm);
    return (double) tm / COUNTS_PER_SECOND;
}

// バッファを初期化する
void init_buf ()
{
    int i, j;
    memset(buf1, 0, sizeof(buf1));
    memset(buf2, 0, sizeof(buf2));
    for (i = 4; i < N; i += 8) {
        for (j = 4; j < N; j += 8) {
            buf1[i][j] = (i << 16) + (j << 4);
        }
    }
    buf1[4][4] = 0x0fffffff;
}

// ステンシル計算（ソフトウェア処理）
void stencil_soft (unsigned int src[][N], unsigned int dst[][N])
{
    int x, y;
    for (y = 1; y < N - 1; y++) {
        for (x = 1; x < N - 1; x++) {
            dst[y][x] = (src[y-1][x-1] + src[y-1][x] + src[y-1][x+1] +
                         src[y  ][x-1] + src[y  ][x] + src[y  ][x+1] +
                         src[y+1][x-1] + src[y+1][x] + src[y+1][x+1]) / 9;
        }
    }
    dst[4][4] = 0x0fffffff;
}

void stencil_hard (unsigned int src[][N], unsigned int dst[][N])
{
    STENCIL_SIZE    = N;
    STENCIL_SRC_PTR = (unsigned int) src;
    STENCIL_DST_PTR = (unsigned int) dst;
    STENCIL_GO     = 1;
    while (STENCIL_DONE);
    STENCIL_GO     = 0;
    while (! STENCIL_DONE);
}

void printresult (unsigned int dst[][N], double elapsed)
{
    int x, y;
    unsigned int sum = 0;
    for (y = 0; y < N; y++) {
        for (x = 0; x < N; x++) {
            sum += dst[y][x];
        }
    }
    for (y = 0; y < 16; y++) {
        for (x = 0; x < 8; x++) {
            xil_printf("%08x ", dst[y][x]);
        }
        xil_printf("\n");
    }
    xil_printf("checksum         : %08x\n", sum);
    xil_printf("elapsed time [ms]: %d.%03d\n",
        (int) (elapsed * 1000), (int) (elapsed * 1000000) % 1000);
}

// メイン: ソフトとハードの両方でステンシル計算
int main ()
{
    int i;
    double start_time, flush_time, end_time;
    unsigned int (*src)[N], (*dst)[N];
    xil_printf("== STENCIL ==\n");
    xil_printf("size = %d, iteration = %d\n\n", N, ITER);

    xil_printf("-- SOFTWARE --\n");
    init_buf();
    start_time = getclock();
    for (i = 0; i < ITER; i += 2) {
        src = buf1;
        dst = buf2;
        stencil_soft(src, dst);
        if (i == ITER - 1)
            break;
        src = buf2;
        dst = buf1;
        stencil_soft(src, dst);
    }
    end_time = getclock();
    printresult(dst, end_time - start_time);
    
    xil_printf("\n-- HARDWARE --\n");
    init_buf();
    start_time = getclock();
    Xil_DCacheFlushRange((u32) buf1, sizeof(buf1));
    Xil_DCacheFlushRange((u32) buf2, sizeof(buf2));
    flush_time = getclock() - start_time;
    for (i = 0; i < ITER; i += 2) {
        src = buf1;
        dst = buf2;
        stencil_hard(src, dst);
        if (i == ITER - 1)
            break;
        src = buf2;
        dst = buf1;
        stencil_hard(src, dst);
    }
    end_time = getclock();
    printresult(dst, end_time - start_time);
    xil_printf("(incl. %d.%03d ms to flush cache)\n\n",
        (int) (flush_time * 1000), (int) (flush_time * 1000000) % 1000);
    return 0;
}