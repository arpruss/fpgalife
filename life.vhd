LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.all;
USE ieee.std_logic_unsigned.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;
--library work;
--use work.fonts.all;    
    
entity life is 
    generic
    (
    screen_x0 : natural := 4; -- must be non-zero
    screen_y0 : natural := 38; -- must be at least 2
    screen_width : natural := 612-4;
    screen_height : natural := 440-38; -- 470-38;
    rows : natural := 15;
    cols : natural := 15
    );

    port
    (
    sync_output : out std_logic;
    bw_output : out std_logic;
    main_clock : in std_logic;
    button : in std_logic
    );

    function bits(maxValue : natural) return natural is
    begin
        return 1+natural(ceil(log2(real(maxValue))));
    end bits;    

constant pixelsPerBox : natural := screen_height/rows/2*2; -- must be even
type board is array(0 to cols-1, 0 to rows-1) of unsigned(0 downto 0);    
attribute altera_chip_pin_lc : string;
attribute altera_chip_pin_lc of button : signal is "@144";   
attribute altera_chip_pin_lc of bw_output : signal is "@96";   
attribute altera_chip_pin_lc of sync_output : signal is "@119";   
attribute altera_attribute : string;
attribute altera_attribute of button : signal is "-name WEAK_PULL_UP_RESISTOR ON";
end life;   

architecture behavioral of life is
    constant pwmBits : natural := 2;
    constant screenWidth : natural := 640;
    constant clockFrequency : real := 52.083333e6; -- 104.166667e6;
    signal clock : std_logic; 
    signal req: std_logic;
    signal x : unsigned(9 downto 0);
    signal y : unsigned(8 downto 0);
    signal pixel: unsigned(pwmBits-1 downto 0);
    signal posX : signed(10 downto 0) := to_signed(screenWidth/2,11);
    signal vX : signed(1 downto 0) := to_signed(1,2);
    signal posY : signed(9 downto 0) := to_signed(240,10);
    signal vY : signed(1 downto 0) := to_signed(1,2);
    signal ch : integer range 0 to 127;
    signal display_board : board;
    signal game_board : board;
    signal new_frame : std_logic;
    signal display_row : unsigned(bits(rows+1)-1 downto 0) := to_unsigned(0, bits(rows+1));
    signal display_col : unsigned(bits(cols+1)-1 downto 0) := to_unsigned(0, bits(cols+1));
    signal display_col_counter : unsigned(bits(pixelsPerBox)-1 downto 0) := to_unsigned(0, bits(pixelsPerBox));
    signal display_row_counter : unsigned(bits(pixelsPerBox/2)-1 downto 0) := to_unsigned(0, bits(pixelsPerBox/2));
    signal initialized : std_logic := '0';
    signal frame_count : unsigned(1 downto 0);
    signal clock_count : unsigned(31 downto 0) := to_unsigned(0, 32);

begin
    PLL_INSTANCE: entity work.pll port map(main_clock, clock);
    output: entity work.ntsc 
                generic map(clockFrequency => clockFrequency, pwmBits=>pwmBits, screenWidth=>screenWidth) 
                port map(sync_output=>sync_output, bw_output=>bw_output, clock=>clock, pixel=>pixel, 
                    req=>req, x=>x, y=>y, new_frame=>new_frame);

    process(clock,new_frame)
    variable neighbors : unsigned(3 downto 0);
    begin
        if rising_edge(clock) then            
            clock_count <= clock_count + 1;
            if new_frame = '1' then   
                frame_count <= frame_count + 1;
                if initialized = '0' or button = '0' then
                    initialized <= '1';
                    for i in 0 to cols-1 loop
                        for j in 0 to rows-1 loop
                            if (i+234*j)mod 17 < 5 xor clock_count(i+j)='0' then
                                game_board(i,j) <= to_unsigned(1,1);
                            else
                                game_board(i,j) <= to_unsigned(0,1);
                            end if;
                        end loop;
                    end loop;
                 else
                    display_board <= game_board;
                 end if;
            end if;  
            if initialized = '1' then
                for i in 0 to cols-1 loop
                    for j in 0 to rows-1 loop
                        case resize(game_board((i-1)mod cols,j),4) + 
                                     resize(game_board((i+1)mod cols,j),4) +
                                     resize(game_board((i-1)mod cols,(j-1)mod rows),4) + 
                                     resize(game_board(i,(j-1)mod rows),4) + 
                                     resize(game_board((i+1)mod cols,(j-1)mod rows),4) + 
                                     resize(game_board((i-1)mod cols,(j+1)mod rows),4) + 
                                     resize(game_board(i,(j+1)mod rows),4) + 
                                     resize(game_board((i+1)mod cols,(j+1)mod rows),4) is 
                            when to_unsigned(3,4) =>
                                game_board(i,j) <= to_unsigned(1,1);
                            when to_unsigned(2,4) =>
                                game_board(i,j) <= game_board(i,j);
                            when others =>
                                game_board(i,j) <= to_unsigned(0,1);
                        end case;
                    end loop;
                end loop;
            end if;
        end if;
    end process;
                    
    process(req)

    begin
        if rising_edge(req) then
            if screen_x0-1 = x then
                display_col <= to_unsigned(0, display_col'length);
                display_col_counter <= to_unsigned(0, display_col_counter'length);
                if screen_y0/2-1 = y(y'high downto 1) then
                    display_row <= to_unsigned(0, display_row'length);
                    display_row_counter <= to_unsigned(0, display_row_counter'length);
                else
                    if display_row_counter = pixelsPerBox/2 then
                        display_row <= display_row + 1;
                        display_row_counter <= to_unsigned(0, display_row_counter'length);
                    else
                        display_row_counter <= display_row_counter + 1;
                    end if;
                end if;
            else
                if display_col_counter = pixelsPerBox then
                    display_col <= display_col + 1;
                    display_col_counter <= to_unsigned(0, display_col_counter'length);
                else
                    display_col_counter <= display_col_counter + 1;
                end if;                
            end if;
                    
            if screen_x0 <= x and display_col < cols and
                screen_y0 <= y and display_row < rows then
                pixel <= display_board(to_integer(display_col), to_integer(display_row))(0) & '1';
            else
                pixel <= to_unsigned(0, pwmBits);
            end if;
         end if;
    end process;
end behavioral;
