`timescale 1ns / 1ps

module asic_pack_sync_fifo #(
    parameter integer WIDTH = 48,
    parameter integer DEPTH = 16384,
    parameter integer RESET_HOLD_CYCLES = 13,
    parameter integer WRITE_VISIBILITY_DELAY = 5
) (
    input  wire                 clk,
    input  wire                 arst,
    input  wire [WIDTH-1:0]     din,
    input  wire                 wr_en,
    input  wire                 rd_en,
    output wire [WIDTH-1:0]     dout,
    output wire                 full,
    output wire                 empty,
    output reg  [13:0]          rd_data_count,
    output wire                 wr_rst_busy,
    output wire                 rd_rst_busy
);

    reg [4:0] reset_hold_count;
    reg reset_busy_delay1;
    reg reset_busy_delay2;
    reg [WRITE_VISIBILITY_DELAY-1:0] write_visibility_pipeline;
    reg [14:0] visible_occupancy;

    wire reset_active = arst || (reset_hold_count != 0);
    wire core_empty;
    wire core_valid;
    wire core_overflow;
    wire core_underflow;
    wire core_wr_rst_busy;
    wire core_rd_rst_busy;
    wire core_write_enable = wr_en && !reset_active;
    wire core_read_enable = rd_en && !empty && !reset_active;
    wire write_accept = core_write_enable && !full;
    wire read_accept = core_read_enable && !core_empty;
    wire matured_write = write_visibility_pipeline[WRITE_VISIBILITY_DELAY-1];

    assign empty = (visible_occupancy == 0);
    assign wr_rst_busy = reset_busy_delay2;
    assign rd_rst_busy = reset_active;

    always @(posedge clk or posedge arst) begin
        if (arst) begin
            reset_hold_count <= RESET_HOLD_CYCLES;
            reset_busy_delay1 <= 1'b1;
            reset_busy_delay2 <= 1'b1;
        end
        else begin
            if (reset_hold_count != 0) begin
                reset_hold_count <= reset_hold_count - 1'b1;
            end
            reset_busy_delay1 <= reset_active;
            reset_busy_delay2 <= reset_busy_delay1;
        end
    end

    always @(posedge clk or posedge arst) begin
        if (arst) begin
            write_visibility_pipeline <= {WRITE_VISIBILITY_DELAY{1'b0}};
            visible_occupancy <= 15'd0;
            rd_data_count <= 14'd0;
        end
        else if (reset_active) begin
            write_visibility_pipeline <= {WRITE_VISIBILITY_DELAY{1'b0}};
            visible_occupancy <= 15'd0;
            rd_data_count <= 14'd0;
        end
        else begin
            write_visibility_pipeline <= {write_visibility_pipeline[WRITE_VISIBILITY_DELAY-2:0], write_accept};

            case ({matured_write, read_accept})
                2'b10: visible_occupancy <= visible_occupancy + 1'b1;
                2'b01: visible_occupancy <= visible_occupancy - 1'b1;
                default: visible_occupancy <= visible_occupancy;
            endcase

            if (visible_occupancy >= 15'd16383) begin
                rd_data_count <= 14'h3fff;
            end
            else begin
                rd_data_count <= visible_occupancy[13:0] + matured_write;
            end
        end
    end

    asic_sync_fifo #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH)
    ) u_storage_fifo (
        .clk(clk),
        .srst(reset_active),
        .din(din),
        .wr_en(core_write_enable),
        .rd_en(core_read_enable),
        .dout(dout),
        .full(full),
        .empty(core_empty),
        .valid(core_valid),
        .overflow(core_overflow),
        .underflow(core_underflow),
        .wr_rst_busy(core_wr_rst_busy),
        .rd_rst_busy(core_rd_rst_busy)
    );

endmodule
