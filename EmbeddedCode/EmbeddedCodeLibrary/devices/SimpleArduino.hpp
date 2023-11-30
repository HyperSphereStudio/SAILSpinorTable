/**********************************************************************
   NAME: SimpleArduino.hpp
   AUTHOR: Johnathan Bizzano
   DATE: 6/22/2023

    The Simple Project
		Medium Level (from Low) library that abstracts away from embedded device hardware

    Simple Arduino
        Arduino implementation of the simple library
*********************************************************************/

#ifndef SIMPLE_ARDUINO_C_H
#define SIMPLE_ARDUINO_C_H

#include "../SimpleTimer.hpp"
#include "../SimpleConnection.hpp"

using namespace Simple;

namespace Simple{
    time_t NativeMillis(){
        return millis();
    }

    /**Wrapper of a Arduino Stream to an IO**/
    struct StreamIO : public IO{
        Stream& uart;
        StreamIO(Stream& uart = Serial) : uart(uart){}
        int WriteByte(uint8_t b) { return uart.write(b); }
        int WriteBytes(uint8_t *ptr, int nbytes) final { return uart.write((uint8_t*) ptr, nbytes); }
        int ReadByte() { return uart.read(); }
        int ReadBytesUnlocked(uint8_t *ptr, int buffer_size) final { return uart.readBytes((char*) ptr, buffer_size); }
        int BytesAvailable() final { return uart.available(); }
    };

    StreamIO Out, Error;

    /**Wrapper of a Arduino Serial Port to an IO**/
    struct SerialConnection : public Connection{
        void Update(){
            uint8_t buffer[BUFSIZ];
            while(Serial.available() > 0)
                Receive(buffer, Serial.readBytes((char*) buffer, BUFSIZ));
        }
    protected:
        void Write(IOBuffer* io) final {
            uint8_t buffer[BUFSIZ];
            int read;
            while((read = io->ReadBytesUnlocked(buffer, BUFSIZ)) > 0){
                Serial.write(buffer, read);
            }
        }
    };


}

#endif