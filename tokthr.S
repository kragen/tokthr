# Simple token-threaded "Forth" interpreter. -*- asm -*-
# Version 3.
# by Kragen Javier Sitaker; dedicated to the public domain,
# i.e. I relinquish whatever exclusive rights copyright law
# gives me with regard to this work.
# Major parts taken from Richard W.M. Jones's public-domain
# JONESFORTH 42 by Richard W.M. Jones <rich@annexia.org>
# http://annexia.org/forth

# As of version 2, this program just outputs the following under
# Linux:
# hell, world, hello
# -120 1 104 
# s: 102 101 100 
# 397 
# lit8 lit ret execute (if) (else) (loop) ! @ c! c@ rp@ rp! r> >r sp@ sp! pop dup over swap 0< & | ^ um+ /% um* r@ syscall5 syscall3 syscall1 bye 0 1 type hello world comma count cr -1 + 1- rot -rot tuck emit u. (u.) ((u.)) ~ 1+ negate . scolon .s pick cells * depth - / cellsize nip (do) i 2dup 2drop dict dictp dictsize nextword pastdict? words < >= 0= cbcmp c@+ bcmp memcmp unloop find r2@ 2swap 
# hello134517863 
# , 0 
# 134517710 

# to compile:   
# gcc -m32 -nostdlib -static -o tokthr2 tokthr2.S


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

# There are essentially no 386-compatible devices in this price
# range as far as I can tell; for why I'm not worried about
# that, see the section "How Small This Is".

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
#    and two instructions; my 'next' here is 41 bytes and 14
#    instructions, which is big enough that I jump to it (2
#    bytes) rather than making an assembler macro.  Which blows
#    your branch target buffers to pieces.  Oh well.  The
#    performance penalty is probably two orders of magnitude
#    over native code, but I haven't measured it yet.  I
#    measured an earlier version on my 700MHz PIII laptop on an
#    empty loop at about a factor of 3.5 over simple
#    direct-threading, which in turn is on the order of 10 times
#    slower than machine code.

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
#   instead, I implemented (loop).        
# - I didn't implement !IO because it's a no-op in this context;
# - I haven't yet implemented ?RX, although I think it's
#   possible to implement it on top of syscall5, using select();
# Additionally, I implemented multiply and divide primitives.

# However, some of it is untested and therefore probably broken.
# Procedure call and return and the system calls do work.

# Currently registers are used as follows:
# %esi --- interpreter pointer; points to next byte to execute
# %ebp --- return stack pointer; points to last thing pushed.  This stack, 
#          like the other one, grows downwards.
# %esp --- data stack pointer; points to last thing pushed.  This is
#          the processor's standard stack pointer; "push" and "pop"
#          instructions use it, which makes assembly code to use it
#          quite concise.  The Intel "call" and "ret" instructions
#          would also use this stack, but they aren't used in this
#          program.
# flags --- the "down" direction flag must be cleared.

# It's probably missing a couple of primitives needed because of
# the token-threading implementation strategy; the address of
# the token table probably needs to be knowable, at least.

# Direct and indirect threading, the normal Forth approaches to
# allowing unrestricted coexistence of words written in assembly
# language and interpreted Forth, both had heavy space costs
# here --- close to 100% for the bytecode currently in the
# system.  So the inner interpreter checks, for each bytecode,
# whether it is in the range of bytecodes whose interpretations
# are in native code, and picks the relevant code path.  This
# avoids consuming any space per-word for this distinction, but with
# what appears to be a heavy performance cost.

# This is similar to an approach called "bit threading"; as
# explained by Jeff Fox in a comp.lang.forth message
# 2007-05-13, on thread "Cases where Forth seems a little
# clunky":

#       I have seen hardware and software implemenations of
#       bit-threading where the msb of the address space
#       selects between threaded code address lists and
#       addresses of CODE subroutines. In both cases 0 is a
#       valid address and negative addresses are valid. I think
#       this applied to Novix.

# Except that this approach uses a fraction of a bit for most
# tokens instead of a whole bit.

### How Small This Is

# As a point of comparison, eForth 1.0's machine-code part seems
# to be 171 instructions and 399 bytes, including some data
# that's mixed in there with it.

# As of version 3, the machine-code part of this interpreter is
# 239 bytes in 129 machine-code instructions, plus 19 bytes of
# read-only data, 172 bytes of token table for the 86
# currently-defined words (30 of which are primitive), 397
# bytes of their names, and another 370 bytes of bytecode in
# the 56 bytecode words (including a couple of data values
# scattered around), and then another 56 bytes in the main
# program, for a total of 1253 bytes.  So the program is
# already less than half written in assembly, in terms of
# object-code size.

# As of version 3, the machine-code part of this program uses
# only 25 different instructions: cld; jmp, jz, jnc, jbe; push,
# pop, lodsb, lodsl, xchg, mov; cmp, movsbl, inc, and, xor, or,
# lea, cdq, rcl, add, idiv, imul; and int.  Interestingly, many
# of them are only used once.

# Just before version 3, the non-comment lines were 14%
# assembler macros, 51% assembly language, and 35% bytecode.

# From Brad Rodriguez's January/February 1993 Computer Journal
# article, "Moving Forth: Part 1: Design Decisions in the Forth
# Kernel":
#       You can expect the usual 16-bit Forth kernel (see below)
#       to occupy about 8K bytes of program space. For a full
#       kernel that can compile Forth definitions, you should
#       allow a minimum of 1K byte of RAM.

# I'm pretty sure I can beat the 8K requirement by quite a bit
# and still be able to compile Forth definitions --- I'm hoping
# for a factor of 4.  Consider, from Jeff Fox's "Thoughtful
# Programming", chapter 3: http://www.ultratechnology.com/forth3.htm

#       People assume that since Chuck has refined his Forth down to
#       about a 1K object that this means he has just stripped his
#       Forth down to a 1K kernel that will boot like in the old days
#       and that he is going to compile a complete Forth system on top
#       of the 1K before he starts an application. This is wrong. The
#       complete Forth system is 1K, and the reason for that is
#       maximize Chuck's productivity. What stops people from doing
#       what they need to do to solve a problem is all the time spend
#       solving all the related sub-problems that pop up as a result
#       of complex interconnections between components. To maximize
#       his productivity Chuck minimizes the number of these side
#       problems that pop up. Keep it simple, and don't get to where
#       you are spending 90% or 99% or you time dealing with related
#       sub-problems. Avoid unsolvable problems, don't waste your time
#       trying to solve them.

# Consider also this quote from Elizabeth Rather:

#       As you have seen, so much depends on the specific
#       machine architecture. We implemented a TTC [token
#       threaded] Forth on some low-end AVR processors with
#       very limited code space, and it ran faster than a
#       native-code 8051 at comparable clock speed.

# (2007-06-23 comp.lang.forth post on thread "Build your own
# Forth for Microchip PIC (Episode 838): Threading")
# http://objectmix.com/forth/168105-build-your-own-forth-microchip-pic-episode-838-threading.html

# Consider also this quote from the abstract of Frank
# Sergeant's 1991 "A 3-Instruction Forth for Embedded Systems
# Work: Illustrated on the Motorola MC68HC11":

#       A 3- instruction Forth makes Forth affordable for
#       target systems with very limited memory. It can be
#       brought up quickly on strange new hardware. You don't
#       have to do without Forth because of memory or time
#       limitations. It only takes 66 bytes for the Motorola
#       MC68HC11. Full source is provided. . . . The absolute
#       minimum the target must do, it seems to me, is fetch a
#       byte, store a byte, and call a subroutine.

# http://pygmy.utoh.org/3ins4th.html

# As I said before, there are no small, cheap 386s, and so of
# course the code size of this version is an approximation, and
# it won't be a simple recompile to port it to one of these
# other architectures; but 129 instructions' worth of assembly
# are probably not that big a deal to rewrite for a new
# platform.  (I'll probably want to write multiply and divide
# routines, though.)

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
# the machine-code part was 216 bytes, 115 instructions,
# compared to 197 bytes, 112 instructions for the version using
# the current strategy.  In the version using %eax as
# top-of-stack, it was only 215 bytes, but that's still worse
# than 197.

# In previous versions, all routines were machine-code routines
# that you could just jmp to.  High-level bytecode words began
# with "call dolist", which took the saved %eip off the stack
# and stuck it in %esi.  Unfortunately, that added 5 bytes to
# each bytecode word; in version 2, the bytecode region is 221
# bytes and contains 36 word definitions (the 30 machine-code
# primitives aren't defined there) --- so 5 bytes each would
# have been 180 bytes of overhead, or 82%!  It also would have
# required a region to be both executable and writable to
# support run-time routine definition, which is kind of a pain
# thse days, and also on Harvard-architecture microcontrollers.

# In previous versions, the token-table entries were 32 bits
# each (instead of 16 bits as they are now), which added
# another 2 bytes of overhead per word.  In version 2, there
# are currently 66 words, so that's another 132 bytes of shaved
# overhead.

### Performance (Speed)

# To version 2, I added a simple program to print out a
# badly-formatted 8-bit extended ASCII table; it was 11
# bytecode operations long.  It executed 81615 bytecodes in all
# (according to gdb).  On my 700MHz PIII-Coppermine laptop from
# 1999, 'time' reports CPU times varying from 4-12
# milliseconds.  So it seems like it can execute about 10 000
# bytecodes in a millisecond, or about 10 million bytecodes in
# a second --- about 100ns per bytecode.

# It also made 1459 system calls.

# That's slightly faster than Python's bytecode engine (maybe
# --- probably within measurement error --- and anyway Python's
# bytecodes are larger-grained), and an order of magnitude
# slower than simple direct-threading, and about three times
# slower than direct-threading with a simple bytecode
# indirection layer.

# I would be surprised if version 3 had any measurable change
# in speed from version 2.

# To version 3, I added a little loop to repeatedly search the
# 86-word wordlist for ", ", which isn't there.  I was able to
# do this search 10 000 times in 4.59 CPU seconds, which is
# 5.34 microseconds per comparison, or about 3700 CPU cycles.
# If we eventually have 300 words in the wordlist, each search
# will therefore take 1.6 milliseconds in the worst case, so
# the system won't be able to compile or interpret more than
# about 50-100 lines of code per second.  It should probably be
# pretty easy to fix this particular performance problem
# (recode wordlist search in asm, restructure, or whatever) if
# it comes up, but it's a bit worrisome...

### What's Wrong With This Program

# - It's a long way from doing anything useful.
# - There's 21 instructions of unused code which may be broken.
#   In Version 3, these words are in use and so probably work:
#   hello, sub1, type, comma, world, newline, dolit_s8, dot,
#   bye, exit, branch_on_0, c_bang, drop, dup, swap, negative,
#   umplus, divmod, syscall5, syscall3, zero, syscall1, rpop,
#   rpush, one, dolit_32, neg1, add, emit, tuck, udot,
#   udot_nospc, udot_nonzero, branch, invert, add1, negate,
#   xor, printstack, cells, mul, depth, div, sub, cellsize,
#   nip, pick, twodup, i, _do, r_at, over, at, sp_at, bang,
#   twoswap, r_2at, find, unloop, memcmp, bcmp, c_at_inc,
#   cbcmp, zeq, ge, lt, words, pastdict, nextword, dictsize,
#   dictp, dict, c_at.  These are not tested, and therefore may be
#   broken: execute, rp_at, rp_bang, sp_bang, and, or.
# - There's no dictionary structure yet.
# - It probably needs another couple of primitives.
# - There's no checking for stack overflow or underflow, but
#   they will break things.
# - It's slow; see above about performance.

### The Beginning of the Program

# .. include system library header so we know __NR_exit = 1 and
# __NR_write = 4
#include <asm/unistd.h>

### The token table and dictionary

        # To save space, we're trying to avoid storing pointers
        # as much as possible.  So most of the code is
        # represented as "tokens", which are offsets into the
        # "token table", which contains 16-bit offsets into
        # either the machine-code primitives or the data
        # segment.

        # The "dictionary" is stored in this program as a
        # sequence of strings, stuffed next to each other with
        # no intervening pointers at all.  The idea is that if
        # you want to execute or compile a word, you walk
        # through the dictionary, examining each string in turn
        # to see if it's the right word.  If so, then the
        # number of strings you rejected is the index into the
        # token table.

        # This implies that the dictionary needs to be stored
        # somewhere where it can expand without overwriting
        # other stuff.  So I'm putting it in its own section
        # for the time being.  I'm pretty sure that means it'll
        # get at least a page, which is enough space to define
        # at least several hundred words.  Maybe at some future
        # time I'll copy it into .bss at boot time instead.

        .data 1                 # Start putting stuff in data subsection 1
        .align 4
        ## table to define the "bytecode" instructions
token_table:
        # "a" means "allocatable", "w" means "writable"
        .section .dictionary, "aw"
dictionary:

        ## I was frustrated with the unreadability of my
        ## bytecode lists; I was counting token table entries
        ## by hand and writing bytecodes numerically.  So I
        ## wrote a macro to help.

        ## Note that we are using a separate .subsection
        ## directive because gas 2.17 doesn't support putting
        ## that in the .pushsection line, even though it is
        ## documented to do so; see message from Maciej
        ## W. Rozycki on 2007-10-11, subject "Re: How to use
        ## .pushsection?",
        ## http://sourceware.org/ml/binutils/2007-10/msg00176.html
        ## for more details)

        ## The first few entries in the table of bytecodes are
        ## all defined in machine code; the rest are all
        ## defined in bytecode.  The inner interpreter examines
        ## each bytecode to determine which category it falls
        ## in in order to figure out how to execute it,
        ## including what base address to add its offset to.
        ## This sucks for extensibility but rocks for
        ## compactness.

        .macro countedstring name
        .byte stringlength\@
1:      .ascii "\name"
        ## Here we count the length of the string --- computers
        ## are for counting bytes so people don't have to!
        stringlength\@ = . - 1b
        .endm

        .macro define_bytecode name, realname, origin
        .pushsection .data      # save current position, go to data section
        .subsection 1           # and subsection 1, where we put the addrs
        b_\name = (. - token_table) / 2 # define b_foo as the index of this ptr
        .ifeq b_\name - 256
        .error "\name got bytecode 256"
        .endif
        .short \name - \origin # insert offset which will be resolved next
        .popsection             # return to where we were, and
        .pushsection .dictionary
        countedstring "\realname"
        .popsection
\name:                          # define the name
        .endm
        .macro defasm name, realname
        define_bytecode \name, "\realname", machine_code_primitives
        .endm
        .macro defbytes name, realname
        define_bytecode \name, "\realname", bytecode_start
        .endm

### The Return Stack
# We put Forth return addresses here, but programs can also use
# it for other purposes.

        .bss
        .space 4096
initial_return_stack_pointer:   

### Initialization
                
        .text                   # the following stuff goes in the text segment
        .global _start          # declare _start as a global symbol 
                                # (otherwise ld won't be able to find it)
_start:                         # this is the entry point for ELF I guess
        cld                     # clear direction flag; unnecessary?
        mov $initial_return_stack_pointer, %ebp
        mov $instructions, %esi # %esi is the interpreter pointer register
        jmp next                # and now we start the interpreter.
                                # (somewhat silly since we could just
                                # fall through..)

### The Machine-Code Primitives
# Also next (aka the address interpreter or inner interpreter)
# is in this section.

machine_code_primitives:
                
# dolit_s8 takes a signed 8-bit literal from the instruction
# stream and pushes it onto the stack.

        defasm dolit_s8, "lit8"
        lodsb
        movsbl %al, %eax
        jmp pusheax

        defasm dolit_32, "lit"  # more general dolit
        lodsl
        jmp pusheax
        
        defasm exit, "ret"      # Return from a colon defn.
        xchg %ebp, %esp
        pop %esi
        xchg %ebp, %esp
        jmp next

        defasm execute, "execute" # Run xt on data stack.
        pop %eax                # Here 'xt' is the one-byte token.
        jmp execute_eax

# Branch if top of stack is 0 (implementing IF).
# Both branch instructions take a signed byte offset from the bytecode
# stream.
        defasm branch_on_0, "(if)"
        pop %eax
        and %eax, %eax
        jz branch
        inc %esi                # skip 1-byte jump offset
        jmp next

        defasm branch, "(else)"
        lodsb
        movsbl %al, %eax        # same insn size as cbtw; cwde
        add %eax, %esi
        jmp next        

# (loop) is what we do at the end of a DO LOOP.

# DO puts a number on top of the return stack that is zero minus
# the number of iterations remaining.  So when it finally
# reaches zero, we're done.  It also put a number underneath
# that on the return stack from which you can recover the
# iteration counter.

# This scheme is mostly due to F-83, except that in F-83 it
# reached 0x8000 instead of 0, which seemed perverse to me.

# This isn't strictly necessary as part of the minimal primitive
# set, but it seemed like it would make inner loops maybe ten
# times faster, and as with most words that do return-stack
# manipulation, the size penalty is actually negative.  (This
# version is 14 bytes; in bytecode it would be 17.)

# ( -- ) ( R: -1 adjustment -- ) in end-of-loop case, and skip
# the interpreter pointer over the jump offset.
# ( -- ) ( R: counter -- counter+1 ) in normal case,  and adjust
# interpreter pointer by number of bytes stored after call to
# this routine.

        defasm _loop, "(loop)"
        xor %eax, %eax          # mov $1, %eax is 5 bytes
        inc %eax
        add %eax, (%ebp)
        jnc branch              # if no carry, go branch
        # If there was a carry, we're done!
        add $8, %ebp            # drop loop-sys from rstack
        lodsb                   # skip jump offset
        jmp next

# Store a cell.
        defasm bang, "!"
        pop %ebx
        pop (%ebx)              # I'm amazed this is legal
        jmp next

# Fetch a cell.
        defasm at, "@"
        pop %ebx
        push (%ebx)             # I'm amazed this is legal too
        jmp next

# Store a byte.
        defasm c_bang, "c!"
        pop %ebx
        pop %eax
        mov %al, (%ebx)         # push and pop don't do bytes
        jmp next

# Fetch a byte.
        defasm c_at, "c@"
        pop %ebx
        xor %eax, %eax
        mov (%ebx), %al
        jmp pusheax
        
# Get the return stack pointer.
        defasm rp_at, "rp@"
        push %ebp
        jmp next
        
# Set the return stack pointer.
        defasm rp_bang, "rp!"
        pop %ebp
        jmp next
        
# Pop the return stack to the data stack
        defasm rpop, "r>"
        xchg %esp, %ebp
        pop %eax
        xchg %esp, %ebp
        jmp pusheax
        
# Push the return stack from the data stack
        defasm rpush, ">r"
        lea -4(%ebp), %ebp
        pop (%ebp)
        jmp next

# Get the data stack pointer (before it gets pushed).
        defasm sp_at, "sp@"
        push %esp               # safe on 286 and later
        jmp next

# Set the data stack pointer.
        defasm sp_bang, "sp!"
        pop %esp
        jmp next
        
# Pop the stack.
        defasm drop, "pop"
        pop %eax
        jmp next
        
# Push a copy of TOS.
# eForth 1.0 used BX to index the stack here, for a couple of
# reasons: on the 8086, SP got decremented prior to the fetch,
# and also wasn't valid as a base or index register.
        defasm dup, "dup"
        pop %eax
        push %eax
        jmp pusheax
        
# Stack manipulation ( w1 w2 -- w1 w2 w1 )
# technically not necessary, but it's so easy and tiny
        defasm over, "over"
        push 4(%esp)           
        jmp next

# Swap top two stack items ("exch" in PostScript)
        defasm swap, "swap"
        pop %edx
        pop %eax
#       jmp pushedxeax       fall through because pushedxeax is next

# pusheax and pushedxeax: a prologue to 'next' that first pushes %edx
# and %eax, or just %eax.

# For a net savings of 13 bytes, last I checked, in all those
# primitives that finish up by pushing something!  Clever trick from
# F-83's 1PUSH and 2PUSH.
pushedxeax:     
        push %edx
pusheax:        
        push %eax
        # now we fall through to 'next'
                
# "next" fetches the next bytecode and runs it.  It's placed
# here in the middle of the bytecode definitions so that more
# of them can use the short two-byte jump form to get to it.

next:
        xor %eax, %eax          # set %eax to 0
        xor %ebx, %ebx          # clear high half of %ebx
        lodsb                   # load %al from where %esi points
                                # (%esi is the interpreter pointer)
execute_eax:
        ## load offset of new word into %ebx
        mov token_table(,%eax,2), %bx  # bx := token_table[eax * 2bytes]
        cmp $last_asm_bytecode, %eax
        jbe next_primitive      # if primitive, handle primitive word
        ## otherwise, handle a bytecode definition or "colon list"
        # save old %esi on return stack
        xchg %ebp, %esp
        push %esi
        xchg %ebp, %esp
        lea bytecode_start(%ebx), %esi
        jmp next

next_primitive:
        lea machine_code_primitives(%ebx), %ebx
        jmp *%ebx
        

# Push true if n negative. ( n -- f )
        defasm negative, "0<"
        pop %eax                
        cdq
        push %edx
        jmp next

# Bitwise operators:
        defasm and, "&"
        pop %eax
        pop %ebx
        and %ebx, %eax
        jmp pusheax

        defasm or, "|"
        pop %eax
        pop %ebx
        or %ebx, %eax
        jmp pusheax

        defasm xor, "^"
        pop %eax
        pop %ebx
        xor %ebx, %eax
        jmp pusheax
        
# add two unsigned numbers, returning sum and carry.
# ( u1 u2 -- u3 cy )
        defasm umplus, "um+"
        xor %eax, %eax
        pop %edx
        pop %ebx
        add %ebx, %edx
        rcl $1, %eax
        jmp pushedxeax

# Divide double-precision by single-precision, unsigned (?).
# UM/MOD from eForth.  ( udl udh un -- ur uq )
        defasm divmod, "/%"
        pop %ebx
        pop %edx
        pop %eax
        idiv %ebx
        jmp pushedxeax

# Multiply two single-precision numbers, giving a double-
# precision result. ( d1 d2 -- udl udh )
        defasm mmul, "um*"
        pop %eax
        pop %ebx
        imul %ebx
        push %eax
        push %edx
        jmp next

# Copy the top of the return stack onto the data stack.
        defasm r_at, "r@"
        push (%ebp)
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
        defasm syscall5, "syscall5"
        pop %edi
        ## we have to save %esi for the interpreter
        mov %esi, -4(%ebp)
        pop %esi
        pop %edx
        pop %ecx
        pop %ebx
        pop %eax
        int $0x80
        mov -4(%ebp), %esi
        jmp pusheax

        last_asm_bytecode = b_syscall5

### Basic Interpreted Words
        ## a macro for defining interpreted words
        ## Because after I left off b_exit once, I wasted a long
        ## time trying to figure out what was wrong, so I use this when I can:
        .macro def name, realname, bytes:vararg
        defbytes \name, "\realname"
        .byte \bytes
        .byte b_exit
        .endm
        ## Macros for conditional branch and loop:
        ## Because I am tired of tracking down bugs due to 
        ## getting the jump offsets wrong.
        .macro fif, target      # if, or end of while loop
        .byte b_branch_on_0, \target - . - 1
        .endm
        .macro floop, target    # do loop
        .byte b__loop, \target - . - 1
        .endm
        .macro felse, target    # else, unconditional jump
        .byte b_branch, \target - . - 1
        .endm

        .data 2                 # separate subsection from token table
bytecode_start:
# System call with three arguments.
        def syscall3, "syscall3", b_zero, b_zero, b_syscall5
# System call with one argument.
        def syscall1, "syscall1", b_zero, b_zero, b_syscall3
        def bye, "bye", b_dolit_s8,__NR_exit, b_zero, b_syscall1 # exit program
        def zero, "0", b_dolit_s8,0            # push 0
        def one, "1", b_dolit_s8,1
        
# This word outputs a string whose address and count are on 
# the stack.  ( b u -- )

        defbytes type, "type"
        .byte b_rpush, b_rpush  # move two args onto rstack
                                # system call is __NR_write:    
        .byte b_dolit_s8,__NR_write
        .byte b_one             # push constant 1: stdout
        .byte b_rpop, b_rpop    # move two args back from rstack
        .byte b_syscall3        # call syscall with 3 args
        .byte b_drop            # discard return value
        .byte b_exit            # return

# The next few words exist just to poke string addresses
# and lengths onto the stack so "type" can print them.
        .macro def_counted_string name, contents
        defbytes \name, "\name"
        .byte b_dolit_32        # dolit_32 pushes a 32-bit
        .int string_\name       # literal --- an addr, here
                                # now push literal length and return
        .byte b_count, b_exit
        .pushsection .rodata    # define the actual string:
string_\name:
        countedstring "\contents"
        .popsection
        .endm

        def_counted_string hello, "hello"
        def_counted_string world, "world"
        def_counted_string comma, ", "

        # convert a counted string in memory to an address and
        # count on the stack
        def count, "count", b_dup, b_add1, b_swap, b_c_at

        def cr, "cr", b_dolit_s8, '\n, b_emit

### Some More Basic Words

        def neg1, "-1", b_dolit_s8, -1   # ( -- -1 )
        def add, "+", b_umplus, b_drop  # ( a b -- a+b ) drop the carry
        def sub1, "1-", b_neg1, b_add    # ( n -- n-1 )
        def rot, "rot", b_rpush, b_swap, b_rpop, b_swap # ( a b c -- b c a )
        def unrot, "-rot", b_rot, b_rot    # ( a b c -- c a b )
        def tuck, "tuck", b_dup, b_unrot    # ( a b -- b a b )

# emit: output a single byte.  eForth calls this "TX!".

# This version is 11 bytes, including the buffer byte, plus the 2-byte
# token table pointer. a machine-code version I wrote the other day
# was 28 bytes.  However, I also added rot, unrot, and tuck to support
# this function, and they total 11 bytes, plus 6 bytes of overhead.
# For a total of 11+2+11+6 = 30 bytes.  Not winning yet on size over
# x86 asm!  But we're getting close.

emit_buffer:
        .byte 0
        defbytes emit, "emit"
        .byte b_dolit_32
        .int emit_buffer
        .byte b_tuck            # save a copy of address for b_type
        .byte b_c_bang          # store into emit buffer
        .byte b_one, b_type, b_exit # output one-byte buffer

### "u." prints out an unsigned number.
# I had a version of this in x86 machine code in 52 bytes (23
# instructions), essentially exactly the same code as here.
# This is 31 bytes, plus 6 bytes of overhead, plus I had 
# to define b_divmod (9 bytes plus 2 bytes overhead).  Now we are
# starting to win!

        defbytes udot, "u."            # print space after number
        .byte b_udot_nospc, b_dolit_s8, 0x20, b_emit, b_exit 
        defbytes udot_nospc, "(u.)"    # print number without space
        .byte b_dup
        fif 1f
        .byte b_udot_nonzero, b_exit
1:      .byte b_drop, b_dolit_s8, '0, b_emit, b_exit
        defbytes udot_nonzero, "((u.))"
        .byte b_zero, b_dolit_s8,10, b_divmod # divide by 10
        .byte b_dup
        fif 2f                  # recurse if nonzero
        .byte b_udot_nonzero
        felse 3f
2:      .byte b_drop            # drop zero quotient
3:      .byte b_dolit_s8, '0, b_add, b_emit # print digit
        .byte b_exit
        
### Add signed numeric output, ".".  This cost 20 bytes plus 8 bytes
# of overhead, but added some fundamental numeric operations; only 12
# of those 28 bytes are specific to "."

        # logical bitwise not
        def invert, "~", b_dolit_s8, -1, b_xor
        def add1, "1+", b_one, b_add
        # arithmetic negation
        def negate, "negate", b_invert, b_add1
        # print signed number
        defbytes dot, "."
        .byte b_dup, b_negative
        fif 1f
        .byte b_dolit_s8, '-, b_emit, b_negate # in the negative case
1:      .byte b_udot, b_exit

### Obviously the next thing to do is to add ".S", print the
# stack, so that I can stop having to investigate problems by
# using gdb.

# The bytecode for this consumed 78 bytes in 12 words, plus a
# new 8-byte primitive (mmul) and a new 14-byte primitive
# (_loop), plus six bytes in the initialization routine, for 28
# bytes of overhead and a total of 78+28+14+8+6 = 134 bytes.
# This is definitely not a size win over machine code!  Machine
# code would only be 22 bytes in 7 instructions, if there were a
# way to just CALL the "." routine from machine code, which
# there isn't.
        
# However, the words added were  cells * - / cellsize nip (do)
# (loop) 2dup  which are all generally useful, and  
# depth pick .s  which are more special-purpose.
# The special-purpose words are 35 out of those 78 bytes.  

# PRINTSTACK itself is only 15 bytes, and there's hope that the
# 6 bytes of PICK and the 14 bytes of DEPTH will be useful in
# other debugging routines.

# I'm not happy with (do) and (loop), only because (do)
# implements dpANS DO, not dpANS ?DO, so it loops many times
# when it should loop zero times;

        def_counted_string scolon, "s: "
        defbytes printstack, ".s"
        .byte b_scolon, b_type
        .byte b_depth, b_zero   # loop limits
        .byte b_twodup, b_xor
        fif 1f                  # skip loop if stack empty
        .byte b__do
2:      .byte b_i, b_pick, b_dot # DO I PICK . LOOP
        floop 2b
1:      .byte b_cr, b_exit
        def pick, "pick", b_add1, b_cells, b_sp_at, b_add, b_at
        def cells, "cells", b_cellsize, b_mul
        def mul, "*", b_mmul, b_drop # drop upper 32 bits of multiplication result
bottom_of_stack:
        .int 0
        defbytes depth, "depth"
        .byte b_sp_at, b_dolit_32
        .int bottom_of_stack
        .byte b_at, b_swap, b_sub, b_zero, b_cellsize, b_div, b_exit

        def sub, "-", b_negate, b_add # subtract ( a b -- a-b )
        def div, "/", b_divmod, b_nip # int divide ( ul uh n -- quotient )
        def cellsize, "cellsize", b_dolit_s8,4   # ( -- 4 )
        def nip, "nip", b_swap, b_drop  # stack manipulation ( a b -- b )

        # 10 0 DO ... LOOP loops 0, 1...9.
        # _do sets up return stack for _loop
        # similar to F83: ( limit initial -- ) ( R: X -- X initial-limit limit )
        defbytes _do, "(do)"
        .byte b_over, b_sub,  b_swap,  b_rpop,  b_swap, b_rpush
        .byte b_swap, b_rpush,  b_rpush,  b_exit
        ##  return loop counter
        def i, "i", b_rpop, b_rpop, b_r_at, b_over, b_rpush, b_add, b_swap, b_rpush

        def twodup, "2dup", b_over, b_over
        def twodrop, "2drop", b_drop, b_drop

# Now some stuff for dealing with the dictionary.

# This stuff was from 804930a to 8049396, 140 bytes.  In that we got:
# - new words: dict dictp dictsize nextword pastdict? words < >= 0=
#   cbcmp c@+ bcmp memcmp unloop find r2@ 2swap
# - less concretely:
#   - the ability to list of words in the dictionary;
#   - the ability to find words in the dictionary;
#   - <, >=, and 0= numerical comparisons;
#   - cbcmp, bcmp, and memcmp memory manipulations;
#   - 2swap and r2@ stack manipulations;
#   - unloop loop control;
#   - c@+ for iterating over memory.
# That's 17 new words, averaging 8.2 bytecodes each.

dictionary_pointer:             
        .int end_of_dictionary
        defbytes dict, "dict"
        .byte b_dolit_32
        .int dictionary
        .byte b_exit
        defbytes dictp, "dictp"
        .byte b_dolit_32
        .int dictionary_pointer
        .byte b_exit
        def dictsize, "dictsize", b_dictp, b_at, b_dict, b_sub
        def nextword, "nextword", b_dup, b_c_at, b_add, b_add1
        def pastdict, "pastdict?", b_dictp, b_at, b_ge
        defbytes words, "words"
        .byte b_dict
1:      .byte b_dup, b_count, b_type, b_dolit_s8,32, b_emit
        .byte b_nextword
        .byte b_dup, b_pastdict
        fif 1b
        .byte b_exit
        def lt, "<", b_sub, b_negative
        def ge, ">=", b_lt, b_zeq
        # logical not: return true for 0, false (0) otherwise
        defbytes zeq, "0="
        fif 1f
        .byte b_zero, b_exit
1:      .byte b_neg1, b_exit

        # To find a word in the dictionary:
        # - move the word onto the return stack, and get the dictionary pointer
        # - then loop:
        #   - see if the word is at the current place
        #   - if so, clean up and return that place
        #   - otherwise, go to the next word
        #   - and repeat if we're still in the dictionary
        # - then clean up the stacks and return 0
        # Tells whether a counted string equals an address-and-count string.
        # 0 for equal, nonzero for unequal.
        # ( c-addr1 c-addr2 u -- n )
        def cbcmp, "cbcmp", b_rot, b_count, b_twoswap, b_bcmp
        # like F21 @A+: ( c-addr -- c-addr+1 char )
        def c_at_inc, "c@+", b_dup, b_add1, b_swap, b_c_at
        # Keep in mind memcmp() in libc is only 30 bytes long.
        # This bcmp is a little different from C memcmp or bcmp in
        # that it compares two lengths.
        defbytes bcmp, "bcmp" # ( c-addr1 u1 c-addr2 u2 -- n )
        .byte b_rot, b_over, b_xor
        fif 3f
        .byte b_twodrop, b_drop, b_one, b_exit
3:      .byte b_memcmp, b_exit
        defbytes memcmp, "memcmp"  # ( c-addr1 c-addr2 u -- n )
        .byte b_zero, b__do
2:      .byte b_c_at_inc, b_rot, b_c_at_inc, b_rot
        .byte b_sub, b_dup # - dup if
        fif 1f
        .byte b_unrot, b_twodrop, b_unloop, b_exit
1:      .byte b_drop, b_swap
        floop 2b
        .byte b_twodrop, b_zero, b_exit
        # this should probably go with the other do loop stuff
        def unloop, "unloop", b_rpop, b_rpop, b_rpop, b_twodrop, b_rpush

        # FIND: ( c-addr u -- token 1 | 0 )
        
        # 30 bytes; jonesforth 42's asm version is 56 bytes.  It's
        # fairly directly comparable, although jonesforth's FIND has
        # to do bit-masking and includes its own inline NEXTWORD and
        # CBCMP, which are actually fairly large here.
        
        defbytes find, "find"
        .byte b_rpush, b_rpush, b_zero, b_dict
1:      .byte b_dup, b_r_2at, b_cbcmp, b_zeq            # start loop
        fif 2f                  # bcmp 0= if
        .byte b_rpop, b_rpop, b_twodrop, b_drop, b_one, b_exit
2:      .byte b_swap, b_add1, b_swap, b_nextword, b_dup, b_pastdict
        fif 1b
        .byte b_rpop, b_rpop, b_twodrop, b_twodrop, b_zero, b_exit

        # copy two cells from return stack
        defbytes r_2at, "r2@"
        .byte b_rpop, b_rpop, b_r_at, b_over, b_rpush, b_rot, b_rpush, b_exit
        # ( a b c d -- c d a b )
        def twoswap, "2swap", b_rpush, b_unrot, b_rpop, b_unrot

        .macro create, name
        defbytes \name, "\name"
        .byte b_dolit_32
        .int 1f
        .byte b_exit
1:      
        .endm
        
        create "tib"
        _tibmax = 80
        .space _tibmax
        defbytes tibmax, "tibmax"
        .byte b_dolit_32
        .int _tibmax
        .byte b_exit
        create "tibsize"
        .int 0

        defbytes fgets, "fgets"
        .byte b_tib, b_tibmax, b_read, b_tibsize, b_bang # XXX handle errors
        .byte b_tib, b_tibsize, b_at, b_exit
        def gets, "gets", b_zero, b_fgets

        defbytes read, "read"
        .byte b_rpush, b_rpush, b_dolit_s8,__NR_read
        .byte b_zero             # fd 0: stdin
        .byte b_rpop, b_rpop, b_syscall3, b_exit

        def bl, "bl", b_dolit_s8,32 # space, blank

        # parse parses out a token of input from a string and leaves
        # the token's address and length atop the stack
        # ( c-addr u -- c-addr+n u-n c-addr2 u2 )
        defbytes parse, "parse"
        .byte b_skipwhitespace
        ##  XXX finish him!
        .byte b_exit

        defbytes skipwhitespace, "-wsp"
1:      .byte b_dup, b_zeq
        fif 3f                  # return empty tail
        .byte b_exit
3:      .byte b_sub1, b_swap, b_c_at_inc, b_whitespace
        fif 2f                  # escape loop if not whitespace
        .byte b_swap
        felse 1b
2:      .byte b_sub1, b_swap, b_add1, b_exit

        ## costs 9+5 bytes
        def_counted_string wsps, " \n\t"
        defbytes whitespace, "wsp"
        .byte b_dup, b_bl, b_xor
        fif 1f
        .byte b_dup, b_dolit_s8,'\n, b_xor
        fif 1f
        .byte b_dup, b_dolit_s8,'\t, b_xor
        fif 1f
        .byte b_drop, b_zero, b_exit
1:      .byte b_drop, b_one, b_exit

#         def repl, "repl", b_gets, b_eval, b_exit

#         defbytes eval, "eval"
# 2:      .byte b_parse
#         .byte b_dup, b_zeq
#         fif 3f                  # escape from loop
#         .byte b_rot, b_rpush, b_rot, b_rpush, b_find
#         fif 1f
#         .byte b_execute
# 1:      .byte b_rpop, b_rpop
#         felse 2b
# 3:      .byte b_2drop, b_2drop, b_exit

        .data 3
instructions:
        # And here is the actual "main program" in that bytecode.
        .byte b_sp_at, b_dolit_32
        .int bottom_of_stack    # variable to remember initial stack bottom
        .byte b_bang            # initialize that variable
        .byte b_hello           # string "hello" and count
        .byte b_sub1            # subtract 1 from count: "hell"
        .byte b_type            # spit it out
        .byte b_comma, b_type, b_world, b_type # ", world"
        .byte b_comma, b_type, b_hello, b_type, b_cr
        # test the "dot" command to print out numbers
        .byte b_dolit_s8, -120, b_dot
        # test positive numbers and "depth" command
        .byte b_dolit_s8, 104, b_depth, b_dot, b_dot, b_cr
        # test printstack
        .byte b_dolit_s8,100, b_dolit_s8,101, b_dolit_s8,102, b_printstack
        # test dictsize
        .byte b_dictsize, b_dot, b_cr
        .byte b_words, b_cr
        .byte b_hello, b_twodup, b_type, b_find, b_printstack
        .byte b_comma, b_twodup, b_type, b_find, b_printstack
        .byte b_dict, b_dot, b_cr
        .byte b_dolit_s8, '?, b_emit, b_bl, b_emit, b_gets, b_twodup
        .byte b_zero, b__do
1:      .byte b_c_at_inc, b_whitespace, b_dot
        floop 1b
        .byte b_drop
        .byte b_skipwhitespace, b_type
        .byte b_bye

        # At end of the assembly program, we initialize the
        # end_of_dictionary pointer by putting it at the end of the
        # assembled .dictionary section:
        .section .dictionary
end_of_dictionary:      
