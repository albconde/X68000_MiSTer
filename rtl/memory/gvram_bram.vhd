-- Lower 256 KiB of canonical GVRAM: two interleaved 64K x 16 banks.
-- Bank 0 stores even logical words and bank 1 stores odd logical words.

library ieee;
use ieee.std_logic_1164.all;
library altera_mf;
use altera_mf.altera_mf_components.all;

entity gvram_bram is
port(
	c0_address_a : in std_logic_vector(15 downto 0);
	c0_data_a : in std_logic_vector(15 downto 0);
	c0_wren_a : in std_logic := '0';
	c0_nibbleena_a : in std_logic_vector(3 downto 0) := "1111";
	c0_q_a : out std_logic_vector(15 downto 0);
	c0_address_b : in std_logic_vector(15 downto 0);
	c0_q_b : out std_logic_vector(15 downto 0);
	c1_address_a : in std_logic_vector(15 downto 0);
	c1_data_a : in std_logic_vector(15 downto 0);
	c1_wren_a : in std_logic := '0';
	c1_nibbleena_a : in std_logic_vector(3 downto 0) := "1111";
	c1_q_a : out std_logic_vector(15 downto 0);
	c1_address_b : in std_logic_vector(15 downto 0);
	c1_q_b : out std_logic_vector(15 downto 0);
	clock_a : in std_logic;
	clock_b : in std_logic
);
end gvram_bram;

architecture syn of gvram_bram is
	signal data_b_zero : std_logic_vector(3 downto 0);
begin
	data_b_zero <= (others=>'0');

	bank0_planes: for i in 0 to 3 generate
		plane: altsyncram
		generic map(
			address_reg_b=>"CLOCK1", clock_enable_input_a=>"BYPASS", clock_enable_input_b=>"BYPASS",
			clock_enable_output_a=>"BYPASS", clock_enable_output_b=>"BYPASS",
			intended_device_family=>"Cyclone V", lpm_type=>"altsyncram",
			numwords_a=>65536, numwords_b=>65536, operation_mode=>"BIDIR_DUAL_PORT",
			ram_block_type=>"M10K", outdata_aclr_a=>"NONE", outdata_aclr_b=>"NONE",
			outdata_reg_a=>"UNREGISTERED", outdata_reg_b=>"UNREGISTERED",
			power_up_uninitialized=>"FALSE", read_during_write_mode_mixed_ports=>"DONT_CARE",
			read_during_write_mode_port_a=>"DONT_CARE", read_during_write_mode_port_b=>"NEW_DATA_NO_NBE_READ",
			widthad_a=>16, widthad_b=>16, width_a=>4, width_b=>4,
			width_byteena_a=>1, width_byteena_b=>1, wrcontrol_wraddress_reg_b=>"CLOCK1")
		port map(address_a=>c0_address_a,address_b=>c0_address_b,clock0=>clock_a,clock1=>clock_b,
			data_a=>c0_data_a(i*4+3 downto i*4),byteena_a=>"1",data_b=>data_b_zero,
			wren_a=>c0_wren_a and c0_nibbleena_a(i),wren_b=>'0',
			q_a=>c0_q_a(i*4+3 downto i*4),q_b=>c0_q_b(i*4+3 downto i*4));
	end generate;

	bank1_planes: for i in 0 to 3 generate
		plane: altsyncram
		generic map(
			address_reg_b=>"CLOCK1", clock_enable_input_a=>"BYPASS", clock_enable_input_b=>"BYPASS",
			clock_enable_output_a=>"BYPASS", clock_enable_output_b=>"BYPASS",
			intended_device_family=>"Cyclone V", lpm_type=>"altsyncram",
			numwords_a=>65536, numwords_b=>65536, operation_mode=>"BIDIR_DUAL_PORT",
			ram_block_type=>"M10K", outdata_aclr_a=>"NONE", outdata_aclr_b=>"NONE",
			outdata_reg_a=>"UNREGISTERED", outdata_reg_b=>"UNREGISTERED",
			power_up_uninitialized=>"FALSE", read_during_write_mode_mixed_ports=>"DONT_CARE",
			read_during_write_mode_port_a=>"DONT_CARE", read_during_write_mode_port_b=>"NEW_DATA_NO_NBE_READ",
			widthad_a=>16, widthad_b=>16, width_a=>4, width_b=>4,
			width_byteena_a=>1, width_byteena_b=>1, wrcontrol_wraddress_reg_b=>"CLOCK1")
		port map(address_a=>c1_address_a,address_b=>c1_address_b,clock0=>clock_a,clock1=>clock_b,
			data_a=>c1_data_a(i*4+3 downto i*4),byteena_a=>"1",data_b=>data_b_zero,
			wren_a=>c1_wren_a and c1_nibbleena_a(i),wren_b=>'0',
			q_a=>c1_q_a(i*4+3 downto i*4),q_b=>c1_q_b(i*4+3 downto i*4));
	end generate;
end syn;
