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

char dig2char(int i){
    switch(i){
        case 0: return '0';
        case 1: return '1';
        case 2: return '2';
        case 3: return '3';
        case 4: return '4';
        case 5: return '5';
        case 6: return '6';
        case 7: return '7';
        case 8: return '8';
        case 9: return '9';
        default: return '?';
    }
}

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

//Fast Light Weight Printf Implementation
void fprint(print_char_f _writeChar, char* fmt, ...){
    va_list sprintf_args;
    va_start(sprintf_args, fmt);
    char buffer[15];
    double number;

    while(true){
        top:
        switch(*fmt){
            case '%':
                fmt++;
                switch(*(fmt++)){
                    case 'c': _writeChar(va_arg(sprintf_args, char)); break;
                    case 'b': fprint_str(_writeChar, va_arg(sprintf_args, bool)?"true":"false"); break;
                    case 'i': number = va_arg(sprintf_args, int); goto write_number;
                    case 'u': number = va_arg(sprintf_args, unsigned int); goto write_number;
                    case 'l': number = va_arg(sprintf_args, long); goto write_number;
                    case 'U': fprint_ulong(_writeChar, buffer, va_arg(sprintf_args, unsigned long)); break;
                    case 'f': number = va_arg(sprintf_args, float); goto write_number;
                    case 'd': number = va_arg(sprintf_args, double); goto write_number;
                    case 'p': number = (long) va_arg(sprintf_args, void*); goto write_number;
                    case 's': fprint_str(_writeChar, va_arg(sprintf_args, char*)); break;
                    case '\0': return;
                    default: _writeChar('%'); fmt--; break;
                }
                goto top;
            case '\0': return;
            default: _writeChar(*(fmt++)); continue;
        }

        write_number:
            if(number < 0){
                _writeChar('-');
                number *= -1;
            }
            unsigned long units = floor(number);
            fprint_ulong(_writeChar, buffer, units);
            unsigned long decimals = (unsigned long) (10E3 * (number - units));
            if(decimals > 0){
                _writeChar('.');
                fprint_ulong(_writeChar, buffer, decimals);
            }
    }
    va_end(sprintf_args);
}

#endif //SPINNERTABLE_BIZZANOMFIO_H
