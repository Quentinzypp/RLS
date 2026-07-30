`timescale 1ns / 1ps

`ifdef CONVERGENCE_DIVOPT
`define CONV_CORE tb.u_RLS12_c_MW_top.u_core
`define CONV_MONITOR_ACTIVE tb.monitor_enable
`define CONV_RESET_READY tb.reset_ready
`else
`define CONV_CORE tb.u_RLS12_c_MW_top
`define CONV_MONITOR_ACTIVE tb.rst_n
`define CONV_RESET_READY tb.rst_n
`endif

`define CONV_FIR `CONV_CORE.u_RLS12_c_rls_fir3_out_new
`define CONV_MATRIX `CONV_CORE.u_RLS_c_matrixP_update

module test_rls_convergence;
    test_rls tb();

    wire monitor_active = `CONV_MONITOR_ACTIVE;
    wire reset_ready_observed = `CONV_RESET_READY;
    wire residual_valid = `CONV_FIR.dout_sub_en;
    wire [23:0] dout_sub_data1_raw = `CONV_FIR.dout_sub_data1;
    wire [23:0] dout_sub_data2_raw = `CONV_FIR.dout_sub_data2;
    wire signed [23:0] dout_sub_data1_signed = $signed(dout_sub_data1_raw);
    wire signed [23:0] dout_sub_data2_signed = $signed(dout_sub_data2_raw);
    wire output_valid = `CONV_FIR.o_rls_en;
    wire [47:0] output_raw = `CONV_FIR.o_rls_data;
    wire [19:0] update_count_observed = tb.update_cnt;
    wire update_pulse = `CONV_CORE.wt_pulse;
    wire weight_valid = `CONV_CORE.wt_update_en;
    wire [71:0] weight_output = `CONV_CORE.wt_update;

`ifdef CONVERGENCE_DIVOPT
    wire divider_start = `CONV_MATRIX.u_float_complex_div.div_start;
    wire divider_busy1 = `CONV_MATRIX.u_float_complex_div.div_busy1;
    wire divider_busy2 = `CONV_MATRIX.u_float_complex_div.div_busy2;
    wire divider_valid1 = `CONV_MATRIX.u_float_complex_div.div_rdy1;
    wire divider_valid2 = `CONV_MATRIX.u_float_complex_div.div_rdy2;
    wire [39:0] divider_numerator_real = `CONV_MATRIX.u_float_complex_div.result8;
    wire [39:0] divider_numerator_imag = `CONV_MATRIX.u_float_complex_div.result7;
    wire [39:0] divider_denominator = `CONV_MATRIX.u_float_complex_div.result9;
    wire [71:0] divider_quotient_real = `CONV_MATRIX.u_float_complex_div.out10;
    wire [71:0] divider_quotient_imag = `CONV_MATRIX.u_float_complex_div.out11;
`else
    wire divider_start = 1'b0;
    wire divider_busy1 = 1'b0;
    wire divider_busy2 = 1'b0;
    wire divider_valid1 = 1'b0;
    wire divider_valid2 = 1'b0;
    wire [39:0] divider_numerator_real = 40'd0;
    wire [39:0] divider_numerator_imag = 40'd0;
    wire [39:0] divider_denominator = 40'd0;
    wire [71:0] divider_quotient_real = 72'd0;
    wire [71:0] divider_quotient_imag = 72'd0;
`endif

    integer cycle_file;
    integer weight_file;
    integer update_file;
    integer status_file;
    integer target_updates;
    integer trailing_cycles;
    integer monitor_cycle;
    integer update_events;
    integer weight_samples;
    integer tail_count;
    integer xz_flag;
    integer last_update_cycle;
    integer update_interval;
    reg capture_closed;

    task close_capture;
        input integer timed_out;
        begin
            if (!capture_closed) begin
                capture_closed = 1'b1;
                $fflush(cycle_file);
                $fflush(weight_file);
                $fflush(update_file);
                $fclose(cycle_file);
                $fclose(weight_file);
                $fclose(update_file);
                status_file = $fopen("convergence_capture_status.txt", "w");
                if (status_file != 0) begin
                    $fdisplay(status_file, "marker=MODELSIM_CONVERGENCE_CAPTURE_STOP");
                    $fdisplay(status_file, "timed_out=%0d", timed_out);
                    $fdisplay(status_file, "updates=%0d", update_events);
                    $fdisplay(status_file, "weights=%0d", weight_samples);
                    $fdisplay(status_file, "cycles=%0d", monitor_cycle);
                    $fdisplay(status_file, "sim_time_ps=%0t", $time);
                    $fclose(status_file);
                end
                $display(
                    "MODELSIM_CONVERGENCE_CAPTURE_STOP timed_out=%0d updates=%0d weights=%0d cycles=%0d",
                    timed_out, update_events, weight_samples, monitor_cycle
                );
                $stop;
            end
        end
    endtask

    initial begin
        if (!$value$plusargs("CONVERGENCE_UPDATES=%d", target_updates)) target_updates = 1000;
        if (!$value$plusargs("CONVERGENCE_TAIL_CYCLES=%d", trailing_cycles)) trailing_cycles = 50;
        cycle_file = $fopen("residual_cycle_samples.csv", "w");
        weight_file = $fopen("weights_samples_raw.csv", "w");
        update_file = $fopen("update_timing_raw.csv", "w");
        if (cycle_file == 0 || weight_file == 0 || update_file == 0)
            $fatal(1, "Unable to open convergence capture files");
        $fdisplay(cycle_file, "sim_time_ps,cycle,update_index,valid,dout_sub_data1_raw,dout_sub_data1_signed,dout_sub_data2_raw,dout_sub_data2_signed,rls_out_raw,rls_out_rdy,o_rls_valid,o_rls_raw,xz");
        $fdisplay(weight_file, "event,tap_index,sim_time_ps,cycle,update_index,weight_raw,xz");
        $fdisplay(update_file, "event,sim_time_ps,cycle,update_index,interval_cycles");
        monitor_cycle = 0;
        update_events = 0;
        weight_samples = 0;
        tail_count = 0;
        last_update_cycle = -1;
        capture_closed = 1'b0;
    end

    always @(posedge tb.clk) begin
        #0.001;
        if (monitor_active && !capture_closed) begin
            xz_flag = ((^dout_sub_data1_raw === 1'bx) ||
                       (^dout_sub_data2_raw === 1'bx) ||
                       (^output_raw === 1'bx) ||
                       (residual_valid === 1'bx));
            $fdisplay(
                cycle_file,
                "%0t,%0d,%0d,%b,%h,%0d,%h,%0d,%h,%b,%b,%h,%0d",
                $time,
                monitor_cycle,
                update_count_observed,
                residual_valid,
                dout_sub_data1_raw,
                dout_sub_data1_signed,
                dout_sub_data2_raw,
                dout_sub_data2_signed,
                tb.RLS_out,
                tb.RLS_out_rdy,
                output_valid,
                output_raw,
                xz_flag
            );
            if (weight_valid) begin
                $fdisplay(
                    weight_file,
                    "%0d,%0d,%0t,%0d,%0d,%h,%0d",
                    weight_samples / 12,
                    weight_samples % 12,
                    $time,
                    monitor_cycle,
                    update_count_observed,
                    weight_output,
                    (^weight_output === 1'bx)
                );
                weight_samples = weight_samples + 1;
            end
            if (update_pulse) begin
                update_interval = (last_update_cycle < 0) ? 0 : monitor_cycle - last_update_cycle;
                $fdisplay(
                    update_file,
                    "%0d,%0t,%0d,%0d,%0d",
                    update_events,
                    $time,
                    monitor_cycle,
                    update_count_observed,
                    update_interval
                );
                last_update_cycle = monitor_cycle;
                update_events = update_events + 1;
            end
            if (update_events >= target_updates && weight_samples >= target_updates * 12)
                tail_count = tail_count + 1;
            monitor_cycle = monitor_cycle + 1;
            if (tail_count >= trailing_cycles) close_capture(0);
        end
    end

    initial begin
        #15000000;
        close_capture(1);
    end
endmodule

`undef CONV_CORE
`undef CONV_MONITOR_ACTIVE
`undef CONV_RESET_READY
`undef CONV_FIR
`undef CONV_MATRIX
