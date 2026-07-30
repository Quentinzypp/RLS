`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/01/10 19:58:09
// Design Name: 
// Module Name: float_complex_div
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: (a+bi)/(c+di)=((ac+bd)+(bc-ad)i)/(c^2+d^2)
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
//����c*c��d*dʱ��Ҫ�����ֵ����λ�������ֵ��λ��

module float_complex_div(
    input clk,                //����ʱ���ź�        
    input rst_n,              //���븴λ�ź�
    input start,              //���뿪ʼ�ź�
    input [33:0] re_a,        //���뱻����a��ʵ��34Q25
    //input [24:0] im_a,        //���뱻����a���鲿25Q18
    input [33:0] im_a,        //���뱻����a���鲿34Q25
    input [33:0] re_b,        //�������b��ʵ��34Q25
    //input [24:0] im_b,        //���뱻����a���鲿25Q18
    input [33:0] im_b,        //�������b���鲿34Q25
    output reg over,          //�����������ź�
    output reg [39:0] re_res, //�����������ʵ��
    output reg [39:0] im_res  //������������鲿
    );


    reg valid1;               //����Ч�ź� 
    reg valid2;               //�Ӽ���Ч�ź� 
    reg valid3;               //����Ч�ź�

    reg [39:0] result1;      //���1       
    reg [39:0] result2;      //���2
    reg [39:0] result3;      //���3
    reg [39:0] result4;      //���4
    reg [39:0] result5;      //���5
    reg [39:0] result6;      //���6

    reg [39:0] result7;      //���7
    reg [39:0] result8;      //���8
    reg [39:0] result9;      //���9
    
    reg [39:0] result10;     //���10
    reg [39:0] result11;     //���11


    wire [49:0] out1;      //�˷������ac
    wire [49:0] out2;      //�˷������bd
    wire [49:0] out3;      //�˷������ad
    wire [49:0] out4;      //�˷������bc
    wire [49:0] out5;      //�˷������cc
    wire [49:0] out6;      //�˷������dd
    wire [71:0] out10;     //���������(ac+bd)/(c^2+d^2)
    wire [71:0] out11;     //���������(bc-ad)/(c^2+d^2)
    
    
    // wire [67:0] out1;      //�˷������ac
    // wire [67:0] out2;      //�˷������bd
    // wire [67:0] out3;      //�˷������ad
    // wire [67:0] out4;      //�˷������bc
    // wire [67:0] out5;      //�˷������cc
    // wire [67:0] out6;      //�˷������dd
    // wire [71:0] out10;     //���������(ac+bd)/(c^2+d^2)
    // wire [71:0] out11;     //���������(bc-ad)/(c^2+d^2)

    reg     [2:0]   state;
    wire            div_rdy1;//�����׼
  wire            div_rdy2;//�����׼
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            valid1   <= 0;  valid2   <= 0; valid3  <= 0;
            result1  <= 0;  result2  <= 0; result3 <= 0;
            result4  <= 0;  result5  <= 0; result6 <= 0;
            result7  <= 0;  result8  <= 0; result9 <= 0;
            result10 <= 0;  result11 <= 0;
            over     <= 0;
            re_res   <= 0;  im_res   <= 0;
            state    <= 0;
        end
        else begin
            if(start == 1) begin
                case(state)
                        default:        begin
                            valid1   <= 0;  valid2   <= 0; valid3  <= 0;
                            result1  <= 0;  result2  <= 0; result3 <= 0;
                            result4  <= 0;  result5  <= 0; result6 <= 0;
                            result7  <= 0;  result8  <= 0; result9 <= 0;
                            //result10 <= 0;  result11 <= 0;
                            over     <= 0;
                            re_res   <= 0;  im_res   <= 0;
                            state <= 3'd1;
                        end
                        3'd1:      begin//����ac,bd,ad,bc,cc,dd
                            valid1   <= 1;  valid2   <= 0; valid3  <= 0;
                            result1 <= out1[48:9];//50Q36-->40Q23
                            result2 <= out2[48:9];//50Q40-->40Q23
                            result3 <= out3[48:9];//50Q40-->40Q23
                            result4 <= out4[48:9];//50Q36-->40Q23
                            result5 <= out5[48:9];//50Q32-->40Q23
                            result6 <= out6[48:9];//50Q40-->40Q23

                            // result1 <= out1[66:27]; result2 <= out2[66:27]; result3 <= out3[66:27];
                            // result4 <= out4[66:27]; result5 <= out5[66:27]; result6 <= out6[66:27];//68Q50-->40Q23
                            
                            state <= 3'd2;
                        end
                        3'd2:      begin
                            valid1   <= 0;  valid2   <= 1; valid3  <= 0;
                            result7 <= result4 - result3;//����bc-ad
                            result8 <= result1 + result2;//����ac+bd
                            result9 <= result5 + result6;//����cc+dd   40Q23
                            state <= 3'd3;
                        end
                        3'd3:      begin//����(ac+bd)/(c^2+d^2)��(bc-ad)/(c^2+d^2)
                            valid1   <= 0;  valid2   <= 0; valid3  <= 1;
                            state <= 3'd4;
                        end
                        3'd4:       begin
                            if(div_rdy1&&div_rdy2) begin
                                valid3  <= 0;
                                result10 <= out10[44:5];    //72Q32-->40Q27(40Q32)
                                result11 <= out11[44:5];    //out10,out11��72Q32
                                state <= 3'd5;
                            end
                            else begin  end
                        end
                        3'd5:       begin
                            over     <= 1;
                            re_res   <= result10;  im_res   <= result11;
                            state <= 3'd0;
                        end
                endcase
            end
            else begin
                valid1   <= 0;  valid2   <= 0; valid3  <= 0;
                result1  <= 0;  result2  <= 0; result3 <= 0;
                result4  <= 0;  result5  <= 0; result6 <= 0;
                result7  <= 0;  result8  <= 0; result9 <= 0;
                result10 <= 0;  result11 <= 0;
                over     <= 0;
                re_res   <= 0;  im_res   <= 0;
            end
        end
    end


    mult_div u1_mult_div (                              //�˷���1    ����a(25Q20)*c(25Q16)=out1(50Q36)
        .CLK(clk),  // input wire CLK
        .A(re_a[33:9]),      // input wire [24 : 0] A
        .B(re_b[33:9]),      // input wire [24 : 0] B
        .P(out1)      // output wire [49 : 0] P
    );
    mult_div u2_mult_div (                              //�˷���2    ����b(25Q20)*d(25Q20)=out2(50Q40)
        .CLK(clk),  // input wire CLK
        .A(im_a[33:9]),      // input wire [24 : 0] A
        .B(im_b[33:9]),      // input wire [24 : 0] B
        .P(out2)      // output wire [49 : 0] P
    );
    mult_div u3_mult_div (                              //�˷���3    ����a(25Q20)*d(25Q20)=out3(50Q40)
        .CLK(clk),  // input wire CLK
        .A(re_a[33:9]),      // input wire [24 : 0] A
        .B(im_b[33:9]),      // input wire [24 : 0] B
        .P(out3)      // output wire [49 : 0] P
    );
    mult_div u4_mult_div (                              //�˷���4    ����b(25Q20)*c(25Q16)=out4(50Q36)
        .CLK(clk),  // input wire CLK
        .A(im_a[33:9]),      // input wire [24 : 0] A
        .B(re_b[33:9]),      // input wire [24 : 0] B
        .P(out4)      // output wire [49 : 0] P
    );
    mult_div u5_mult_div (                              //�˷���5    ����c(25Q16)*c(25Q16)=out5(50Q32)
        .CLK(clk),  // input wire CLK
        .A(re_b[33:9]),      // input wire [24 : 0] A
        .B(re_b[33:9]),      // input wire [24 : 0] B
        .P(out5)      // output wire [49 : 0] P
    );
    mult_div u6_mult_div (                              //�˷���6    ����d(25Q20)*d(25Q20)=out6(50Q40)
        .CLK(clk),  // input wire CLK
        .A(im_b[33:9]),      // input wire [24 : 0] A
        .B(im_b[33:9]),      // input wire [24 : 0] B
        .P(out6)      // output wire [49 : 0] P
    );






    // mult u1_mult (                              //�˷���1    ����ac
    //     .CLK(clk),  // input wire CLK
    //     .A(re_a),      // input wire [33 : 0] A
    //     .B(re_b),      // input wire [33 : 0] B
    //     .P(out1)      // output wire [67 : 0] P
    // );
    // mult u2_mult (                              //�˷���2    ����bd
    //     .CLK(clk),  // input wire CLK
    //     .A(im_a),      // input wire [33 : 0] A
    //     .B(im_b),      // input wire [33 : 0] B
    //     .P(out2)      // output wire [67 : 0] P
    // );
    // mult u3_mult (                              //�˷���3    ����ad
    //     .CLK(clk),  // input wire CLK
    //     .A(re_a),      // input wire [33 : 0] A
    //     .B(im_b),      // input wire [33 : 0] B
    //     .P(out3)      // output wire [67 : 0] P
    // );
    // mult u4_mult (                              //�˷���4    ����bc
    //     .CLK(clk),  // input wire CLK
    //     .A(im_a),      // input wire [33 : 0] A
    //     .B(re_b),      // input wire [33 : 0] B
    //     .P(out4)      // output wire [67 : 0] P
    // );
    // mult u5_mult (                              //�˷���5    ����c*c
    //     .CLK(clk),  // input wire CLK
    //     .A(re_b),      // input wire [33 : 0] A
    //     .B(re_b),      // input wire [33 : 0] B
    //     .P(out5)      // output wire [67 : 0] P
    // );
    // mult u6_mult (                              //�˷���6    ����d*d
    //     .CLK(clk),  // input wire CLK
    //     .A(im_b),      // input wire [33 : 0] A
    //     .B(im_b),      // input wire [33 : 0] B
    //     .P(out6)      // output wire [67 : 0] P
    // );

 
    div u1_div (                                          //������1   ����(ac+bd)/(cc+dd)
        .aclk(clk),                                      // input wire aclk
        .s_axis_divisor_tvalid(valid3),    // input wire s_axis_divisor_tvalid
        .s_axis_divisor_tready(),    // output wire s_axis_divisor_tready
        .s_axis_divisor_tdata(result9),      // input wire [39 : 0] s_axis_divisor_tdata
        .s_axis_dividend_tvalid(valid3),  // input wire s_axis_dividend_tvalid
        .s_axis_dividend_tready(),  // output wire s_axis_dividend_tready
        .s_axis_dividend_tdata(result8),    // input wire [39 : 0] s_axis_dividend_tdata
        .m_axis_dout_tvalid(div_rdy1),          // output wire m_axis_dout_tvalid
        .m_axis_dout_tdata(out10)            // output wire [71 : 0] m_axis_dout_tdata
    );//72Q32



    div u2_div (                                          //������2   ����(bc-ad)/(cc+dd)
        .aclk(clk),                                      // input wire aclk
        .s_axis_divisor_tvalid(valid3),    // input wire s_axis_divisor_tvalid
        .s_axis_divisor_tready(),    // output wire s_axis_divisor_tready
        .s_axis_divisor_tdata(result9),      // input wire [39 : 0] s_axis_divisor_tdata
        .s_axis_dividend_tvalid(valid3),  // input wire s_axis_dividend_tvalid
        .s_axis_dividend_tready(),  // output wire s_axis_dividend_tready
        .s_axis_dividend_tdata(result7),    // input wire [39 : 0] s_axis_dividend_tdata
        .m_axis_dout_tvalid(div_rdy2),          // output wire m_axis_dout_tvalid
        .m_axis_dout_tdata(out11)            // output wire [71 : 0] m_axis_dout_tdata
    );//72Q32



    // integer save_file31;//result1
    // integer save_file32;//result2
    // integer save_file33;//result3
    // integer save_file34;//result4
    // integer save_file35;//result5
    // integer save_file36;//result6

    // integer save_file31_1;//out1
    // integer save_file32_2;//out2
    // integer save_file33_3;//out3
    // integer save_file34_4;//out4
    // integer save_file35_5;//out5
    // integer save_file36_6;//out6


    // integer save_file37;//result7
    // integer save_file38;//result8
    // integer save_file39;//result9


    // integer save_file310_10;//out10
    // integer save_file311_11;//out11


    // integer save_file310;//result10
    // integer save_file311;//result11



    // initial begin
    // //     save_file31 = $fopen("build/debug/RLS/dmresult1.txt");
    // //     save_file32 = $fopen("build/debug/RLS/dmresult2.txt");
    // //     save_file33 = $fopen("build/debug/RLS/dmresult3.txt");
    // //     save_file34 = $fopen("build/debug/RLS/dmresult4.txt");
    // //     save_file35 = $fopen("build/debug/RLS/dmresult5.txt");
    // //     save_file36 = $fopen("build/debug/RLS/dmresult6.txt");

    // //     save_file31_1 = $fopen("build/debug/RLS/dmout1.txt");
    // //     save_file32_2 = $fopen("build/debug/RLS/dmout2.txt");
    // //     save_file33_3 = $fopen("build/debug/RLS/dmout3.txt");
    // //     save_file34_4 = $fopen("build/debug/RLS/dmout4.txt");
    //     save_file35_5 = $fopen("build/debug/RLS/dmout5.txt");
    //     save_file36_6 = $fopen("build/debug/RLS/dmout6.txt");

    // //     save_file37 = $fopen("build/debug/RLS/dmresult7.txt");
    // //     save_file38 = $fopen("build/debug/RLS/dmresult8.txt");
    // //     save_file39 = $fopen("build/debug/RLS/dmresult9.txt");

    // //     save_file310_10 = $fopen("build/debug/RLS/dmout10.txt");
    // //     save_file311_11 = $fopen("build/debug/RLS/dmout11.txt");

    // //     save_file310 = $fopen("build/debug/RLS/dmresult10.txt");
    // //     save_file311 = $fopen("build/debug/RLS/dmresult11.txt");
    // end

    // always @(posedge clk or negedge rst_n) begin
    //     if(valid1) begin
    //         // $fdisplay(save_file31_1 ,"%b",out1);
    //         // $fdisplay(save_file32_2 ,"%b",out2);
    //         // $fdisplay(save_file33_3 ,"%b",out3);
    //         // $fdisplay(save_file34_4 ,"%b",out4);
    //         $fdisplay(save_file35_5 ,"%b",out5);
    //         $fdisplay(save_file36_6 ,"%b",out6);
    //     end
    // //     if(valid1) begin
    // //         $fdisplay(save_file31 ,"%b",result1);
    // //         $fdisplay(save_file32 ,"%b",result2);
    // //         $fdisplay(save_file33 ,"%b",result3);
    // //         $fdisplay(save_file34 ,"%b",result4);
    // //         $fdisplay(save_file35 ,"%b",result5);
    // //         $fdisplay(save_file36 ,"%b",result6);
    // //     end
    // //     if(valid2) begin
    // //         $fdisplay(save_file37 ,"%b",result7);
    // //         $fdisplay(save_file38 ,"%b",result8);
    // //         $fdisplay(save_file39 ,"%b",result9);
    // //     end
    // //     if(div_rdy) begin
    // //         $fdisplay(save_file310_10 ,"%b",out10);
    // //         $fdisplay(save_file311_11 ,"%b",out11);
    // //     end
    // //     if(over) begin
    // //         $fdisplay(save_file310 ,"%b",result10);
    // //         $fdisplay(save_file311 ,"%b",result11);
    // //     end
    //  end



endmodule
