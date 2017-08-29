;************************************************************************
; Filename: Final_Lab														*
;																		*
; ELEC3450 - Microprocessors											*
; Wentworth Institute of Technology										*
; Professor Bruce Decker												*
;																		*
; Student #1 Name: Takaris Seales										*
; Course Section: 03													*
; Date of Lab: <08-02-2017>												*
; Semester: Summer 2017													*
;																		*
; Function: This program uses a Pulse-Width Modulation (PWM), ADC  		* 
; and USART SPI to remotely control the intensity of an LED on 	  		*
; another PIC board by varying the voltage on an external power supply  *	 	        	
;																		*
; Wiring: 																*
; One wire connected to External Power Supply connected to RA0 as       *
; Analog Input and other wire connected as ground for Power Supply		*
; RS232 RS_TX and RS_RX connected to PortC TX and RX pins respectively  *
; RS232 Pins 9 & 10 wired to ground										*
; PortC CCP1 pin connected to one LED as output for LED					*			
;************************************************************************											
; A register may hold an instruction, a storage address, or any kind of data
;(such as a bit sequence or individual characters)
;BYTE-ORIENTED INSTRUCTION:	
;'f'-specifies which register is to be used by the instruction	
;'d'-designation designator: where the result of the operation is to be placed
;BIT-ORIENTED INSTRUCTION:
;'b'-bit field designator: selects # of bit affected by operation
;'f'-represents # of file in which the bit is located
;
;'W'-working register: accumulator of device. Used as an operand in conjunction with
;	 the ALU during two operand instructions														
;************************************************************************

		#include <p16f877a.inc>

TEMP_W					EQU 0X21			
TEMP_STATUS				EQU 0X22
TEMP_B					EQU 0X23
TEMP_C					EQU 0X24
TEMP_LED				EQU 0X25
ADC_RESULT				EQU 0X26
		__CONFIG		0X373A 				;Control bits for CONFIG Register w/o WDT enabled			

		
		ORG				0X0000				;Start of memory
		GOTO 		MAIN

		ORG 			0X0004				;INTR Vector Address
PUSH										;Stores Status and W register in temp. registers

		MOVWF 		TEMP_W
		SWAPF		STATUS,W
		MOVWF 		TEMP_STATUS
		GOTO		INTR

POP											;Restores W and Status registers
	
		SWAPF		TEMP_STATUS,W
		MOVWF		STATUS
		SWAPF		TEMP_W,F
		SWAPF		TEMP_W,W				
		RETFIE

INTR										;ISR - Calls subroutines depending on flag set
		BTFSC		PIR1, ADIF				;Check ADC
		CALL		ADINTR
		BTFSC		PIR1, TMR2IF			;TMR2 to PR2 match occured
		CALL		PWMINTR
		BTFSC		PIR1, TXIF				;Check Transmit Flag
		CALL		USARTTransmit
		BTFSC		PIR1, RCIF				;Check Receive Flag
		CALL		USARTReceive
		GOTO 		POP						
				

MAIN
		CLRF		PORTA					;Clear GPIOs to be used	
		CLRF 		PORTC					
		BCF			INTCON, GIE				;Disable all interrupts
		CALL		INIT_ADC
		CALL		INIT_PWM
		CALL		INIT_USART
	
		BCF			STATUS, RP0				;Bank0
		BSF			INTCON, PEIE			;Enable Peripheral Interrupts
		BSF			INTCON, GIE				;Enable all interrupts

LOOP
		;Peripheral Start
ADC_START
		BSF			ADCON0, GO				;Start A/D Conversion. ADIF Bit set and Go/Done bit cleared upon completion


USART_START
		MOVF		ADC_RESULT, W
		MOVWF		TXREG


		GOTO LOOP

		;Peripheral Register Initialization
INIT_ADC
		BSF			STATUS, RP0				;Bank1
		MOVLW		0XFF					;Set RA0 as input for External Power Supply
		MOVWF		TRISA
		MOVLW		0X0E					;Left-Justified, Internal Vref, RA0 as Analog and rest of pins as Digital I/O
		MOVWF		ADCON1
		BCF			STATUS, RP0				;Bank0
		MOVLW		0X81					;Fosc/32, RA0 as Channel
		MOVWF		ADCON0
		
		RETURN

INIT_PWM
		BSF			STATUS, RP0				;Bank1			
		BSF			PIE1, TMR2IE			;Timer2 Interrupts Enabled
		MOVLW		0X3F					;Set PR2 to 3F for TMR2 equal to PR2
		MOVWF		PR2		
		BCF			STATUS, RP0				;Bank0
		CLRF		CCPR1L
		MOVLW		0X04					;TMR2 = ON, Postscale and Prescaler is 1
		MOVWF		T2CON	
		MOVLW		0X0F					;Set CCP1CON to PWM Mode
		MOVWF		CCP1CON	

		RETURN

INIT_USART	
		BSF			STATUS, RP0				;Bank1
		MOVLW		0X80					;CCP1 as output, RC6 as output for TX, RC7 as input for RX
		MOVWF		TRISC
		MOVLW		0X26					;Asynchronous mode, High Speed Baud, 8-bit transmission, no parity
		MOVWF		TXSTA
		MOVLW		0X81					;Set Baud Rate (9600)
		MOVWF		SPBRG			
		BSF			PIE1, RCIE				;USART Receive Interrupt Enable Bit
		BSF			PIE1, TXIE				;USART Transmit Interrupt Enable Bit
		BCF			STATUS, RP0				;Bank0
		BSF			PIR1, RCIF				;Enable USART Receive Interrupt Flag Bit
		BSF			PIR1, TXIF				;Enable USART Transmit Interrupt Flag Bit
		MOVLW		0X90					;Asynchronous Mode, parity bit always set at 0
		MOVWF		RCSTA

		RETURN


		;ISRs
		;USART Interrupt
USARTTransmit
		MOVF		ADC_RESULT, W
		MOVWF		TXREG

		RETURN

USARTReceive
		BCF			STATUS, C
		BTFSC		RCSTA, OERR				;Checks Overrun Error Bit
		GOTO		Overrun
		BTFSC		RCSTA, FERR				;Checks Framing Error Bit
		GOTO		Framing

Bit0		;Put first LSB into CCP1CON
		MOVF		RCREG, W				;Move Receive Register values into Temporary D register
		MOVWF		TEMP_LED
		BTFSS		TEMP_LED, 0
		GOTO		Clear0
		BSF			CCP1CON, CCP1Y

		
Bit1		;Put second LSB into CCP1CON
		BTFSS		TEMP_LED, 1
		GOTO		Clear1
		BSF			CCP1CON, CCP1X


Upper6		;Right Shift twice to put MSBs into CCP1L
		MOVLW		0xFC
		ANDWF		TEMP_LED, F
		RRF			TEMP_LED, F				;Rotate bits twice
		RRF			TEMP_LED, F	
		MOVF		TEMP_LED, W				;Put MSBs into W register
		MOVWF		CCPR1L					;Put MSBs into CCPR1L
	
		RETURN


Clear0		;Clear first LSB
		BCF			CCP1CON, CCP1Y
	
		GOTO		Bit1

Clear1		;Clear second LSB
		BCF			CCP1CON, CCP1X

		GOTO		Upper6


Overrun		
		BCF			RCSTA, CREN				;Clears OERR by clearing then setting CREN bit
		BSF			RCSTA, CREN				;(resets receive logic)
		CLRF 		RCREG					;Dumps Receiver Register and returns to interrupt

		GOTO		POP	

Framing
		CLRF		RCREG					;Dumps Receiver Register
		
		GOTO		POP


		;ADC Interrupt
ADINTR
		BCF			PIR1,  ADIF
		MOVF		ADRESH, W				;Moves High Result to W Register
		MOVWF		ADC_RESULT				;Moves High Result to Temp Register (to use for SPI)
		BSF			ADCON0, GO				;Start next conversion

		RETURN

		;PWM Interrupt
PWMINTR
		BCF			PIR1, TMR2IF			;TMR2 to PR2 match occured

		RETURN







		END