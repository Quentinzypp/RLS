`timescale 1ns / 1ps

module RLS12_c_MW_top_divopt #(
    parameter width = 48,
    parameter coe_widthout = 72,
    parameter FIFO_depth = 14
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire [FIFO_depth-1:0]        BUF_len,
    input  wire                         sel_en,
    input  wire [width-1:0]             sel_rx,
    input  wire [width-1:0]             sel_fb1,
    input  wire [width-1:0]             sel_fb2,
    input  wire [35:0]                  in_var_p,
    output wire                         RLS_out_rdy,
    output wire [width-1:0]             RLS_out,
    output wire                         coef_update_plus,
    output wire                         coef_update_en,
    output wire [coe_widthout-1:0]      coef_update_data,
    output wire [19:0]                  update_cnt,
    output wire                         reset_ready
);

    wire core_rst_n;
    wire core_sel_en = sel_en && core_rst_n;

    asic_reset_sync_2ff u_reset_sync (
        .clk    (clk),
        .arst_n (rst_n),
        .srst_n (core_rst_n)
    );

    assign reset_ready = core_rst_n;

    RLS12_c_MW_core_divopt #(
        .width        (width),
        .coe_widthout (coe_widthout),
        .FIFO_depth   (FIFO_depth)
    ) u_core (
        .clk              (clk),
        .rst_n            (core_rst_n),
        .BUF_len          (BUF_len),
        .sel_en           (core_sel_en),
        .sel_rx           (sel_rx),
        .sel_fb1          (sel_fb1),
        .sel_fb2          (sel_fb2),
        .in_var_p         (in_var_p),
        .RLS_out_rdy      (RLS_out_rdy),
        .RLS_out          (RLS_out),
        .coef_update_plus (coef_update_plus),
        .coef_update_en   (coef_update_en),
        .coef_update_data (coef_update_data),
        .update_cnt       (update_cnt)
    );

endmodule
