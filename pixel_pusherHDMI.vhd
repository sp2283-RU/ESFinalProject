----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 04/09/2026 01:39:31 AM
-- Design Name: 
-- Module Name: pixel_pusher - Behavioral
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

entity pixel_pusherHDMI is
Port (
clk, clk_en, Vs : in std_logic;
pixel : in std_logic_vector(7 downto 0);
hcount : in std_logic_vector(9 downto 0);
vid : in std_logic;
vga_R, vga_B : out std_logic_vector(7 downto 0) := (others => '0');
vga_G : out std_logic_vector(7 downto 0) := (others => '0');
addr : out std_logic_vector(17 downto 0)
);
end pixel_pusherHDMI;

architecture Behavioral of pixel_pusherHDMI is
signal addrbuffer : integer range 0 to 262143 := 0;
begin

addr <= std_logic_vector(to_unsigned(addrbuffer + 1,18));

process (clk) begin
    if (rising_edge(clk)) then
        if (clk_en = '1') then
            if (Vs = '0') then
                addrbuffer <= 0;
                vga_R <= (others => '0');
                vga_G <= (others => '0');
                vga_B <= (others => '0');
            elsif ((vid = '1') and (hcount <= "0111100000")) then
                addrbuffer <= addrbuffer + 1;
                vga_R <= pixel(7 downto 5) & "00000";
                vga_G <= pixel(4 downto 2) & "00000";
                vga_B <= pixel(1 downto 0) & "000000";
            else
                vga_R <= (others => '0');
                vga_G <= (others => '0');
                vga_B <= (others => '0');
            end if;
       end if;
   end if;
end process;
            
            
                


end Behavioral;
