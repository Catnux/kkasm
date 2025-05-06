# KKASM
KKASM is the assembler for KittyKernel. It is written in pure Zig, and should be completely cross-platform.
## Syntax
Each line of KKASM assembly is terminated by a semicolon, and all but one type of line has a sigil prefixing it. 
Example code: 

        
    %testregister 0; /Register alias;
    %one 1;
    %counter_ptr 2;
    
    .TEST_CONST 12345; /Constant;
    
    LOD %testregister .TEST_CONST; /LOD instruction. Loads .TEST_CONST into %testregister;
    LOD %one 1; /Create "one" register;
    LOD %counter_ptr #counter; /Load the mark into %counter_ptr;
    
    #counter; /Create a mark named "counter" here;
    ADD %test %one; /Add one to %test;
    JWC %one %counter_ptr; /Jump back to the mark.
This simple program counts up from 12345. In it you can see a few of the types of lines being used. This creates three register aliases, which are prefixed by %. These allow you to use names instead of numbers 0-9 for registers. It also defines a constant, which is simply a placeholder number. Constants are prefixed by a period. Instructions have no prefix and have two inputs. The first one is a register or alias, and the second one is a register or alias for most instructions, or a mark, constant, or integer value if the instruction takes a static input. You can also directly insert bites with the prefix of +. `*x;' multiplies the previous bite by x.

