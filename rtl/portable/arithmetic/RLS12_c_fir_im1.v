`timescale 1ns / 1ps

module RLS12_c_fir_im1 (
    input  wire         aresetn,
    input  wire         aclk,
    input  wire         s_axis_data_tvalid,
    output wire         s_axis_data_tready,
    input  wire [47:0]  s_axis_data_tdata,
    input  wire         s_axis_config_tvalid,
    output wire         s_axis_config_tready,
    input  wire [7:0]   s_axis_config_tdata,
    input  wire         s_axis_reload_tvalid,
    output wire         s_axis_reload_tready,
    input  wire         s_axis_reload_tlast,
    input  wire [39:0]  s_axis_reload_tdata,
    output wire         m_axis_data_tvalid,
    output wire [127:0] m_axis_data_tdata,
    output wire         event_s_reload_tlast_missing,
    output wire         event_s_reload_tlast_unexpected
);
    wire raw_output_valid;
    wire [127:0] raw_output_data;

    asic_reloadable_fir #(
        .DATA_WIDTH (24),
        .COEFF_WIDTH(36),
        .ACC_WIDTH  (64),
        .TAPS       (12),
        .LATENCY    (29)
    ) u_fir (
        .clk                   (aclk),
        .rst_n                 (aresetn),
        .data_valid            (s_axis_data_tvalid),
        .data_ready            (s_axis_data_tready),
        .data                  (s_axis_data_tdata),
        .reload_valid          (s_axis_reload_tvalid),
        .reload_ready          (s_axis_reload_tready),
        .reload_last           (s_axis_reload_tlast),
        .reload_data           (s_axis_reload_tdata[35:0]),
        .config_valid          (s_axis_config_tvalid),
        .config_ready          (s_axis_config_tready),
        .output_valid          (raw_output_valid),
        .output_data           (raw_output_data),
        .reload_last_missing   (event_s_reload_tlast_missing),
        .reload_last_unexpected(event_s_reload_tlast_unexpected)
    );

`ifdef PHASE2_VENDOR_MIXED_SIM
    assign #0.1 m_axis_data_tvalid = raw_output_valid;
    assign #0.1 m_axis_data_tdata = raw_output_data;
`else
    assign m_axis_data_tvalid = raw_output_valid;
    assign m_axis_data_tdata = raw_output_data;
`endif
endmodule
