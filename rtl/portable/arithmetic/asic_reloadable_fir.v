`timescale 1ns / 1ps

module asic_reloadable_fir #(
    parameter integer DATA_WIDTH  = 24,
    parameter integer COEFF_WIDTH = 36,
    parameter integer ACC_WIDTH   = 64,
    parameter integer TAPS        = 12,
    parameter integer LATENCY     = 29
) (
    input  wire                              clk,
    input  wire                              rst_n,
    input  wire                              data_valid,
    output wire                              data_ready,
    input  wire [(2*DATA_WIDTH)-1:0]         data,
    input  wire                              reload_valid,
    output wire                              reload_ready,
    input  wire                              reload_last,
    input  wire signed [COEFF_WIDTH-1:0]     reload_data,
    input  wire                              config_valid,
    output wire                              config_ready,
    output wire                              output_valid,
    output wire [(2*ACC_WIDTH)-1:0]          output_data,
    output reg                               reload_last_missing,
    output reg                               reload_last_unexpected
);
    localparam integer PRODUCT_WIDTH = DATA_WIDTH + COEFF_WIDTH;
    localparam integer HISTORY_TAPS  = TAPS - 1;

    reg signed [COEFF_WIDTH-1:0] shadow_coeff [0:TAPS-1];
    reg signed [COEFF_WIDTH-1:0] active_coeff [0:TAPS-1];
    reg signed [DATA_WIDTH-1:0] history_path0 [0:HISTORY_TAPS-1];
    reg signed [DATA_WIDTH-1:0] history_path1 [0:HISTORY_TAPS-1];
    reg [HISTORY_TAPS-1:0] history_valid;
    reg [3:0] reload_count;
    reg reload_complete;
    reg active_valid;

    reg signed [ACC_WIDTH-1:0] data_pipeline [0:LATENCY-1];
    reg signed [ACC_WIDTH-1:0] data_pipeline_path1 [0:LATENCY-1];
    reg [LATENCY-1:0] valid_pipeline;

    wire signed [DATA_WIDTH-1:0] current_path0 = data[DATA_WIDTH-1:0];
    wire signed [DATA_WIDTH-1:0] current_path1 = data[(2*DATA_WIDTH)-1:DATA_WIDTH];

    reg signed [ACC_WIDTH-1:0] accumulator_path0;
    reg signed [ACC_WIDTH-1:0] accumulator_path1;
    reg signed [PRODUCT_WIDTH-1:0] product_path0;
    reg signed [PRODUCT_WIDTH-1:0] product_path1;
    reg signed [COEFF_WIDTH-1:0] selected_coeff;
    integer comb_tap;
    integer seq_tap;
    integer stage;

    assign data_ready = 1'b1;
    assign reload_ready = 1'b1;
    assign config_ready = reload_complete;
    assign output_valid = valid_pipeline[LATENCY-1];
    assign output_data = {
        data_pipeline_path1[LATENCY-1],
        data_pipeline[LATENCY-1]
    };

    always @* begin
        accumulator_path0 = {ACC_WIDTH{1'b0}};
        accumulator_path1 = {ACC_WIDTH{1'b0}};
        product_path0 = {PRODUCT_WIDTH{1'b0}};
        product_path1 = {PRODUCT_WIDTH{1'b0}};
        selected_coeff = {COEFF_WIDTH{1'b0}};

        if (active_valid || (config_valid && config_ready)) begin
            selected_coeff = (config_valid && config_ready) ? shadow_coeff[0] : active_coeff[0];
            product_path0 = current_path0 * selected_coeff;
            product_path1 = current_path1 * selected_coeff;
            accumulator_path0 = {{(ACC_WIDTH-PRODUCT_WIDTH){product_path0[PRODUCT_WIDTH-1]}}, product_path0};
            accumulator_path1 = {{(ACC_WIDTH-PRODUCT_WIDTH){product_path1[PRODUCT_WIDTH-1]}}, product_path1};

            for (comb_tap = 1; comb_tap < TAPS; comb_tap = comb_tap + 1) begin
                if (history_valid[comb_tap-1]) begin
                    selected_coeff = (config_valid && config_ready) ? shadow_coeff[comb_tap] : active_coeff[comb_tap];
                    product_path0 = history_path0[comb_tap-1] * selected_coeff;
                    product_path1 = history_path1[comb_tap-1] * selected_coeff;
                    accumulator_path0 = accumulator_path0
                        + {{(ACC_WIDTH-PRODUCT_WIDTH){product_path0[PRODUCT_WIDTH-1]}}, product_path0};
                    accumulator_path1 = accumulator_path1
                        + {{(ACC_WIDTH-PRODUCT_WIDTH){product_path1[PRODUCT_WIDTH-1]}}, product_path1};
                end
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reload_count <= 4'd0;
            reload_complete <= 1'b0;
            active_valid <= 1'b0;
            reload_last_missing <= 1'b0;
            reload_last_unexpected <= 1'b0;
            history_valid <= {HISTORY_TAPS{1'b0}};
            valid_pipeline <= {LATENCY{1'b0}};
        end else begin
            reload_last_missing <= 1'b0;
            reload_last_unexpected <= 1'b0;

            if (reload_valid && reload_ready) begin
                shadow_coeff[TAPS-1-reload_count] <= reload_data;
                reload_complete <= 1'b0;
                if (reload_count == TAPS-1) begin
                    reload_count <= 4'd0;
                    if (reload_last) begin
                        reload_complete <= 1'b1;
                    end else begin
                        reload_last_missing <= 1'b1;
                    end
                end else if (reload_last) begin
                    reload_count <= 4'd0;
                    reload_last_unexpected <= 1'b1;
                end else begin
                    reload_count <= reload_count + 1'b1;
                end
            end

            if (config_valid && config_ready) begin
                for (seq_tap = 0; seq_tap < TAPS; seq_tap = seq_tap + 1) begin
                    active_coeff[seq_tap] <= shadow_coeff[seq_tap];
                end
                active_valid <= 1'b1;
                reload_complete <= 1'b0;
            end

            if (data_valid && data_ready) begin
                for (seq_tap = HISTORY_TAPS-1; seq_tap > 0; seq_tap = seq_tap - 1) begin
                    history_path0[seq_tap] <= history_path0[seq_tap-1];
                    history_path1[seq_tap] <= history_path1[seq_tap-1];
                    history_valid[seq_tap] <= history_valid[seq_tap-1];
                end
                history_path0[0] <= current_path0;
                history_path1[0] <= current_path1;
                history_valid[0] <= 1'b1;
            end

            data_pipeline[0] <= accumulator_path0;
            data_pipeline_path1[0] <= accumulator_path1;
            valid_pipeline[0] <= data_valid && data_ready;
            for (stage = 1; stage < LATENCY; stage = stage + 1) begin
                data_pipeline[stage] <= data_pipeline[stage-1];
                data_pipeline_path1[stage] <= data_pipeline_path1[stage-1];
                valid_pipeline[stage] <= valid_pipeline[stage-1];
            end
        end
    end
endmodule
