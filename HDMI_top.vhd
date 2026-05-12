----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 04/09/2026 01:09:27 PM
-- Design Name: 
-- Module Name: HDMI_top - Behavioral
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

entity HDMI_top is
Port (
clk : in std_logic;
voutcount : out std_logic_vector(9 downto 0);
douta : in std_logic_vector(7 downto 0);
addra : out std_logic_vector(17 downto 0);
hdmi_tx_clk_p, hdmi_tx_clk_n : out std_logic;
hdmi_tx_n, hdmi_tx_p : out std_logic_vector(2 downto 0)
);
end HDMI_top;

architecture Behavioral of HDMI_top is

component clock_div is
Port (
i_Clk : in std_logic;
o_ClkEN : out std_logic
 );
end component;

component vga_ctrl is
Port (
clk,clk_en : in std_logic;
hcount, vcount : out std_logic_vector(9 downto 0);
vid,hs,vs : out std_logic
);
end component;

component pixel_pusherHDMI is
Port (
clk, clk_en, Vs : in std_logic;
pixel : in std_logic_vector(7 downto 0);
hcount : in std_logic_vector(9 downto 0);
vid : in std_logic;
vga_R, vga_B : out std_logic_vector(7 downto 0);
vga_G : out std_logic_vector(7 downto 0);
addr : out std_logic_vector(17 downto 0)
);
end component;

component rgb2dvi_0 IS
  PORT (
    TMDS_Clk_p : OUT STD_LOGIC;
    TMDS_Clk_n : OUT STD_LOGIC;
    TMDS_Data_p : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
    TMDS_Data_n : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
    aRst : IN STD_LOGIC;
    vid_pData : IN STD_LOGIC_VECTOR(23 DOWNTO 0);
    vid_pVDE : IN STD_LOGIC;
    vid_pHSync : IN STD_LOGIC;
    vid_pVSync : IN STD_LOGIC;
    PixelClk : IN STD_LOGIC;
    SerialClk : IN STD_LOGIC
  );
END component;

signal clken, Vsbuf, Vidbuf, Hsbuf : std_logic;
signal addrbuf : std_logic_vector(17 downto 0);
signal pixeldata : std_logic_vector(7 downto 0);
signal hcountbuf : std_logic_vector(9 downto 0);
signal vcountbuf : std_logic_vector(9 downto 0);
signal VGArbuf, VGAgbuf, VGAbbuf : std_logic_vector(7 downto 0);
signal databuf : std_logic_vector(23 downto 0);
begin


pixeldata <= douta;
addra <= addrbuf;
voutcount <= vcountbuf;

myclockdiv : clock_div port map(i_Clk => clk, o_ClkEN => clken); 
mypixelpusher : pixel_pusherHDMI port map(clk => clk, clk_en => clken, Vs => Vsbuf, pixel => pixeldata, hcount => hcountbuf, vid => Vidbuf, vga_R => VGArbuf, vga_B => VGAbbuf, vga_G => VGAgbuf, addr => addrbuf); 
myvgactrl : vga_ctrl port map(clk => clk, clk_en => clken, hcount => hcountbuf, vid => Vidbuf, vs => Vsbuf, hs => Hsbuf, vcount => vcountBuf);
rgb2dvi : rgb2dvi_0 port map(TMDS_Clk_p => hdmi_tx_clk_p, TMDS_Clk_n => hdmi_tx_clk_n, TMDS_Data_p => hdmi_tx_p, TMDS_Data_n => hdmi_tx_n, aRST => '0', vid_pData => databuf, vid_pVDE => vidBuf, vid_pHsync => Hsbuf, vid_pVsync => Vsbuf, SerialClk => clk, PixelClk => clken); 


databuf <= VGArbuf & VGAgbuf & VGAbbuf;

end Behavioral;
