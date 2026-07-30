`timescale 1ns / 1ps

module divider_synth_baseline_expanded (
    input wire clk, input wire rst_n, input wire start,
    input wire signed [39:0] dividend, input wire signed [39:0] divisor,
    output wire busy, output wire done, output wire valid,
    output wire signed [71:0] quotient, output wire divide_by_zero
);
    wire divisor_ready_unused;
    wire dividend_ready_unused;
    wire result_valid;

    asic_signed_fractional_divider #(
        .INPUT_WIDTH(40), .FRACTIONAL_WIDTH(32), .OUTPUT_WIDTH(72), .LATENCY(41)
    ) u_divider (
        .clk(clk),
        .divisor_valid(start), .divisor_ready(divisor_ready_unused), .divisor_data(divisor),
        .dividend_valid(start), .dividend_ready(dividend_ready_unused), .dividend_data(dividend),
        .result_valid(result_valid), .result_data(quotient), .divide_by_zero(divide_by_zero)
    );

    assign busy = 1'b0;
    assign done = result_valid;
    assign valid = result_valid;
    wire rst_n_unused = rst_n;
endmodule

module divider_synth_radix2_exact (
    input wire clk, input wire rst_n, input wire start,
    input wire signed [39:0] dividend, input wire signed [39:0] divisor,
    output wire busy, output wire done, output wire valid,
    output wire signed [71:0] quotient, output wire divide_by_zero
);
    asic_signed_fractional_divider_radix2_exact u_divider (
        .clk(clk), .rst_n(rst_n), .start(start), .dividend(dividend), .divisor(divisor),
        .busy(busy), .done(done), .valid(valid), .quotient(quotient), .divide_by_zero(divide_by_zero)
    );
endmodule

module divider_synth_radix4_exact (
    input wire clk, input wire rst_n, input wire start,
    input wire signed [39:0] dividend, input wire signed [39:0] divisor,
    output wire busy, output wire done, output wire valid,
    output wire signed [71:0] quotient, output wire divide_by_zero
);
    asic_signed_fractional_divider_radix4_exact u_divider (
        .clk(clk), .rst_n(rst_n), .start(start), .dividend(dividend), .divisor(divisor),
        .busy(busy), .done(done), .valid(valid), .quotient(quotient), .divide_by_zero(divide_by_zero)
    );
endmodule

module divider_synth_radix4_aligned (
    input wire clk, input wire rst_n, input wire start,
    input wire signed [39:0] dividend, input wire signed [39:0] divisor,
    output wire busy, output wire done, output wire valid,
    output wire signed [71:0] quotient, output wire divide_by_zero
);
    asic_signed_fractional_divider_radix4_aligned u_divider (
        .clk(clk), .rst_n(rst_n), .start(start), .dividend(dividend), .divisor(divisor),
        .busy(busy), .done(done), .valid(valid), .quotient(quotient), .divide_by_zero(divide_by_zero)
    );
endmodule
