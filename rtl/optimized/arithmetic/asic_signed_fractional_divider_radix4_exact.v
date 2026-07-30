`timescale 1ns / 1ps

module asic_signed_fractional_divider_radix4_exact #(
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
    reg [INPUT_WIDTH-1:0] remainder_magnitude;
    reg [INPUT_WIDTH-1:0] divisor_magnitude;
    reg negative_result;
    reg divisor_zero;
    reg [5:0] iterations_remaining;

    wire [INPUT_WIDTH+1:0] trial_remainder = {
        remainder_magnitude, numerator_shift[OUTPUT_WIDTH-1:OUTPUT_WIDTH-2]
    };
    wire [INPUT_WIDTH+1:0] divisor_x1 = {{2{1'b0}}, divisor_magnitude};
    wire [INPUT_WIDTH+1:0] divisor_x2 = divisor_x1 << 1;
    wire [INPUT_WIDTH+1:0] divisor_x3 = divisor_x2 + divisor_x1;
    reg [1:0] quotient_digit;
    reg [INPUT_WIDTH+1:0] reduced_remainder;

    always @* begin
        if (trial_remainder >= divisor_x3) begin
            quotient_digit = 2'd3;
            reduced_remainder = trial_remainder - divisor_x3;
        end
        else if (trial_remainder >= divisor_x2) begin
            quotient_digit = 2'd2;
            reduced_remainder = trial_remainder - divisor_x2;
        end
        else if (trial_remainder >= divisor_x1) begin
            quotient_digit = 2'd1;
            reduced_remainder = trial_remainder - divisor_x1;
        end
        else begin
            quotient_digit = 2'd0;
            reduced_remainder = trial_remainder;
        end
    end

    wire [OUTPUT_WIDTH-1:0] next_quotient = {
        quotient_magnitude[OUTPUT_WIDTH-3:0], quotient_digit
    };
    wire [INPUT_WIDTH-1:0] next_remainder = reduced_remainder[INPUT_WIDTH-1:0];
    wire [INPUT_WIDTH:0] twice_next_remainder = {next_remainder, 1'b0};
    wire [INPUT_WIDTH:0] extended_divisor = {1'b0, divisor_magnitude};
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
            remainder_magnitude <= {INPUT_WIDTH{1'b0}};
            divisor_magnitude <= {INPUT_WIDTH{1'b0}};
            negative_result <= 1'b0;
            divisor_zero <= 1'b0;
            iterations_remaining <= 6'd0;
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
                remainder_magnitude <= {INPUT_WIDTH{1'b0}};
                divisor_magnitude <= magnitude(divisor);
                negative_result <= dividend[INPUT_WIDTH-1] ^ divisor[INPUT_WIDTH-1];
                divisor_zero <= divisor == {INPUT_WIDTH{1'b0}};
                iterations_remaining <= OUTPUT_WIDTH >> 1;
                busy <= 1'b1;
            end
            else if (busy) begin
                numerator_shift <= {numerator_shift[OUTPUT_WIDTH-3:0], 2'b00};
                quotient_magnitude <= next_quotient;
                remainder_magnitude <= next_remainder;
                iterations_remaining <= iterations_remaining - 1'b1;
                if (iterations_remaining == 6'd1) begin
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
