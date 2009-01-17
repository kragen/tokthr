all = tokthr tokthr-symbols tokthr-disassembly
all: $(all)
clean:
	rm -f $(all) *~ .*~
tokthr: tokthr.S
	gcc -m32 -nostdlib -static -o $@ $<
tokthr-symbols: tokthr
	(echo '-*- auto-revert -*-'; nm $<) > $@
tokthr-disassembly: tokthr
	(echo '-*- auto-revert -*-'; objdump -D $<) > $@
