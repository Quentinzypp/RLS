onerror {puts stderr $errorInfo; quit -code 2}
set repo [file normalize $::env(RLS_ROOT)]
transcript file [file join [file normalize $::env(RLS_BUILD)] divider_transcript.log]
transcript on
if {[file exists work]} {file delete -force work}
vlib work
vmap work work
vlog -sv -work work \
    [file join $repo rtl optimized arithmetic asic_signed_fractional_divider_radix2_exact.v] \
    [file join $repo rtl optimized arithmetic asic_signed_fractional_divider_radix4_exact.v] \
    [file join $repo rtl optimized arithmetic asic_signed_fractional_divider_radix4_aligned.v] \
    [file join $repo tb divider test_divider_exact_candidates.sv]
vsim -c -lib work work.test_divider_exact_candidates
run -all
quit -code 0
