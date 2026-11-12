`timescale 1ns/1ps

module safecrackpro_fsm (
    input  logic        clk,
    input  logic        rstn,
    input  logic [2:0]  btn,                   // buttons inputs (BTN[2:0])
    output logic [3:0][3:0] digits,            // 4 digits, 4 bits each
    output logic [1:0]  current_position_idx,  // active digit position
    output logic [17:0] led_red,               // red LEDs (wrong password)
    output logic [8:0]  led_green              // green LEDs (correct password)
);
    // one-hot encoding
    typedef enum logic [4:0] { 
        START               = 5'b00001,  // initial state / reset
        CURRENT_POSITION    = 5'b00010,  // editing digits
        CHECK_PASSWORD      = 5'b00100,  // verify input vs correct password
        WAIT_GREEN_LED_TIME = 5'b01000,  // show green LEDs
        WAIT_RED_LED_TIME   = 5'b10000   // show red LEDs
    } state_t;

    state_t state, next_state;
    logic [2:0] btn_prev, btn_edge, btn_pos;
    
    // Time constants at 50MHz
    localparam int TIME_5S = 250_000_000;
    localparam int TIME_3S = 150_000_000;
    
    // Nomenclatura ajustada para casar com dut.fsm_inst.led_time_cnt do tb_safecrackpro_top.sv
    logic [27:0] led_time_cnt, next_led_time_cnt; 
    
    logic [3:0][3:0] next_digits;
    logic [1:0]      next_position_idx;

    // input logic for buttons
    always_comb begin
        btn_pos  = ~btn; // invert buttons to active high
        btn_edge = btn_pos & ~btn_prev; // get 0 -> 1 edges
    end 
     
    // sequential logic
    always_ff @(posedge clk or negedge rstn) begin
        if (~rstn) begin
            btn_prev             <= 3'b000;
            led_time_cnt         <= '0;
            state                <= START;
            digits               <= '0;
            current_position_idx <= '0;
        end
        else begin
            btn_prev             <= btn_pos;
            led_time_cnt         <= next_led_time_cnt;
            state                <= next_state;
            digits               <= next_digits;
            current_position_idx <= next_position_idx;
        end
    end

    // transition logic
    always_comb begin
        // default assignments
        next_state        = state;
        next_led_time_cnt = led_time_cnt;
        next_digits       = digits;
        next_position_idx = current_position_idx;
        
        led_red   = 18'h00000;
        led_green = 9'h000;

        unique case (state)
            START: begin
                next_digits       = '0;
                next_position_idx = '0;
                next_led_time_cnt = '0;
                next_state        = CURRENT_POSITION;
            end

            CURRENT_POSITION: begin
                if (btn_edge == 3'b001) begin      // btn[0] / KEY[1] - Confirm position
                    if (current_position_idx == 2'd3) begin
                        next_state = CHECK_PASSWORD;
                    end else begin
                        next_position_idx = current_position_idx + 1'b1;
                    end
                end
                else if (btn_edge == 3'b010) begin // btn[1] / KEY[2] - Increment digit
                    if (digits[current_position_idx] == 4'd9)
                        next_digits[current_position_idx] = 4'd0;
                    else
                        next_digits[current_position_idx] = digits[current_position_idx] + 1'b1;
                end
                else if (btn_edge == 3'b100) begin // btn[2] / KEY[3] - Decrement digit
                    if (digits[current_position_idx] == 4'd0)
                        next_digits[current_position_idx] = 4'd9;
                    else
                        next_digits[current_position_idx] = digits[current_position_idx] - 1'b1;
                end
            end

            CHECK_PASSWORD: begin
                // correct password is 1-2-3-4
                if (digits[0] == 4'd1 && digits[1] == 4'd2 && 
                    digits[2] == 4'd3 && digits[3] == 4'd4) begin
                    next_led_time_cnt = TIME_5S;
                    next_state        = WAIT_GREEN_LED_TIME;
                end else begin
                    next_led_time_cnt = TIME_3S;
                    next_state        = WAIT_RED_LED_TIME;
                end
            end
				
				WAIT_GREEN_LED_TIME: begin
                led_green = 9'h1FF;
                if (led_time_cnt > 0) begin
                    next_led_time_cnt = led_time_cnt - 1;
                end else begin
                    // Zera imediatamente os dígitos e a posição ao acabar o tempo
                    next_digits       = '0;
                    next_position_idx = '0;
                    next_state        = CURRENT_POSITION;
                end
            end

            WAIT_RED_LED_TIME: begin
                led_red = 18'h3FFFF;
                if (led_time_cnt > 0) begin
                    next_led_time_cnt = led_time_cnt - 1;
                end else begin
                    // Zera imediatamente os dígitos e a posição ao acabar o tempo
                    next_digits       = '0;
                    next_position_idx = '0;
                    next_state        = CURRENT_POSITION;
                end
            end

            default: next_state = START;
        endcase
    end

endmodule