`timescale 1ns / 1ps

module test_divider_exact_candidates;
    localparam integer VECTOR_COUNT = 1160;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg start = 1'b0;
    reg signed [39:0] dividend = 40'sd0;
    reg signed [39:0] divisor = 40'sd1;
    wire radix2_busy;
    wire radix2_done;
    wire radix2_valid;
    wire signed [71:0] radix2_quotient;
    wire radix2_zero;
    wire radix4_busy;
    wire radix4_done;
    wire radix4_valid;
    wire signed [71:0] radix4_quotient;
    wire radix4_zero;
    wire aligned_busy;
    wire aligned_done;
    wire aligned_valid;
    wire signed [71:0] aligned_quotient;
    wire aligned_zero;

    reg [39:0] dividend_memory [0:VECTOR_COUNT-1];
    reg [39:0] divisor_memory [0:VECTOR_COUNT-1];
    reg [71:0] expected_memory [0:VECTOR_COUNT-1];
    reg zero_memory [0:VECTOR_COUNT-1];
    integer cycle = 0;
    integer result_file;
    integer mismatches = 0;
    integer unknowns = 0;
    integer latency_errors = 0;
    integer protocol_errors = 0;
    integer radix2_outputs = 0;
    integer radix4_outputs = 0;
    integer aligned_outputs = 0;
    integer index;

    asic_signed_fractional_divider_radix2_exact u_radix2 (
        .clk(clk), .rst_n(rst_n), .start(start),
        .dividend(dividend), .divisor(divisor),
        .busy(radix2_busy), .done(radix2_done), .valid(radix2_valid),
        .quotient(radix2_quotient), .divide_by_zero(radix2_zero)
    );

    asic_signed_fractional_divider_radix4_exact u_radix4 (
        .clk(clk), .rst_n(rst_n), .start(start),
        .dividend(dividend), .divisor(divisor),
        .busy(radix4_busy), .done(radix4_done), .valid(radix4_valid),
        .quotient(radix4_quotient), .divide_by_zero(radix4_zero)
    );

    asic_signed_fractional_divider_radix4_aligned u_aligned (
        .clk(clk), .rst_n(rst_n), .start(start),
        .dividend(dividend), .divisor(divisor),
        .busy(aligned_busy), .done(aligned_done), .valid(aligned_valid),
        .quotient(aligned_quotient), .divide_by_zero(aligned_zero)
    );

    always #5 clk = ~clk;
    always @(posedge clk) cycle = cycle + 1;

    task automatic pulse_start(input [39:0] next_dividend, input [39:0] next_divisor);
        begin
            @(negedge clk);
            dividend = next_dividend;
            divisor = next_divisor;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
        end
    endtask

    task automatic check_reset_abort;
        begin
            rst_n = 1'b1;
            pulse_start(40'h0123456789, 40'h0000000123);
            repeat (10) @(posedge clk);
            #1;
            if (!radix2_busy || !radix4_busy || !aligned_busy) protocol_errors = protocol_errors + 1;
            @(negedge clk);
            rst_n = 1'b0;
            repeat (2) @(posedge clk);
            #1;
            if (radix2_busy || radix4_busy || aligned_busy ||
                radix2_done || radix4_done || aligned_done ||
                radix2_valid || radix4_valid || aligned_valid) begin
                protocol_errors = protocol_errors + 1;
            end
            @(negedge clk);
            rst_n = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic run_vector(input integer vector_index);
        integer accept_cycle;
        integer wait_cycles;
        integer radix2_latency;
        integer radix4_latency;
        integer aligned_latency;
        reg radix2_seen;
        reg radix4_seen;
        reg aligned_seen;
        reg [71:0] radix2_result;
        reg [71:0] radix4_result;
        reg [71:0] aligned_result;
        reg radix2_zero_result;
        reg radix4_zero_result;
        reg aligned_zero_result;
        begin
            while (radix2_busy || radix4_busy || aligned_busy) @(posedge clk);
            @(negedge clk);
            dividend = dividend_memory[vector_index];
            divisor = divisor_memory[vector_index];
            start = 1'b1;
            @(posedge clk);
            #1;
            accept_cycle = cycle;
            @(negedge clk);
            start = 1'b0;

            if (vector_index == 0) begin
                repeat (5) @(posedge clk);
                @(negedge clk);
                dividend = 40'h1555555555;
                divisor = 40'h0000000007;
                start = 1'b1;
                @(negedge clk);
                start = 1'b0;
            end

            radix2_seen = 1'b0;
            radix4_seen = 1'b0;
            aligned_seen = 1'b0;
            radix2_latency = -1;
            radix4_latency = -1;
            aligned_latency = -1;
            wait_cycles = 0;
            while ((!radix2_seen || !radix4_seen || !aligned_seen) && wait_cycles < 100) begin
                @(posedge clk);
                #1;
                wait_cycles = wait_cycles + 1;
                if (radix2_done) begin
                    if (radix2_seen || !radix2_valid) protocol_errors = protocol_errors + 1;
                    radix2_seen = 1'b1;
                    radix2_outputs = radix2_outputs + 1;
                    radix2_latency = cycle - accept_cycle;
                    radix2_result = radix2_quotient;
                    radix2_zero_result = radix2_zero;
                    if ($isunknown({radix2_quotient,radix2_zero})) unknowns = unknowns + 1;
                end
                if (radix4_done) begin
                    if (radix4_seen || !radix4_valid) protocol_errors = protocol_errors + 1;
                    radix4_seen = 1'b1;
                    radix4_outputs = radix4_outputs + 1;
                    radix4_latency = cycle - accept_cycle;
                    radix4_result = radix4_quotient;
                    radix4_zero_result = radix4_zero;
                    if ($isunknown({radix4_quotient,radix4_zero})) unknowns = unknowns + 1;
                end
                if (aligned_done) begin
                    if (aligned_seen || !aligned_valid) protocol_errors = protocol_errors + 1;
                    aligned_seen = 1'b1;
                    aligned_outputs = aligned_outputs + 1;
                    aligned_latency = cycle - accept_cycle;
                    aligned_result = aligned_quotient;
                    aligned_zero_result = aligned_zero;
                    if ($isunknown({aligned_quotient,aligned_zero})) unknowns = unknowns + 1;
                end
            end
            if (!radix2_seen || !radix4_seen || !aligned_seen) protocol_errors = protocol_errors + 1;
            if (radix2_latency != 72 || radix4_latency != 36 || aligned_latency != 40) latency_errors = latency_errors + 1;
            if (radix2_result !== expected_memory[vector_index] ||
                radix4_result !== expected_memory[vector_index] ||
                aligned_result !== expected_memory[vector_index] ||
                radix2_zero_result !== zero_memory[vector_index] ||
                radix4_zero_result !== zero_memory[vector_index] ||
                aligned_zero_result !== zero_memory[vector_index]) begin
                mismatches = mismatches + 1;
            end
            $fdisplay(
                result_file,
                "%0d,%010h,%010h,%018h,%018h,%0d,%018h,%0d,%018h,%0d,%0d,%0d,%0d",
                vector_index,
                dividend_memory[vector_index],
                divisor_memory[vector_index],
                expected_memory[vector_index],
                radix2_result,
                radix2_latency,
                radix4_result,
                radix4_latency,
                aligned_result,
                aligned_latency,
                radix2_zero_result,
                radix4_zero_result,
                aligned_zero_result
            );
            @(posedge clk);
            #1;
            if (radix2_done || radix4_done || aligned_done ||
                radix2_valid || radix4_valid || aligned_valid) begin
                protocol_errors = protocol_errors + 1;
            end
        end
    endtask

    initial begin
        $readmemh("dividend.mem", dividend_memory);
        $readmemh("divisor.mem", divisor_memory);
        $readmemh("expected.mem", expected_memory);
        $readmemb("divide_by_zero.mem", zero_memory);
        result_file = $fopen("divider_candidate_results.csv", "w");
        if (result_file == 0) $fatal(1, "Unable to open divider_candidate_results.csv");
        $fdisplay(result_file, "index,dividend,divisor,expected,radix2,radix2_latency,radix4,radix4_latency,aligned,aligned_latency,radix2_zero,radix4_zero,aligned_zero");

        repeat (4) @(posedge clk);
        check_reset_abort();
        for (index = 0; index < VECTOR_COUNT; index = index + 1) begin
            run_vector(index);
        end
        $fclose(result_file);
        $display("PHASE4_DIVIDER_CANDIDATE_VECTORS=%0d", VECTOR_COUNT);
        $display("PHASE4_DIVIDER_RADIX2_OUTPUTS=%0d", radix2_outputs);
        $display("PHASE4_DIVIDER_RADIX4_OUTPUTS=%0d", radix4_outputs);
        $display("PHASE4_DIVIDER_ALIGNED_OUTPUTS=%0d", aligned_outputs);
        $display("PHASE4_DIVIDER_MISMATCHES=%0d", mismatches);
        $display("PHASE4_DIVIDER_UNKNOWNS=%0d", unknowns);
        $display("PHASE4_DIVIDER_LATENCY_ERRORS=%0d", latency_errors);
        $display("PHASE4_DIVIDER_PROTOCOL_ERRORS=%0d", protocol_errors);
        if (radix2_outputs == VECTOR_COUNT && radix4_outputs == VECTOR_COUNT && aligned_outputs == VECTOR_COUNT &&
            mismatches == 0 && unknowns == 0 && latency_errors == 0 && protocol_errors == 0) begin
            $display("PHASE4_DIVIDER_EXACT_CANDIDATES_PASS");
            $finish;
        end
        $fatal(1, "PHASE4_DIVIDER_EXACT_CANDIDATES_FAIL");
    end

    initial begin
        #2000000;
        $fatal(1, "PHASE4_DIVIDER_EXACT_CANDIDATES_TIMEOUT");
    end
endmodule
