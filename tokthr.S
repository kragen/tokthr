# Simple direct-token-threaded "Forth" interpreter. -*- asm -*-
# by Kragen Javier Sitaker; dedicated to the public domain,
# i.e. I relinquish whatever exclusive rights copyright law
# gives me with regard to this work.
# Major parts taken from Richard W.M. Jones's public-domain
# JONESFORTH 42 by Richard W.M. Jones <rich@annexia.org>
# http://annexia.org/forth

# This program just outputs "hello, world, hello" under Linux.

# to compile:   
# gcc -m32 -nostdlib -static -o tokthr tokthr.S


### Why Small Things are Interesting

# There are still a lot of computers out there that have tens of
# kilobytes of memory or less, and they cost a lot less than,
# say, a cellphone.  Cellphones are apparently still too
# expensive for half the world's population.  I want to see how
# close I can get to having a comfortable programming
# environment in a smaller device.

# Some smallish microcontroller chips from five different
# manufacturers, with current Digi-Key prices:
# Name              bytes RAM  bytes ROM  MHz  price    
# ATtiny2313        128        2048       20   US$1.38  
# ATMega48-20AU     512        4096       20   US$1.62  
# MSP430F1111AIPW   128        2264       8    US$2.43  
# LPC2101           2048       8192       70   US$2.52  
# H8/300H Tiny      1536       8192       12   US$3.58  
# M16C/R8C/Tiny/1B  1024       16384      12   US$3.54  
# SX28AC/SS         136        3072       50   US$2.79  

# More practically and short-termly, small projects can take
# less time to finish, and I feel like I need to learn about
# different approaches to implementing programming languages.

### Why This is Small

# The normal Forth representation of a function is as an array
# of pointers to the other functions it calls, in sequence; a
# few of those other functions may move the interpreter pointer
# around in that array, or snarf up a constant that's stored in
# the array, or stuff like that, but for the most part, the
# functions just get called in sequence.  This is called
# "threaded code" and it's fairly compact, especially on 16-bit
# systems where the pointers are only two bytes.

# A traditional approach taken by Forth implementations to
# reduce code size even further is called "token threading".
# Rather than making arrays of 16-bit or 32-bit pointers, they
# make lists of 8-bit indices into an array of pointers.  This
# has two advantages:

# 1. the indices are one fourth the size of a list of 32-bit
#    pointers;
# 2. it is possible to save these lists of indices somewhere
#    outside of memory and continue to use them even after
#    making some changes to the code, as long as the same
#    indices in the table have the same meanings.  So, for
#    example, you could write some boot firmware in this
#    "bytecode".

# It also has some disadvantages:
# 1. You run out of space in the table.  Even a fairly minimal
#    full Forth system contains close to 256 subroutines.  You
#    can mitigate this by packing, say, two 12-bit pointers
#    every three bytes, or maybe by having a special bytecode
#    that looks up the next byte in an extended table.
# 2. It's slower and makes the machine-code part of the program
#    take more space.  The traditional LODSW; JMP AX version of
#    $NEXT from the eForth Model, which fetches and executes the
#    next execution token in the threaded list, is three bytes
#    and two instructions; my 'next' here is 12 bytes and four
#    instructions, which is big enough that I jump to it (5
#    bytes) rather than making an assembler macro.  Which blows
#    your branch target buffers to pieces.  Oh well.  I measured
#    the speed hit on my 700MHz PIII laptop on an empty loop at
#    about a factor of 3.5 over simple direct-threading, which
#    in turn is on the order of 10 times slower than machine
#    code.

# Anyway, so this is an example program built using this
# technique.  It implements two Forthlike stacks and interpreted
# subroutines, but not yet the ability to define new subroutines
# at run-time.

### What's Here

# I've implemented all of the primitives from C. H. Ting and
# Bill Muench's public-domain (?) eForth Model 1.0, except for
# the following:
# - I haven't implemented their lowercase "next" (as in FOR
#   NEXT) because I think it's a bad idea, it's complex, and it
#   can be implemented at a higher level if you really need it;
# - I didn't implment !IO because it's a no-op in this context;
# - I haven't yet implemented ?RX, although I think it's
#   possible to implement it on top of syscall5, using select();
# - I haven't implemented TX!, although it would be
#   straightforward to implement on top of "type".

# However, most of it is untested and therefore probably broken.
# Procedure call and return and the system calls do work.

# Currently registers are used as follows:
# %esi --- interpreter pointer; points to next byte to execute
# %ebp --- return stack pointer; points to last thing pushed
# %esp --- data stack pointer; points to last thing pushed
# flags --- the "down" direction flag must be cleared.
#           Fortunately this seems to be the case by default.

# I'll probably try the colorForth thing of keeping the top of
# the data stack in a register and see if that makes things
# smaller.  It probably won't make them faster, since most of
# this interpreter's time will be spent in the interpreting
# loop anyway.

# It's probably missing a couple of primitives needed because of
# the token-threading implementation strategy; the address of
# the token table probably needs to be knowable, at least.

### How Small This Is

# The pure machine-code part of the program runs from 0x08048074
# to 0x08048139, which is 197 bytes.  This is fairly small.  I
# haven't been able to compile or disassemble eForth 1.0 to see
# how big its machine-code part is, but it seemed to be 171
# instructions, while this is 112.  So this is fairly small.

# It uses only 20 different instructions: jmp, jz; push, pop,
# lodsb, lodsl, xchg, mov; movsbl, inc, and, xor, or, lea,
# cdq, rcl, add; int, ret, and call.

# The bytecode part of the program, including the five-byte
# machine-code header on each word, runs from 0x08048139 to
# 0x080481a8, which is another 111 bytes.  At present this just
# includes some system-call glue, a word to exit cleanly, words
# to push literal zero and one, a word to output a string, and a
# few constant strings.

# These two parts add up to 308 bytes.

# Additionally there is some read-only data: 38 pointers to
# words, 13 bytes of "main program", and then some string data:
# "helloworld, \n".  This totals 178 bytes.

# The whole program, therefore, is 486 bytes.  Why "strip" only
# reduces it to 836 bytes, I don't know.  But I don't think that
# problem will carry over to microcontroller contexts.

# One important thing that's missing here is the dictionary
# structure, which will minimally use up another hundred bytes
# or so.

# In another program I coded a fairly simple unsigned decimal
# print routine in assembly; it was 23 instructions and 52
# bytes. I think I can do better in bytecode.

### Other Things I Tried

# I tried switching to caching the top of the data stack in a
# register, on the theory that it would shorten things like
# 'and'.  Currently 'and' is pop %eax; pop %ebx; and %ebx,
# %eax; push %eax; jmp next.  If top of stack is cached in %eax
# instead of being stored in memory, this becomes pop %ebx; and
# %ebx, %eax; jmp next, which is considerably shorter.
# However, most things don't change, and other things become
# longer due to the extra work to save top-of-stack.  I tried
# using both %ebx and %eax as the top-of-stack cache.

# In the version using %ebx as top-of-stack, the total size of
# the machine-code part is 216 bytes, 115 instructions,
# compared to 197 bytes, 112 instructions beforehand for the
# other version, which is a net loss.  In the version using
# %eax as top-of-stack, it was only 215 bytes, but still a net
# loss.

### What's Wrong With This Program

# - It's a long way from doing anything useful.
# - The bytecode is numeric and unreadable, and it confuses
#   disassemblers.
# - Most of the primitives are untested and therefore probably
#   broken, except for dolit_s8, dolit_32, dolist, exit, and
#   syscall5.
# - There's no dictionary structure yet.
# - It probably needs another couple of primitives.
# - There's no checking for stack overflow or underflow, but
#   they will break things.

### The Beginning of the Program

# .. include system library header so we know __NR_exit = 1 and
# __NR_write = 4
#include <asm/unistd.h>

### The token table
	
        .section .rodata        # stuff goes in ELF's read-only data section
        .align 4
token_table:                    # table to define the "bytecode" instructions
        ## These are pointers to machine-code subroutines
        ##   0      1     2      3      4      5
        .int bye, type, hello, world, comma, newline
        ##     6         7          8      9     10
        .int dolit_s8, dolit_32, dolist, exit, execute
        ##       11        12      13   14    15     16    17
        .int branch_on_0, branch, bang, at, c_bang, c_at, rp_at
        ##     18      19    20     21      22      23    24
        .int rp_bang, rpop, rpush, sp_at, sp_bang, drop, dup
        ##    25    26      27     28   29  30     31     32
        .int swap, over, negative, and, or, xor, umplus, r_at
        ##     33        34       35   36     37
        .int syscall5, syscall1, zero, one, syscall3
instructions:
	# And here is the actual "program" in that bytecode.
        .byte 2, 1, 4, 1, 3, 1, 4, 1, 2, 1, 5, 1, 0

### The Return Stack
# We put Forth return addresses here, but programs can also use
# it for other purposes.

        .bss
        .space 4096
initial_return_stack_pointer:   

### Initialization
        	
        .text                   # the following stuff goes in the text segment
        .globl _start           # declare _start as a global symbol 
                                # (otherwise ld won't be able to find it)
_start:                         # this is the entry point for ELF I guess
	mov $initial_return_stack_pointer, %ebp
        mov $instructions, %esi # %esi is the interpreter pointer register
        jmp next                # and now we start the interpreter.
                                # (somewhat silly since we could just
                                # fall through..)

### The Machine-Code Primitives
# Also dolist (aka DOCOL) and next (aka the address interpreter
# or inner interpreter) are in this section.

# dolit_s8 takes a signed 8-bit literal from the instruction
# stream and pushes it onto the stack.
dolit_s8:
        lodsb
        movsbl %al, %eax
        push %eax
        jmp next
dolit_32:                       # more general dolit
        lodsl
        push %eax
        jmp next
# Process colon list by popping saved %eip from stack and 
# putting it into %esi, saving old %esi on return stack.
dolist:                         # approach from eForth 1.0
        xchg %ebp, %esp         # 8 bytes, 5 insns.
        push %esi               # The sub $4, %ebp (or lea)
        xchg %ebp, %esp         # mov %esi, (%ebp) approach was 
        pop %esi                # 1 byte longer.
        jmp next
exit:   xchg %ebp, %esp         # Return from a colon defn.
        pop %esi
        xchg %ebp, %esp
        jmp next
execute:                        # Run xt on data stack.
        ret                     # Here 'xt' is the actual addr,
                                # not the one-byte token.

# Branch if top of stack is 0 (implementing IF).
# Both branch instructions take a signed byte offset from the bytecode
# stream.
branch_on_0:
        pop %eax
        and %eax, %eax
        jz branch
        inc %esi                # skip jump offset
        jmp next
branch:
        lodsb
        movsbl %al, %eax        # same insn size as cbtw; cwde
        add %eax, %esi
        jmp next	

# Store a cell.
bang:   pop %ebx
        pop (%ebx)              # I'm amazed this is legal
        jmp next
# Fetch a cell.
at:     pop %ebx
        push (%ebx)             # XXX illegal
        jmp next

# Store a byte.
c_bang: pop %ebx
        pop %eax
        mov %al, (%ebx)         # push and pop don't do bytes
        jmp next
# Fetch a byte.
c_at:   pop %ebx
        xor %eax, %eax
	mov (%ebx), %al
        push %eax
        jmp next
# Get the return stack pointer.
rp_at:  push %ebp
        jmp next
# Set the return stack pointer.
rp_bang:
        pop %ebp
        jmp next
# Pop the return stack to the data stack ( R> )
rpop:   push (%ebp)
        lea 4(%ebp), %ebp       # add or xchg/pop: same size
        jmp next
# Push the return stack from the data stack ( >R )
rpush:  lea -4(%ebp), %ebp
        pop (%ebp)
        jmp next

# Get the data stack pointer (before it gets pushed).
sp_at:  push %esp               # safe on 286 and later
        jmp next
# Set the data stack pointer.
sp_bang:
        pop %esp
        jmp next
# Pop the stack.
drop:   pop %eax
        jmp next
# Push a copy of TOS.
# eForth 1.0 used BX to index the stack here, for a couple of
# reasons: on the 8086, SP got decremented prior to the fetch,
# and also wasn't valid as a base or index register.
dup:    push (%esp)
        jmp next
# Swap top two stack items ("exch" in PostScript)
swap:   pop %eax
        pop %ebx
        push %eax
        push %ebx
        jmp next
# Stack manipulation ( w1 w2 -- w1 w2 w1 )
# technically not necessary, but it's so easy and tiny
over:   push 4(%esp)           
#        jmp next               fall through because "next" is next
	
# "next" fetches the next bytecode and runs it.  It's placed
# here in the middle of the bytecode definitions so that more
# of them can use the short two-byte jump form to get to it.

next:
        xor %eax, %eax          # set %eax to 0
        lodsb                   # load %al from where %esi points
                                # (%esi is the interpreter pointer)
        lea token_table(,%eax,4), %eax  # eax := token_table + eax * 4bytes
        jmp *(%eax)             # now %eax points at an address in the token
                                # table; so we fetch that address from the
                                # token table and jump to it.

# Push true if n negative. ( n -- f )
negative:
        pop %eax                
        cdq
        push %edx
        jmp next
# Bitwise operators:  
and:    pop %eax
        pop %ebx
        and %ebx, %eax
        push %eax
        jmp next
or:     pop %eax
        pop %ebx
        or %ebx, %eax
        push %eax
        jmp next
xor:    pop %eax
        pop %ebx
        xor %ebx, %eax
        push %eax
	jmp next
# add two unsigned numbers, returning sum and carry.
# ( u1 u2 -- u3 cy )
umplus:
        xor %ecx, %ecx
        pop %eax
        pop %ebx
        add %ebx, %eax
        rcl $1, %ecx
        push %eax
        push %ecx
        jmp next

# Copy the top of the return stack onto the data stack.
# May be the traditional Forth word "I".
r_at:   push (%ebp)
        jmp next

# syscall5:   
# Linux system call with up to 5 arguments
# This is no longer the fashionable way to make system calls
# in Linux.  Now you're supposed to use SYSENTER on newer
# CPUs, and rather than have you figure out which one to use,
# the kernel mmaps a chunk of code called a VDSO into your
# memory space at a random address and tells you where to
# find it using the ELF auxiliary vector.  Then you're
# supposed to invoke the dynamic linker or something to parse
# the ELF executable mysteriously manifested in this way by
# the kernel, and then resolve an undefined symbol in libc
# into calls to it.  See "What is linux-gate.so.1?"
# http://www.trilithium.com/johan/2005/08/linux-gate/
# "The Linux kernel: System Calls" by Andries Brouwer, 2003-02-01
# http://www.win.tue.nl/%7Eaeb/linux/lk/lk-4.html
# "About ELF Auxiliary Vectors" by Manu Garg
# http://manugarg.googlepages.com/aboutelfauxiliaryvectors

# But the old int $0x80 approach still works, thank goodness,
# because all of that is *way* more than these ten
# instructions.
syscall5:
        pop %edi
        ## we have to save %esi for the interpreter
        mov %esi, -4(%ebp)
        pop %esi
        pop %edx
        pop %ecx
        pop %ebx
        pop %eax
        int $0x80
        push %eax
        mov -4(%ebp), %esi
        jmp next

### Basic Interpreted Words

# System call with three arguments.
syscall3:
        call dolist
        .byte 35, 35, 33, 9     # push two 0s, syscall5, ret
# System call with one argument.
syscall1:       
        call dolist
        .byte 35, 35, 37, 9     # push two 0s, syscall3, ret
bye:    call dolist
        .byte 6,__NR_exit, 35, 34, 9
zero:   call dolist             # push 0
        .byte 6,0, 9
one:    call dolist             # push 1
        .byte 6,1, 9

	
# This word outputs a string whose address and count are on 
# the stack.  ( b u -- )
# "call dolist" magically treats whatever follows as bytecode.
# This confuses disassemblers.
type:    call dolist
        .byte 20, 20            # move two args onto rstack
        .byte 6,__NR_write      # system call is __NR_write
        .byte 36                # push constant 1: stdout
        .byte 19, 19            # move two args back from rstack
        .byte 37                # call syscall with 3 args
        .byte 23                # discard return value
        .byte 9                 # return

# The last few words exist just to poke string addresses
# and lengths onto the stack so "type" can print them.
# (I probably should have just written a gas macro...)
hello:  call dolist
        .byte 7                 # dolit_32 pushes a 32-bit
        .int hello_string       # literal, an addr here
        .byte 6,5, 9	        # push literal 5 and return
        .section .rodata        # define the actual string:
hello_string:
        .ascii "hello"
        .text

world:  call dolist
        .byte 7
        .int world_string
        .byte 6,5, 9	
        .section .rodata
world_string:
        .ascii "world"
        .text

comma:  call dolist
        .byte 7
        .int comma_string
        .byte 6,2, 9            # comma string only 2 in length
        .section .rodata
comma_string:
        .ascii ", "
        .text

newline:        
        call dolist
        .byte 7
        .int newline_string
        .byte 6,1, 9
        .section .rodata
newline_string:
        .ascii "\n"
        .text
