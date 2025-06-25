module pixelart_top(
    input 	logic			clock,
    input	logic			reset_n,
    input 	logic	[3:0]	KEY,
    input 	logic	[9:0]	SW,
    output 	logic 	[3:0] 	LED,
    output	logic			blank_n,
    output	logic			hsync_n,
    output	logic			vsync_n,
    output	logic	[7:0]	red,
    output	logic	[7:0]	green,
    output	logic	[7:0]	blue,
    output	logic			vga_clock
    );
    logic			lck;		// for pll
    logic	[9:0]	hcount;
    logic	[9:0]	vcount;

    logic			key3_enable;
    logic			key2_enable;
    logic			key1_enable;
    logic			key0_enable;


    vga_controller		cont(.vga_clock(vga_clock), .reset_n(reset_n), .blank_n(blank_n), .hsync_n(hsync_n), .vsync_n(vsync_n), .hcount(hcount), .vcount(vcount));
    pattern_generator	patgen(.vga_clock(vga_clock), .reset_n(reset_n), .hcount(hcount), .vcount(vcount), .key({key3_enable, key2_enable, key1_enable, key0_enable}), .sw({SW[9],SW[8], SW[7], SW[6], SW[5], SW[4], SW[3], SW[2], SW[1], SW[0]}), .led(LED), .red(red), .green(green), .blue(blue));
    pll 			pllclk(.refclk(clock), .rst(!reset_n), .outclk_0(vga_clock), .locked(lck));

    keypress	key3(.clock(vga_clock), .reset_n(reset_n), .key_in(KEY[3]), .enable_out(key3_enable));
    keypress	key2(.clock(vga_clock), .reset_n(reset_n), .key_in(KEY[2]), .enable_out(key2_enable));
    keypress	key1(.clock(vga_clock), .reset_n(reset_n), .key_in(KEY[1]), .enable_out(key1_enable));
    keypress	key0(.clock(vga_clock), .reset_n(reset_n), .key_in(KEY[0]), .enable_out(key0_enable));

endmodule

////////////////////////////////////////////////////

module vga_controller(
    input   logic       vga_clock,      // clock that is required to get desried pixel refresh rate
    input   logic       reset_n,
    output  logic       blank_n,        // asserted when video is in inactive region
    output  logic       hsync_n,        // must be 0 when a horizontal scan is finished
    output  logic       vsync_n,        // must be 0 when a vertical scan is finished
    output  logic [9:0] hcount,         // where the scan is, horizontally
    output  logic [9:0] vcount          // where the scan is, vertically
    );

    always_ff@(posedge vga_clock or negedge reset_n) begin
        if (!reset_n) begin
            hcount <= 10'd0;
            vcount <= 10'd0;
        end
        else begin
        if (hcount == 10'd799) begin
            hcount <= 10'd0;
        if (vcount == 10'd524)
            vcount <= 10'd0;
        else
            vcount <= vcount + 10'd1;
        end 
        else
            hcount <= hcount + 10'd1;
        end
    end

    always_comb begin
        if (hcount > 10'd655 && hcount <= 10'd751)
            hsync_n = 1'b0;
        else
            hsync_n = 1'b1;
        if (vcount > 10'd489 && vcount <= 10'd491)
            vsync_n = 1'b0;
        else
            vsync_n = 1'b1;
        if (hcount <= 10'd639 && vcount <= 10'd479)
            blank_n = '1;
        else
            blank_n = '0;
    end


endmodule

/////////////////////////////////////////////////////////////////

module pattern_generator(
    input  logic        vga_clock,
    input  logic        reset_n,
    input  logic [9:0]  hcount,
    input  logic [9:0]  vcount,
    input  logic [3:0]  key,
    input  logic [9:0]  sw,
    output logic [3:0]  led,
    output logic [7:0]  red,
    output logic [7:0]  green,
    output logic [7:0]  blue
    );
    // rom stuff
    logic [23:0] cursor_pixel_data;
    logic [23:0] brush_pixel_data;
    logic [23:0] eraser_pixel_data;
    logic [23:0] clear_pixel_data;
    logic [23:0] undo_pixel_data;
    logic [23:0] toolbar_pixel_data;
    logic [23:0] palette_pixel_data;
    logic [23:0] fill_pixel_data;

    // current cursor and tool positions
    logic [9:0] x_pos;                // cursor x position
    logic [9:0] y_pos;                // cursor y position
    logic [1:0] tool;                 // current tool
    logic [9:0] tool_x_pos;           // tool x position
    logic [9:0] tool_y_pos;           // tool y position

    // color management
    logic [23:0] recent_colors[7:0];  // recent color array (unfinished)
    logic update_color_history;       // flag
    logic [23:0] selected_color;      // currently selected color

    // canvas parameters
    localparam CANVAS_MIN_W = 10'd0;
    localparam CANVAS_MIN_H = 10'd80;
    localparam CANVAS_WIDTH = 10'd640;
    localparam CANVAS_HEIGHT = 10'd480;
    localparam CANVAS_GRID_W = 10'd80;  // 80 cells wide (640/8)
    localparam CANVAS_GRID_H = 10'd50;  // 50 cells high (400/8)
    localparam BACKGROUND_COLOR = 24'hFFFFFF;

    // canvas memory
    logic canvas_write_enable;        // write enable
    logic [11:0] canvas_read_addr;    // read address
    logic [11:0] canvas_write_addr;   // write addres
    logic [7:0] red_data;             // red data
    logic [7:0] green_data;           // green data
    logic [7:0] blue_data;            // blue data
    logic [7:0] red_pixel_out;        // red data
    logic [7:0] green_pixel_out;      // green data
    logic [7:0] blue_pixel_out;       // blue data

    // canvas initialization
    logic init_done;                  // flag for canvas initialization
    logic [11:0] init_addr;           // address counter for initialization

    // display calculation
    logic [9:0] sprite_row;           // Row in sprite ROM
    logic [9:0] toolbar_row;          // Row in toolbar ROM
    logic [9:0] sprite_col;           // Column in sprite ROM
    logic [9:0] toolbar_col;          // Column in toolbar ROM
    logic [17:0] sprite_addr;         // Full address for sprite ROM
    logic [17:0] toolbar_addr;        // Full address for toolbar ROM

    // pixel data for display
    logic [23:0] requested_pixel_data;  // Final pixel color to display
    logic [23:0] canvas_pixel_data;     // Canvas pixel from memory

    // color selection ui
    logic [3:0] color_index;          // Index of color in palette
    logic [9:0] block_x;              // X position within color block
    logic [3:0] selected_index;       // Index of selected color
    logic [2:0] palette_index;

    // used for selecting the right border
    assign palette_index = (hcount - recent_colors_start_x) / color_block_width;

    // canvas grid coords
    logic [9:0] grid_x, grid_y;       // Grid coordinates
    logic in_canvas_area;             // Flag if cursor is in canvas

    // the palette
    logic [23:0] color_palette;

    // color selection
    always_comb begin
        case (sw[5:3])
            3'b000: color_palette = 24'hFFFFFF;  // White
            3'b001: color_palette = 24'hFF0000;  // Red
            3'b010: color_palette = 24'hFF8800;  // Orange
            3'b011: color_palette = 24'hFFFF00;  // Yellow
            3'b100: color_palette = 24'h00FF00;  // Green
            3'b101: color_palette = 24'h0000FF;  // Blue
            3'b110: color_palette = 24'hFF00FF;  // Purple
            3'b111: color_palette = 24'h000000;  // Black
            default: color_palette = 24'hFFFFFF; // Default white
        endcase
    end

    // ROM modules
    cursor_rom      cursor(.addr(sprite_addr), .rom(cursor_pixel_data));
    brush_rom       brush(.addr(sprite_addr), .rom(brush_pixel_data));
    eraser_rom      eraser(.addr(sprite_addr), .rom(eraser_pixel_data));
    clear_rom       clear(.addr(sprite_addr), .rom(clear_pixel_data));
    toolbar_rom     toolbar(.addr(toolbar_addr), .rom(toolbar_pixel_data));
    undo_rom        undo(.addr(sprite_addr), .rom(undo_pixel_data));
    palette_rom     palette(.addr(sprite_addr), .rom(palette_pixel_data));
    fill_rom		fill(.addr(sprite_addr), .rom(fill_pixel_data));

    // canvas RAM modules
    canvas_red_ram canvas_red(.clock(vga_clock),.data(red_data),.rdaddress(canvas_read_addr),.wraddress(canvas_write_addr),.wren(canvas_write_enable),.q(red_pixel_out));
    canvas_green_ram canvas_green(.clock(vga_clock),.data(green_data),.rdaddress(canvas_read_addr),.wraddress(canvas_write_addr),.wren(canvas_write_enable),.q(green_pixel_out));
    canvas_blue_ram canvas_blue(.clock(vga_clock),.data(blue_data),.rdaddress(canvas_read_addr),.wraddress(canvas_write_addr),.wren(canvas_write_enable),.q(blue_pixel_out));

    // tool position and selection
    pointer_object toolobj(.reset_n(reset_n),.vga_clock(vga_clock),.move_left(key[3]),.move_right(key[0]),.move_up(key[2]),.move_down(key[1]),.sw(sw[0]),.cursor_x(x_pos),.cursor_y(y_pos));
    pointer_pos toolpos(.x_location(x_pos),.y_location(y_pos),.pointer(tool),.origin_pointer_x(tool_x_pos),.origin_pointer_y(tool_y_pos));

    // color history management
    recent_colors color_hist(.vga_clock(vga_clock),.reset_n(reset_n),.update_color(update_color_history),.new_color(selected_color),.recent_colors(recent_colors));

    // sprite dimensions
    localparam sprite_width  = 10'd24;
    localparam sprite_height = 10'd24;

    // toolbar/canvas dimensions
    localparam toolbar_width = 10'd640;
    localparam toolbar_height = 10'd80;
    localparam canvas_width = 10'd640;
    localparam canvas_height = 10'd400;

    // sprite range y
    localparam origin_icon_y = 10'd28;
    localparam max_icon_y    = 10'd52;

    // spring range x
    localparam origin_palette_x = 10'd44;
    localparam origin_cursor_x = 10'd452;
    localparam origin_brush_x = 10'd476;
    localparam origin_fill_x = 10'd500;
    localparam origin_eraser_x = 10'd524;
    localparam origin_clear_x  = 10'd548;
    localparam origin_undo_x   = 10'd572;

    // palette locations
    localparam color_block_width = 10'd24;  // Each color block is 24 pixels wide
    localparam color_border = 10'd2;        // 2 pixel border around each color
    localparam recent_colors_start_x = origin_palette_x + sprite_width + 10'd10; // 10 pixels after palette

    // tool selection
    always_comb begin
        case (sw[2:1])
            2'b00:          tool = 2'b00;  // Cursor
            2'b01:          tool = 2'b01;  // Brush
            2'b10:          tool = 2'b10;  // Eraser
            2'b11:			tool = 2'b11;  // Fill
            default:        tool = 2'b00;  // Default to cursor
        endcase
    end

    // calculation of grid position for canvas
    assign grid_x = (x_pos - CANVAS_MIN_W) >> 3;  // Divide by 8
    assign grid_y = (y_pos - CANVAS_MIN_H) >> 3;  // Divide by 8

    // temporary changed
    assign in_canvas_area = (y_pos >= CANVAS_MIN_H) && (x_pos < CANVAS_WIDTH) && (grid_x < CANVAS_GRID_W) && (grid_y < CANVAS_GRID_H);
    // assign in_canvas_area = (y_pos >= CANVAS_MIN_H) && (y_pos < CANVAS_HEIGHT) && (x_pos >= CANVAS_MIN_W) && (x_pos < CANVAS_WIDTH);

    // 8x8 pixel map assignment
    assign canvas_read_addr = ((vcount - CANVAS_MIN_H) >> 3) * CANVAS_GRID_W + ((hcount - CANVAS_MIN_W) >> 3);

    // sprite and toolbar address
    assign sprite_row = (vcount >= origin_icon_y && vcount < max_icon_y) ? (vcount - origin_icon_y) : (vcount - tool_y_pos);
    assign toolbar_row = vcount;
    assign toolbar_col = hcount;

    assign sprite_addr = sprite_row * sprite_width + sprite_col;
    assign toolbar_addr = toolbar_row * toolbar_width + toolbar_col;

    assign canvas_pixel_data = {red_pixel_out, green_pixel_out, blue_pixel_out};

    // current tool
    logic [23:0] current_tool_pixel;
    always_comb begin
        case (tool)
            2'b00: current_tool_pixel = cursor_pixel_data;
            2'b01: current_tool_pixel = brush_pixel_data;
            2'b10: current_tool_pixel = eraser_pixel_data;
            2'b11: current_tool_pixel = fill_pixel_data;
            default: current_tool_pixel = cursor_pixel_data;
        endcase
    end

    // canvas initialization
    enum logic [1:0] {
        INIT_CLEAR,
        NORMAL_OPERATION,
        FILL_OPERATION,
        CLEAR_CANVAS
    } canvas_state;

    localparam BRIGHTNESS_STEP = 8'd8;
    logic brightness_up;
    logic brightness_up_prev;
    logic brightness_down_prev;
    logic brightness_down;
    logic [23:0] adjusted_color;
    logic [2:0] changed_palette;
    logic [2:0] changed_palette_prev;

    // FSM for canvas
    always_ff @(posedge vga_clock or negedge reset_n) begin
        if (!reset_n) begin
            canvas_state <= INIT_CLEAR;         // first state on reset
            init_addr <= 12'd0;
            canvas_write_enable <= 1'b1;
            canvas_write_addr <= 12'd0;
            red_data <= BACKGROUND_COLOR[23:16];        // set rgb to white
            green_data <= BACKGROUND_COLOR[15:8];
            blue_data <= BACKGROUND_COLOR[7:0];
            update_color_history <= 1'b0;
            brightness_up <= 1'b0;
            brightness_down <= 1'b0;
            changed_palette <= 3'b000;
            changed_palette_prev <= 3'b000;
            adjusted_color <= 24'hffffff;       // start palette color on white
        end
        else begin
            brightness_up_prev <= brightness_up;
            brightness_up <= sw[7];             // assign increased brightness to sw7
            brightness_down_prev <= brightness_down;
            brightness_down <= sw[8];           // assign decreasesd beirhtnes to sw8
            changed_palette_prev <= changed_palette;
            changed_palette <= sw[5:3];     // change in base color
        if (brightness_up && !brightness_up_prev) begin     // compare last states of sw7
            case(sw[5:3])
                3'b000 : begin		// white
                    adjusted_color[23:16] <= (adjusted_color[23:16] > (8'hFF - BRIGHTNESS_STEP)) ? 8'hFF : (adjusted_color[23:16] + BRIGHTNESS_STEP);
                    adjusted_color[15:8] <= (adjusted_color[15:8] > (8'hFF - BRIGHTNESS_STEP)) ? 8'hFF : (adjusted_color[15:8] + BRIGHTNESS_STEP);
                    adjusted_color[7:0] <= (adjusted_color[7:0] > (8'hFF - BRIGHTNESS_STEP)) ? 8'hFF : (adjusted_color[7:0] + BRIGHTNESS_STEP);
                end
                3'b001: begin		// red
                if (adjusted_color[23:16] >= 8'hff) begin
                    adjusted_color[15:8] <= (adjusted_color[15:8] > (8'hFF - BRIGHTNESS_STEP)) ? 8'hFF : (adjusted_color[15:8] + BRIGHTNESS_STEP);
                    adjusted_color[7:0] <= (adjusted_color[7:0] > (8'hFF - BRIGHTNESS_STEP)) ? 8'hFF : (adjusted_color[7:0] + BRIGHTNESS_STEP);
                end
                else
                    adjusted_color[23:16] <= (adjusted_color[23:16] > (8'hFF - BRIGHTNESS_STEP)) ? 8'hFF : (adjusted_color[23:16] + BRIGHTNESS_STEP);
                end
                3'b010: begin		// orange
                if (adjusted_color[23:16] >= 8'hFF && adjusted_color[15:8] >= 8'h88) begin
                    adjusted_color[15:8] <= (adjusted_color[15:8] > (8'hFF - BRIGHTNESS_STEP)) ? 8'hFF : (adjusted_color[15:8] + BRIGHTNESS_STEP);
                    adjusted_color[7:0] <= (adjusted_color[7:0] > (8'h77 - BRIGHTNESS_STEP)) ? 8'h77 : (adjusted_color[7:0] + BRIGHTNESS_STEP);
                end
                else begin
                    adjusted_color[23:16] <= (adjusted_color[23:16] > (8'hFF - BRIGHTNESS_STEP)) ? 8'hFF : (adjusted_color[23:16] + BRIGHTNESS_STEP);
                    adjusted_color[15:8] <= (adjusted_color[15:8] > (8'h88 - BRIGHTNESS_STEP)) ? 8'h88 : (adjusted_color[15:8] + BRIGHTNESS_STEP);
                end
                end
                3'b011: begin		// yellow
                    if (adjusted_color[23:16] >= 8'hff && adjusted_color[15:8] >= 8'hff)
                    adjusted_color[7:0] <= (adjusted_color[7:0] > (8'hFF - BRIGHTNESS_STEP)) ? 8'hFF : (adjusted_color[7:0] + BRIGHTNESS_STEP);
                else begin
                    adjusted_color[23:16] <= (adjusted_color[23:16] > (8'hFF - BRIGHTNESS_STEP)) ? 8'hFF : (adjusted_color[23:16] + BRIGHTNESS_STEP);
                    adjusted_color[15:8] <= (adjusted_color[15:8] > (8'hFF - BRIGHTNESS_STEP)) ? 8'hFF : (adjusted_color[15:8] + BRIGHTNESS_STEP);
                end
                end
                3'b100: begin		// green
                    if (adjusted_color[15:8] >= 8'hff) begin
                        adjusted_color[23:16] <= (adjusted_color[23:16] > (8'hFF - BRIGHTNESS_STEP)) ? 8'hFF : (adjusted_color[23:16] + BRIGHTNESS_STEP);
                        adjusted_color[7:0] <= (adjusted_color[7:0] > (8'hFF - BRIGHTNESS_STEP)) ? 8'hFF : (adjusted_color[7:0] + BRIGHTNESS_STEP);
                    end
                    else
                        adjusted_color[15:8] <= (adjusted_color[15:8] > (8'hFF - BRIGHTNESS_STEP)) ? 8'hFF : (adjusted_color[15:8] + BRIGHTNESS_STEP);
                    end
                3'b101: begin		// blue
                    if (adjusted_color[7:0] >= 8'hFF) begin
                        adjusted_color[23:16] <= (adjusted_color[23:16] > (8'hFF - BRIGHTNESS_STEP)) ? 8'hFF : (adjusted_color[23:16] + BRIGHTNESS_STEP);
                        adjusted_color[15:8] <= (adjusted_color[15:8] > (8'hFF - BRIGHTNESS_STEP)) ? 8'hFF : (adjusted_color[15:8] + BRIGHTNESS_STEP);
                    end
                    else
                        adjusted_color[7:0] <= (adjusted_color[7:0] > (8'hFF - BRIGHTNESS_STEP)) ? 8'hFF : (adjusted_color[7:0] + BRIGHTNESS_STEP);
                end
                3'b110: begin		// magenta
                    if (adjusted_color[23:16] >= 8'hFF && adjusted_color[7:0] >= 8'hFF)
                        adjusted_color[15:8] <= (adjusted_color[15:8] > (8'hFF - BRIGHTNESS_STEP)) ? 8'hFF : (adjusted_color[15:8] + BRIGHTNESS_STEP);
                    else begin
                        adjusted_color[23:16] <= (adjusted_color[23:16] > (8'hFF - BRIGHTNESS_STEP)) ? 8'hFF : (adjusted_color[23:16] + BRIGHTNESS_STEP);
                        adjusted_color[7:0] <= (adjusted_color[7:0] > (8'hFF - BRIGHTNESS_STEP)) ? 8'hFF : (adjusted_color[7:0] + BRIGHTNESS_STEP);
                    end
                end
                3'b111: begin		// black
                    adjusted_color[23:16] <= (adjusted_color[23:16] > (8'hFF - BRIGHTNESS_STEP)) ? 8'hFF : (adjusted_color[23:16] + BRIGHTNESS_STEP);
                    adjusted_color[15:8] <= (adjusted_color[15:8] > (8'hFF - BRIGHTNESS_STEP)) ? 8'hFF : (adjusted_color[15:8] + BRIGHTNESS_STEP);
                    adjusted_color[7:0] <= (adjusted_color[7:0] > (8'hFF - BRIGHTNESS_STEP)) ? 8'hFF : (adjusted_color[7:0] + BRIGHTNESS_STEP);
                    end
                default:
                adjusted_color <= 24'hffffff;
                endcase
                end
        else if (brightness_down && !brightness_down_prev) begin        // compare last states of sw8
            case(sw[5:3])
                3'b000 : begin		// white
                    adjusted_color[23:16] <= (adjusted_color[23:16] < BRIGHTNESS_STEP) ? 8'h00 : (adjusted_color[23:16] - BRIGHTNESS_STEP);
                    adjusted_color[15:8] <= (adjusted_color[15:8] <  BRIGHTNESS_STEP) ? 8'h00 : (adjusted_color[15:8] - BRIGHTNESS_STEP);
                    adjusted_color[7:0] <= (adjusted_color[7:0] < BRIGHTNESS_STEP) ? 8'h00 : (adjusted_color[7:0] - BRIGHTNESS_STEP);
                end
                3'b001: begin		// red
                    if (adjusted_color[15:8] > 0 || adjusted_color[7:0] > 0) begin
                        adjusted_color[15:8] <= (adjusted_color[15:8] < BRIGHTNESS_STEP) ? 8'h00 : (adjusted_color[15:8] - BRIGHTNESS_STEP);
                        adjusted_color[7:0] <= (adjusted_color[7:0] < BRIGHTNESS_STEP) ? 8'h00 : (adjusted_color[7:0] - BRIGHTNESS_STEP);
                    end
                else
                    adjusted_color[23:16] <= (adjusted_color[23:16] < BRIGHTNESS_STEP)? 8'h00 : (adjusted_color[23:16] - BRIGHTNESS_STEP);
                end
                3'b010: begin		// orange
                    if (adjusted_color[7:0] > 0)
                        adjusted_color[7:0] <= (adjusted_color[7:0] < BRIGHTNESS_STEP) ? 8'h00 : (adjusted_color[7:0] - BRIGHTNESS_STEP);
                    else if (adjusted_color[15:8] > 8'h88)
                        adjusted_color[15:8] <= (adjusted_color[15:8] - 8'h88 < BRIGHTNESS_STEP) ? 8'h88 : (adjusted_color[15:8] - BRIGHTNESS_STEP); 
                    else if (adjusted_color[23:16] > 8'h88) begin
                        adjusted_color[23:16] <= (adjusted_color[23:16] - 8'h88 < BRIGHTNESS_STEP) ? 8'h88 : (adjusted_color[23:16] - BRIGHTNESS_STEP);
                    end
                end
                3'b011: begin		// yellow
                    if (adjusted_color[7:0] > 0)
                        adjusted_color[7:0] <= (adjusted_color[7:0] < BRIGHTNESS_STEP) ? 8'h00 : (adjusted_color[7:0] - BRIGHTNESS_STEP);
                    else begin
                        adjusted_color[23:16] <= (adjusted_color[23:16] < BRIGHTNESS_STEP) ? 8'h00 : (adjusted_color[23:16] - BRIGHTNESS_STEP);
                        adjusted_color[15:8] <= (adjusted_color[15:8] < BRIGHTNESS_STEP) ? 8'h00 : (adjusted_color[15:8] - BRIGHTNESS_STEP);
                    end
                end
                3'b100: begin		// green
                    if (adjusted_color[23:16] > 0 || adjusted_color[7:0] > 0) begin
                        adjusted_color[23:16] <= (adjusted_color[23:16] < BRIGHTNESS_STEP) ? 8'h00 : (adjusted_color[23:16] - BRIGHTNESS_STEP);
                        adjusted_color[7:0] <= (adjusted_color[7:0] < BRIGHTNESS_STEP) ? 8'h00 : (adjusted_color[7:0] - BRIGHTNESS_STEP);
                    end
                    else
                        adjusted_color[15:8] <= (adjusted_color[15:8] < BRIGHTNESS_STEP) ? 8'h00 : (adjusted_color[15:8] - BRIGHTNESS_STEP);
                end
                3'b101: begin		// blue
                    if (adjusted_color[23:16] > 0 || adjusted_color[15:8] > 0) begin
                        adjusted_color[23:16] <= (adjusted_color[23:16] < BRIGHTNESS_STEP) ? 8'h00 : (adjusted_color[23:16] - BRIGHTNESS_STEP);
                        adjusted_color[15:8] <= (adjusted_color[15:8] < BRIGHTNESS_STEP) ? 8'h00 : (adjusted_color[15:8] - BRIGHTNESS_STEP);
                    end
                    else
                        adjusted_color[7:0] <= (adjusted_color[7:0] < BRIGHTNESS_STEP)? 8'h00 : (adjusted_color[7:0] - BRIGHTNESS_STEP);
                end
                3'b110: begin		// magenta
                    if (adjusted_color[15:8] > 0)
                        adjusted_color[15:8] <= (adjusted_color[15:8] < BRIGHTNESS_STEP) ? 8'h00 : (adjusted_color[15:8] - BRIGHTNESS_STEP);
                    else begin
                        adjusted_color[23:16] <= (adjusted_color[23:16] < BRIGHTNESS_STEP) ? 8'h00 : (adjusted_color[23:16] - BRIGHTNESS_STEP);
                        adjusted_color[7:0] <= (adjusted_color[7:0] < BRIGHTNESS_STEP) ? 8'h00 : (adjusted_color[7:0] - BRIGHTNESS_STEP);
                    end
                end
                3'b111: begin		// black
                    adjusted_color[23:16] <= (adjusted_color[23:16] < BRIGHTNESS_STEP) ? 8'h00 : (adjusted_color[23:16] - BRIGHTNESS_STEP);
                    adjusted_color[15:8] <= (adjusted_color[15:8] < BRIGHTNESS_STEP) ? 8'h00 : (adjusted_color[15:8] - BRIGHTNESS_STEP);
                    adjusted_color[7:0] <= (adjusted_color[7:0] < BRIGHTNESS_STEP) ? 8'h00 : (adjusted_color[7:0] - BRIGHTNESS_STEP);
                end
                default:
                    adjusted_color <= 24'hffffff;
            endcase
        end
        else if (changed_palette != changed_palette_prev) begin
            adjusted_color <= color_palette;
        end

        update_color_history <= 1'b0;

        case (canvas_state)
            INIT_CLEAR: begin
                // Initialize canvas to white
                canvas_write_enable <= 1'b1;
                canvas_write_addr <= init_addr;
                red_data <= BACKGROUND_COLOR[23:16];
                green_data <= BACKGROUND_COLOR[15:8];
                blue_data <= BACKGROUND_COLOR[7:0];

                if (init_addr >= (CANVAS_GRID_W * CANVAS_GRID_H - 1)) begin
                    canvas_state <= NORMAL_OPERATION;
                    init_addr <= 12'd0;
                    canvas_write_enable <= 1'b0;
                end
                else begin
                    init_addr <= init_addr + 12'd1;
                end
            end

            NORMAL_OPERATION: begin // brush, erase, or fill
                if (sw[0] && in_canvas_area && (tool == 2'b01 || tool == 2'b10)) begin
                    canvas_write_enable <= 1'b1;
                    canvas_write_addr <= grid_y * CANVAS_GRID_W + grid_x;

                if (tool == 2'b01) begin  // current tool is brush
                    red_data <= adjusted_color[23:16];
                    green_data <= adjusted_color[15:8];
                    blue_data <= adjusted_color[7:0];
                end
                else begin // current tool is eraser (acts like a white brush)
                    red_data <= BACKGROUND_COLOR[23:16];
                    green_data <= BACKGROUND_COLOR[15:8];
                    blue_data <= BACKGROUND_COLOR[7:0];
                end
                end
                else begin
                    canvas_write_enable <= 1'b0;
                end

                // clear canvas command
                if (sw[6]) begin
                    canvas_state <= CLEAR_CANVAS;
                    init_addr <= 12'd0;
                end
                // fill command
                if (sw[0] && in_canvas_area && tool == 2'b11) begin
                    canvas_state <= FILL_OPERATION;
                    init_addr <= 12'd0;
                end
            end

            FILL_OPERATION: begin
                // fill canvas (similar to clear)
                if (sw[0] && in_canvas_area && (tool == 2'b11))
                    canvas_write_enable <= 1'b1;
                    canvas_write_addr <= init_addr;
                    red_data <= adjusted_color[23:16];
                    green_data <= adjusted_color[15:8];
                    blue_data <= adjusted_color[7:0];

                if (init_addr >= (CANVAS_GRID_W * CANVAS_GRID_H - 1)) begin
                    canvas_state <= NORMAL_OPERATION;
                    init_addr <= 12'd0;
                    canvas_write_enable <= 1'b0;
                end
                else begin
                    init_addr <= init_addr + 12'd1;
                end
            end

            CLEAR_CANVAS: begin
                canvas_write_enable <= 1'b1;
                canvas_write_addr <= init_addr;
                red_data <= BACKGROUND_COLOR[23:16];            // replace screen w background color
                green_data <= BACKGROUND_COLOR[15:8];
                blue_data <= BACKGROUND_COLOR[7:0];

                if (init_addr >= (CANVAS_GRID_W * CANVAS_GRID_H - 1)) begin
                    canvas_state <= NORMAL_OPERATION;
                    init_addr <= 12'd0;
                    canvas_write_enable <= 1'b0;
                end
                else begin
                    init_addr <= init_addr + 12'd1;
                end
            end
        endcase
        end
    end

    always_comb begin               // finally set r g b of screen
        red = requested_pixel_data[23:16];
        green = requested_pixel_data[15:8];
        blue = requested_pixel_data[7:0];
    end

    always_comb begin
        if (hcount >= recent_colors_start_x && hcount < recent_colors_start_x + (8 * color_block_width)) begin      // for palette indexing
            color_index = (hcount - recent_colors_start_x) / color_block_width;
            block_x = (hcount - recent_colors_start_x) % color_block_width;
        end 
        else begin
            color_index = 4'd0;
            block_x = 10'd0;
        end

        if (tool_x_pos >= recent_colors_start_x && tool_x_pos < recent_colors_start_x + (8 * color_block_width)) begin      // furthermore for palette indexing
            selected_index = (tool_x_pos - recent_colors_start_x) / color_block_width;
        end
        else begin
            selected_index = 4'd0;
        end
    end

    always_comb begin
        if (hcount < 640 && vcount < 480) begin
            if (vcount >= origin_icon_y && vcount <= max_icon_y) begin
                if (hcount >= origin_palette_x && hcount < origin_palette_x + sprite_width)
                    sprite_col = hcount - origin_palette_x;
                else if (hcount >= origin_cursor_x && hcount < origin_cursor_x + sprite_width)
                    sprite_col = hcount - origin_cursor_x;
                else if (hcount >= origin_brush_x && hcount < origin_brush_x + sprite_width)
                    sprite_col = hcount - origin_brush_x;
                else if (hcount >= origin_fill_x && hcount < origin_fill_x + sprite_width)
                    sprite_col = hcount - origin_fill_x;
                else if (hcount >= origin_eraser_x && hcount < origin_eraser_x + sprite_width)
                    sprite_col = hcount - origin_eraser_x;
                else if (hcount >= origin_clear_x && hcount < origin_clear_x + sprite_width)
                    sprite_col = hcount - origin_clear_x;
                else if (hcount >= origin_undo_x && hcount < origin_undo_x + sprite_width)
                    sprite_col = hcount - origin_undo_x;
                else
                    sprite_col = hcount;
            end
            else if (hcount >= tool_x_pos && hcount < tool_x_pos + sprite_width && 
                vcount >= tool_y_pos && vcount < tool_y_pos + sprite_height) begin
                sprite_col = hcount - tool_x_pos;
            end
            else begin
                sprite_col = hcount;
            end
        end
        else begin
            sprite_col = 10'd0;
        end
    end

    always_comb begin
    if (hcount < 10'd640 && vcount < 10'd480) begin             // in display area
        if (hcount >= tool_x_pos && hcount < tool_x_pos + sprite_width && vcount >= tool_y_pos && vcount < tool_y_pos + sprite_height) begin        // in area where cursor is
            // display tool cursor
            if (current_tool_pixel == 24'hffffff) begin         // white background means transparent
                if (vcount >= 10'd80)
                    requested_pixel_data = canvas_pixel_data;
                else if (vcount < 10'd80)
                    requested_pixel_data = toolbar_pixel_data;
                else
                    requested_pixel_data = 24'hffffff;
            end
            else
                requested_pixel_data = current_tool_pixel;
        end
        else if (vcount >= origin_icon_y && vcount < max_icon_y) begin
            if (hcount >= recent_colors_start_x && hcount < recent_colors_start_x + (8 * color_block_width)) begin
                if (block_x < color_border || block_x >= color_block_width - color_border || vcount - origin_icon_y < color_border || vcount - origin_icon_y >= sprite_height - color_border) begin
                    if (palette_index == sw[5:3])
                        requested_pixel_data = 24'h30d5c8;	// selected color border is turqouise
                    else
                        requested_pixel_data = 24'h333333;  // unselected color border is grey
                end 
                else begin
                    requested_pixel_data = recent_colors[color_index];  // palette colors
                end
            end
            else if (hcount >= origin_palette_x && hcount < origin_palette_x + sprite_width) begin
                if (palette_pixel_data == 24'hffffff)
                    requested_pixel_data = toolbar_pixel_data;
                else
                    requested_pixel_data = palette_pixel_data;
            end
            else if (hcount >= origin_cursor_x && hcount < origin_brush_x) begin
                if (cursor_pixel_data == 24'hffffff)
                    requested_pixel_data = toolbar_pixel_data;
                else
                    requested_pixel_data = cursor_pixel_data;
            end
            else if (hcount >= origin_brush_x && hcount < origin_fill_x) begin
                if (brush_pixel_data == 24'hffffff)
                    requested_pixel_data = toolbar_pixel_data;
                else
                    requested_pixel_data = brush_pixel_data;
            end
            else if (hcount >= origin_fill_x && hcount < origin_eraser_x) begin
                if (fill_pixel_data == 24'hffffff)
                    requested_pixel_data = toolbar_pixel_data;
                else
                    requested_pixel_data = fill_pixel_data;
            end
            else if (hcount >= origin_eraser_x && hcount < origin_clear_x) begin
                if (eraser_pixel_data == 24'hffffff)
                    requested_pixel_data = toolbar_pixel_data;
                else
                    requested_pixel_data = eraser_pixel_data;
            end
            else if (hcount >= origin_clear_x && hcount < origin_undo_x) begin
                if (clear_pixel_data == 24'hffffff)
                    requested_pixel_data = toolbar_pixel_data;
                else
                    requested_pixel_data = clear_pixel_data;
            end
            else if (hcount >= origin_undo_x && hcount < origin_undo_x + sprite_width) begin
                if (undo_pixel_data == 24'hffffff)
                    requested_pixel_data = toolbar_pixel_data;
                else
                    requested_pixel_data = undo_pixel_data;
            end
            else
                requested_pixel_data = toolbar_pixel_data;
        end
        else if (vcount < 10'd80) begin
            // toolbar area
            requested_pixel_data = toolbar_pixel_data;
        end
        else if (vcount >= 10'd80 && hcount < CANVAS_WIDTH) begin
            // canvas area
            requested_pixel_data = canvas_pixel_data;
        end
        else begin
            requested_pixel_data = 24'd0;
        end
    end
    else begin
        requested_pixel_data = 24'd0;
    end
    end

endmodule

////////////////////////////////////////////////////////

module pointer_object(
    input  logic       reset_n,
    input  logic       vga_clock,
    input  logic	   sw,
    input  logic       move_left,
    input  logic       move_right,
    input  logic       move_up,
    input  logic       move_down,
    output logic [9:0] cursor_x,
    output logic [9:0] cursor_y
    );
    localparam left_bound  = 10'd0;
    localparam right_bound = 10'd639;
    localparam upper_bound = 10'd80;
    localparam lower_bound = 10'd479;

    logic LEFT_POSSIBLE;
    logic RIGHT_POSSIBLE;
    logic UP_POSSIBLE;
    logic DOWN_POSSIBLE;

    assign LEFT_POSSIBLE  = (cursor_x > left_bound);
    assign RIGHT_POSSIBLE = (cursor_x < right_bound - 8);
    assign UP_POSSIBLE    = (cursor_y > upper_bound);
    assign DOWN_POSSIBLE  = (cursor_y < lower_bound - 8);

    logic move_left_prev, move_right_prev, move_up_prev, move_down_prev;

    always_ff @(posedge vga_clock or negedge reset_n) begin
        if (!reset_n) begin
            cursor_x <= 10'd0;
            cursor_y <= 10'd80;
            move_left_prev  <= 1'b0;
            move_right_prev <= 1'b0;
            move_up_prev    <= 1'b0;
            move_down_prev  <= 1'b0;
        end
        else begin
            move_left_prev  <= move_left;
            move_right_prev <= move_right;
            move_up_prev    <= move_up;
            move_down_prev  <= move_down;

            if (cursor_y >= 80) begin // below toolbar, move on each riding edge
                if (move_left && !move_left_prev && LEFT_POSSIBLE) begin                // change on key press of key3
                    cursor_x <= cursor_x - 10'd8;
                    cursor_y <= cursor_y + 10'd0;
                end
                else if (move_right && !move_right_prev && RIGHT_POSSIBLE) begin           // change on key press of key0
                    cursor_x <= cursor_x + 10'd8;
                    cursor_y <= cursor_y + 10'd0;
                end
                else if (move_up && !move_up_prev && UP_POSSIBLE) begin             // change on key press of key2
                    cursor_y <= cursor_y - 10'd8;
                    cursor_x <= cursor_x + 10'd0;
                end
                else if (move_down && !move_down_prev && DOWN_POSSIBLE) begin       // change on key press of key1
                    cursor_y <= cursor_y + 10'd8;
                    cursor_x <= cursor_x + 10'd0;
                end
                else begin
                // No changes when no button pressed
                    cursor_x <= cursor_x + 10'd0;
                    cursor_y <= cursor_y + 10'd0;
                end
            end
        end
    end

endmodule

///////////////////////////////////

module pointer_pos(
    input logic [9:0] x_location,
    input logic [9:0] y_location,
    input logic [1:0] pointer,
    output logic [9:0] origin_pointer_x,
    output logic [9:0] origin_pointer_y
    );
    localparam cursor = 2'b00;
    localparam brush = 2'b01;
    localparam eraser = 2'b10;

    always_comb begin
        if (y_location >= 80) begin
            origin_pointer_x = x_location + 10'd4;
            if (pointer == cursor)							// cursor
                origin_pointer_y = y_location + 10'd4;
            else											// brush or eraser or bucket
                origin_pointer_y = y_location - 10'd20;
        end
        else begin
            origin_pointer_x = x_location + 10'd12;
            if (pointer == cursor)							// cursor
                origin_pointer_y = y_location + 10'd12;
            else											// brush or eraser or bucket
                origin_pointer_y = y_location - 10'd12;
        end
    end

endmodule

module keypress(
    input  logic    clock,
    input  logic    reset_n,
    input  logic    key_in,
    output logic    enable_out
    );
    localparam CLOCK_FREQ = 50000000;  //50 mhz

    localparam INITIAL_DELAY = CLOCK_FREQ;      //supposedly 1 second hold before repeat (but feels like 2)
    localparam REPEAT_DELAY = CLOCK_FREQ / 24;   //  movement speed 

    logic [25:0] delay_counter;
    logic key_was_pressed;
    logic repeat_mode;

    always_ff @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            enable_out <= 1'b0;
            delay_counter <= 26'd0;
            key_was_pressed <= 1'b0;
            repeat_mode <= 1'b0;
        end
        else begin
            enable_out <= 1'b0;

            if (key_in == 1'b0) begin  // active low keypress
                if (!key_was_pressed) begin
                    enable_out <= 1'b1;
                    key_was_pressed <= 1'b1;
                    delay_counter <= 26'd0;
                    repeat_mode <= 1'b0;
                end
                else begin
                    delay_counter <= delay_counter + 26'd1;
                    if (!repeat_mode) begin
                        if (delay_counter >= INITIAL_DELAY) begin
                            repeat_mode <= 1'b1;
                            delay_counter <= 26'd0;
                            enable_out <= 1'b1;
                        end
                    end
                    else begin
                        if (delay_counter >= REPEAT_DELAY) begin
                            enable_out <= 1'b1;
                            delay_counter <= 26'd0;
                        end
                    end
                end
            end
            else begin
                key_was_pressed <= 1'b0;
                repeat_mode <= 1'b0;
                delay_counter <= 26'd0;
            end
        end
    end
endmodule

////////////////////////////////////////////////////////////

module recent_colors(                               // turned out as palette module
    input  logic        vga_clock,
    input  logic        reset_n,
    input  logic        update_color,
    input  logic [23:0] new_color,
    output logic [23:0] recent_colors[7:0]
    );
    // presets
    localparam COLORS_WHITE  = 24'hFFFFFF;
    localparam COLORS_RED    = 24'hFF0000;
    localparam COLORS_ORANGE = 24'hFF8800;
    localparam COLORS_YELLOW = 24'hFFFF00;
    localparam COLORS_GREEN  = 24'h00FF00;
    localparam COLORS_BLUE   = 24'h0000FF;
    localparam COLORS_VIOLET = 24'h880088;
    localparam COLORS_BLACK  = 24'h000000;

    always_ff @(posedge vga_clock or negedge reset_n) begin
        if (!reset_n) begin
            recent_colors[0] <= COLORS_WHITE;
            recent_colors[1] <= COLORS_RED;
            recent_colors[2] <= COLORS_ORANGE;
            recent_colors[3] <= COLORS_YELLOW;
            recent_colors[4] <= COLORS_GREEN;
            recent_colors[5] <= COLORS_BLUE;
            recent_colors[6] <= COLORS_VIOLET;
            recent_colors[7] <= COLORS_BLACK;
        end
        // shift colors down by 1
        else if (update_color) begin
            recent_colors[7] <= recent_colors[6];
            recent_colors[6] <= recent_colors[5];
            recent_colors[5] <= recent_colors[4];
            recent_colors[4] <= recent_colors[3];
            recent_colors[3] <= recent_colors[2];
            recent_colors[2] <= recent_colors[1];
            recent_colors[1] <= recent_colors[0];
            recent_colors[0] <= new_color;
        end
    end
endmodule