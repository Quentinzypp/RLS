`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/07/05 14:56:54
// Design Name: 
// Module Name: RLS12_c_data_pack_fb2
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

//�����ź�2����������·��ϵ���������ģ��
module RLS12_c_data_pack_fb2(
    //input
    clk,
    rst_n,
    BUF_LEN,     //���泤�ȣ�FIFO������Ϊ16383
    pack_in_nd,  //���ǰ������ʹ��
    pack_in,     //���ǰ������
    //output
    pack_out_rdy,//����������ʹ��
    pack_out     //����������
    );

    parameter width         = 48;
    parameter widthout      = 48;
    parameter out_delay     = 175;  //ÿ��175clk���12������
    parameter pack_len      = 12;   //Ϊ��������12������
    parameter FIFO_depth    = 14;   //����FIFO������λ��  log2(16383)=14

    input                       clk;
    input                       rst_n;
    input   [FIFO_depth-1:0]    BUF_LEN;
    input                       pack_in_nd;//sel_en
    input   [width-1:0]         pack_in;//sel_fb

    output  reg                         pack_out_rdy;
    output  reg     [widthout-1:0]      pack_out;

    reg								pack_nd_r1,wr_fifo;
	reg		   [width-1:0]          pack_in_r1,fifo_in;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            pack_nd_r1  <= 0;
            pack_in_r1  <= 0;
        end
        else begin
            pack_nd_r1	<=pack_in_nd;
		    pack_in_r1	<=pack_in;
        end
    end

    //FIFOд���ƣ�д��������buf_len������,FIFO���Ϊ16384
    reg [FIFO_depth-1:0]    cnt_in;
    reg                     wr_state;
    wire                    empty;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            cnt_in      <= 0;
            wr_state    <= 0;
            wr_fifo     <= 0;
            fifo_in     <= 0;
        end
        else begin
            case(wr_state)
                    1'b0: begin
                        if(empty) begin
                            wr_state <= 1'b1;//���˾�Ҫ��ʼд��
                        end
                        else begin
                            wr_state <= 1'b0;
                        end
                    end
                    1'b1: begin
                        if(pack_nd_r1) begin
                            if(cnt_in == BUF_LEN) begin
                                cnt_in      <= 0;
                                wr_state    <= 1'b0;
                                wr_fifo     <= 1'b0;
                            end
                            else begin
                                cnt_in  <= cnt_in + 1'b1;
                                wr_fifo <= 1'b1;
                                fifo_in <= pack_in_r1;
                            end
                        end
                        else begin
                            wr_fifo <= 0;
                        end
                    end
            endcase
        end
    end


reg                         rd_fifo;  //FIFO��ʹ��
wire    [width-1:0]         fifo_out;
wire    [FIFO_depth-1:0]    fifo_cnt;
wire                        fifo_full;
wire                        fifo_wr_rst_busy;
wire                        fifo_rd_rst_busy;

RLS12_pack_fifo u_pack_fifo_buf_len_fb (
    .rst(!rst_n), // input rst�ߵ�ƽ��Ч
    .wr_clk(clk), // input wr_clk
    .rd_clk(clk), // input rd_clk
    .din(fifo_in), // input [47 : 0] din
    .wr_en(wr_fifo), // input wr_en
    .rd_en(rd_fifo), // input rd_en
    .dout(fifo_out), // output [47 : 0] dout
    .full(fifo_full), // output full
    .empty(empty), // output empty
    .rd_data_count(fifo_cnt), // output [13 : 0] rd_data_count fifo�л��ж��ٿ��Զ�ȡ��������Ŀ
    .wr_rst_busy(fifo_wr_rst_busy),
    .rd_rst_busy(fifo_rd_rst_busy)
);




reg     [1:0]       rd_state;
reg                 update_flag;
reg                 flag;       //�����ж϶�ȡ���Ƿ�Ϊ��һ�����ݿ�
reg     [7:0]       cnt_delay;  //����һ��ϵ����Ҫ����ʱ,��175clk���
reg     [3:0]       cnt_out11;  //������12������


always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        rd_fifo     <= 0;
        rd_state    <= 2'b0;
        cnt_delay   <= 8'b0;
        cnt_out11   <= 4'b0;
        update_flag <= 0;
        flag        <= 0;  //�����ж϶�ȡ���Ƿ�Ϊ��һ�����ݿ�
    end
    else begin
        case(rd_state)
                2'b00: begin
                    if(!empty) begin
                        if(!flag) begin
                            rd_state <= 2'b01;  //�ǿ���flagΪ0�����ǵ�һ�����ݿ�
                        end
                        else begin
                            rd_state <= 2'b10;  //����ǿղ���flagΪ1  ����һ�����ݿ���һ�����ݿ��������Ķ�12��
                        end
                    end
                    cnt_delay <= 0;
                end
                2'b01: begin
                    flag <= 1'b1;
                    if(cnt_delay == out_delay-1) begin     //�����ƹ�175clk ���߶�ʹ��
                        cnt_delay   <= 8'b0;
                        rd_fifo     <= 1;
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
                2'b10: begin
                    if(fifo_cnt >= pack_len-1) begin
                        update_flag		<=1'b1;
                        rd_fifo         <= 1;
                        cnt_out11       <= 1;
                        rd_state        <= 2'b11;  //��FIFO�л��д���12������ʱ�����Լ�����ȡ
                    end
                    else begin
                        rd_state    <= 2'b00;
                    end
                end
                2'b11: begin
                    if(cnt_out11 == pack_len) begin  //������ȡ12������ֹͣ
                        update_flag	<= 0;//����ﵽ�������������
                        rd_fifo     <= 0;
                        cnt_out11   <= 0;
                    end
                    else begin
                        cnt_out11   <= cnt_out11 + 1'b1;  //��������12������֮�����Ͷ�ʹ��
                    end
                    if(cnt_out11 == pack_len) begin
                        rd_state    <= 2'b01;
                    end
                    else begin
                        rd_state    <= rd_state;
                    end
                end
        endcase
    end
end

reg 				rd_r,flag_r;
reg					pack_rdy,flag_rdy;
reg	[width-1:0]		pack_data;



always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        rd_r		<=0;
		flag_r		<=0;
		flag_rdy	<=0;
		pack_rdy	<=0;
		pack_data	<=0;
    end
    else begin
        flag_r		<=update_flag;
		flag_rdy	<=flag_r;
		rd_r		<=rd_fifo;
		pack_rdy	<=rd_r;   //pack_rdy��rd_fifo��һ��
		pack_data	<=fifo_out;	
    end
end



wire                    packto12_rdy;
wire    [width-1:0]     packto12;

packto121 u_packto121(
    .clk(clk),
    .rst_n(rst_n),
    .din_nd(pack_rdy),
    .din_data(pack_data),
    .flag_nd(flag_rdy),
    .dout_rdy(packto12_rdy),
    .dout_data(packto12)
);

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        pack_out_rdy    <= 0;
        pack_out        <= 0;
    end
    else begin
        pack_out_rdy    <= packto12_rdy;
        pack_out        <= packto12;
    end
end


endmodule

