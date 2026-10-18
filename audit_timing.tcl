set base [file dirname [string map {\\ /} [info script]]]
cd [file join $base td_project]
import_device eagle_s20.db -package EG4S20BG256
import_db tf_bmp_scaler_pr.db
update_timing -mode final
report_timing_exception -file tf_bmp_scaler.exceptions
report_timing_summary -file tf_bmp_scaler.audit.timing
exit
