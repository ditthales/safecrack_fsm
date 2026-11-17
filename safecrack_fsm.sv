`timescale 1ns/1ps

module safecrackpro_fsm (
    input  logic        clk,
    input  logic        rstn,
    input  logic [2:0]  btn,                   // Entradas dos botões (BTN[2:0])
    output logic [3:0][3:0] digits,            // 4 dígitos da senha, com 4 bits cada
    output logic [1:0]  current_position_idx,  // Índice do dígito sendo editado
    output logic [17:0] led_red,               // LEDs vermelhos (senha incorreta)
    output logic [8:0]  led_green              // LEDs verdes (senha correta)
);
    // Definição dos estados da FSM utilizando One-Hot Encoding para otimização em FPGA
    typedef enum logic [4:0] { 
        START               = 5'b00001,  // Estado inicial / Reset
        CURRENT_POSITION    = 5'b00010,  // Edição e navegação entre os dígitos
        CHECK_PASSWORD      = 5'b00100,  // Verificação da senha inserida
        WAIT_GREEN_LED_TIME = 5'b01000,  // Exibição de sucesso (LEDs verdes)
        WAIT_RED_LED_TIME   = 5'b10000   // Exibição de erro (LEDs vermelhos)
    } state_t;

    state_t state, next_state;
    logic [2:0] btn_prev, btn_edge, btn_pos;
    
    // Constantes de temporização baseadas no clock de 50MHz da placa
    localparam int TIME_5S = 250_000_000;
    localparam int TIME_3S = 150_000_000;
    
    // Contador para o tempo dos LEDs (nomeado para compatibilidade com o testbench)
    logic [27:0] led_time_cnt, next_led_time_cnt; 
    
    logic [3:0][3:0] next_digits;
    logic [1:0]      next_position_idx;

    // Lógica para detectar apenas o clique (borda de subida) dos botões
    always_comb begin
        btn_pos  = ~btn; // Inverte os botões, pois a placa opera em lógica ativa-baixa
        btn_edge = btn_pos & ~btn_prev; // Detecta a transição de 0 para 1
    end 
     
    // Bloco sequencial: Atualiza o estado da máquina e os registradores a cada ciclo de clock
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

    // Bloco combinacional: Define a lógica de transição de estados e as saídas da FSM
    always_comb begin
        // Valores padrão para evitar a criação indesejada de latches
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

            // Estado responsável pela edição da senha. Avalia as ações de incrementar, decrementar e confirmar.
            CURRENT_POSITION: begin
                if (btn_edge == 3'b001) begin      // Confirma o dígito e avança a posição
                    if (current_position_idx == 2'd3) begin
                        next_state = CHECK_PASSWORD; // Inicia a verificação se estiver na última posição
                    end else begin
                        next_position_idx = current_position_idx + 1'b1;
                    end
                end
                else if (btn_edge == 3'b010) begin // Incrementa o dígito com wrap-around (9 -> 0)
                    if (digits[current_position_idx] == 4'd9)
                        next_digits[current_position_idx] = 4'd0;
                    else
                        next_digits[current_position_idx] = digits[current_position_idx] + 1'b1;
                end
                else if (btn_edge == 3'b100) begin // Decrementa o dígito com wrap-around (0 -> 9)
                    if (digits[current_position_idx] == 4'd0)
                        next_digits[current_position_idx] = 4'd9;
                    else
                        next_digits[current_position_idx] = digits[current_position_idx] - 1'b1;
                end
            end

            // Compara a senha inserida com a sequência correta e define o tempo e o próximo estado correspondentes
            CHECK_PASSWORD: begin
                if (digits[0] == 4'd1 && digits[1] == 4'd2 && 
                    digits[2] == 4'd3 && digits[3] == 4'd4) begin
                    next_led_time_cnt = TIME_5S;
                    next_state        = WAIT_GREEN_LED_TIME;
                end else begin
                    next_led_time_cnt = TIME_3S;
                    next_state        = WAIT_RED_LED_TIME;
                end
            end
				
            // Acende os LEDs verdes e realiza a contagem regressiva para reiniciar o sistema
            WAIT_GREEN_LED_TIME: begin
                led_green = 9'h1FF;
                if (led_time_cnt > 0) begin
                    next_led_time_cnt = led_time_cnt - 1;
                end else begin
                    next_digits       = '0;
                    next_position_idx = '0;
                    next_state        = CURRENT_POSITION;
                end
            end

            // Acende os LEDs vermelhos e realiza a contagem regressiva para reiniciar o sistema
            WAIT_RED_LED_TIME: begin
                led_red = 18'h3FFFF;
                if (led_time_cnt > 0) begin
                    next_led_time_cnt = led_time_cnt - 1;
                end else begin
                    next_digits       = '0;
                    next_position_idx = '0;
                    next_state        = CURRENT_POSITION;
                end
            end

            default: next_state = START;
        endcase
    end

endmodule