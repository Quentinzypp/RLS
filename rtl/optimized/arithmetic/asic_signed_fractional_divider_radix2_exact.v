`timescale 1ns / 1ps

module asic_signed_fractional_divider_radix2_exact #(
    parameter integer INPUT_WIDTH = 40,
    parameter integer FRACTIONAL_WIDTH = 32,
    parameter integer OUTPUT_WIDTH = 72
) (
    input  wire                           clk,
    input  wire                           rst_n,
    input  wire                           start,
    input  wire signed [INPUT_WIDTH-1:0]  dividend,
    input  wire signed [INPUT_WIDTH-1:0]  divisor,
    output reg                            busy,
    output reg                            done,
    output reg                            valid,
    output reg signed [OUTPUT_WIDTH-1:0]  quotient,
    output reg                            divide_by_zero
);

    reg [OUTPUT_WIDTH-1:0] numerator_shift;
    reg [OUTPUT_WIDTH-1:0] quotient_magnitude;
    reg [INPUT_WIDTH:0] remainder_magnitude;
    reg [INPUT_WIDTH-1:0] divisor_magnitude;
    reg negative_result;
    reg divisor_zero;
    reg [6:0] iterations_remaining;

    wire [INPUT_WIDTH:0] trial_remainder = {
        remainder_magnitude[INPUT_WIDTH-1:0],
        numerator_shift[OUTPUT_WIDTH-1]
    };
    wire trial_ge_divisor = trial_remainder >= {1'b0, divisor_magnitude};
    wire [INPUT_WIDTH:0] next_remainder = trial_ge_divisor ?
        (trial_remainder - {1'b0, divisor_magnitude}) : trial_remainder;
    wire [OUTPUT_WIDTH-1:0] next_quotient = {
        quotient_magnitude[OUTPUT_WIDTH-2:0], trial_ge_divisor
    };
    wire [INPUT_WIDTH+1:0] twice_next_remainder = {next_remainder, 1'b0};
    wire [INPUT_WIDTH+1:0] extended_divisor = {{2{1'b0}}, divisor_magnitude};
    wire round_up = (twice_next_remainder > extended_divisor) ||
        ((twice_next_remainder == extended_divisor) && negative_result);
    wire [OUTPUT_WIDTH-1:0] rounded_magnitude =
        next_quotient + {{OUTPUT_WIDTH-1{1'b0}}, round_up};
    wire [OUTPUT_WIDTH-1:0] signed_rounded_quotient = negative_result ?
        (~rounded_magnitude + {{OUTPUT_WIDTH-1{1'b0}}, 1'b1}) : rounded_magnitude;

    function [INPUT_WIDTH-1:0] magnitude;
        input signed [INPUT_WIDTH-1:0] value;
        begin
            magnitude = value[INPUT_WIDTH-1] ?
                (~value + {{INPUT_WIDTH-1{1'b0}}, 1'b1}) : value;
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            numerator_shift <= {OUTPUT_WIDTH{1'b0}};
            quotient_magnitude <= {OUTPUT_WIDTH{1'b0}};
            remainder_magnitude <= {(INPUT_WIDTH+1){1'b0}};
            divisor_magnitude <= {INPUT_WIDTH{1'b0}};
            negative_result <= 1'b0;
            divisor_zero <= 1'b0;
            iterations_remaining <= 7'd0;
            busy <= 1'b0;
            done <= 1'b0;
            valid <= 1'b0;
            quotient <= {OUTPUT_WIDTH{1'b0}};
            divide_by_zero <= 1'b0;
        end
        else begin
            done <= 1'b0;
            valid <= 1'b0;
            divide_by_zero <= 1'b0;

            if (start && !busy) begin
                numerator_shift <= {magnitude(dividend), {FRACTIONAL_WIDTH{1'b0}}};
                quotient_magnitude <= {OUTPUT_WIDTH{1'b0}};
                remainder_magnitude <= {(INPUT_WIDTH+1){1'b0}};
                divisor_magnitude <= magnitude(divisor);
                negative_result <= dividend[INPUT_WIDTH-1] ^ divisor[INPUT_WIDTH-1];
                divisor_zero <= divisor == {INPUT_WIDTH{1'b0}};
                iterations_remaining <= OUTPUT_WIDTH;
                busy <= 1'b1;
            end
            else if (busy) begin
                numerator_shift <= {numerator_shift[OUTPUT_WIDTH-2:0], 1'b0};
                quotient_magnitude <= next_quotient;
                remainder_magnitude <= next_remainder;
                iterations_remaining <= iterations_remaining - 1'b1;
                if (iterations_remaining == 7'd1) begin
                    quotient <= divisor_zero ? {OUTPUT_WIDTH{1'b0}} : signed_rounded_quotient;
                    divide_by_zero <= divisor_zero;
                    busy <= 1'b0;
                    done <= 1'b1;
                    valid <= 1'b1;
                end
            end
        end
    end

endmodule
