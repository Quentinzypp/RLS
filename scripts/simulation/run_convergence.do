onerror {puts stderr $errorInfo; quit -code 2}

foreach variable {RLS_ROOT RLS_BUILD RLS_REFERENCE_VECTOR RLS_DESIRED_VECTOR} {
    if {![info exists ::env($variable)] || $::env($variable) eq ""} {
        error "$variable is missing"
    }
}

set repo [file normalize $::env(RLS_ROOT)]
set build [file normalize $::env(RLS_BUILD)]
transcript file [file join $build modelsim_transcript.log]
transcript on

if {[file exists work]} {file delete -force work}
vlib work
vmap work work

set sources [list]
set stream [open [file join $repo rtl filelists divopt.f] r]
while {[gets $stream line] >= 0} {
    set line [string trim $line]
    if {$line eq "" || [string index $line 0] eq "#"} {continue}
    lappend sources [file join $repo $line]
}
close $stream
lappend sources [file join $repo tb convergence test_rls_stimulus.sv]
lappend sources [file join $repo tb convergence test_rls_convergence.sv]
eval vlog -sv -mfcu +define+PHASE2_VENDOR_MIXED_SIM +define+CONVERGENCE_DIVOPT -work work "+incdir+$repo" $sources

vsim -c -t 1ps -voptargs="+acc" -lib work work.test_rls_convergence \
    +CONVERGENCE_UPDATES=1000 +CONVERGENCE_TAIL_CYCLES=50 \
    +REFERENCE_VECTOR=$::env(RLS_REFERENCE_VECTOR) \
    +DESIRED_VECTOR=$::env(RLS_DESIRED_VECTOR)
set NumericStdNoWarnings 1
set StdArithNoWarnings 1
run 15 ms
quit -code 0
