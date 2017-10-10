SPIN = spin
CC = gcc
CFLAGS = -O2 -w
SPINFLAGS = -DXUSAFE -DCOLLAPSE

TARGET = echronos.pml
OUT = pan
MLIMIT ?= 1024

$(OUT).c:
	$(SPIN) -a $(TARGET)

$(OUT): $(OUT).c
	$(CC) $(CFLAGS) -DMEMLIM=$(MLIMIT) $(SPINFLAGS) -o $@ $<

$(OUT)_safety: SPINFLAGS += -DBFS -DSAFETY
$(OUT)_safety: $(OUT)

safety_bfs: $(OUT)_safety
	./$(OUT) -c1

safety_bfs_full: MLIMIT = 53248  # memory limit 52G
safety_bfs_full: safety_bfs

.PHONY: cleanall clean cleantrail
clean:
	rm -rf $(OUT)*

cleantrail:
	rm -rf $(TARGET).trail

cleanall: clean cleantrail

