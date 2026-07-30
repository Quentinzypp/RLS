`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/01/03 09:23:05
// Design Name: 
// Module Name: RLS12_c_data_pack_rx
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

//�����ź�
module RLS12_c_data_pack_rx(
    //input
    clk,
    rst_n,
    pack_in_nd,
    BUF_LEN,            //������ȣ�FIFO������Ϊ16384
    pack_in,            //���ǰ����
    //output
    pack_out_rdy,       //���������ʹ��
    pack_out            //���������
    );
    parameter width          = 48;
    parameter widthout       = 48;
    parameter out_delay      = 175;  //ÿ��175��clk���һ������
    parameter pack_len       = 12;
    parameter FIFO_depth     = 14;   //FIFO�������������


    input                       clk;
    input                       rst_n;
    input                       pack_in_nd;
    input [FIFO_depth-1:0]      BUF_LEN;
    input [width-1:0]           pack_in;

    output reg                  pack_out_rdy;
    output reg [width-1:0]      pack_out;

    reg                         pack_nd_r1,wr_fifo;
    reg [width-1:0]             pack_in_r1,fifo_in;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            pack_nd_r1 <= 0;
            pack_in_r1 <= 0;
        end
        else begin
            pack_nd_r1 <= pack_in_nd;
            pack_in_r1 <= pack_in;
        end
    end

    //FIFOд���ƣ�д��������buf_len������,FIFO���Ϊ16384
    reg     [FIFO_depth-1:0]    cnt_in;
    reg                         wr_state;
    wire                        empty;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            cnt_in      <= 0;
            wr_state    <= 0;
            wr_fifo     <= 0;
            fifo_in     <= 0;
        end
        else begin
            case(wr_state)
                    1'b0:   begin
                        if(empty) begin
                            wr_state <= 1'b1;
                        end
                        else begin
                            wr_state <= 1'b0;
                        end
                    end
                    1'b1:   begin
                        if(pack_nd_r1) begin
                            if(cnt_in == BUF_LEN) begin
                                cnt_in      <= 0;
                                wr_state    <= 1'b0;
                                wr_fifo     <= 0;
                            end
                            else begin
                                cnt_in      <= cnt_in + 1'b1;
                                wr_fifo     <= 1'b1;
                                fifo_in     <= pack_in_r1;
                            end
                        end
                        else begin
                            wr_fifo <= 0;
                        end
                    end
            endcase
        end
    end

    wire    [width-1:0]         fifo_out;
    reg                         rd_fifo;
    wire    [FIFO_depth-1:0]    fifo_cnt;

   
    RLS12_pack_fifo u_pack_fifo_buf_len_rx (
        .rst(!rst_n),                      // input wire rst
        .wr_clk(clk),                // input wire wr_clk
        .rd_clk(clk),                // input wire rd_clk
        .din(fifo_in),                      // input wire [47 : 0] din
        .wr_en(wr_fifo),                  // input wire wr_en
        .rd_en(rd_fifo),                  // input wire rd_en
        .dout(fifo_out),                    // output wire [47 : 0] dout
        .full(),                    // output wire full
        .empty(empty),                  // output wire empty
        .rd_data_count(fifo_cnt)  // output wire [13 : 0] rd_data_count
    );



    reg [7:0]   cnt_delay;
    reg [1:0]   rd_state;
    reg [3:0]   cnt_out11;
    reg         update_flag;
    reg         flag;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            rd_fifo     <= 0;
            cnt_delay   <= 0;
            rd_state    <= 0;
            cnt_out11   <= 0;
            update_flag <= 0;
            flag        <= 0;  //�����ж϶�ȡ���Ƿ�Ϊ��һ�����ݿ�
        end
        else begin
            case(rd_state)
                    2'b00:  begin
                        if(!empty) begin
                            if(!flag) begin
                                rd_state <= 2'b01;
                            end
                            else begin
                                rd_state <= 2'b10;
                            end
                        end
                        else begin
                        end
                        cnt_delay <= 0;
                    end
                    2'b01:  begin
                        flag <= 1'b1;
                        if(cnt_delay == out_delay-1) begin
                            cnt_delay   <= 0;
                            rd_fifo     <= 1'b1;
                        end
                        else begin
                            cnt_delay   <= cnt_delay + 1'b1;
                            rd_fifo     <= 1'b0;
                        end
                        if(empty) begin
                            rd_state <= 2'b00;
                        end
                        else begin
                            rd_state <= rd_state;
                        end
                    end
                    2'b10:  begin
                        if(fifo_cnt >= pack_len-1) begin
                            update_flag <= 1'b1;
                            rd_fifo     <= 1'b1;
                            cnt_out11   <= 1;
                            rd_state    <= 2'b11;  //��FIFO�л��д���12������ʱ�����Լ�����ȡ
                        end
                        else begin
                            rd_state    <= 2'b00;
                        end
                    end
                    2'b11:  begin
                        if(cnt_out11 == pack_len) begin   //������ȡ12������ֹͣ
                            update_flag <= 0;
                            rd_fifo     <= 1'b0;
                            cnt_out11   <= 0;
                        end
                        else begin
                            cnt_out11 <= cnt_out11 + 1'b1;
                        end
                        if(cnt_out11 == pack_len) begin
                            rd_state <= 2'b01;
                        end
                        else begin
                            rd_state <= rd_state;
                        end
                    end
            endcase
        end
    end

    reg                 rd_r,flag_r;
    reg                 pack_rdy;
    reg [width-1:0]     pack_data;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            rd_r        <= 0;
            flag_r      <= 0;
            pack_rdy    <= 0;
            pack_data   <= 0;
        end
        else begin
            flag_r      <= update_flag;
            rd_r        <= rd_fifo;
            pack_rdy    <= rd_r & (!flag_r);
            pack_data   <= fifo_out;
        end
    end

    wire [width:0] delay_out;

    RLS12_delay_rd u_RLS12_delay_rd (
        .D({pack_rdy,pack_data}),        // input wire [48 : 0] D
        .CLK(clk),    // input wire CLK
        .SCLR(!rst_n),  // input wire SCLR
        .Q(delay_out)        // output wire [48 : 0] Q
    );



    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            pack_out_rdy    <= 0;
            pack_out        <= 0;
        end
        else begin
            pack_out_rdy    <= delay_out[48];
            pack_out        <= delay_out[47:0];
        end
    end
endmodule