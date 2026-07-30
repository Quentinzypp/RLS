`timescale 1ns / 1ps

module asic_signed_fractional_divider #(
    parameter integer INPUT_WIDTH = 40,
    parameter integer FRACTIONAL_WIDTH = 32,
    parameter integer OUTPUT_WIDTH = 72,
    parameter integer LATENCY = 41
) (
    input  wire                          clk,
    input  wire                          divisor_valid,
    output wire                          divisor_ready,
    input  wire signed [INPUT_WIDTH-1:0] divisor_data,
    input  wire                          dividend_valid,
    output wire                          dividend_ready,
    input  wire signed [INPUT_WIDTH-1:0] dividend_data,
    output wire                          result_valid,
    output wire signed [OUTPUT_WIDTH-1:0] result_data,
    output wire                          divide_by_zero
);

    wire accept = divisor_valid && dividend_valid;
    wire [OUTPUT_WIDTH-1:0] quotient_value;
    wire quotient_divide_by_zero = accept && (divisor_data == {INPUT_WIDTH{1'b0}});
    reg [OUTPUT_WIDTH-1:0] quotient_pipeline [0:LATENCY-1];
    reg [LATENCY-1:0] valid_pipeline;
    reg [LATENCY-1:0] divide_by_zero_pipeline;
    integer stage;

    function [INPUT_WIDTH-1:0] magnitude;
        input signed [INPUT_WIDTH-1:0] value;
        begin
            magnitude = value[INPUT_WIDTH-1] ? (~value + {{INPUT_WIDTH-1{1'b0}}, 1'b1}) : value;
        end
    endfunction

    function [OUTPUT_WIDTH-1:0] rounded_fractional_quotient;
        input signed [INPUT_WIDTH-1:0] dividend;
        input signed [INPUT_WIDTH-1:0] divisor;
        reg negative;
        reg [OUTPUT_WIDTH-1:0] numerator_magnitude;
        reg [INPUT_WIDTH-1:0] divisor_magnitude;
        reg [OUTPUT_WIDTH-1:0] quotient_magnitude;
        reg [OUTPUT_WIDTH-1:0] remainder_magnitude;
        reg [OUTPUT_WIDTH-1:0] twice_remainder;
        begin
            if (divisor == {INPUT_WIDTH{1'b0}}) begin
                rounded_fractional_quotient = {OUTPUT_WIDTH{1'b0}};
            end
            else begin
                negative = dividend[INPUT_WIDTH-1] ^ divisor[INPUT_WIDTH-1];
                numerator_magnitude = {magnitude(dividend), {FRACTIONAL_WIDTH{1'b0}}};
                divisor_magnitude = magnitude(divisor);
                quotient_magnitude = numerator_magnitude / divisor_magnitude;
                remainder_magnitude = numerator_magnitude % divisor_magnitude;
                twice_remainder = remainder_magnitude << 1;
                if ((twice_remainder > divisor_magnitude) ||
                    ((twice_remainder == divisor_magnitude) && negative)) begin
                    quotient_magnitude = quotient_magnitude + {{OUTPUT_WIDTH-1{1'b0}}, 1'b1};
                end
                rounded_fractional_quotient = negative ?
                    (~quotient_magnitude + {{OUTPUT_WIDTH-1{1'b0}}, 1'b1}) :
                    quotient_magnitude;
            end
        end
    endfunction

    assign divisor_ready = 1'b1;
    assign dividend_ready = 1'b1;
    assign quotient_value = rounded_fractional_quotient(dividend_data, divisor_data);

    always @(posedge clk) begin
        quotient_pipeline[0] <= quotient_value;
        valid_pipeline[0] <= accept;
        divide_by_zero_pipeline[0] <= quotient_divide_by_zero;
        for (stage = 1; stage < LATENCY; stage = stage + 1) begin
            quotient_pipeline[stage] <= quotient_pipeline[stage-1];
            valid_pipeline[stage] <= valid_pipeline[stage-1];
            divide_by_zero_pipeline[stage] <= divide_by_zero_pipeline[stage-1];
        end
    end

    assign result_data = quotient_pipeline[LATENCY-1];
    assign result_valid = valid_pipeline[LATENCY-1];
    assign divide_by_zero = divide_by_zero_pipeline[LATENCY-1];

endmodule
