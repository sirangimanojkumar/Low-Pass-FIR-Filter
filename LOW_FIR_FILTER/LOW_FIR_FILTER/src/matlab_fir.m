%% 1. Filter Specifications
Fs   = 48000;       % Sampling Frequency (Hz)
Fp   = 4000;        % Passband Cutoff Frequency (Hz)
Fstop = 8000;       % Stopband Cutoff Frequency (Hz)
N    = 15;          % Filter Order (Number of Taps = N + 1 = 16)
Wb   = 16;          % Word length for fixed-point coefficients

%% 2. Calculate Ideal Coefficients (Normalized Cutoff)
Fc = (Fp + Fstop) / (2 * Fs); % Center of transition band
b_float = fir1(N, Fc * 2, Hamming(N+1));

%% 3. Quantize Coefficients for Hardware (Q1.15 Fixed-Point)
% Scale floating point coefficients to signed 16-bit integer representation
b_int = round(b_float * (2^(Wb-1) - 1));

disp('Quantized Signed Integer Coefficients:');
disp(b_int);

%% 4. Plot Frequency Response
figure;
freqz(b_float, 1, 1024, Fs);
title('FIR Filter Frequency Response (Floating Point)');

%% 5. Automatically Generate SystemVerilog Module File
sv_filename = 'fir_filter.sv';
fid = fopen(sv_filename, 'w');

fprintf(fid, '// Auto-generated SystemVerilog Direct-Form FIR Filter\n');
fprintf(fid, '// Taps: %d, Coefficient Width: %d-bit\n\n', N+1, Wb);
fprintf(fid, 'module fir_filter #(\n');
fprintf(fid, '    parameter DATA_WIDTH = 16\n');
fprintf(fid, ') (\n');
fprintf(fid, '    input  logic                   clk,\n');
fprintf(fid, '    input  logic                   rst_n,\n');
fprintf(fid, '    input  logic signed [DATA_WIDTH-1:0] din,\n');
fprintf(fid, '    output logic signed [DATA_WIDTH*2:0] dout // Accounts for bit growth\n');
fprintf(fid, ');\n\n');

% Write Coefficient Array
fprintf(fid, '    // Quantized Coefficients\n');
fprintf(fid, '    localparam signed [DATA_WIDTH-1:0] COEFF [%d] = ''{\n', N+1);
for i = 1:N+1
    if i == N+1
        fprintf(fid, '        16''sd%d\n', b_int(i));
    else
        fprintf(fid, '        16''sd%d,\n', b_int(i));
    end
end
fprintf(fid, '    };\n\n');

% Delay Line Shift Register
fprintf(fid, '    // Shift Register Pipeline\n');
fprintf(fid, '    logic signed [DATA_WIDTH-1:0] shift_reg [0:%d];\n\n', N);
fprintf(fid, '    always_ff @(posedge clk or negedge rst_n) begin\n');
fprintf(fid, '        if (!rst_n) begin\n');
fprintf(fid, '            for (int i = 0; i <= %d; i++) begin\n', N);
fprintf(fid, '                shift_reg[i] <= ''0;\n');
fprintf(fid, '            end\n');
fprintf(fid, '        end else begin\n');
fprintf(fid, '            shift_reg[0] <= din;\n');
fprintf(fid, '            for (int i = 1; i <= %d; i++) begin\n', N);
fprintf(fid, '                shift_reg[i] <= shift_reg[i-1];\n');
fprintf(fid, '            end\n');
fprintf(fid, '        end\n');
fprintf(fid, '    end\n\n');

% Multiply-Accumulate Structure
fprintf(fid, '    // Multiply-Accumulate (MAC) Tree\n');
fprintf(fid, '    logic signed [(DATA_WIDTH*2)-1:0] mult_out [0:%d];\n', N);
fprintf(fid, '    logic signed [(DATA_WIDTH*2):0]   acc;\n\n');
fprintf(fid, '    always_comb begin\n');
fprintf(fid, '        acc = ''0;\n');
fprintf(fid, '        for (int i = 0; i <= %d; i++) begin\n', N);
fprintf(fid, '            mult_out[i] = shift_reg[i] * COEFF[i];\n');
fprintf(fid, '            acc = acc + mult_out[i];\n');
fprintf(fid, '        end\n');
fprintf(fid, '    end\n\n');

fprintf(fid, '    always_ff @(posedge clk or negedge rst_n) begin\n');
fprintf(fid, '        if (!rst_n)\n');
fprintf(fid, '            dout <= ''0;\n');
fprintf(fid, '        else\n');
fprintf(fid, '            dout <= acc;\n');
fprintf(fid, '    end\n\n');
fprintf(fid, 'endmodule\n');

fclose(fid);
fprintf('SystemVerilog code successfully exported to %s\n', sv_filename);