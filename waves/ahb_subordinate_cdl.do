onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_ahb_subordinate_cdl/clk
add wave -noupdate /tb_ahb_subordinate_cdl/n_rst
add wave -noupdate -radix unsigned /tb_ahb_subordinate_cdl/test
add wave -noupdate -divider {Bus Signals}
add wave -noupdate /tb_ahb_subordinate_cdl/hsel
add wave -noupdate /tb_ahb_subordinate_cdl/haddr
add wave -noupdate /tb_ahb_subordinate_cdl/htrans
add wave -noupdate /tb_ahb_subordinate_cdl/hsize
add wave -noupdate /tb_ahb_subordinate_cdl/hwrite
add wave -noupdate /tb_ahb_subordinate_cdl/hburst
add wave -noupdate -radix hexadecimal /tb_ahb_subordinate_cdl/hwdata
add wave -noupdate -radix hexadecimal /tb_ahb_subordinate_cdl/hrdata
add wave -noupdate /tb_ahb_subordinate_cdl/hresp
add wave -noupdate /tb_ahb_subordinate_cdl/hready
add wave -noupdate -divider Inputs
add wave -noupdate /tb_ahb_subordinate_cdl/busy
add wave -noupdate /tb_ahb_subordinate_cdl/data_ready
add wave -noupdate /tb_ahb_subordinate_cdl/output_count
add wave -noupdate /tb_ahb_subordinate_cdl/inf_err
add wave -noupdate /tb_ahb_subordinate_cdl/nan_err
add wave -noupdate /tb_ahb_subordinate_cdl/addr
add wave -noupdate -radix unsigned /tb_ahb_subordinate_cdl/ahb_rdata
add wave -noupdate -divider Outputs
add wave -noupdate /tb_ahb_subordinate_cdl/check_pulse
add wave -noupdate -radix unsigned /tb_ahb_subordinate_cdl/ahb_wdata
add wave -noupdate /tb_ahb_subordinate_cdl/DFT/error
add wave -noupdate /tb_ahb_subordinate_cdl/DFT/next_hrdata
add wave -noupdate /tb_ahb_subordinate_cdl/DFT/bias
add wave -noupdate /tb_ahb_subordinate_cdl/DFT/next_bias
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {6890883 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 126
configure wave -valuecolwidth 144
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update
WaveRestoreZoom {6800572 ps} {6931212 ps}
