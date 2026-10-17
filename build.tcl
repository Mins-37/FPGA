set base [file dirname [string map {\\ /} [info script]]]
cd [file join $base td_project]
import_device eagle_s20.db -package EG4S20BG256
open_project tf_bmp_fade.al
elaborate -top top
read_adc ../user_source/constraints_source/pin.adc
read_sdc ../user_source/constraints_source/timing.sdc
optimize_rtl
optimize_gate -packarea tf_bmp_fade_gate.area
legalize_phy_inst
place
route
update_timing -mode final
report_timing_summary -file tf_bmp_fade.timing
report_area -io_info -file tf_bmp_fade.area
export_db tf_bmp_fade_pr.db
bitgen -bit tf_bmp_fade.bit
exit
