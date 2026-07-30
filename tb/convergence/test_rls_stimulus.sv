`timescale 1ns / 1ps

module test_rls;
    localparam integer WIDTH = 48;
    localparam integer COE_WIDTH = 72;
    localparam integer FIFO_DEPTH = 14;

    reg clk = 1'b1;
    reg rst_n = 1'b0;
    reg sel_en = 1'b0;
    reg [FIFO_DEPTH-1:0] BUF_LEN_200m = 14'd1000;
    reg [WIDTH-1:0] sel_in_fb1 = '0;
    reg [WIDTH-1:0] sel_in_fb1_d1 = '0;
    reg [WIDTH-1:0] sel_in_fb1_d2 = '0;
    reg [WIDTH-1:0] sel_in_fb2 = '0;
    reg [WIDTH-1:0] sel_in_rx = '0;
    reg [WIDTH-1:0] sel_in_rx_d1 = '0;
    reg [WIDTH-1:0] sel_in_rx_d2 = '0;
    reg [35:0] in_var_p = 36'd4294967296;
    reg [20:0] cnt = '0;
    reg [47:0] din_data_fb1 [0:99999];
    reg [47:0] din_data_fb2 [0:99999];
    reg [47:0] din_data_rx [0:99999];
    string reference_vector;
    string desired_vector;

    wire RLS_out_rdy;
    wire [WIDTH-1:0] RLS_out;
    wire coef_update_plus;
    wire coef_update_en;
    wire [COE_WIDTH-1:0] coef_update_data;
    wire [19:0] update_cnt;
    wire reset_ready;
    reg monitor_enable = 1'b0;

    always #32.552 clk = ~clk;

    initial begin
        if (!$value$plusargs("REFERENCE_VECTOR=%s", reference_vector))
            $fatal(1, "REFERENCE_VECTOR plusarg is required");
        if (!$value$plusargs("DESIRED_VECTOR=%s", desired_vector))
            $fatal(1, "DESIRED_VECTOR plusarg is required");
        $readmemb(reference_vector, din_data_fb1);
        $readmemb(reference_vector, din_data_fb2);
        $readmemb(desired_vector, din_data_rx);
        #100 rst_n = 1'b1;
        #10 sel_en = 1'b1;
    end

    always @(posedge clk or negedge reset_ready) begin
        if (!reset_ready) begin
            cnt <= '0;
            monitor_enable <= 1'b0;
        end else begin
            monitor_enable <= 1'b1;
            cnt <= (cnt == 21'd16383) ? 21'd0 : cnt + 1'b1;
        end
    end

    always @(posedge clk or negedge reset_ready) begin
        if (!reset_ready) begin
            sel_in_fb1 <= '0;
            sel_in_fb1_d1 <= '0;
            sel_in_fb1_d2 <= '0;
            sel_in_fb2 <= '0;
            sel_in_rx <= '0;
            sel_in_rx_d1 <= '0;
            sel_in_rx_d2 <= '0;
        end else begin
            sel_in_fb1 <= din_data_fb1[cnt];
            sel_in_fb1_d1 <= sel_in_fb1;
            sel_in_fb1_d2 <= sel_in_fb1_d1;
            sel_in_fb2 <= din_data_fb2[cnt];
            sel_in_rx <= din_data_rx[cnt];
            sel_in_rx_d1 <= sel_in_rx;
            sel_in_rx_d2 <= sel_in_rx_d1;
        end
    end

    RLS12_c_MW_top_divopt u_RLS12_c_MW_top (
        .clk(clk),
        .rst_n(rst_n),
        .BUF_len(BUF_LEN_200m),
        .sel_en(sel_en),
        .sel_rx(sel_in_rx_d2),
        .sel_fb1(sel_in_fb1),
        .sel_fb2(sel_in_fb1),
        .in_var_p(in_var_p),
        .RLS_out_rdy(RLS_out_rdy),
        .RLS_out(RLS_out),
        .coef_update_plus(coef_update_plus),
        .coef_update_en(coef_update_en),
        .coef_update_data(coef_update_data),
        .update_cnt(update_cnt),
        .reset_ready(reset_ready)
    );

    always @(posedge clk) begin
        if (reset_ready && sel_en && sel_in_fb1 !== sel_in_fb2)
            $fatal(1, "single-reference alias contract violated");
    end
endmodule
