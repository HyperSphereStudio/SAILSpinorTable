#define F_CPU 8000000UL
#include <avr/io.h>
#include <util/delay.h>
#include <stdio.h>
#include <math.h>
#include <avr/interrupt.h>

#define UART_BAUD1 9600  // Baud for talking to computer software
#define UART_BAUD2 19200 // Baud for talking to motor controller (Pololu, TReX Jr)


//Define Baud Rate as described in AVR manual
#define UART_UBBR_VALUE1 (((F_CPU / (UART_BAUD1 * 8UL))) - 1) // Baud for talking to computer, 9600
#define UART_UBBR_VALUE2 (((F_CPU / (UART_BAUD2 * 8UL))) - 1) // Baud for talking to motor controller, 19,200 (Pololu, TReX Jr)

// Function Prototypes
void uart_init();
void adc_init();
void timer_init();
void write_uart1(unsigned char c[]);
void write_uart2(unsigned char c);
unsigned char receive();


int ADCflag = 0;

int main()
{
	int i = 0; // Counter variable
	int j = 0; // Counter variable
	int vals[4] = {0,0,0,0}; // Store the 4 most recent time intervals for the rotation
	int sum = 0; // Sum of the four values in vals[]
	int ave = 0; // Average of the four values in vals[]
	unsigned char buffer[15];

	adc_init();
	timer_init();
	uart_init(); // Initializes BOTH uarts (for talking to computer at 9600 and motor controller at 19,200)
	
	UCSR0B |= (1 << RXCIE0); // For received interupt - NEED THIS! IMPORTANT
	sei(); // Enable global interrupts

	// For the LED or wire-cutter.  Set the pin to output and then make sure it's off.
	DDRD |= (1<<DDD6);
	PORTD |= (1<<PORTD6);
	PORTD &= ~(1<<PORTD6);
	
	sei(); // Enable global interrupts

	while(1) // Loop waiting for interupts and sending the RPM of the stand to the matlab program
	{	
		ADCSRA |= (1<<ADSC); // Start ADC

		if(ADCflag == 1)
		{
			ADCSRA &= ~(1<<ADEN); // Disable ADC
			ADCflag = 2;

			vals[i] = TCNT1/4;

			sum = 0;
			for(j=0; j<4; j++)
			{
				sum = sum+vals[j];
			}

			ave = sum/4;
		
			sprintf(buffer,"RPMstring\t%d\n\r", ave); // TCNT1 is the count of timer1
			TCNT1=0; // Reset the timer back to zero
			write_uart1(buffer);
			
			ADCSRA |= (1<<ADEN); // Enable ADC
			ADCSRA |= (1<<ADSC); // Start ADC

			i++;
			if(i == 4)
			{
				i = 0;
			}
		}			
	}
}



void uart_init()
{
// For RX and TX 0, to talk to the computer at 9600
	//Set Baud rate
	UBRR0H = UART_UBBR_VALUE1 >> 8;
	UBRR0L = UART_UBBR_VALUE1;
	UCSR0A |= (1<<U2X0);
	//Frame format: 8 data bits, no parity, 1 stop bit
	UCSR0C |= (1<<UCSZ01)|(1<<UCSZ00);
	//Enable Transmit and Receive
	UCSR0B |= (1<< RXEN0)|(1<<TXEN0);

// For RX and TX 1, to talk to the motor controller (Pololu, TReX Jr) at 19,200
	//Set Baud rate
	UBRR1H = UART_UBBR_VALUE2 >> 8;
	UBRR1L = UART_UBBR_VALUE2;
	UCSR1A |= (1<<U2X0);
	//Frame format: 8 data bits, no parity, 1 stop bit
	UCSR1C |= (1<<UCSZ11)|(1<<UCSZ10);
	//Enable Transmit and Receive
	UCSR1B |= (1<< RXEN1)|(1<<TXEN1);
}

void adc_init()
{
	ADCSRA |= (1<<ADATE); // Set ADC auto trigger enable bit
	ADMUX &= 0xe0;
	ADMUX |= 0; // Set ADCMUX to choose the MUX pin where the IR sensor is wired to
	ADCSRA |= (1<<ADPS1) | (1<<ADPS0); // Set ADC prescaler select bits for CLK/8
	ADMUX |= (1<<REFS0); // Set ADC reference to AVCC
	ADMUX |= (1<<ADLAR); // Set ADLAR pin to left-adjust for CLK/8
	ADCSRA |= (1<<ADIE); // Set ADC interupt bit
	ADCSRA |= (1<<ADEN); // Enable ADC
}

void timer_init()
{
	TCCR1B |= (1<<WGM12); // CTC with OCR1A TOP
	OCR1A = 2000*8; // Timer1 should reach TOP every 67s
	TIMSK1 |= (1<<OCIE1A); // Output compare interrupt
	TCCR1B |= (1<<CS10) | (1<<CS12); // CLK/1024
}

void write_uart1(unsigned char c[])
{
	do 
	{
		while((UCSR0A&(1<<UDRE0)) == 0); // Wait for Transmit Buffer to Empty
		UDR0 = *c; // Transmit the character
		c++; // Increment the pointer to point to the next character
	}while(*c != '\0');
}

void write_uart2(unsigned char c) // Sending commands to the motor controller (Pololu, TReX Jr)
{
		while((UCSR1A&(1<<UDRE1)) == 0); // Wait for Transmit Buffer to Empty
		UDR1 = c; // Transmit the character
}

// Timer Interupt
ISR(TIMER1_COMPA_vect) // this interrupt is fired when timer 1 equals OCR1A
{
	write_uart1("RPMstring\t0\n\r"); // Write the string to the UART
}

// ADC Interupt
ISR(ADC_vect) // When each ADC completes, this routine is executed
{
	int tripCount = 240;

	if(ADCH >= tripCount && ADCflag == 0)
	{
		ADCflag = 1;
	}
	else if(ADCH >= tripCount && ADCflag == 1)
	{
		ADCflag = 2;
	}
	else if(ADCH <= tripCount && ADCflag == 2)
	{
		ADCflag = 0;
	}
}

// Receive Interupt
ISR(USART0_RX_vect)
{
	char c = 0;
	char k = 0;

	k = receive();	

	// If the received bite is between 0 and 127 inclusive, send that same value to motor controller (speed)
	if(k <= 127)
	{
		c = 0xCA;
		write_uart2(c);
		c = k;
		write_uart2(c);
	}

	// If the received bite is 128, turn on pin D6. If 129, turn if off.
	else
	{
		if(k == 128)
		{
			PORTD |= (1<<PORTD6); // Turn on
		}
		else if(k == 129)
		{
			PORTD &= ~(1<<PORTD6); // Turn off
		}
	}
}

unsigned char receive() // Return the received character
{
	while ((UCSR0A & (1<<RXC0)) == 0);
	return UDR0;
}
