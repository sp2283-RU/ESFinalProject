----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 04/08/2026 07:29:06 PM
-- Design Name: 
-- Module Name: vga_ctrl - Behavioral
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

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity vga_ctrl is
Port (
clk,clk_en : in std_logic;
hcount, vcount : out std_logic_vector(9 downto 0);
vid,hs,vs : out std_logic
);
end vga_ctrl;

architecture Behavioral of vga_ctrl is

signal horizontalCount : integer range 0 to 799 := 0;
signal verticalCount : integer range 0 to 524 := 0;
signal hreset : std_logic;

begin

hcount <= std_logic_vector(to_unsigned(horizontalCount,10));
vcount <= std_logic_vector(to_unsigned(verticalCount,10));

process (clk) begin
    if (rising_edge(clk)) then
        if (clk_en = '1') then
            if (horizontalCount < 799) then
                horizontalCount <= horizontalCount + 1;
            else 
                horizontalCount <= 0;
                if (verticalCount < 524) then
                    verticalCount <= verticalCount + 1;
                else 
                    verticalCount <= 0;
                end if;
            end if;
       
            if ((horizontalCount < 640) and (verticalCount < 480)) then
                vid <= '1';
            else
                vid <= '0';
            end if;
            
            if ((horizontalCount < 752) and horizontalCount > 655) then
                hs <= '0';
            else
                hs <= '1';
            end if;
            
            if ((verticalCount < 492) and (verticalCount > 489)) then
                vs <= '0';
            else
                vs <= '1';
            end if;
        end if;
   end if;
end process;
            
        
        


end Behavioral;
