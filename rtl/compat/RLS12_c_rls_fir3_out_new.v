`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/01/22 19:22:51
// Design Name: 
// Module Name: RLS12_c_rls_fir3_out_new
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


module RLS12_c_rls_fir3_out_new
#(
	parameter   IN_WIDTH    =   48, //输入信号位宽    (24q13,24q13)
    parameter   IN_WIDTH1   =   24, //输入信号位宽    24q13
    parameter   COE_WIDTH   =   72, //输入滤波器系数位宽 (36Q27,36Q27)
    parameter   OUT_WIDTH1  =   24, //输出信号位宽    24q13
    parameter   OUT_WIDTH   =   48  //输出信号位宽    (24q13,24q13)
)
(
    input                           clk,
    input                           rst_n,
    input                           i_rx_en,
    input       [IN_WIDTH-1:0]      i_rx_data,
    input                           i_fb_en,
    input       [IN_WIDTH-1:0]      i_fb_data,   
    input                           i_coe_pulse,    
    input                           i_coe_en,
    input       [COE_WIDTH-1:0]     i_coe_data,
    output  reg                     o_rls_en,
    output  reg [OUT_WIDTH-1:0]     o_rls_data

    );
// wire [47:0] i_rx_data_dly;
// c_d1 d1_dly2 (
//   .D(i_rx_data),      // input wire [47 : 0] D
//   .CLK(clk),  // input wire CLK
//   .Q(i_rx_data_dly)      // output wire [47 : 0] Q
// );
//输入打一拍
reg                             i_rx_en_reg;
reg         [IN_WIDTH-1:0]      i_rx_data_reg;
reg                             i_fb_en_reg;
reg         [IN_WIDTH-1:0]      i_fb_data_reg;   
reg                             i_coe_pulse_reg;    
reg                             i_coe_en_reg;
reg         [COE_WIDTH-1:0]     i_coe_data_reg;

reg [IN_WIDTH1-1:0] i_fb_data_im;
reg [IN_WIDTH1-1:0] i_fb_data_re;
	always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            i_fb_data_im<=0;
            i_fb_data_re<=0;
        end
        else begin
            i_fb_data_re<=i_fb_data[23:0];
            i_fb_data_im<=i_fb_data[47:24];
        end
    end

always @(posedge clk or negedge rst_n)begin
    if(!rst_n) begin
        i_rx_en_reg     <=   'd0;
        i_rx_data_reg   <=   'd0;
        i_fb_en_reg     <=   'd0;
        i_fb_data_reg   <=   'd0;
        i_coe_pulse_reg <=   'd0;
        i_coe_en_reg    <=   'd0;
        i_coe_data_reg  <=   'd0;
    end
    else begin
        i_rx_en_reg     <=   i_rx_en;
        i_rx_data_reg   <=   i_rx_data;
        i_fb_en_reg     <=   i_fb_en;
        i_fb_data_reg   <=   i_fb_data;
        i_coe_pulse_reg <=   i_coe_pulse;
        i_coe_en_reg    <=   i_coe_en;
        i_coe_data_reg  <=   i_coe_data;
    end
end 



// //读取反馈信号
// always @(posedge clk or negedge rst_n) begin
//     if(i_fb_en_reg) begin
//         $fdisplay(save_file1 ,"%b",i_fb_data_reg);
//     end
// end


// //读取接收信号
// integer save_file2;//rx

// initial begin
//     save_file2 = $fopen("build/debug/RLS12_hf/dmrx21.txt");
// end

// always @(posedge clk or negedge rst_n) begin
//     if(i_rx_en_reg) begin
//         $fdisplay(save_file2 ,"%b",{i_rx_data_reg[23:0],i_rx_data_reg[47:24]});
//     end
// end



//将系数更新脉冲进行延时
reg         [12:0]  i_coe_pulse_reg_d;
    
always @(posedge clk or negedge rst_n)begin
    if(!rst_n) begin
        i_coe_pulse_reg_d   <=  'd0;
    end
    else begin
        i_coe_pulse_reg_d   <=  {i_coe_pulse_reg_d[11:0],i_coe_pulse_reg};
    end
end

wire        [12:0]  delay_i_coe_pulse_reg_d;

RLS12_delay_coe_pluse u_RLS12_delay_coe_pluse (
  .D(i_coe_pulse_reg_d),        // input wire [12 : 0] D
  .CLK(clk),    // input wire CLK
  .SCLR(!rst_n),  // input wire SCLR
  .Q(delay_i_coe_pulse_reg_d)        // output wire [12 : 0] Q
);

//重载系数顺序
reg [4:0]   cnt_coe;
reg         state_cnt_coe;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        cnt_coe <= 5'd0;
        state_cnt_coe <= 'd0;
    end
    else begin
        case(state_cnt_coe)
                            default: begin
                                if(i_coe_pulse) begin
                                    state_cnt_coe <= 1'b1;
                                end
                                else begin
                                    state_cnt_coe <= state_cnt_coe;
                                end
                            end
                            1'b1: begin
                                if(cnt_coe == 5'd12) begin
                                    cnt_coe <= 5'd0;
                                    state_cnt_coe <= 1'b0;
                                end
                                else begin
                                    cnt_coe <= cnt_coe + 1'b1;
                                end
                            end
        endcase
    end
end


reg [71:0] coe0,coe1,coe2,coe3,coe4,coe5,coe6,coe7,coe8,coe9,coe10,coe11;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        coe0 <= 72'd0;  coe1 <= 72'd0;  coe2 <= 72'd0; coe3  <= 72'd0; coe4  <= 72'd0; coe5  <= 72'd0;
        coe6 <= 72'd0;  coe7 <= 72'd0;  coe8 <= 72'd0; coe9  <= 72'd0; coe10 <= 72'd0; coe11 <= 72'd0;
    end
    else begin
        if(cnt_coe == 5'd1) begin
            coe11 <= i_coe_data_reg;
        end
        else if(cnt_coe == 5'd2) begin
            coe10 <= i_coe_data_reg;
        end
        else if(cnt_coe == 5'd3) begin
            coe9 <= i_coe_data_reg;
        end
        else if(cnt_coe == 5'd4) begin
            coe8 <= i_coe_data_reg;
        end
        else if(cnt_coe == 5'd5) begin
            coe7 <= i_coe_data_reg;
        end
        else if(cnt_coe == 5'd6) begin
            coe6 <= i_coe_data_reg;
        end
        else if(cnt_coe == 5'd7) begin
            coe5 <= i_coe_data_reg;
        end
        else if(cnt_coe == 5'd8) begin
            coe4 <= i_coe_data_reg;
        end
        else if(cnt_coe == 5'd9) begin
            coe3 <= i_coe_data_reg;
        end
        else if(cnt_coe == 5'd10) begin
            coe2 <= i_coe_data_reg;
        end
        else if(cnt_coe == 5'd11) begin
            coe1 <= i_coe_data_reg;
        end
        else if(cnt_coe == 5'd12) begin
            coe0 <= i_coe_data_reg;
        end
    end
end

//根据IP核重载系数的顺序来构造要重载的系数数据
reg [3:0]           state_coe;
reg [COE_WIDTH-1:0] coe_cross;
reg                 coe_en;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        state_coe <= 4'd0;
        coe_cross <= 50'd0;
        coe_en <= 'd0;
    end
    else begin
        case(state_coe)
                        default: begin
                            if(cnt_coe == 5'd12) begin
                                coe_en <= 'd1;
                                coe_cross <= coe11;
                                state_coe <= 4'd1;
                            end
                        end
                        4'd1: begin
                            coe_cross <= coe10;
                            state_coe <= 4'd2;
                        end
                        4'd2: begin
                            coe_cross <= coe9;
                            state_coe <= 4'd3;
                        end
                        4'd3: begin
                            coe_cross <= coe8;
                            state_coe <= 4'd4;
                        end
                        4'd4: begin
                            coe_cross <= coe7;
                            state_coe <= 4'd5;
                        end
                        4'd5: begin
                            coe_cross <= coe6;
                            state_coe <= 4'd6;
                        end
                        4'd6: begin
                            coe_cross <= coe5;
                            state_coe <= 4'd7;
                        end
                        4'd7: begin
                            coe_cross <= coe4;
                            state_coe <= 4'd8;
                        end
                        4'd8: begin
                            coe_cross <= coe3;
                            state_coe <= 4'd9;
                        end
                        4'd9: begin
                            coe_cross <= coe2;
                            state_coe <= 4'd10;
                        end
                        4'd10: begin
                            coe_cross <= coe1;
                            state_coe <= 4'd11;
                        end
                        4'd11: begin
                            coe_cross <= coe0;
                            state_coe <= 4'd12;
                        end
                        4'd12: begin
                            coe_en <= 'd0;
                            //coe_cross <= 50'd0;
                            state_coe <= 4'd0;
                        end
        endcase
    end
end



//可变系数fir滤波器
wire                s_axis_data_tready_re;
wire                s_axis_config_tready_re;
wire                s_axis_reload_tready_re;
wire                m_axis_data_tvalid_re; //输出数据使能
wire    [127 : 0]   m_axis_data_tdata_re;   //输出数据[127:0]有效，(64q40,64q40)
wire                event_s_reload_tlast_missing_re;
wire                event_s_reload_tlast_unexpected_re;

RLS12_c_fir_im1 u_RLS12_c_fir_re1 (
  .aresetn(rst_n),                                                  // input wire aresetn
  .aclk(clk),                                                        // input wire aclk
  .s_axis_data_tvalid(i_fb_en_reg),                            // input wire s_axis_data_tvalid
  .s_axis_data_tready(s_axis_data_tready_re),                            // output wire s_axis_data_tready
  .s_axis_data_tdata(i_fb_data_reg),                              // input wire [47 : 0] s_axis_data_tdata
  .s_axis_config_tvalid(delay_i_coe_pulse_reg_d[12]),                        // input wire s_axis_config_tvalid
  .s_axis_config_tready(s_axis_config_tready_re),                        // output wire s_axis_config_tready
  .s_axis_config_tdata(8'd0),                          // input wire [7 : 0] s_axis_config_tdata
  .s_axis_reload_tvalid(coe_en),                        // input wire s_axis_reload_tvalid
  .s_axis_reload_tready(s_axis_reload_tready_re),                        // output wire s_axis_reload_tready
  .s_axis_reload_tlast(delay_i_coe_pulse_reg_d[11]),                          // input wire s_axis_reload_tlast
  .s_axis_reload_tdata({4'b0,coe_cross[35:0]}),                          // input wire [39 : 0] s_axis_reload_tdata
  .m_axis_data_tvalid(m_axis_data_tvalid_re),                            // output wire m_axis_data_tvalid
  .m_axis_data_tdata(m_axis_data_tdata_re),                              // output wire [127 : 0] m_axis_data_tdata
  .event_s_reload_tlast_missing(event_s_reload_tlast_missing_re),        // output wire event_s_reload_tlast_missing
  .event_s_reload_tlast_unexpected(event_s_reload_tlast_unexpected_re)  // output wire event_s_reload_tlast_unexpected
);


wire                s_axis_data_tready_im;
wire                s_axis_config_tready_im;
wire                s_axis_reload_tready_im;
wire                m_axis_data_tvalid_im; //输出数据使能
wire    [127 : 0]   m_axis_data_tdata_im;  //输出数据[127:0]有效，(64q40,64q40)
wire                event_s_reload_tlast_missing_im;
wire                event_s_reload_tlast_unexpected_im;

RLS12_c_fir_im1 u_RLS12_c_fir_im1 (
  .aresetn(rst_n),                                                  // input wire aresetn
  .aclk(clk),                                                        // input wire aclk
  .s_axis_data_tvalid(i_fb_en_reg),                            // input wire s_axis_data_tvalid
  .s_axis_data_tready(s_axis_data_tready_im),                            // output wire s_axis_data_tready
  .s_axis_data_tdata(i_fb_data_reg),                              // input wire [47 : 0] s_axis_data_tdata
  .s_axis_config_tvalid(delay_i_coe_pulse_reg_d[12]),                        // input wire s_axis_config_tvalid
  .s_axis_config_tready(s_axis_config_tready_im),                        // output wire s_axis_config_tready
  .s_axis_config_tdata(8'd0),                          // input wire [7 : 0] s_axis_config_tdata
  .s_axis_reload_tvalid(coe_en),                        // input wire s_axis_reload_tvalid
  .s_axis_reload_tready(s_axis_reload_tready_im),                        // output wire s_axis_reload_tready
  .s_axis_reload_tlast(delay_i_coe_pulse_reg_d[11]),                          // input wire s_axis_reload_tlast
  .s_axis_reload_tdata({4'b0,coe_cross[71:36]}),                          // input wire [39 : 0] s_axis_reload_tdata
  .m_axis_data_tvalid(m_axis_data_tvalid_im),                            // output wire m_axis_data_tvalid
  .m_axis_data_tdata(m_axis_data_tdata_im),                              // output wire [127 : 0] m_axis_data_tdata
  .event_s_reload_tlast_missing(event_s_reload_tlast_missing_im),        // output wire event_s_reload_tlast_missing
  .event_s_reload_tlast_unexpected(event_s_reload_tlast_unexpected_im)  // output wire event_s_reload_tlast_unexpected
);




// RLS12_c_fir_im1 u_RLS12_c_fir_im1 (
//   .aresetn(rst_n),                                                  // input wire aresetn
//   .aclk(clk),                                                        // input wire aclk
//   .s_axis_data_tvalid(i_fb_en_reg),                            // input wire s_axis_data_tvalid
//   .s_axis_data_tready(s_axis_data_tready_im),                            // output wire s_axis_data_tready
//   .s_axis_data_tdata(i_fb_data_reg),                              // input wire [47 : 0] s_axis_data_tdata
//   .s_axis_config_tvalid(i_coe_pulse_reg_d[12]),                        // input wire s_axis_config_tvalid
//   .s_axis_config_tready(s_axis_config_tready_im),                        // output wire s_axis_config_tready
//   .s_axis_config_tdata(8'd0),                          // input wire [7 : 0] s_axis_config_tdata
//   .s_axis_reload_tvalid(i_coe_en_reg),                        // input wire s_axis_reload_tvalid
//   .s_axis_reload_tready(s_axis_reload_tready_im),                        // output wire s_axis_reload_tready
//   .s_axis_reload_tlast(i_coe_pulse_reg_d[11]),                          // input wire s_axis_reload_tlast
//   .s_axis_reload_tdata({6'b0,i_coe_data_reg[48:31]}),                          // input wire [23 : 0] s_axis_reload_tdata
//   .m_axis_data_tvalid(m_axis_data_tvalid_im),                            // output wire m_axis_data_tvalid
//   .m_axis_data_tdata(m_axis_data_tdata_im),                              // output wire [95 : 0] m_axis_data_tdata
//   .event_s_reload_tlast_missing(event_s_reload_tlast_missing_im),        // output wire event_s_reload_tlast_missing
//   .event_s_reload_tlast_unexpected(event_s_reload_tlast_unexpected_im)  // output wire event_s_reload_tlast_unexpected
// );


// RLS12_c_fir_im u_RLS12_c_fir_im (
//   .aresetn(rst_n),                                                       // input wire aresetn
//   .aclk(clk),                                                            // input wire aclk
//   .s_axis_data_tvalid(i_fb_en_reg),                                      // input wire s_axis_data_tvalid
//   .s_axis_data_tready(s_axis_data_tready_im),                            // output wire s_axis_data_tready
//   .s_axis_data_tdata(i_fb_data_reg),                                     // input wire [47 : 0] s_axis_data_tdata
//   .s_axis_config_tvalid(i_coe_pulse_reg_d[12]),                          // input wire s_axis_config_tvalid
//   .s_axis_config_tready(s_axis_config_tready_im),                        // output wire s_axis_config_tready
//   .s_axis_config_tdata(8'd0),                                            // input wire [7 : 0] s_axis_config_tdata
//   .s_axis_reload_tvalid(i_coe_en_reg),                                   // input wire s_axis_reload_tvalid
//   .s_axis_reload_tready(s_axis_reload_tready_im),                        // output wire s_axis_reload_tready
//   .s_axis_reload_tlast(i_coe_pulse_reg_d[11]),                           // input wire s_axis_reload_tlast
//   .s_axis_reload_tdata({7'b0,i_coe_data_reg[49:25]}),   //取锟斤拷锟斤拷       // input wire [31 : 0] s_axis_reload_tdata
//   .m_axis_data_tvalid(m_axis_data_tvalid_im),                            // output wire m_axis_data_tvalid
//   .m_axis_data_tdata(m_axis_data_tdata_im),                              // output wire [111 : 0] m_axis_data_tdata
//   .event_s_reload_tlast_missing(event_s_reload_tlast_missing_im),        // output wire event_s_reload_tlast_missing
//   .event_s_reload_tlast_unexpected(event_s_reload_tlast_unexpected_im)   // output wire event_s_reload_tlast_unexpected
// );



//对滤波器输出进行截位64q40-->24q13
//u(n):a+bj,w(n):c+dj       u(n)卷w(n)共轭=(a卷c+b卷d)+j(b卷c-a卷d)
//re滤波器输入的是分两路输入u(n),输入的系数为实部，输出的结果为a卷c、b卷c
//im滤波器输入的是分两路输入u(n),输入的系数为虚部，输出的结果为a卷d、b卷d

reg                         dout_fir_en;
reg     [IN_WIDTH1-1:0]     dout_fir_data_1,dout_fir_data_2,dout_fir_data_3,dout_fir_data_4;

always @(posedge clk or negedge rst_n)begin
    if(!rst_n) begin
        dout_fir_en     <=  'd0;
        dout_fir_data_1 <=  'd0;
        dout_fir_data_2 <=  'd0;
        dout_fir_data_3 <=  'd0;
        dout_fir_data_4 <=  'd0;
    
    end
    else begin
        dout_fir_en       <=  m_axis_data_tvalid_re;
        dout_fir_data_1   <=  {m_axis_data_tdata_re[63],m_axis_data_tdata_re[49:27]};//ac
        dout_fir_data_2   <=  {m_axis_data_tdata_re[127],m_axis_data_tdata_re[113:91]};//bc
        dout_fir_data_3   <=  {m_axis_data_tdata_im[63],m_axis_data_tdata_im[49:27]};//ad
        dout_fir_data_4   <=  {m_axis_data_tdata_im[127],m_axis_data_tdata_im[113:91]};//bd      
    end
end



// always @(posedge clk or negedge rst_n)begin
//     if(!rst_n) begin
//         dout_fir_en     <=  'd0;
//         dout_fir_data_1 <=  'd0;
//         dout_fir_data_2 <=  'd0;
//         dout_fir_data_3 <=  'd0;
//         dout_fir_data_4 <=  'd0;
    
//     end
//     else begin
//         dout_fir_en       <=  m_axis_data_tvalid_re;
//         dout_fir_data_1   <=  {m_axis_data_tdata_re[52],m_axis_data_tdata_re[42:20]};//ac
//         dout_fir_data_2   <=  {m_axis_data_tdata_re[108],m_axis_data_tdata_re[98:76]};//bc
//         dout_fir_data_3   <=  {m_axis_data_tdata_im[52],m_axis_data_tdata_im[42:20]};//ad
//         dout_fir_data_4   <=  {m_axis_data_tdata_im[108],m_axis_data_tdata_im[98:76]};//bd      
//     end
// end

reg                         dout_fir_en1;
reg     [IN_WIDTH1-1:0]     dout_fir_data_14,dout_fir_data_23;//24Q13

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        dout_fir_en1     <= 'd0;
        dout_fir_data_14 <= 'd0;
        dout_fir_data_23 <= 'd0;
    end
    else begin
        dout_fir_en1     <= dout_fir_en;
        dout_fir_data_14 <= dout_fir_data_1 + dout_fir_data_4;//ac+bd
        dout_fir_data_23 <= dout_fir_data_2 - dout_fir_data_3;//bc-ad
    end
end

reg                         dout_fir_en2;
reg     [IN_WIDTH-1:0]      dout_fir_data;//(24Q13,24Q13)

always @(posedge clk or negedge rst_n)begin
    if(!rst_n) begin
        dout_fir_en2     <= 'd0;
        dout_fir_data    <= 'd0;
    
    end
    else begin
        dout_fir_en2     <=  dout_fir_en1;
        dout_fir_data    <=  {dout_fir_data_23,dout_fir_data_14};
    end
end


//将输入接收数据缓存起来，等fir输出后对齐输出
wire    [47:0]  dout_fifo_rx_data;
wire            dout_fifo_rx_dull;
wire            dout_fifo_rx_empty;
wire            dout_fifo_rx_vaild; //输出使能  

fifo_RLS12_c_rx u_fifo_RLS12_c_rx (
  .clk(clk),                   // input wire clk
  .srst(!rst_n),                // input wire rst
  .din(i_rx_data_reg),         // input wire [47 : 0] din
  .wr_en(i_rx_en_reg),         // input wire wr_en
  .rd_en(dout_fir_en2),        // input wire rd_en
  .dout(dout_fifo_rx_data),    // output wire [47 : 0] dout
  .full(dout_fifo_rx_dull),    // output wire full
  .empty(dout_fifo_rx_empty),  // output wire empty
  .valid(dout_fifo_rx_vaild)   // output wire valid
);



//将滤波器输出(截位之后)打两拍
reg                         dout_fir_en_d1;
reg     [OUT_WIDTH-1:0]     dout_fir_data_d1;

reg                         dout_fir_en_d2;
reg     [OUT_WIDTH-1:0]     dout_fir_data_d2;
always @(posedge clk or negedge rst_n)begin
    if(!rst_n) begin
        dout_fir_en_d1      <=  'd0;
        dout_fir_data_d1    <=  'd0;
        dout_fir_en_d2      <=  'd0;
        dout_fir_data_d2    <=  'd0;
    end
    else begin
        dout_fir_en_d1      <=  dout_fir_en2;
        dout_fir_data_d1    <=  dout_fir_data;
        dout_fir_en_d2      <=  dout_fir_en_d1;
        dout_fir_data_d2    <=  dout_fir_data_d1;           
    end
end



//将fifo输出打一拍，保证 dout_fifo_rx_vaild_d1 与 dout_fir_en_d2 对齐，方便后面做减法
reg             dout_fifo_rx_vaild_d1; //输出使能
reg     [47:0]  dout_fifo_rx_data_d1;
always @(posedge clk or negedge rst_n)begin
    if(!rst_n) begin
        dout_fifo_rx_vaild_d1   <=  'd0;
        dout_fifo_rx_data_d1    <=  'd0;        
    end
    else begin
        dout_fifo_rx_vaild_d1   <=  dout_fifo_rx_vaild;
        dout_fifo_rx_data_d1    <=  dout_fifo_rx_data;        
    end
end



//减法
reg                         dout_sub_en;
reg     [OUT_WIDTH1-1:0]    dout_sub_data1,dout_sub_data2;
always @(posedge clk or negedge rst_n)begin
    if(!rst_n) begin
        dout_sub_en     <=  'd0;
        dout_sub_data1  <=  'd0;
        dout_sub_data2  <=  'd0;
    
    end
    else begin
        dout_sub_en     <=  dout_fir_en_d2 & dout_fifo_rx_vaild_d1;
        dout_sub_data1  <=  dout_fifo_rx_data_d1[47:24] - dout_fir_data_d2[47:24];
        dout_sub_data2  <=  dout_fifo_rx_data_d1[23:0] - dout_fir_data_d2[23:0];        
    end
end
// wire [23:0] dout_fifo_rx_data_d1_re;
// wire [23:0] dout_fir_data_d2_re;
// assign dout_fifo_rx_data_d1_re=dout_fifo_rx_data_d1[23:0];
// assign dout_fir_data_d2_re=dout_fir_data_d2[23:0];


reg                         dout_sub_en1;
reg     [OUT_WIDTH-1:0]     dout_sub_data;
always @(posedge clk or negedge rst_n)begin
    if(!rst_n) begin
        dout_sub_en1     <=  'd0;
        dout_sub_data    <=  'd0;
    
    end
    else begin
        dout_sub_en1    <=  dout_sub_en;
        dout_sub_data   <=  {dout_sub_data1,dout_sub_data2};//高虚低实  
    end
end


/* ila_rlsfir u_ila_rlsfir (
	.clk(clk), // input wire clk


	.probe0(dout_fifo_rx_data_d1_re), // input wire [23:0]  probe0  
	.probe1(dout_fir_data_d2_re), // input wire [23:0]  probe1 
	.probe2(dout_sub_data2) // input wire [23:0]  probe2
); */

//输出
always @(posedge clk or negedge rst_n)begin
    if(!rst_n) begin
        o_rls_en    <=  'd0;
        o_rls_data  <=  'd0;
    end
    else begin
        if(dout_sub_en1) begin
            o_rls_en    <=  'd1;
            o_rls_data  <=  {(dout_sub_data[23:0]),(dout_sub_data[47:24])};//输出高实低虚        
        end
        else begin
            o_rls_en    <=  'd0;
            o_rls_data  <=  'd0;            
        end
    end
end
reg     [IN_WIDTH1-1:0] o_rls_data_im;
reg     [IN_WIDTH1-1:0] o_rls_data_re;
	always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            o_rls_data_im<=0;
            o_rls_data_re<=0;
        end
        else begin
            o_rls_data_re<=o_rls_data[23:0];
            o_rls_data_im<=o_rls_data[47:24];
        end
    end


// integer save_file6;//rlsout

// initial begin
//     save_file6 = $fopen("build/debug/RLS12_hf/dmrls21.txt");
// end

// always @(posedge clk or negedge rst_n) begin
//     if(o_rls_en) begin
//         $fdisplay(save_file6 ,"%b",o_rls_data);
//     end
// end

endmodule
