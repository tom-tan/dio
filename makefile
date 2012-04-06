SRCS=io\core.d io\file.d io\buffer.d io\filter.d io\text.d

DFLAGS=-property -w

unittest: unittest.exe

unittest.exe: $(SRCS) emptymain.d
	dmd -unittest $(DFLAGS) $(SRCS) emptymain.d -ofunittest.exe

rununittest: unittest.exe
	unittest

