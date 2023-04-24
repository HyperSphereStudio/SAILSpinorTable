/*Author: Johnathan Bizzano
 * Date 4/12/2023
 * Purpose: Provide Light Weight IO for MicroControllers
 * **/

#ifndef SPINNERTABLE_BIZZANOMFIO_H
#define SPINNERTABLE_BIZZANOMFIO_H

void stdout_print_char(uint8_t c);

#define print(fmt, ...) fprint(stdout_print_char, fmt, ##__VA_ARGS__)
#define println(fmt, ...) print(fmt "\r\n", ##__VA_ARGS__)

typedef void print_char_f(uint8_t c);

char dig2char(int i){ return (i >= 0 && i <= 9) ? (char) ('0' + i) : '?'; }

void fprint_str(print_char_f _writeChar, char* str){
    if(str != NULL){
        while(*str != '\0'){ _writeChar(*(str++)); }
    }else{
        _writeChar('?');
        _writeChar('?');
    }
}

void fprint_ulong(print_char_f _writeChar, char* buffer, unsigned long l){
    if(l == 0){
        _writeChar('0');
        return;
    }
    int i = 0, k = 0, hl;
    while(l > 0){
        buffer[i++] = dig2char((int) (l % 10));
        l /= 10;
    }
    //Reverse Order
    for(hl = i/2; k < hl; k++){
        int idx2 = i - k - 1;
        char tmp = buffer[k];
        buffer[k] = buffer[idx2];
        buffer[idx2] = tmp;
    }
    buffer[i] = '\0';
    fprint_str(_writeChar, buffer);
}

void fprint_long(print_char_f _writeChar, char* buffer, long l){
    if(l < 0){
        _writeChar('-');
        l *= -1;
    }
    fprint_ulong(_writeChar, buffer, (unsigned long) l);
}

void fprint_double(print_char_f _writeChar, char* buffer, double d){
    if(d < 0){
        _writeChar('-');
        d *= -1;
    }
    unsigned long units = floor(d);
    fprint_ulong(_writeChar, buffer, units);
    unsigned long decimals = (unsigned long) (10E3 * (d - units));
    if(decimals > 0){
        _writeChar('.');
        fprint_ulong(_writeChar, buffer, decimals);
    }
}

//Fast Light Weight Printf Implementation
void fprint(print_char_f _writeChar, char* fmt, ...){
    va_list sprintf_args;
    va_start(sprintf_args, fmt);
    char buffer[15];

    while(true){
        switch(*fmt){
            case '%':
                fmt++;
                switch(*(fmt++)){
                    case 'c': _writeChar(va_arg(sprintf_args, int)); break;
                    case 'b': fprint_str(_writeChar, va_arg(sprintf_args, bool)?"true":"false"); break;
                    case 'i': fprint_long(_writeChar, buffer, va_arg(sprintf_args, int)); break;
                    case 'u': fprint_long(_writeChar, buffer, va_arg(sprintf_args, unsigned int)); break;
                    case 'l': fprint_long(_writeChar, buffer, va_arg(sprintf_args, long)); break;
                    case 'U': fprint_ulong(_writeChar, buffer, va_arg(sprintf_args, unsigned long)); break;
                    case 'f': fprint_double(_writeChar, buffer, va_arg(sprintf_args, double)); break;
                    case 'd': fprint_double(_writeChar, buffer, va_arg(sprintf_args, double)); break;
                    case 'p':fprint_ulong(_writeChar, buffer, (unsigned long) va_arg(sprintf_args, void*)); break;
                    case 's': fprint_str(_writeChar, va_arg(sprintf_args, char*)); break;
                    case '\0': return;
                    default: _writeChar('%'); fmt--; break;
                }
                break;
            case '\0': return;
            default: _writeChar(*(fmt++)); continue;
        }
    }
    va_end(sprintf_args);
}

#endif //SPINNERTABLE_BIZZANOMFIO_H
