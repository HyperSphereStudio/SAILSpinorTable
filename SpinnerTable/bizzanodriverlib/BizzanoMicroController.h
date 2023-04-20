/*
 * BizzanoMicroController.h
 * Author : John Bizzano
 * Custom MicroController Driver Library Wrapper for MSP5696
 */

#ifndef _BIZZANO_MC_H_
#define _BIZZANO_MC_H_

#ifdef __CLION_IDE__
    #include "../clion/msp430fr5969.h"
    #include "../clion/msp430fr5xx_6xxgeneric.h"
    #define __MSP430_HAS_EUSCI_Ax__
    #define __MSP430_HAS_TxA7__
    #define __delay_cycles(cycles){}
    #define __interrupt
    #define __even_in_range(reg, x) reg
    #define __enable_interrupt()
#else
    #include <msp430.h>
#endif

#ifdef DEBUG
    #define ASSERT(x, msg) if(!(x)) println(msg)
    #define debug(msg) println(msg)
#else
    #define ASSERT(x, msg) x
    #define debug(msg)
#endif

#include "driverlib.h"
#include <stdint.h>
#include <stdio.h>
#include <math.h>
#include <time.h>
#include <stdarg.h>

//Utilities
#define delay_ms(x) _delay_ms(x)
#define SetBit(x, n, v) ((v) ? ((x) | (1<<(n))) : ((x) & ~(1<<(n))))
#define GetBit(x, n) ((x) & (1<<(n)))
#define SetPin(name, n, v) name = SetBit(name, n, v)
#define GetPin(name, n) GetBit(name, n)
#define CAT0(x) _CAT0(x)
#define _CAT0(x) x
#define _CAT(x, y) x ## y
#define CAT(x, y) _CAT(x, y)
#define _CAT2(x, y, z) x ## y ## z
#define CAT2(x, y, z) _CAT2(x, y, z)
#define WaitFor(x) while(!(x))

//Apply A Mask To Source And Dest that Creates a Copy operation
#define ApplyDestMask(dst, src, mask, dest_delta) ((dst) & ~((mask) >> dest_delta)) | (((src) & (mask)) << dest_delta)
#define ApplyMask(dst, src, mask) ApplyDestMask(dst, src, mask, 0)

//Copy A Range of Bits From Src[src_offset:(src_offset+n)] To Desc[dst_offset:(dst_offset+n)]
#define CopyBitRange(dst, dst_offset, src, src_offset, n) ApplyDestMask(dst, src, ((1 << n) - 1) << src_offset, (dst_offset - src_offset))
#define SetBitRange(dst, dst_offset, src, src_offset, n) dst = CopyBitRange(dst, dst_offset, src, src_offset, n)

#define true 1
#define false 0

//Prevent GCC Optimization
#define NoOpt(x) *&x

#define HoldWatchDogTimer() WDT_A_hold(WDT_A_BASE)

typedef int iterator(int* array, int length, int* idx);

int forward_cyclic_iterator(int* array, int length, int* idx){
	int v = array[*idx];
	if(++*idx >= length)
		*idx = 0;
	return v;
}

int reverse_cyclic_iterator(int* array, int length, int* idx){
	if(*idx <= 0) *idx = length - 1;
	else *idx -= 1;
	return array[*idx];
}

uint16_t Fast_Timer_A_getCounterValue(uint16_t baseAddress){ return HWREG16(baseAddress + OFS_TAxR); }
void Fast_Timer_A_setCounterValue(uint16_t baseAddress, long v){ HWREG16(baseAddress + OFS_TAxR) = v; }

#include "BizzanoMFIO.h"

#endif // _BIZZANO_MC_H_