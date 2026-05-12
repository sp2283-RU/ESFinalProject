----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 02/20/2026 06:29:30 AM
-- Design Name: 
-- Module Name: clock_div - Structural
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity clock_div is
Port (
i_Clk : in std_logic;
o_ClkEN : out std_logic
 );
end clock_div;

architecture Structural of clock_div is
signal count : integer range 0 to 4 := 0;

begin

    process (i_Clk) begin
        if (rising_edge(i_Clk)) then
            if (count < 4) then
                count <= count + 1;
                o_ClkEN <= '0';
            else 
                count <= 0;
                o_ClkEN <= '1';
            end if;
        end if;
    end process;
    


end Structural;
