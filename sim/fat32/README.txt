FAT32 tests use synthetic sector images and a physical-sector card model.
Run from any directory:
python run_tests.py --tools-dir <portable-Icarus-root>
The tool root contains bin/iverilog.exe, bin/vvp.exe and lib/ivl/.
If Icarus is installed on PATH, omit --tools-dir.
--unit-only omits the long 6-frame player pixel comparison.
Fixtures are generated in a temporary directory and never access an SD card.
Coverage includes filesystem parsing, sorting, fragmentation and player output.
Encrypted HDMI/SDRAM blocks and actual SPI electrical timing are not simulated.
