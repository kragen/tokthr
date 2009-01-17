b *0x08048075
display/i $pc
display/a ((void**)$esp)[2]
display/a ((void**)$esp)[1]
display/a ((void**)$esp)[0]
display/a $esi
display/a $eax

define rstack
  p/a ((void**)$ebp)[0]@3
end
document rstack
  Prints the top three entries of the return stack, 
  topmost first.
end

define fb
  b execute_eax if $esi == &$arg0
end
document fb
  Sets a breakpoint to stop the interpreter when it enters a given Forth word.
end