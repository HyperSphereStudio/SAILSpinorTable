/**********************************************************************
   NAME: SimpleFeather.hpp
   AUTHOR: Johnathan Bizzano
   DATE: 6/22/2023

    The Simple Project
		Medium Level (from Low) library that abstracts away from embedded device hardware

    Simple Arduino
        Feather implementation of the simple library
*********************************************************************/

#ifndef SIMPLE_FEATHER_C_H
#define SIMPLE_FEATHER_C_H

#include "SimpleArduino.hpp"

#include <SPI.h>
#include <RH_RF95.h>

namespace Simple{

    enum Range{
        Short,
        Medium,
        Long,
        UltraLong
    };

    struct PacketHeader{
        uint8_t to = 0, from = 0, id = 0;

        PacketHeader(uint8_t to = 0, uint8_t from = 0, uint8_t id = 0) : to(to), from(from), id(id){}
    };

    /**Wrapper of the radio to an IO **/
    class RadioIO : public Connection{
    protected:
        RH_RF95 rf95;
        const uint8_t resetPin;
    public:
        RadioIO(uint8_t slaveSelectPin, uint8_t interruptPin, uint8_t resetPin) : rf95(slaveSelectPin, interruptPin), resetPin(resetPin){
            pinMode(resetPin, OUTPUT);
            digitalWrite(resetPin, HIGH);
        }

        virtual bool Initialize(float frequency, int8_t power, Range range, bool useRFO = false){
            digitalWrite(resetPin, LOW);
            delay(10);
            digitalWrite(resetPin, HIGH);

            if(!rf95.init()) {
                println("LoRa radio init failed\nUncomment '#define SERIAL_DEBUG' in RH_RF95.cpp for detailed debug info");
                return false;
            }

            //Defaults after init are 434.0MHz, modulation GFSK_Rb250Fd250, +13dbM
            if(!rf95.setFrequency(frequency)){
                println("setFrequency failed");
                return false;
            }

            // Defaults after init are 434.0MHz, 13dBm, Bw = 125 kHz, Cr = 4/5, Sf = 128chips/symbol, CRC on
            // The default transmitter power is 13dBm, using PA_BOOST.
            // If you are using RFM95/96/97/98 modules which uses the PA_BOOST transmitter pin, then
            // you can set transmitter powers from 5 to 23 dBm:
            rf95.setTxPower(power, useRFO);

            RH_RF95::ModemConfigChoice modemConfig;
            switch(range){
                case Short: modemConfig = RH_RF95::Bw500Cr45Sf128; break;      //Fast Short
                case Medium: modemConfig = RH_RF95::Bw125Cr45Sf128; break;     //Medium
                case Long: modemConfig = RH_RF95::Bw125Cr45Sf2048; break;      //Long Slow
                case UltraLong: modemConfig = RH_RF95::Bw125Cr48Sf4096; break; //Long Really Slow
            }
            rf95.setModemConfig(modemConfig);
            return true;
        }

        void Send(IOBuffer* io) override{
            rf95.send(io->Interpret(), io->Size());
        }

        void Send(IOBuffer* io, PacketHeader header){
            rf95.setHeaderTo(header.to);
            rf95.setHeaderId(header.id);
            rf95.setHeaderFrom(header.from);
            Send(io);
        }

        void Write(IOBuffer* io) override {
            uint8_t buffer[RH_RF95_MAX_MESSAGE_LEN];
            int read;
            while((read = io->ReadBytesUnlocked(buffer, RH_RF95_MAX_MESSAGE_LEN)) > 0){
                rf95.send(buffer, read)
            }
        }

        void Update(){
            if(rf95.available()){
                IOBuffer io(RH_RF95_MAX_MESSAGE_LEN);
                uint8_t len = RH_RF95_MAX_MESSAGE_LEN;
                rf95.recv(io.Interpret(0), &len);
                io.SetSize(len);
                PacketHeader header;
                header.to = rf95.headerTo();
                header.from = rf95.headerFrom();
                header.id = rf95.headerId();
                Receive(io, header);
            }
        }

        void Receive(IOBuffer* io) final {}
        virtual void Receive(IOBuffer* io, PacketHeader header) = 0;
        void SetAddress(int id){ rf95.setThisAddress(id); }
    };
}
#endif