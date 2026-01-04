transcript on
if {[file exists rtl_work]} {
	vdel -lib rtl_work -all
}
vlib rtl_work
vmap work rtl_work

vlog -vlog01compat -work work +incdir+D:/mb_4816_task2a/t2a_dht/code {D:/mb_4816_task2a/t2a_dht/code/t2a_dht.v}

vlog -vlog01compat -work work +incdir+D:/mb_4816_task2a/t2a_dht/.test {D:/mb_4816_task2a/t2a_dht/.test/tb.v}

vsim -t 1ps -L altera_ver -L lpm_ver -L sgate_ver -L altera_mf_ver -L altera_lnsim_ver -L cycloneive_ver -L rtl_work -L work -voptargs="+acc"  tb

add wave *
view structure
view signals
run 75 ms
