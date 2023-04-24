/*
   BizzanoMicroController.h
   Author : John Bizzano
   Code for Spinner Table

   Used List
    Ports:
     2.0 - UCA0TXD
     1.3 - Motor ADC Input
     1.4 - Release Output
     2.5 - Motor Uart Tx

    Regs:
     ADCMEM0 - Motor ADC Memory

    Timers:
     A0 - IR Timer

    UART
     A0 - PC
     A1 - Motor
 */

#define DEBUG
#include "bizzanodriverlib/BizzanoMicroController.h"

#define UART_BACKCHANNEL_BASE EUSCI_A0_BASE

#define MOTOR_ADC_PORT ADC12_B_INPUT_A3 //Uses ADC Memory 0
#define MOTOR_ADC_GPIO_PORT GPIO_PORT_P1, GPIO_PIN3
#define MOTOR_ADC_OUTPUT ADC12_B_MEMORY_0
#define MOTOR_UART_TX_PORT GPIO_PORT_P2, GPIO_PIN5
#define MOTOR_UART_BASE EUSCI_A1_BASE

#define RELEASE_GPIO_PORT GPIO_PORT_P1, GPIO_PIN4

#define IR_TRIP_COUNT 60
#define IR_TIMER_BASE TIMER_A1_BASE
#define ADC_IR_SAMPLES 4

#define ACLK_FREQ 32768
#define ConversionFactorFreqForFreq (double) (32768)/32

int ir_state = 0, adc_samples = 0;
bool ir_triggered = false;
float adc_avg = 0;

void init_smclock(){
    CS_setDCOFreq(CS_DCORSEL_0, CS_DCOFSEL_0);
    CS_initClockSignal(CS_SMCLK, CS_DCOCLK_SELECT, CS_CLOCK_DIVIDER_1);
}

void init_aclk(){
    GPIO_setAsPeripheralModuleFunctionInputPin(GPIO_PORT_PJ, GPIO_PIN4 + GPIO_PIN5, GPIO_PRIMARY_MODULE_FUNCTION); //Set external frequency for XT1
    CS_setExternalClockSource(ACLK_FREQ, 0);
    CS_initClockSignal(CS_ACLK, CS_LFXTCLK_SELECT, CS_CLOCK_DIVIDER_1);
    ASSERT(CS_turnOnLFXTWithTimeout(CS_LFXT_DRIVE_3, 0xFFF), "ACLK Initialization Failed!");
}

void init_uart(EUSCI_A_UART_initParam* init, uint16_t uartBaseAddr){
    init->selectClockSource = EUSCI_A_UART_CLOCKSOURCE_SMCLK;
    init->parity = EUSCI_A_UART_NO_PARITY;
    init->msborLsbFirst = EUSCI_A_UART_LSB_FIRST;
    init->numberofStopBits = EUSCI_A_UART_ONE_STOP_BIT;
    init->uartMode = EUSCI_A_UART_MODE;

    ASSERT(EUSCI_A_UART_init(uartBaseAddr, init), "Error Enabling UART!");
    EUSCI_A_UART_enable(uartBaseAddr);
}

void init_pc_uart(){
    GPIO_setAsPeripheralModuleFunctionOutputPin(
            GPIO_PORT_P2,
            GPIO_PIN0+GPIO_PIN1,
            GPIO_SECONDARY_MODULE_FUNCTION
    ); //Enable UCA0TXD, UCA0RXD

    //Baud Rate of 115200 given SMCLK freq of 1Mhz
    EUSCI_A_UART_initParam init = { .clockPrescalar = 8,
                                    .firstModReg = 0,
                                    .secondModReg = 214,
                                    .overSampling = EUSCI_A_UART_LOW_FREQUENCY_BAUDRATE_GENERATION};

    init_uart(&init, UART_BACKCHANNEL_BASE);
    EUSCI_A_UART_enableInterrupt(EUSCI_A0_BASE, EUSCI_A_UART_RECEIVE_INTERRUPT);
    debug("Hello World!");
}

void init_motor_uart(){
    GPIO_setAsPeripheralModuleFunctionOutputPin(MOTOR_UART_TX_PORT, GPIO_SECONDARY_MODULE_FUNCTION); //Enable UCA1TXD

    //Baud Rate of 19200 given SMCLK freq of 1Mhz for motor controller (Pololu, TReX Jr)
    EUSCI_A_UART_initParam init = { .clockPrescalar = 3,
                                    .firstModReg = 4,
                                    .secondModReg = 4,
                                    .overSampling = EUSCI_A_UART_OVERSAMPLING_BAUDRATE_GENERATION};

    init_uart(&init, MOTOR_UART_BASE);
}

void motor_uart_write(uint8_t v){ EUSCI_A_UART_transmitData(MOTOR_UART_BASE, v); }
void write_Freq(double speed){println("\r\nFreq%d", speed);}

#pragma vector = USCI_A0_VECTOR
__interrupt void USCI_A0_ISR(void) {
    switch(__even_in_range(UCA0IV, USCI_UART_UCTXCPTIFG)) {
        case USCI_NONE:
            break;
        case USCI_UART_UCRXIFG: {
                uint8_t k = EUSCI_A_UART_receiveData(UART_BACKCHANNEL_BASE);
                if(k <= 127){
                    motor_uart_write(0xCA);
                    motor_uart_write(k);
                    ir_state = 0; //Reset the IR state so that Freq is not miscalculated
                }else{
                    switch(k){
                        case 128: GPIO_setOutputHighOnPin(RELEASE_GPIO_PORT); break;
                        case 129: GPIO_setOutputLowOnPin(RELEASE_GPIO_PORT); break;
                        default: debug("Found Invalid Recieve Byte!");
                    }
                }
                ADC12_B_clearInterrupt(EUSCI_A0_BASE, 0, USCI_UART_UCRXIFG);
            }
            break;
        case USCI_UART_UCSTTIFG: break;
    }
}

void adc_init(){
    GPIO_setAsPeripheralModuleFunctionOutputPin(MOTOR_ADC_GPIO_PORT, GPIO_TERNARY_MODULE_FUNCTION);

    ADC12_B_initParam adc_init = {0};
    adc_init.sampleHoldSignalSourceSelect = ADC12_B_SAMPLEHOLDSOURCE_SC;
    adc_init.clockSourceDivider = ADC12_B_CLOCKDIVIDER_8;
    adc_init.clockSourcePredivider = ADC12_B_CLOCKPREDIVIDER__64;
    adc_init.internalChannelMap = ADC12_B_NOINTCH;
    adc_init.clockSourceSelect = ADC12_B_CLOCKSOURCE_ADC12OSC;
    ASSERT(ADC12_B_init(ADC12_B_BASE, &adc_init), "Error Enabling ADC12!");
    ADC12_B_enable(ADC12_B_BASE);
    ADC12_B_setupSamplingTimer(ADC12_B_BASE,
                               ADC12_B_CYCLEHOLD_4_CYCLES,
                               ADC12_B_CYCLEHOLD_8_CYCLES,
                               ADC12_B_MULTIPLESAMPLESENABLE);
    ADC12_B_setResolution(ADC12_B_BASE, ADC12_B_RESOLUTION_8BIT);

    ADC12_B_configureMemoryParam con;
    con.memoryBufferControlIndex = MOTOR_ADC_OUTPUT;
    con.inputSourceSelect = MOTOR_ADC_PORT;
    con.refVoltageSourceSelect = ADC12_B_VREFPOS_AVCC_VREFNEG_VSS;
    con.endOfSequence = ADC12_B_NOTENDOFSEQUENCE;
    con.windowComparatorSelect = ADC12_B_WINDOW_COMPARATOR_DISABLE;
    con.differentialModeSelect = ADC12_B_DIFFERENTIAL_MODE_DISABLE;
    ADC12_B_configureMemory(ADC12_B_BASE, &con);

    ADC12_B_clearInterrupt(ADC12_B_BASE, 0, ADC12_B_IFG0);
    ADC12_B_enableInterrupt(ADC12_B_BASE, ADC12_B_IE0, 0, 0);
    ADC12_B_startConversion(ADC12_B_BASE, MOTOR_ADC_OUTPUT, ADC12_B_REPEATED_SINGLECHANNEL);
}

void on_adc_sample(float value){
    bool wasTripped = value < IR_TRIP_COUNT;
    bool stateChange = wasTripped != ir_triggered;
    ir_triggered = wasTripped;
    if(ir_state == 0)
        Fast_Timer_A_setCounterValue(IR_TIMER_BASE, 0); //Start the clock

    if(stateChange){
        if(++ir_state == 6){ //6 Different States Per Rev
            ir_state = 0; //Reset
            write_Freq((ConversionFactorFreqForFreq / (double) Fast_Timer_A_getCounterValue(IR_TIMER_BASE)));
        }
    }
}

#pragma vector=ADC12_VECTOR
__interrupt void ADC12_ISR(void) {
    switch(__even_in_range(ADC12IV, ADC12IFG0)){
        case 12: //ADC Mem0 ready
            adc_avg += (float) ADC12_B_getResults(ADC12_B_BASE, ADC12_B_MEMORY_0);
            if(++adc_samples == ADC_IR_SAMPLES){
                on_adc_sample(adc_avg/ADC_IR_SAMPLES);
                adc_avg = 0;
                adc_samples = 0;
            }
            ADC12_B_clearInterrupt(ADC12_B_BASE, 0, ADC12_B_IFG0); //Doesnt Clear Auto?? MUST HAVE THIS!!
            break;
    }
}

void init_ir_timer(){
    Timer_A_clearTimerInterrupt(IR_TIMER_BASE);
    Timer_A_initContinuousModeParam init = {0};
    init.clockSource = TIMER_A_CLOCKSOURCE_ACLK;
    init.clockSourceDivider = TIMER_A_CLOCKSOURCE_DIVIDER_32; //Reset every 64 seconds (65535/(32768/32))
    init.timerInterruptEnable_TAIE = TIMER_A_TAIE_INTERRUPT_ENABLE;
    init.timerClear = TIMER_A_DO_CLEAR;
    init.startTimer = false;
    Timer_A_initContinuousMode(IR_TIMER_BASE, &init);
    Timer_A_startCounter(IR_TIMER_BASE, TIMER_A_CONTINUOUS_MODE);
}

#pragma vector=TIMER1_A1_VECTOR
__interrupt void TIMER1_A1_ISR(void) {
    switch (__even_in_range(TA1IV, 14)){
        case 14: // overflow
            write_Freq(0);
            debug("Timer OverFlow!");
            break;
        default: break;
    }
    Timer_A_clearTimerInterrupt(IR_TIMER_BASE);
}

void init_release(){
    GPIO_setAsOutputPin(RELEASE_GPIO_PORT);
    GPIO_setOutputLowOnPin(RELEASE_GPIO_PORT);
}

int main(void) {
    HoldWatchDogTimer();
    PMM_unlockLPM5();
    init_smclock();
    init_pc_uart();
    init_aclk();
    init_motor_uart();
    adc_init();
    init_ir_timer();
    init_release();
    __enable_interrupt();

    unsigned int cycle_count = 0;

    while(true){
#ifdef DEBUG
        if(cycle_count++ % 1000 == 0)
            println("HeartBeat: %u", cycle_count);
#endif
    }
}

void stdout_print_char(uint8_t c){ EUSCI_A_UART_transmitData(UART_BACKCHANNEL_BASE, c); }
